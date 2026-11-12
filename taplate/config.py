from pathlib import Path

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    openai_api_key: SecretStr = SecretStr("")
    openai_model: str = "gpt-6.1-sol"
    data_dir: Path = Field(Path("data"), validation_alias="TAPLATE_DATA_DIR")
    retention_days: int = Field(7, ge=1, le=365, validation_alias="TAPLATE_RETENTION_DAYS")
    max_upload_mb: int = Field(20, ge=1, le=100, validation_alias="TAPLATE_MAX_UPLOAD_MB")
    ocr_model: str = Field("medium", pattern="^(small|medium)$", validation_alias="TAPLATE_OCR_MODEL")
    ocr_device: str = Field("cuda", pattern="^(cuda|cpu)$", validation_alias="TAPLATE_OCR_DEVICE")
