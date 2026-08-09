# storage_manager/models.py
from enum import Enum
from typing import Dict, List, Optional
from pydantic import BaseModel, Field


class SortBy(str, Enum):
    date = "date"
    rating = "rating"
    plays = "plays"
    name = "name"
    coordinate = "coordinate"
    last_played = "last_played"


class ShaderCategory(str, Enum):
    generative = "generative"
    reactive = "reactive"
    transition = "transition"
    filter = "filter"
    distortion = "distortion"
    image = "image"
    interactive = "interactive"
    simulation = "simulation"
    visual_effects = "visual-effects"
    artistic = "artistic"
    retro_glitch = "retro-glitch"
    geometric = "geometric"
    liquid_effects = "liquid-effects"
    other = "other"


class ItemPayload(BaseModel):
    name: str
    author: str
    description: Optional[str] = ""
    type: str = "song"
    data: dict
    rating: Optional[int] = None


class LocationPayload(BaseModel):
    id: Optional[str] = None
    name: str
    lat: float
    lng: float
    heading: float = 0.0
    pitch: float = 0.0
    zoom: float = 1.0
    description: Optional[str] = ""
    tags: List[str] = Field(default_factory=list)


class MetaData(BaseModel):
    name: Optional[str] = None
    author: Optional[str] = None
    description: Optional[str] = None
    rating: Optional[float] = None
    tags: Optional[List[str]] = None


class SampleMetaUpdatePayload(BaseModel):
    name: Optional[str] = None
    author: Optional[str] = None
    description: Optional[str] = None
    rating: Optional[float] = None
    genre: Optional[str] = None
    last_played: Optional[str] = None


class ShaderParam(BaseModel):
    name: str
    value: float
    min: float = 0.0
    max: float = 1.0
    step: float = 0.01


class MetaPatch(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[List[str]] = None
    rating: Optional[float] = None
    coordinate: Optional[int] = None
    params: Optional[List[ShaderParam]] = None


class PresetPackPublishPayload(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    description: Optional[str] = Field("", max_length=500)
    author: Optional[str] = Field("Anonymous", max_length=60)
    chain: str = Field(..., min_length=1)


class PresetPackMeta(BaseModel):
    id: str
    name: str
    description: Optional[str] = ""
    author: Optional[str] = "Anonymous"
    date: str
    chain: str
    play_count: Optional[int] = 0


class CoordinateSyncPayload(BaseModel):
    coordinates: dict
    overwrite: bool = False


class ShaderRescanPayload(BaseModel):
    pull_latest: bool = True


class ApplyIntentPayload(BaseModel):
    intent_id: str
    acknowledge_divergence: bool = False
