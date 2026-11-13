from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class GlassSettings(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)

    frost: float = Field(1.0, ge=0, le=6)
    matte: float = Field(0, ge=0, le=1)
    refraction_index: float = Field(1.52, ge=1, le=2.4)
    refraction_strength: float = Field(1.6, ge=0, le=3)
    edge_width: float = Field(32, ge=4, le=48)
    curvature: float = Field(2.1, ge=0, le=4)
    magnification: float = Field(1.045, ge=1, le=1.15)
    dispersion: float = Field(0.85, ge=0, le=3)
    gloss: float = Field(1, ge=0, le=2)
    reflection: float = Field(0.07, ge=0, le=0.3)
    press_response: float = Field(1, ge=0, le=2)
    resolution: Literal["auto", "2x", "3x"] = "auto"
