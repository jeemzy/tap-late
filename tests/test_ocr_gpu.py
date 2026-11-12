from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import numpy as np
import pytest

from taplate.config import Settings
from taplate.providers import ProcessingError, RapidOCRProvider


@pytest.fixture
def runtime(monkeypatch):
    """Exercise our public provider with controllable ONNX sessions, without GPU/network access."""
    ort = SimpleNamespace(
        preload_dlls=Mock(),
        get_available_providers=Mock(return_value=["CUDAExecutionProvider", "CPUExecutionProvider"]),
    )
    sessions = {
        name: SimpleNamespace(
            get_providers=Mock(return_value=["CUDAExecutionProvider", "CPUExecutionProvider"]),
            disable_fallback=Mock(),
        )
        for name in ("det", "cls", "rec")
    }
    engine = Mock()
    for name, session in sessions.items():
        getattr(engine, f"_load_{name}_model").return_value = SimpleNamespace(
            session=SimpleNamespace(session=session)
        )
    engine.return_value = SimpleNamespace(
        boxes=np.array([[[1, 2], [30, 2], [30, 15], [1, 15]]]),
        txts=["你好 Nike"],
        scores=[0.98],
    )
    rapidocr = SimpleNamespace(
        EngineType=SimpleNamespace(ONNXRUNTIME="onnxruntime"),
        LangDet=SimpleNamespace(CH="ch"),
        LangRec=SimpleNamespace(CH="ch"),
        ModelType=SimpleNamespace(MEDIUM="medium", SMALL="small"),
        OCRVersion=SimpleNamespace(PPOCRV6="PP-OCRv6"),
        RapidOCR=Mock(return_value=engine),
    )
    monkeypatch.setitem(__import__("sys").modules, "onnxruntime", ort)
    monkeypatch.setitem(__import__("sys").modules, "rapidocr", rapidocr)
    return SimpleNamespace(ort=ort, rapidocr=rapidocr, engine=engine, sessions=sessions)


def test_cuda_default_and_explicit_cpu_setting(monkeypatch):
    monkeypatch.delenv("TAPLATE_OCR_DEVICE", raising=False)
    assert Settings(_env_file=None).ocr_device == "cuda"
    assert Settings(_env_file=None, TAPLATE_OCR_DEVICE="cpu").ocr_device == "cpu"
    with pytest.raises(ValueError):
        Settings(_env_file=None, TAPLATE_OCR_DEVICE="automatic")


def test_cuda_requires_real_session_providers_and_preserves_detection(runtime):
    provider = RapidOCRProvider()
    assert provider.health()["loaded"] is False
    runtime.rapidocr.RapidOCR.assert_not_called()
    detections = provider.detect(Path("screen.png"))
    assert detections[0]["raw_text"] == "你好 Nike"
    assert detections[0]["polygon"] == [[1, 2], [30, 2], [30, 15], [1, 15]]
    assert provider.health()["loaded"] is True
    assert set(provider.health()["session_providers"]) == {"det", "cls", "rec"}
    params = runtime.rapidocr.RapidOCR.call_args.kwargs["params"]
    assert params["EngineConfig.onnxruntime.use_cuda"] is True
    assert params["Rec.rec_batch_num"] == 4
    assert params["Det.limit_type"] == "max"
    assert params["Det.limit_side_len"] == 1920
    runtime.ort.preload_dlls.assert_called_once_with(directory="")
    for session in runtime.sessions.values():
        session.disable_fallback.assert_called_once()


def test_missing_cuda_provider_fails_before_inference(runtime):
    runtime.ort.get_available_providers.return_value = ["CPUExecutionProvider"]
    provider = RapidOCRProvider()
    with pytest.raises(ProcessingError, match="CUDA OCR is unavailable"):
        provider.detect(Path("screen.png"))
    assert provider.health()["loaded"] is False
    runtime.rapidocr.RapidOCR.assert_not_called()


def test_silent_cpu_session_fallback_is_rejected_and_retry_can_recover(runtime):
    runtime.sessions["rec"].get_providers.return_value = ["CPUExecutionProvider"]
    provider = RapidOCRProvider()
    with pytest.raises(ProcessingError, match="could not start its rec model"):
        provider.detect(Path("screen.png"))
    runtime.engine.assert_not_called()
    assert provider.health()["loaded"] is False
    runtime.sessions["rec"].get_providers.return_value = ["CUDAExecutionProvider", "CPUExecutionProvider"]
    assert provider.detect(Path("screen.png"))
    assert provider.health()["loaded"] is True


def test_explicit_cpu_never_requests_cuda(runtime):
    for session in runtime.sessions.values():
        session.get_providers.return_value = ["CPUExecutionProvider"]
    provider = RapidOCRProvider(device="cpu")
    assert provider.detect(Path("screen.png"))
    assert provider.health()["configured_device"] == "cpu"
    params = runtime.rapidocr.RapidOCR.call_args.kwargs["params"]
    assert params["EngineConfig.onnxruntime.use_cuda"] is False
    runtime.ort.preload_dlls.assert_not_called()


def test_model_provisioning_does_not_initialize_gpu_or_cache_unvalidated_engine(runtime):
    provider = RapidOCRProvider()
    provider.load(initialize=False)
    runtime.ort.preload_dlls.assert_not_called()
    runtime.ort.get_available_providers.assert_not_called()
    assert provider.engine is None
    for name in runtime.sessions:
        getattr(runtime.engine, f"_load_{name}_model").assert_not_called()
