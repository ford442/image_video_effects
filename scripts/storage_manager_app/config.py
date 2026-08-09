# scripts/storage_manager_app/config.py
import asyncio
import json
import os
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from enum import Enum
from typing import List, Optional

from aiocache import Cache
from fastapi import FastAPI
from google.cloud import storage
from google.oauth2 import service_account
from pydantic import BaseModel, Field

# ========================= CONFIGURATION =========================
BUCKET_NAME = os.environ.get("GCP_BUCKET_NAME")
CREDENTIALS_JSON = os.environ.get("GCP_CREDENTIALS")

# --- STORAGE MAP (extended for Brainfuck WASM benchmarks) ---
STORAGE_MAP = {
    "song": {"folder": "songs/", "index": "songs/_songs.json"},
    "pattern": {"folder": "patterns/", "index": "patterns/_patterns.json"},
    "bank": {"folder": "banks/", "index": "banks/_banks.json"},
    "sample": {"folder": "samples/", "index": "samples/_samples.json"},
    "music": {"folder": "music/", "index": "music/_music.json"},
    "note": {"folder": "notes/", "index": "notes/_notes.json"},
    "shader": {"folder": "shaders/", "index": "shaders/_shaders.json"},
    "brainfuck": {
        "folder": "brainfuck/",
        "index": "brainfuck/_brainfuck.json"
    },
    "default": {"folder": "misc/", "index": "misc/_misc.json"},
}

# --- GLOBAL OBJECTS ---
gcs_client = None
bucket = None
io_executor = ThreadPoolExecutor(max_workers=20)
cache = Cache(Cache.MEMORY)
INDEX_LOCK = asyncio.Lock()


# ========================= HELPERS =========================
def get_gcs_client():
    if CREDENTIALS_JSON:
        cred_info = json.loads(CREDENTIALS_JSON)
        creds = service_account.Credentials.from_service_account_info(cred_info)
        return storage.Client(credentials=creds)
    return storage.Client()


async def run_io(func, *args, **kwargs):
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(io_executor, lambda: func(*args, **kwargs))


def _read_json_sync(blob_path):
    blob = bucket.blob(blob_path)
    if blob.exists():
        return json.loads(blob.download_as_text())
    return []


def _write_json_sync(blob_path, data):
    blob = bucket.blob(blob_path)
    blob.upload_from_string(json.dumps(data), content_type='application/json')


# ========================= LIFESPAN =========================
@asynccontextmanager
async def lifespan(app: FastAPI):
    global gcs_client, bucket
    try:
        gcs_client = get_gcs_client()
        bucket = gcs_client.bucket(BUCKET_NAME)
        print(f"--- GCS CONNECTED: {BUCKET_NAME} ---")
    except Exception as e:
        print(f"!!! GCS CONNECTION FAILED: {e}")
    yield
    io_executor.shutdown()


# ========================= CORS =========================
ALLOWED_ORIGINS = [
    "http://localhost:3000",
    "https://test.1ink.us",
    "https://go.1ink.us",
    "https://noahcohn.com",
]


# ========================= MODELS =========================
class ItemPayload(BaseModel):
    name: str
    author: str
    description: Optional[str] = ""
    type: str = "song"
    data: dict
    rating: Optional[int] = None


class MetaData(BaseModel):
    id: str
    name: str
    author: str
    date: str
    type: str
    description: Optional[str] = ""
    filename: str
    rating: Optional[int] = None
    genre: Optional[str] = None
    last_played: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    coordinate: Optional[int] = None
    stars: Optional[float] = None
    rating_count: Optional[int] = None
    play_count: Optional[int] = None


class SortBy(str, Enum):
    date = "date"
    rating = "rating"
    name = "name"
    last_played = "last_played"
    genre = "genre"
    coordinate = "coordinate"


class ShaderCategory(str, Enum):
    generative = "generative"
    reactive = "reactive"
    transition = "transition"
    filter = "filter"
    distortion = "distortion"


class SampleMetaUpdatePayload(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    rating: Optional[int] = Field(None, ge=1, le=10)
    genre: Optional[str] = None
    last_played: Optional[str] = None


class MetaPatch(BaseModel):
    name: Optional[str] = None
    rating: Optional[int] = Field(None, ge=0, le=10)
    genre: Optional[str] = None
    tags: Optional[List[str]] = None
    last_played: Optional[str] = None
    coordinate: Optional[int] = None


class CoordinateSyncPayload(BaseModel):
    coordinates: dict
    overwrite: bool = False
