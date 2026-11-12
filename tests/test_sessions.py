import asyncio
import threading
import time
from io import BytesIO
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image

from taplate.app import create_app
from taplate.providers import ProcessingError


class OCR:
    def detect(self, path):
        return [
            {
                "polygon": [[20, 40], [180, 40], [180, 75], [20, 75]],
                "raw_text": "请选择颜色 Nike",
                "confidence": 0.97,
            },
            {
                "polygon": [[200, 100], [360, 100], [360, 135], [200, 135]],
                "raw_text": "请选择颜色 Nike",
                "confidence": 0.95,
            },
        ]


class Translator:
    async def translate(self, original, annotated, regions):
        return {
            r["id"]: {"source": r["raw_text"], "translation": f"Choose color {r['id']} Nike"} for r in regions
        }


def wait_for(client, session_id, terminal=("ready", "failed")):
    for _ in range(200):
        doc = client.get(f"/api/sessions/{session_id}").json()
        if doc["status"] in terminal:
            return doc
        time.sleep(0.01)
    raise AssertionError("Processing did not finish")


def screenshot(color="white"):
    image = Image.new("RGB", (400, 800), color)
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def test_upload_opens_persistent_uuid_viewer(tmp_path):
    session_id = str(uuid4())
    with TestClient(create_app(data_dir=tmp_path, start_worker=False)) as client:
        response = client.post(
            "/api/sessions",
            data={"session_id": session_id},
            files={"file": ("screen.png", screenshot(), "image/png")},
        )
        assert response.status_code == 202
        assert response.json()["view_url"] == f"/view/{session_id}"
        session = client.get(f"/api/sessions/{session_id}").json()
        assert (session["width"], session["height"], session["status"]) == (400, 800, "queued")
        assert client.get(session["original_url"]).headers["content-type"] == "image/png"
    with TestClient(create_app(data_dir=tmp_path, start_worker=False)) as client:
        assert client.get(f"/api/sessions/{session_id}").status_code == 200


def test_independent_regions_are_translated_without_moving_geometry(tmp_path):
    with TestClient(create_app(data_dir=tmp_path, ocr=OCR(), translator=Translator())) as client:
        response = client.post("/api/sessions", files={"file": ("screen.png", screenshot())})
        doc = wait_for(client, response.json()["id"])
        assert doc["status"] == "ready", doc.get("error")
        assert [r["id"] for r in doc["regions"]] == ["r001", "r002"]
        assert doc["regions"][0]["box"] == [20, 40, 160, 35]
        assert doc["regions"][0]["translation"] == "Choose color r001 Nike"
        assert doc["regions"][1]["translation"] == "Choose color r002 Nike"
        assert doc["regions"][0]["raw_text"] == "请选择颜色 Nike"
        annotated = client.get(doc["annotated_url"])
        assert annotated.status_code == 200
        assert annotated.content != client.get(doc["original_url"]).content


def test_uuid_conflicts_and_invalid_images_are_rejected(tmp_path):
    identifier = str(uuid4())
    with TestClient(create_app(data_dir=tmp_path, start_worker=False)) as client:

        def post(image):
            return client.post(
                "/api/sessions", data={"session_id": identifier}, files={"file": ("x.png", image)}
            )

        assert post(screenshot()).status_code == 202
        assert post(screenshot()).json()["id"] == identifier
        assert len(client.get("/api/sessions").json()) == 1
        assert post(screenshot("black")).status_code == 409
        assert post(b"not an image").status_code == 422
        assert client.get("/api/missing").status_code == 404
        assert (
            client.post(
                "/api/sessions",
                headers={"Origin": "https://unrelated.example"},
                files={"file": ("x.png", screenshot())},
            ).status_code
            == 403
        )


def test_translation_retry_reuses_ocr_and_rejects_wrong_ids(tmp_path):
    class OnePassOCR(OCR):
        used = False

        def detect(self, path):
            if self.used:
                raise ProcessingError("OCR must not be repeated for a translation retry")
            self.used = True
            return super().detect(path)

    class WrongThenCorrect(Translator):
        first = True

        async def translate(self, original, annotated, regions):
            if self.first:
                self.first = False
                return {"r999": {"source": "wrong", "translation": "wrong"}}
            return await super().translate(original, annotated, regions)

    with TestClient(create_app(data_dir=tmp_path, ocr=OnePassOCR(), translator=WrongThenCorrect())) as client:
        identifier = client.post("/api/sessions", files={"file": ("x.png", screenshot())}).json()["id"]
        failed = wait_for(client, identifier)
        assert failed["status"] == "failed"
        assert "regions" in failed["error"]
        assert client.post(f"/api/sessions/{identifier}/retry").status_code == 202
        assert wait_for(client, identifier)["status"] == "ready"
        assert client.post(f"/api/sessions/{identifier}/retry").status_code == 409


