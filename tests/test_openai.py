import json

import httpx
from fastapi.testclient import TestClient
from openai import AsyncOpenAI

from taplate.app import create_app
from taplate.config import Settings
from taplate.providers import OpenAITranslator
from tests.test_sessions import OCR, screenshot, wait_for


def test_openai_contract_sends_two_images_and_keeps_corrected_source(tmp_path):
    def remote(request):
        body = json.loads(request.content)
        content = body["input"][0]["content"]
        images = [item for item in content if item["type"] == "input_image"]
        assert len(images) == 2
        assert all(item["image_url"].startswith("data:image/png;base64,") for item in images)
        assert images[0]["image_url"] != images[1]["image_url"]
        assert body["store"] is False
        assert set(body["text"]["format"]["schema"]["required"]) == {"r001", "r002"}
        result = {
            "r001": {"source": "请选择颜色 Nike", "translation": "Choose a Nike color"},
            "r002": {"source": "请选择尺寸 Nike", "translation": "Choose a Nike size"},
        }
        return httpx.Response(
            200,
            json={
                "id": "resp_test",
                "object": "response",
                "created_at": 1,
                "model": "test",
                "status": "completed",
                "output": [
                    {
                        "id": "msg_test",
                        "type": "message",
                        "role": "assistant",
                        "status": "completed",
                        "content": [{"type": "output_text", "text": json.dumps(result), "annotations": []}],
                    }
                ],
            },
        )

    client = AsyncOpenAI(
        api_key="test-key", http_client=httpx.AsyncClient(transport=httpx.MockTransport(remote))
    )
    translator = OpenAITranslator(Settings(_env_file=None), client=client)
    with TestClient(create_app(data_dir=tmp_path, ocr=OCR(), translator=translator)) as app:
        identifier = app.post("/api/sessions", files={"file": ("screen.png", screenshot())}).json()["id"]
        doc = wait_for(app, identifier)
        assert doc["status"] == "ready", doc["error"]
        assert doc["regions"][1]["source"] == "请选择尺寸 Nike"
        assert doc["regions"][1]["raw_text"] == "请选择颜色 Nike"
        assert doc["regions"][1]["translation"] == "Choose a Nike size"
        assert doc["regions"][1]["box"] == [200, 100, 160, 35]
