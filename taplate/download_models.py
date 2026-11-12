"""Provision the exact OCR model routes used by this app, before serving requests."""

import tempfile
from enum import Enum
from pathlib import Path

from omegaconf import OmegaConf
from rapidocr import download_models

from taplate.config import Settings
from taplate.providers import RapidOCRProvider


def main():
    provider = RapidOCRProvider(Settings().ocr_model)
    config = provider.load().cfg
    with tempfile.TemporaryDirectory(prefix="taplate-models-") as directory:
        path = Path(directory) / "ocr.yaml"

        def values(item):
            if isinstance(item, Enum):
                return item.value
            if isinstance(item, dict):
                return {key: values(value) for key, value in item.items()}
            if isinstance(item, list):
                return [values(value) for value in item]
            return item

        OmegaConf.save(OmegaConf.create(values(OmegaConf.to_container(config, resolve=True))), path)
        download_models(path)


if __name__ == "__main__":
    main()