def test_delete_during_translation_cannot_resurrect_session(tmp_path):
    started, finish = threading.Event(), threading.Event()

    class Slow(Translator):
        async def translate(self, original, annotated, regions):
            started.set()
            while not finish.is_set():
                await asyncio.sleep(0.01)
            return await super().translate(original, annotated, regions)

    with TestClient(create_app(data_dir=tmp_path, ocr=OCR(), translator=Slow())) as client:
        identifier = client.post("/api/sessions", files={"file": ("x.png", screenshot())}).json()["id"]
        assert started.wait(3)
        assert client.delete(f"/api/sessions/{identifier}").status_code == 204
        finish.set()
        time.sleep(0.05)
        assert client.get(f"/api/sessions/{identifier}").status_code == 404
        assert client.get("/api/sessions").json() == []
    with TestClient(create_app(data_dir=tmp_path, start_worker=False)) as client:
        assert client.get(f"/api/sessions/{identifier}").status_code == 404


def test_interrupted_translation_is_retryable_after_restart(tmp_path):
    started = threading.Event()

    class Interrupted(Translator):
        async def translate(self, original, annotated, regions):
            started.set()
            await asyncio.Event().wait()

    with TestClient(create_app(data_dir=tmp_path, ocr=OCR(), translator=Interrupted())) as client:
        identifier = client.post("/api/sessions", files={"file": ("x.png", screenshot())}).json()["id"]
        assert started.wait(3)
    with TestClient(create_app(data_dir=tmp_path, ocr=OCR(), translator=Translator())) as client:
        assert client.get(f"/api/sessions/{identifier}").json()["status"] == "failed"
        assert client.post(f"/api/sessions/{identifier}/retry").status_code == 202
        assert wait_for(client, identifier)["status"] == "ready"


def test_seven_day_expiry_removes_views_and_image_access(tmp_path):
    now = [1000000.0]
    with TestClient(create_app(data_dir=tmp_path, start_worker=False, clock=lambda: now[0])) as client:
        identifier = client.post("/api/sessions", files={"file": ("x.png", screenshot())}).json()["id"]
        now[0] += 7 * 86400
        assert client.get("/api/sessions").json() == []
        assert client.get(f"/api/sessions/{identifier}/images/original").status_code == 410
        assert client.get(f"/api/sessions/{identifier}").status_code == 404


def test_no_text_is_ready_without_calling_translator(tmp_path):
    class Empty:
        def detect(self, path):
            return []

    class NotNeeded:
        async def translate(self, *args):
            raise RuntimeError("No text requires no paid call")

    with TestClient(create_app(data_dir=tmp_path, ocr=Empty(), translator=NotNeeded())) as client:
        identifier = client.post("/api/sessions", files={"file": ("x.png", screenshot())}).json()["id"]
        assert wait_for(client, identifier)["status"] == "ready"
        assert client.get(f"/api/sessions/{identifier}").json()["regions"] == []


def test_deleted_uuid_replacement_is_not_overwritten_by_old_job(tmp_path):
    started = [threading.Event(), threading.Event()]
    finish = [threading.Event(), threading.Event()]

    class Paused(Translator):
        sequence = 0

        async def translate(self, original, annotated, regions):
            index = self.sequence
            self.sequence += 1
            started[index].set()
            while not finish[index].is_set():
                await asyncio.sleep(0.01)
            return {
                r["id"]: {"source": r["raw_text"], "translation": ["Old capture", "New capture"][index]}
                for r in regions
            }

    with TestClient(create_app(data_dir=tmp_path, ocr=OCR(), translator=Paused())) as client:
        identifier = str(uuid4())

        def post(color):
            return client.post(
                "/api/sessions", data={"session_id": identifier}, files={"file": ("x.png", screenshot(color))}
            )

        try:
            assert post("white").status_code == 202
            assert started[0].wait(3)
            assert client.delete(f"/api/sessions/{identifier}").status_code == 204
            assert post("black").status_code == 202
            finish[0].set()
            assert started[1].wait(3), "Replacement capture was skipped after the old job overwrote it"
            assert client.get(f"/api/sessions/{identifier}").json()["status"] == "translating"
            finish[1].set()
            assert wait_for(client, identifier)["regions"][0]["translation"] == "New capture"
        finally:
            for event in finish:
                event.set()
