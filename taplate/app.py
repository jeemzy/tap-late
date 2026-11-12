import asyncio
import hashlib
import logging
import shutil
import time
import warnings
from contextlib import asynccontextmanager
from io import BytesIO
from pathlib import Path
from typing import Annotated
from urllib.parse import urlsplit
from uuid import UUID, uuid4

from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image, ImageOps, UnidentifiedImageError

from taplate.config import Settings
from taplate.providers import RapidOCRProvider
from taplate.storage import Store

logger = logging.getLogger("taplate")
FRONTEND = Path(__file__).resolve().parent.parent / "frontend" / "dist"


def public_session(doc):
    return {key: value for key, value in doc.items() if key not in ("digest", "generation")}


def create_app(
    data_dir: Path | None = None,
    *,
    settings=None,
    ocr=None,
    translator=None,
    start_worker=True,
    clock=time.time,
    frontend_dir: Path | None = None,
) -> FastAPI:
    config = settings or Settings()
    detector = ocr if ocr is not None else RapidOCRProvider(config.ocr_model, config.ocr_device)
    store = Store(Path(data_dir or config.data_dir))
    queue: asyncio.Queue[str] = asyncio.Queue()
    static = frontend_dir or FRONTEND

    def remove(session_id):
        store.delete(session_id)
        shutil.rmtree(store.root / session_id, ignore_errors=True)

    def purge():
        for session_id in store.expired(clock()):
            remove(session_id)

    @asynccontextmanager
    async def lifespan(app):
        purge()
        for folder in store.root.iterdir():
            if folder.is_dir():
                try:
                    canonical = str(UUID(folder.name))
                except ValueError:
                    continue
                if not store.get(canonical):
                    shutil.rmtree(folder, ignore_errors=True)
        for doc in store.list(clock()):
            if doc["status"] in ("ocr", "translating"):
                store.update(
                    doc["id"], status="failed", error="Processing was interrupted. Retry this screenshot."
                )
            elif doc["status"] == "queued":
                queue.put_nowait(doc["id"])
        tasks = []
        if start_worker:
            from taplate.pipeline import process_session
            from taplate.providers import OpenAITranslator

            provider = translator if translator is not None else OpenAITranslator(config)

            async def work():
                while True:
                    identifier = await queue.get()
                    try:
                        await process_session(store, identifier, detector, provider, clock)
                    except asyncio.CancelledError:
                        raise
                    except Exception:
                        logger.exception("Worker failure for session %s", identifier)
                        store.update(
                            identifier, status="failed", error="Processing failed. Retry this screenshot."
                        )
                    finally:
                        queue.task_done()

            tasks.append(asyncio.create_task(work()))

        async def cleanup():
            while True:
                await asyncio.sleep(3600)
                purge()

        tasks.append(asyncio.create_task(cleanup()))
        yield
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

    app = FastAPI(title="tap-late", lifespan=lifespan)

    @app.middleware("http")
    async def private_browser_boundary(request: Request, call_next):
        origin = request.headers.get("origin")
        if (
            request.method not in ("GET", "HEAD", "OPTIONS")
            and origin
            and urlsplit(origin).netloc != request.headers.get("host")
        ):
            return JSONResponse({"detail": "Cross-origin requests are not allowed."}, status_code=403)
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; img-src 'self' blob: data:; style-src 'self' 'unsafe-inline'; "
            "script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
        )
        return response

    def get_session(identifier):
        doc = store.get(str(identifier))
        if doc and doc["expires_at"] <= clock():
            remove(doc["id"])
            raise HTTPException(410, "This screenshot has expired. Upload it again to translate it.")
        if not doc:
            raise HTTPException(404, "Screenshot not found. It may have been deleted or expired.")
        return doc

    @app.get("/api/health")
    async def health():
        return {
            "status": "ok",
            "translation_configured": bool(config.openai_api_key.get_secret_value()),
            "model": config.openai_model,
            "retention_days": config.retention_days,
            "ocr": detector.health()
            if hasattr(detector, "health")
            else {"configured_device": config.ocr_device, "loaded": False},
        }

    @app.post("/api/sessions", status_code=202)
    async def upload(file: Annotated[UploadFile, File()], session_id: Annotated[UUID | None, Form()] = None):
        raw = await file.read(config.max_upload_mb * 1024 * 1024 + 1)
        await file.close()
        if len(raw) > config.max_upload_mb * 1024 * 1024:
            raise HTTPException(413, f"Choose an image smaller than {config.max_upload_mb} MB.")
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", Image.DecompressionBombWarning)
                with Image.open(BytesIO(raw)) as source:
                    if source.format not in ("PNG", "JPEG", "WEBP"):
                        raise HTTPException(415, "Choose a PNG, JPEG, or WebP screenshot.")
                    if source.width * source.height > 25_000_000:
                        raise HTTPException(413, "Choose a single-screen image under 25 megapixels.")
                    image = ImageOps.exif_transpose(source).convert("RGB")
        except (
            UnidentifiedImageError,
            OSError,
            ValueError,
            Image.DecompressionBombError,
            Image.DecompressionBombWarning,
        ):
            raise HTTPException(422, "This file could not be read as a screenshot.") from None
        digest = hashlib.sha256(str(image.size).encode() + image.tobytes()).hexdigest()
        identifier = str(session_id or uuid4())
        existing = store.get(identifier)
        if existing:
            if existing["expires_at"] <= clock():
                raise HTTPException(410, "This UUID has expired. Capture again with a new UUID.")
            if existing["digest"] != digest:
                raise HTTPException(409, "This UUID already belongs to a different screenshot.")
            return {"id": identifier, "view_url": f"/view/{identifier}"}
        folder = store.root / identifier
        folder.mkdir(parents=True, exist_ok=True)
        try:
            image.save(folder / "original.png")
            now = clock()
            store.create(
                {
                    "id": identifier,
                    "created_at": now,
                    "expires_at": now + config.retention_days * 86400,
                    "status": "queued",
                    "width": image.width,
                    "height": image.height,
                    "digest": digest,
                    "generation": str(uuid4()),
                    "regions": [],
                    "ocr_complete": False,
                    "error": None,
                    "original_url": f"/api/sessions/{identifier}/images/original",
                    "annotated_url": None,
                    "view_url": f"/view/{identifier}",
                }
            )
        except Exception:
            shutil.rmtree(folder, ignore_errors=True)
            raise
        queue.put_nowait(identifier)
        return {"id": identifier, "view_url": f"/view/{identifier}"}

    @app.get("/api/sessions")
    async def recent():
        return [public_session(doc) for doc in store.list(clock())]

    @app.get("/api/sessions/{session_id}")
    async def session(session_id: UUID):
        return public_session(get_session(session_id))

    @app.get("/api/sessions/{session_id}/images/{kind}")
    async def image(session_id: UUID, kind: str):
        get_session(session_id)
        if kind not in ("original", "annotated"):
            raise HTTPException(404, "Image not found.")
        path = store.root / str(session_id) / f"{kind}.png"
        if not path.is_file():
            raise HTTPException(404, "This image is not available yet.")
        return FileResponse(path, media_type="image/png")

    @app.post("/api/sessions/{session_id}/retry", status_code=202)
    async def retry(session_id: UUID):
        doc = get_session(session_id)
        if doc["status"] != "failed":
            raise HTTPException(409, "Only failed sessions can be retried.")
        store.update(doc["id"], status="queued", error=None)
        queue.put_nowait(doc["id"])
        return {"id": doc["id"], "view_url": doc["view_url"]}

    @app.delete("/api/sessions/{session_id}", status_code=204)
    async def delete(session_id: UUID):
        get_session(session_id)
        remove(str(session_id))

    if (static / "assets").is_dir():
        app.mount("/assets", StaticFiles(directory=static / "assets"), name="assets")

    @app.get("/favicon.svg", include_in_schema=False)
    async def favicon():
        path = static / "favicon.svg"
        if not path.is_file():
            raise HTTPException(404)
        return FileResponse(path, media_type="image/svg+xml")

    @app.get("/", include_in_schema=False)
    @app.get("/view/{session_id}", include_in_schema=False)
    async def frontend(session_id: UUID | None = None):
        if (static / "index.html").is_file():
            return FileResponse(static / "index.html")
        return JSONResponse({"detail": "Frontend not built. Run npm run build in frontend."}, status_code=503)

    return app
