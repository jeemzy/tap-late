import asyncio
import logging
import math
from io import BytesIO

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from taplate.providers import ProcessingError

logger = logging.getLogger("taplate")


def prepare_regions(detections, image):
    width, height = image.size
    pixels = np.asarray(image)
    regions = []
    for detection in detections:
        polygon = [[float(x), float(y)] for x, y in detection["polygon"]]
        if len(polygon) != 4 or not all(math.isfinite(v) for p in polygon for v in p):
            continue
        x1 = max(0, int(min(p[0] for p in polygon)))
        y1 = max(0, int(min(p[1] for p in polygon)))
        x2 = min(width, math.ceil(max(p[0] for p in polygon)))
        y2 = min(height, math.ceil(max(p[1] for p in polygon)))
        if x2 <= x1 or y2 <= y1:
            continue
        # Sample a thin surrounding ring, rather than the original text's ink.
        left, top, right, bottom = max(0, x1 - 3), max(0, y1 - 3), min(width, x2 + 3), min(height, y2 + 3)
        strips = [
            pixels[top:y1, left:right].reshape(-1, 3),
            pixels[y2:bottom, left:right].reshape(-1, 3),
            pixels[y1:y2, left:x1].reshape(-1, 3),
            pixels[y1:y2, x2:right].reshape(-1, 3),
        ]
        ring = np.concatenate(strips)
        background = np.median(ring, axis=0).astype(int) if len(ring) else np.array([245, 245, 245])
        if len(ring) and float(np.std(ring, axis=0).mean()) > 28:
            background = np.array([248, 248, 246])
        luminance = sum(background * [0.2126, 0.7152, 0.0722])
        regions.append(
            {
                "id": "",
                "polygon": polygon,
                "box": [x1, y1, x2 - x1, y2 - y1],
                "raw_text": detection["raw_text"],
                "source": detection["raw_text"],
                "confidence": detection["confidence"],
                "translation": None,
                "background": "#" + "".join(f"{v:02x}" for v in background),
                "foreground": "#171918" if luminance > 140 else "#ffffff",
            }
        )
    regions.sort(key=lambda r: (r["box"][1] // 8, r["box"][0], r["box"][1]))
    for index, region in enumerate(regions, 1):
        region["id"] = f"r{index:03d}"
    return regions


def annotated_image(image, regions):
    annotated = image.copy()
    draw = ImageDraw.Draw(annotated)
    font = ImageFont.load_default(size=max(14, image.width // 55))
    for region in regions:
        x, y, _w, _h = region["box"]
        draw.line(
            [tuple(p) for p in region["polygon"]] + [tuple(region["polygon"][0])],
            fill="#007bff",
            width=max(2, image.width // 500),
        )
        label = region["id"]
        label_box = draw.textbbox((0, 0), label, font=font)
        label_height = label_box[3] - label_box[1] + 6
        label_width = label_box[2] + 6
        label_y = max(0, y - label_height)
        label_x = min(x, max(0, image.width - label_width))
        draw.rectangle((label_x, label_y, label_x + label_width, label_y + label_height), fill="#0066d6")
        draw.text((label_x + 3, label_y + 1), label, fill="white", font=font)
    buffer = BytesIO()
    annotated.save(buffer, format="PNG")
    return buffer.getvalue()


async def process_session(store, identifier, detector, translator, clock):
    initial = store.get(identifier)
    if not initial:
        return
    generation = initial.get("generation")

    def current():
        doc = store.get(identifier)
        return doc if doc and doc.get("generation") == generation and doc["expires_at"] > clock() else None

    doc = current()
    if not doc or doc["status"] != "queued":
        return
    folder = store.root / identifier
    try:
        if not doc["ocr_complete"]:
            store.update(identifier, status="ocr", error=None)
            detections = await asyncio.to_thread(detector.detect, folder / "original.png")
            if not current():
                return
            with Image.open(folder / "original.png") as image:
                regions = prepare_regions(detections, image)
                annotation = annotated_image(image, regions)
            # No await between checking the record and publishing files; deletion cannot interleave here.
            (folder / "annotated.png").write_bytes(annotation)
            store.update(
                identifier,
                regions=regions,
                ocr_complete=True,
                annotated_url=f"/api/sessions/{identifier}/images/annotated",
            )
        doc = current()
        if not doc:
            return
        if not doc["regions"]:
            store.update(identifier, status="ready", error=None)
            return
        if len(doc["regions"]) > 500:
            raise ProcessingError("Too many text regions. Crop this screenshot into a smaller image.")
        store.update(identifier, status="translating")
        result = await translator.translate(folder / "original.png", folder / "annotated.png", doc["regions"])
        if not current():
            return
        if not isinstance(result, dict) or set(result) != {r["id"] for r in doc["regions"]}:
            raise ProcessingError("The translation did not match the screenshot's regions. Retry it.")
        for region in doc["regions"]:
            value = result[region["id"]]
            if not isinstance(value, dict) or set(value) != {"source", "translation"}:
                raise ProcessingError("The translation contained invalid region data. Retry it.")
            for key in ("source", "translation"):
                if value[key] is not None and not isinstance(value[key], str):
                    raise ProcessingError("The translation contained invalid text. Retry it.")
            region["source"] = value["source"] or region["raw_text"]
            region["translation"] = value["translation"] if value["source"] else None
        store.update(identifier, status="ready", regions=doc["regions"], error=None)
    except asyncio.CancelledError:
        raise
    except ProcessingError as error:
        if current():
            store.update(identifier, status="failed", error=str(error))
    except Exception as error:
        logger.warning("Processing failed for %s (%s)", identifier, type(error).__name__)
        if current():
            store.update(identifier, status="failed", error="Processing failed. Check the server and retry.")
