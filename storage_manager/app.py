import os
import json
import uuid
import asyncio
import logging
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from typing import List, Optional
from datetime import datetime
import uvicorn
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from aiocache import Cache
# Google Cloud Imports
from google.cloud import storage
from google.oauth2 import service_account
# --- CONFIGURATION ---
BUCKET_NAME = os.environ.get("GCP_BUCKET_NAME")
# Handle Credentials: If provided as a raw JSON string in env var
CREDENTIALS_JSON = os.environ.get("GCP_CREDENTIALS")
# --- STORAGE MAP ---
# Defines the folder structure inside the bucket
STORAGE_MAP = {
    "song": {"folder": "songs/", "index": "songs/_songs.json"},
    "pattern": {"folder": "patterns/", "index": "patterns/_patterns.json"},
    "bank": {"folder": "banks/", "index": "banks/_banks.json"},
    "sample": {"folder": "samples/", "index": "samples/_samples.json"},
    "music": {"folder": "music/", "index": "music/_music.json"},
    "note": {"folder": "notes/", "index": "notes/_notes.json"},
    "default": {"folder": "misc/", "index": "misc/_misc.json"},
    "shader": {
        "folder": "shaders/",
        "index": "shaders/_shaders.json"
    },
}
# --- GLOBAL OBJECTS ---
gcs_client = None
bucket = None
# GCS handles high concurrency well
io_executor = ThreadPoolExecutor(max_workers=20)
cache = Cache(Cache.MEMORY)
INDEX_LOCK = asyncio.Lock() # Prevents race conditions during index writes
# --- HELPERS ---
def get_gcs_client():
    """Initializes the GCS Client from environment variable string or file"""
    if CREDENTIALS_JSON:
        # Load credentials from the JSON string stored in secrets
        cred_info = json.loads(CREDENTIALS_JSON)
        creds = service_account.Credentials.from_service_account_info(
            cred_info)
        return storage.Client(credentials=creds)
    else:
        # Fallback to standard environment variable lookups (local dev)
        return storage.Client()
async def run_io(func, *args, **kwargs):
    """Runs blocking GCS I/O in a thread pool"""
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(io_executor, lambda: func(*args, **kwargs))
# --- LIFESPAN ---
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
app = FastAPI(lifespan=lifespan)
# --- CORS ---
# Replace ["*"] with your actual external site URL to prevent strangers from using your API
ALLOWED_ORIGINS = [
    "http://localhost:3000", # For your local testing
    "https://test.1ink.us", # <--- REPLACE THIS with your actual site
    "https://go.1ink.us", # <--- REPLACE THIS with your actual site
    "https://noahcohn.com", # <--- REPLACE THIS with your actual site
    "https://ford442-storage-manager.hf.space", # HF Space URL
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS, # Uses the list above
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# --- DIRECT STORAGE LISTING ---
@app.get("/api/storage/files")
async def list_gcs_folder(folder: str = Query(..., description="Folder name, e.g., 'songs' or 'samples'")):
    """
    Directly lists files in a GCS folder (ignoring the JSON index).
    Useful for seeing what is actually on the disk.
    """
    # 1. Get the correct prefix from your STORAGE_MAP, or use the folder name directly
    # This handles cases where user types "song" but folder is "songs/"
    config = STORAGE_MAP.get(folder)
    prefix = config["folder"] if config else f"{folder}/"
    try:
        # 2. Run GCS List Blobs in a thread (to keep server fast)
        def _fetch_blobs():
            # 'delimiter' makes it behave like a folder (doesn't show sub-sub-files)
            blobs = bucket.list_blobs(prefix=prefix, delimiter="/")
            file_list = []
            for blob in blobs:
                # Remove the folder prefix (e.g. "songs/beat1.json" -> "beat1.json")
                name = blob.name.replace(prefix, "")
                if name and name != "":
                    file_list.append({
                        "filename": name,
                        "size": blob.size,
                        "updated": blob.updated.isoformat() if blob.updated else None,
                        "url": blob.public_url if blob.public_url else None
                    })
            return file_list
        files = await run_io(_fetch_blobs)
        return {"folder": prefix, "count": len(files), "files": files}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
# --- MODELS ---
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
    last_played: Optional[str] = None # ISO timestamp
    tags: List[str] = Field(default_factory=list) # ← ADD THIS
# --- GCS I/O HELPERS ---
def _read_json_sync(blob_path):
    blob = bucket.blob(blob_path)
    if blob.exists():
        return json.loads(blob.download_as_text())
    return []
def _write_json_sync(blob_path, data):
    blob = bucket.blob(blob_path)
    # Upload as JSON string with correct content type
    blob.upload_from_string(
        json.dumps(data),
        content_type='application/json'
    )
# --- ENDPOINTS ---
@app.get("/")
def home():
    return {"status": "online", "provider": "Google Cloud Storage"}
# --- 0.5 HEALTH CHECK & TEST DATA ---
@app.post("/api/admin/sync-music")
async def sync_music_folder():
    """Scans the music/ folder and rebuilds the music index."""
    config = STORAGE_MAP["music"]
    report = {"added": 0, "removed": 0}
   
    async with INDEX_LOCK:
        try:
            # 1. List all files in music/
            blobs = await run_io(lambda: list(bucket.list_blobs(prefix=config["folder"])))
           
            # Filter for audio files (FLAC, WAV, MP3)
            audio_files = []
            for b in blobs:
                fname = b.name.replace(config["folder"], "")
                if fname and not b.name.endswith(config["index"]):
                    lower = fname.lower()
                    if lower.endswith(('.flac', '.wav', '.mp3', '.ogg')):
                        audio_files.append({
                            "filename": fname,
                            "name": fname,
                            "size": b.size,
                            "url": b.public_url
                        })
           
            # 2. Get current index
            index_data = await run_io(_read_json_sync, config["index"])
            if not isinstance(index_data, list):
                index_data = []
           
            # 3. Compare and update
            index_map = {item["filename"]: item for item in index_data}
            disk_set = set(f["filename"] for f in audio_files)
           
            # Remove missing files
            new_index = [item for item in index_data if item["filename"] in disk_set]
            report["removed"] = len(index_data) - len(new_index)
           
            # Add new files
            for file_info in audio_files:
                if file_info["filename"] not in index_map:
                    new_entry = {
                        "id": str(uuid.uuid4()),
                        "filename": file_info["filename"],
                        "name": file_info["name"],
                        "type": "music",
                        "date": datetime.now().strftime("%Y-%m-%d"),
                        "author": "Unknown",
                        "description": "",
                        "rating": None,
                        "genre": None,
                        "last_played": None,
                        "url": file_info["url"],
                        "size": file_info["size"]
                    }
                    new_index.insert(0, new_entry)
                    report["added"] += 1
           
            if report["added"] > 0 or report["removed"] > 0:
                await run_io(_write_json_sync, config["index"], new_index)
           
            await cache.delete("library:music")
            await cache.delete("library:all")
           
            report["total"] = len(new_index)
            return report
           
        except Exception as e:
            raise HTTPException(500, f"Failed to sync music: {str(e)}")
@app.post("/api/admin/seed-test-samples")
async def seed_test_samples():
    """Creates test sample entries for development."""
    config = STORAGE_MAP["sample"]
    test_samples = [
        {
            "id": "test-flac-001",
            "name": "Test Ambient Track.flac",
            "filename": "test-flac-001.flac",
            "type": "sample",
            "author": "Test Artist",
            "date": "2024-02-09",
            "description": "Test ambient track",
            "rating": 8,
            "genre": "ambient"
        },
        {
            "id": "test-wav-002",
            "name": "Test Bass Line.wav",
            "filename": "test-wav-002.wav",
            "type": "sample",
            "author": "Test Artist",
            "date": "2024-02-09",
            "description": "Test bass line",
            "rating": 7,
            "genre": "bass"
        },
        {
            "id": "test-flac-003",
            "name": "Unrated Demo.flac",
            "filename": "test-flac-003.flac",
            "type": "sample",
            "author": "Unknown",
            "date": "2024-02-09",
            "description": "Demo without rating",
            "rating": None,
            "genre": None
        }
    ]
   
    async with INDEX_LOCK:
        try:
            # Read existing
            index_data = await run_io(_read_json_sync, config["index"])
            if not isinstance(index_data, list):
                index_data = []
           
            # Add test samples (avoid duplicates)
            existing_ids = {item.get("id") for item in index_data}
            added = 0
            for sample in test_samples:
                if sample["id"] not in existing_ids:
                    index_data.insert(0, sample)
                    added += 1
           
            await run_io(_write_json_sync, config["index"], index_data)
            await cache.delete("library:sample")
            await cache.delete("library:all")
           
            return {"success": True, "added": added, "total": len(index_data)}
        except Exception as e:
            raise HTTPException(500, f"Failed to seed: {str(e)}")
@app.get("/api/health")
async def health_check():
    """Returns storage manager status and index counts."""
    status = {}
    for item_type, config in STORAGE_MAP.items():
        if item_type == "default":
            continue
        try:
            items = await run_io(_read_json_sync, config["index"])
            count = len(items) if isinstance(items, list) else 0
            status[item_type] = {"count": count, "status": "ok"}
        except Exception as e:
            status[item_type] = {"count": 0, "status": "error", "error": str(e)}
    return {"status": "online", "storage": status}
# --- 1. LISTING (Cached) ---
from enum import Enum
class SortBy(str, Enum):
    date = "date"
    rating = "rating"
    name = "name"
    last_played = "last_played"
    genre = "genre"

class ShaderCategory(str, Enum):
    # Main categories matching folder structure
    interactive = "interactive"
    generative = "generative"
    distortion = "distortion"
    image = "image"
    artistic = "artistic"
    retro_glitch = "retro-glitch"
    simulation = "simulation"
    geometric = "geometric"
    visual_effects = "visual-effects"
    liquid = "liquid"
    lighting = "lighting"
    
    # Legacy/alias categories for backward compatibility
    reactive = "reactive"
    transition = "transition"
    filter = "filter"
    # Additional categories found in JSON files
    tessellation = "tessellation"
    geometry = "geometry"
    warp = "warp"
    feedback = "feedback"
    shader = "shader"

# Category hierarchy for UI organization
CATEGORY_GROUPS = {
    "interactive": {
        "label": "🖱️ Interactive",
        "description": "Mouse and touch-driven effects",
        "subcategories": ["interactive"]
    },
    "generative": {
        "label": "✨ Generative",
        "description": "Procedural and algorithmic art",
        "subcategories": ["generative", "simulation"]
    },
    "distortion": {
        "label": "🔮 Distortion",
        "description": "Warp, bend, and transform space",
        "subcategories": ["distortion", "warp"]
    },
    "image": {
        "label": "🖼️ Image",
        "description": "Filters, color grading, and adjustments",
        "subcategories": ["image", "filter"]
    },
    "artistic": {
        "label": "🎨 Artistic",
        "description": "Stylized looks and painterly effects",
        "subcategories": ["artistic"]
    },
    "retro": {
        "label": "📺 Retro & Glitch",
        "description": "Vintage, analog, and digital corruption",
        "subcategories": ["retro-glitch", "glitch"]
    },
    "geometric": {
        "label": "📐 Geometric",
        "description": "Patterns, tessellation, and shapes",
        "subcategories": ["geometric", "tessellation", "geometry"]
    },
    "visual": {
        "label": "🎬 Visual Effects",
        "description": "Particles, glow, overlays, and VFX",
        "subcategories": ["visual-effects", "lighting"]
    },
    "liquid": {
        "label": "💧 Liquid",
        "description": "Fluid, water, oil, and viscous effects",
        "subcategories": ["liquid"]
    },
    "other": {
        "label": "🔧 Other",
        "description": "Miscellaneous and specialized effects",
        "subcategories": ["transition", "feedback", "shader", "reactive"]
    }
}
@app.get("/api/songs", response_model=List[MetaData])
async def list_library(
    type: Optional[str] = Query(None),
    sort_by: SortBy = Query(SortBy.date),
    sort_desc: bool = Query(True),
    genre: Optional[str] = Query(None),
    min_rating: Optional[int] = Query(None, ge=1, le=10)
):
    cache_key = f"library:{type or 'all'}:{sort_by}:{sort_desc}:{genre}:{min_rating}"
    cached = await cache.get(cache_key)
    if cached:
        return cached
    search_types = [type] if type else ["song", "pattern", "bank", "sample", "music", "shader"]
    results = []
    for t in search_types:
        config = STORAGE_MAP.get(t, STORAGE_MAP["default"])
        try:
            # Fetch index file from GCS
            items = await run_io(_read_json_sync, config["index"])
            if isinstance(items, list):
                results.extend(items)
        except Exception as e:
            print(f"Error listing {t}: {e}")
    # Filter by genre
    if genre:
        results = [r for r in results if r.get("genre") == genre]
    # Filter by min rating
    if min_rating is not None:
        results = [r for r in results if (r.get("rating") or 0) >= min_rating]
    # Sort results
    def sort_key(item):
        val = item.get(sort_by.value)
        if val is None:
            # None values go to the end
            return (1, "")
        return (0, val)
    results.sort(key=sort_key, reverse=sort_desc)
    await cache.set(cache_key, results, ttl=30)
    return results
# --- 2. UPLOAD JSON ---
@app.post("/api/songs")
async def upload_item(payload: ItemPayload):
    item_id = str(uuid.uuid4())
    date_str = datetime.now().strftime("%Y-%m-%d")
    item_type = payload.type if payload.type in STORAGE_MAP else "song"
    config = STORAGE_MAP[item_type]
    filename = f"{item_id}.json"
    full_path = f"{config['folder']}{filename}" # e.g., songs/uuid.json
    meta = {
        "id": item_id,
        "name": payload.name,
        "author": payload.author,
        "date": date_str,
        "type": item_type,
        "description": payload.description,
        "filename": filename,
        "rating": payload.rating
    }
    # Add meta to the actual data file too
    payload.data["_cloud_meta"] = meta
    async with INDEX_LOCK:
        try:
            # 1. Write the Data File
            await run_io(_write_json_sync, full_path, payload.data)
            # 2. Update the Index
            def _update_index():
                current = _read_json_sync(config["index"])
                current.insert(0, meta)
                _write_json_sync(config["index"], current)
            await run_io(_update_index)
            # Clear cache
            await cache.clear()
            return {"success": True, "id": item_id}
        except Exception as e:
            raise HTTPException(500, f"Upload failed: {str(e)}")
# --- 2.5 UPDATE JSON (PUT) ---
@app.put("/api/songs/{item_id}")
async def update_item(item_id: str, payload: ItemPayload):
    # Verify type configuration
    item_type = payload.type if payload.type in STORAGE_MAP else "song"
    config = STORAGE_MAP[item_type]
    # Assume filename is {id}.json (standard convention for this app)
    filename = f"{item_id}.json"
    full_path = f"{config['folder']}{filename}"
    # We preserve the original ID but update other metadata
    # Note: 'date' field in metadata is typically 'created_at'.
    # We could add an 'updated_at' field if needed, but for now we keep 'date' as is or update it?
    # Usually you don't change the creation date.
    # We will fetch the original creation date if possible, or just use current if not found.
    # However, to avoid complexity, we'll just update the metadata entry in the index.
    # Use current date as 'last updated' effectively?
    date_str = datetime.now().strftime("%Y-%m-%d")
    # Or should we try to preserve original date?
    # Let's try to preserve it by reading the index first.
    new_meta = {
        "id": item_id,
        "name": payload.name,
        "author": payload.author,
        "date": date_str, # Defaulting to now if not found
        "type": item_type,
        "description": payload.description,
        "filename": filename,
        "rating": payload.rating
    }
    # Add meta to data
    payload.data["_cloud_meta"] = new_meta
    async with INDEX_LOCK:
        try:
            # 1. Check if file exists (optional, but good for 404)
            # blob = bucket.blob(full_path)
            # if not await run_io(blob.exists):
            # raise HTTPException(404, "Item not found")
            # 2. Write the Data File (Overwrite)
            await run_io(_write_json_sync, full_path, payload.data)
            # 3. Update the Index
            def _update_index_logic():
                current = _read_json_sync(config["index"])
                if not isinstance(current, list):
                    current = []
                # Find and remove existing entry for this ID
                # Also, capture the original date if possible to preserve "Created Date" behavior
                # But user might want "Updated Date". Let's stick to updating it to "now" so it bubbles to top.
                existing_index = next((i for i, item in enumerate(
                    current) if item.get("id") == item_id), -1)
                if existing_index != -1:
                    # Preserve original creation date if desired, but user wants 'latest' usually.
                    # Let's keep it simple: Remove old, insert new at top (Fresh Update)
                    current.pop(existing_index)
                current.insert(0, new_meta)
                _write_json_sync(config["index"], current)
            await run_io(_update_index_logic)
            # Clear cache
            await cache.clear()
            return {"success": True, "id": item_id, "action": "updated"}
        except Exception as e:
            raise HTTPException(500, f"Update failed: {str(e)}")
# --- 3. FETCH METADATA (without full data) ---
@app.get("/api/songs/{item_id}/meta")
async def get_item_metadata(item_id: str, type: Optional[str] = Query(None)):
    """
    Returns only the metadata for an item without the full data payload.
    Much faster for listing/details views.
    """
    search_types = [type] if type else ["song", "pattern", "bank"]
   
    for t in search_types:
        config = STORAGE_MAP.get(t)
        if not config:
            continue
           
        # Read from index (much faster than fetching full file)
        index_data = await run_io(_read_json_sync, config["index"])
       
        if isinstance(index_data, list):
            entry = next((item for item in index_data if item.get("id") == item_id), None)
            if entry:
                return entry
   
    raise HTTPException(404, "Item not found")
# --- 3.5 FETCH JSON ITEM ---
@app.get("/api/songs/{item_id}")
async def get_item(item_id: str, type: Optional[str] = Query(None)):
    # Try to find the file
    search_types = [type] if type else ["song", "pattern", "bank"]
    for t in search_types:
        config = STORAGE_MAP.get(t)
        filepath = f"{config['folder']}{item_id}.json"
        # Check existence efficiently
        blob = bucket.blob(filepath)
        exists = await run_io(blob.exists)
        if exists:
            data = await run_io(blob.download_as_text)
            return json.loads(data)
    raise HTTPException(404, "Item not found")
# --- 4. STREAMING SAMPLES (Upload & Download) ---
@app.post("/api/samples")
async def upload_sample(
    file: UploadFile = File(...),
    author: str = Form(...),
    description: str = Form(""),
    rating: Optional[int] = Form(None)
):
    sample_id = str(uuid.uuid4())
    ext = os.path.splitext(file.filename)[1]
    storage_filename = f"{sample_id}{ext}"
    config = STORAGE_MAP["sample"]
    full_path = f"{config['folder']}{storage_filename}"
    meta = {
        "id": sample_id,
        "name": file.filename,
        "author": author,
        "date": datetime.now().strftime("%Y-%m-%d"),
        "type": "sample",
        "description": description,
        "filename": storage_filename,
        "rating": rating
    }
    async with INDEX_LOCK:
        try:
            # 1. Stream Upload to GCS
            blob = bucket.blob(full_path)
            # GCS Python client doesn't support async streaming upload easily out of the box,
            # but upload_from_file is efficient.
            # We wrap the spooled temp file from FastAPI
            await run_io(blob.upload_from_file, file.file, content_type=file.content_type)
            # 2. Update Index
            def _update_idx():
                idx = _read_json_sync(config["index"])
                idx.insert(0, meta)
                _write_json_sync(config["index"], idx)
            await run_io(_update_idx)
            await cache.delete("library:sample")
            return {"success": True, "id": sample_id}
        except Exception as e:
            raise HTTPException(500, str(e))
@app.get("/api/samples/{sample_id}")
async def get_sample(sample_id: str):
    config = STORAGE_MAP["sample"]
    # 1. Lookup in Index (to get original filename/extension)
    idx = await run_io(_read_json_sync, config["index"])
    entry = next((i for i in idx if i["id"] == sample_id), None)
    if not entry:
        raise HTTPException(404, "Sample not found in index")
    blob_path = f"{config['folder']}{entry['filename']}"
    blob = bucket.blob(blob_path)
    if not await run_io(blob.exists):
        raise HTTPException(404, "File missing from storage")
    # 2. Stream Download
    # GCS blob.open() returns a file-like object we can stream
    def iterfile():
        with blob.open("rb") as f:
            while chunk := f.read(1024 * 1024): # 1MB chunks
                yield chunk
    return StreamingResponse(
        iterfile(),
        media_type="application/octet-stream",
        headers={
            "Content-Disposition": f"attachment; filename={entry['name']}"}
    )
# --- 4.4 RECORD PLAY ---
@app.post("/api/samples/{sample_id}/play")
async def record_play(sample_id: str):
    """Records that a sample was played by updating last_played timestamp."""
    config = STORAGE_MAP["sample"]
    index_path = config["index"]
    now = datetime.now().isoformat()
    async with INDEX_LOCK:
        try:
            index_data = await run_io(_read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(status_code=500, detail="Sample index is corrupted.")
            entry = next((item for item in index_data if item.get("id") == sample_id), None)
            if not entry:
                raise HTTPException(status_code=404, detail="Sample not found.")
            entry["last_played"] = now
            await run_io(_write_json_sync, index_path, index_data)
           
            await cache.delete("library:sample")
            await cache.delete("library:all")
            return {"success": True, "id": sample_id, "last_played": now}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to record play for {sample_id}: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to record play: {str(e)}")
# --- 4.5 UPDATE SAMPLE METADATA ---
class SampleMetaUpdatePayload(BaseModel):
    """Payload for updating a sample's metadata."""
    name: Optional[str] = None
    description: Optional[str] = None
    rating: Optional[int] = Field(
        None, ge=1, le=10, description="A rating from 1 to 10.")
    genre: Optional[str] = None
    last_played: Optional[str] = None # ISO timestamp
@app.put("/api/samples/{sample_id}")
async def update_sample_metadata(sample_id: str, payload: SampleMetaUpdatePayload):
    """
    Updates the metadata (name, description, rating) for a sample (e.g., a FLAC file).
    This only modifies the JSON index, not the audio file itself.
    """
    config = STORAGE_MAP["sample"]
    index_path = config["index"]
    async with INDEX_LOCK:
        try:
            # 1. Read the index
            index_data = await run_io(_read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(
                    status_code=500, detail="Sample index is corrupted.")
            # 2. Find the item and its index
            entry_index = next((i for i, item in enumerate(
                index_data) if item.get("id") == sample_id), -1)
            if entry_index == -1:
                raise HTTPException(
                    status_code=404, detail="Sample not found in index.")
            entry = index_data[entry_index]
            update_happened = False
            # 3. Update metadata fields if provided in the payload
            if payload.name is not None and payload.name != entry.get("name"):
                entry["name"] = payload.name
                update_happened = True
            if payload.description is not None and payload.description != entry.get("description"):
                entry["description"] = payload.description
                update_happened = True
            if payload.rating is not None and payload.rating != entry.get("rating"):
                entry["rating"] = payload.rating
                update_happened = True
            if payload.genre is not None and payload.genre != entry.get("genre"):
                entry["genre"] = payload.genre
                update_happened = True
            if payload.last_played is not None and payload.last_played != entry.get("last_played"):
                entry["last_played"] = payload.last_played
                update_happened = True
            if not update_happened:
                return {"success": True, "id": sample_id, "action": "no_change", "message": "No new data provided to update."}
            # 4. Write the updated index back to GCS
            await run_io(_write_json_sync, index_path, index_data)
            # 5. Clear relevant cache
            await cache.delete("library:sample")
            await cache.delete("library:all")
            return {"success": True, "id": sample_id, "action": "metadata_updated"}
        except HTTPException:
            raise # Re-raise FastAPI exceptions
        except Exception as e:
            logging.error(
                f"Failed to update sample metadata for {sample_id}: {e}")
            raise HTTPException(
                status_code=500, detail=f"Failed to update sample metadata: {str(e)}")
# --- 4.6 MUSIC ENDPOINTS ---
@app.get("/api/music/{music_id}")
async def get_music_file(music_id: str):
    """Streams a music file from the music folder."""
    config = STORAGE_MAP["music"]
   
    # 1. Lookup in Index
    idx = await run_io(_read_json_sync, config["index"])
    entry = next((i for i in idx if i["id"] == music_id), None)
   
    if not entry:
        raise HTTPException(404, "Music track not found in index")
   
    blob_path = f"{config['folder']}{entry['filename']}"
    blob = bucket.blob(blob_path)
   
    if not await run_io(blob.exists):
        raise HTTPException(404, "File missing from storage")
   
    # 2. Stream Download
    def iterfile():
        with blob.open("rb") as f:
            while chunk := f.read(1024 * 1024): # 1MB chunks
                yield chunk
   
    # Determine content type
    lower_name = entry['filename'].lower()
    if lower_name.endswith('.flac'):
        media_type = 'audio/flac'
    elif lower_name.endswith('.wav'):
        media_type = 'audio/wav'
    elif lower_name.endswith('.mp3'):
        media_type = 'audio/mpeg'
    else:
        media_type = 'audio/mpeg'
   
    return StreamingResponse(
        iterfile(),
        media_type=media_type,
        headers={"Content-Disposition": f'inline; filename="{entry["name"]}"'}
    )
@app.put("/api/music/{music_id}")
async def update_music_metadata(music_id: str, payload: SampleMetaUpdatePayload):
    """Updates metadata for a music track."""
    config = STORAGE_MAP["music"]
    index_path = config["index"]
   
    async with INDEX_LOCK:
        try:
            index_data = await run_io(_read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(status_code=500, detail="Music index is corrupted.")
           
            entry_index = next((i for i, item in enumerate(index_data) if item.get("id") == music_id), -1)
            if entry_index == -1:
                raise HTTPException(status_code=404, detail="Music track not found.")
           
            entry = index_data[entry_index]
            update_happened = False
           
            if payload.name is not None and payload.name != entry.get("name"):
                entry["name"] = payload.name
                update_happened = True
            if payload.rating is not None and payload.rating != entry.get("rating"):
                entry["rating"] = payload.rating
                update_happened = True
            if payload.genre is not None and payload.genre != entry.get("genre"):
                entry["genre"] = payload.genre
                update_happened = True
            if payload.last_played is not None and payload.last_played != entry.get("last_played"):
                entry["last_played"] = payload.last_played
                update_happened = True
            if payload.description is not None and payload.description != entry.get("description"):
                entry["description"] = payload.description
                update_happened = True
           
            if update_happened:
                await run_io(_write_json_sync, index_path, index_data)
                await cache.delete("library:music")
                await cache.delete("library:all")
           
            return {"success": True, "id": music_id, "action": "metadata_updated" if update_happened else "no_change"}
           
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update music metadata: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to update: {str(e)}")
# --- 5. SMART SYNC (The "Magic" Button) ---
from pydantic import Field
from typing import Optional, List
class MetaPatch(BaseModel):
    name: Optional[str] = None
    rating: Optional[int] = Field(None, ge=0, le=10)
    genre: Optional[str] = None
    tags: Optional[List[str]] = None # full list (replace)
    last_played: Optional[str] = None # ISO string
@app.patch("/api/songs/{item_id}")
async def patch_song(item_id: str, patch: MetaPatch):
    config = STORAGE_MAP["song"] # ← FIXED HERE: was "songs", now "song"
    index_path = config["index"]
    async with INDEX_LOCK:
        try:
            index: list = await run_io(_read_json_sync, index_path)
            if not isinstance(index, list):
                index = []
            # Find by id
            entry = next((e for e in index if e.get("id") == item_id), None)
            if not entry:
                raise HTTPException(status_code=404, detail="Song not found")
            changes = patch.model_dump(exclude_unset=True)
            if not changes:
                return {"status": "no-op", "message": "Nothing to update"}
            updated = {}
            for field, value in changes.items():
                if field == "tags":
                    entry["tags"] = value if value is not None else []
                else:
                    entry[field] = value
                updated[field] = entry[field]
            await run_io(_write_json_sync, index_path, index)
            await cache.clear() # or cache.delete("library:songs") for precision
            return {
                "status": "success",
                "item_id": item_id,
                "updated": updated
            }
        except Exception as e:
            logging.error(f"PATCH /songs/{item_id} failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))
           
@app.post("/api/admin/sync")
async def sync_gcs_storage():
    """
    Scans Google Cloud Storage to rebuild JSON indexes based on actual files.
    """
    report = {}
    async with INDEX_LOCK:
        for item_type, config in STORAGE_MAP.items():
            if item_type == "default" or item_type == "music":
                continue # Skip music in default sync, handle separately
            added = 0
            removed = 0
            try:
                # 1. List ALL objects in this folder prefix
                # prefix="songs/" returns "songs/123.json", "songs/456.json", etc.
                blobs = await run_io(lambda: list(bucket.list_blobs(prefix=config["folder"])))
                # Filter out the index file itself
                actual_files = []
                for b in blobs:
                    # Remove the folder prefix to get just filename (e.g., "123.json")
                    fname = b.name.replace(config["folder"], "")
                    # Ensure it's not the index file
                    if fname and not b.name.endswith(config["index"]):
                        actual_files.append(fname)
                # 2. Get Current Index
                index_data = await run_io(_read_json_sync, config["index"])
                # 3. Compare
                index_map = {item["filename"]: item for item in index_data}
                disk_set = set(actual_files)
                # Find Ghosts (In Index, Not on Disk)
                new_index = []
                for item in index_data:
                    if item["filename"] in disk_set:
                        new_index.append(item)
                    else:
                        removed += 1
                # Find Orphans (On Disk, Not in Index)
                for filename in actual_files:
                    if filename not in index_map:
                        # Create new entry
                        new_entry = {
                            # Generate new ID or parse from filename if possible
                            "id": str(uuid.uuid4()),
                            "filename": filename,
                            "type": item_type,
                            "date": datetime.now().strftime("%Y-%m-%d"),
                            "name": filename,
                            "author": "Unknown",
                            "description": "Auto-discovered via Sync",
                            "genre": None,
                            "last_played": None
                        }
                        # If JSON, peek inside for metadata
                        if filename.endswith(".json") and item_type in ["song", "pattern", "bank"]:
                            try:
                                b = bucket.blob(
                                    f"{config['folder']}{filename}")
                                content = json.loads(b.download_as_text())
                                if "name" in content:
                                    new_entry["name"] = content["name"]
                                if "author" in content:
                                    new_entry["author"] = content["author"]
                            except:
                                pass
                        new_index.insert(0, new_entry)
                        added += 1
                # 4. Save if changed
                if added > 0 or removed > 0:
                    await run_io(_write_json_sync, config["index"], new_index)
                report[item_type] = {"added": added,
                                     "removed": removed, "status": "synced"}
            except Exception as e:
                report[item_type] = {"error": str(e)}
        await cache.clear()
        return report
async def load_metadata(shader_id: str):
    config = STORAGE_MAP["shader"]
    meta_path = f"{config['folder']}{shader_id}/metadata.json"
    try:
        meta = await run_io(_read_json_sync, meta_path)
        if not meta:
            # Fallback: Search in main index
            index = await run_io(_read_json_sync, config["index"])
            meta = next((item for item in index if item["id"] == shader_id), {})
        # Defaults
        meta.setdefault("stars", 0.0)
        meta.setdefault("rating_count", 0)
        meta.setdefault("thumbnail", "")  # For future previews
        return meta
    except Exception as e:
        raise HTTPException(404, f"Shader {shader_id} not found: {str(e)}")
async def save_metadata(shader_id: str, meta: dict):
    config = STORAGE_MAP["shader"]
    meta_path = f"{config['folder']}{shader_id}/metadata.json"
    try:
        await run_io(_write_json_sync, meta_path, meta)
        # Also update main index (optional, for consistency)
        async with INDEX_LOCK:
            index = await run_io(_read_json_sync, config["index"])
            for i, item in enumerate(index):
                if item["id"] == shader_id:
                    index[i].update({
                        "stars": meta["stars"],
                        "rating_count": meta["rating_count"],
                        "description": meta.get("description", ""),
                        # Add more fields as needed
                    })
                    break
            else:  # New entry
                index.insert(0, {
                    "id": shader_id,
                    "name": meta.get("name", shader_id),
                    "stars": meta["stars"],
                    "rating_count": meta["rating_count"],
                    "description": meta.get("description", ""),
                    # Defaults...
                })
            await run_io(_write_json_sync, config["index"], index)
        await cache.delete(f"shader:{shader_id}")
        await cache.delete("shaders:list")
    except Exception as e:
        raise HTTPException(500, f"Failed to save metadata: {str(e)}")
# --- SHADER ENDPOINTS ---
@app.get("/api/shaders/{shader_id}")
async def get_shader_meta(shader_id: str):
    return await load_metadata(shader_id)
@app.post("/api/shaders/{shader_id}/rate")
async def rate_shader(shader_id: str, stars: float = Form(...)):  # 1.0–5.0
    if not 1 <= stars <= 5:
        raise HTTPException(400, "Stars must be between 1 and 5")
    meta = await load_metadata(shader_id)
    meta["stars"] = (meta["stars"] * meta["rating_count"] + stars) / (meta["rating_count"] + 1)
    meta["rating_count"] += 1
    await save_metadata(shader_id, meta)
    return meta
@app.post("/api/shaders/{shader_id}/update")
async def update_shader_meta(shader_id: str, description: str = Form(None), tags: str = Form(None)):
    meta = await load_metadata(shader_id)
    if description:
        meta["description"] = description
    if tags:
        meta["tags"] = [t.strip() for t in tags.split(",")]
    await save_metadata(shader_id, meta)
    return meta

@app.get("/api/shaders/{shader_id}/code")
async def get_shader_code(shader_id: str):
    """Returns the actual .wgsl shader code."""
    config = STORAGE_MAP["shader"]
    meta = await load_metadata(shader_id)
    blob_path = f"{config['folder']}{meta['filename']}"
    blob = bucket.blob(blob_path)
    
    if not await run_io(blob.exists):
        raise HTTPException(404, "Shader file not found")
    
    code = await run_io(blob.download_as_text)
    return {"id": shader_id, "code": code, "name": meta.get("name")}

@app.get("/api/shaders")
async def list_shaders(
    category: Optional[ShaderCategory] = Query(None),
    min_stars: float = Query(0.0, ge=0, le=5),
    sort_by: SortBy = Query(SortBy.rating)
):
    """List shaders with optional category filter.
    
    Category filtering checks:
    1. Exact match on category field
    2. Match in tags array
    3. For group categories, matches any subcategory
    """
    cache_key = f"shaders:list:{category}:{min_stars}:{sort_by}"
    cached = await cache.get(cache_key)
    if cached:
        return cached
    config = STORAGE_MAP["shader"]
    try:
        index = await run_io(_read_json_sync, config["index"])
        if not isinstance(index, list):
            index = []
        
        # Filters
        if category:
            cat_value = category.value
            # Get subcategories if this is a group category
            subcats = CATEGORY_GROUPS.get(cat_value, {}).get("subcategories", [cat_value])
            
            def matches_category(shader):
                # Check category field
                shader_cat = shader.get("category", "")
                if shader_cat in subcats:
                    return True
                # Check tags
                tags = shader.get("tags", [])
                if any(tag in subcats for tag in tags):
                    return True
                # Check description for category keywords
                desc = shader.get("description", "").lower()
                return any(subcat.lower() in desc for subcat in subcats)
            
            index = [s for s in index if matches_category(s)]
        
        if min_stars > 0:
            index = [s for s in index if s.get("stars", 0) >= min_stars]
        
        # Sort
        reverse = sort_by in ["rating", "date"]
        if sort_by == "rating":
            index.sort(key=lambda s: s.get("stars", 0), reverse=reverse)
        elif sort_by == "date":
            index.sort(key=lambda s: s.get("date", ""), reverse=reverse)
        elif sort_by == "name":
            index.sort(key=lambda s: s.get("name", "").lower())
        
        await cache.set(cache_key, index, ttl=300)
        return index
    except Exception as e:
        raise HTTPException(500, f"Failed to list shaders: {str(e)}")


@app.get("/api/shaders/categories")
async def list_categories():
    """Return the category hierarchy for UI rendering."""
    return {
        "groups": CATEGORY_GROUPS,
        "all_categories": [c.value for c in ShaderCategory]
    }
@app.post("/api/shaders/upload")
async def upload_shader(
    file: UploadFile = File(...),  # The .wgsl file
    name: str = Form(...),
    description: str = Form(""),
    tags: str = Form(""),  # Comma-separated
    author: str = Form("ford442")
):
    if not file.filename.endswith(".wgsl"):
        raise HTTPException(400, "Only .wgsl files allowed")
    
    shader_id = str(uuid.uuid4())
    storage_filename = f"{shader_id}.wgsl"
    config = STORAGE_MAP["shader"]
    full_path = f"{config['folder']}{storage_filename}"
    
    meta = {
        "id": shader_id,
        "name": name,
        "author": author,
        "date": datetime.now().strftime("%Y-%m-%d"),
        "description": description,
        "tags": [t.strip() for t in tags.split(",")] if tags else [],
        "filename": storage_filename,
        "stars": 0.0,
        "rating_count": 0
    }
    
    async with INDEX_LOCK:
        try:
            # 1. Upload the .wgsl file
            blob = bucket.blob(full_path)
            await run_io(blob.upload_from_file, file.file, content_type="text/plain")
            
            # 2. Save metadata.json
            await save_metadata(shader_id, meta)
            
            # Clear list cache
            await cache.delete("shaders:list")
            
            return {"success": True, "id": shader_id, "meta": meta}
        except Exception as e:
            raise HTTPException(500, f"Shader upload failed: {str(e)}")
   
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=7860)
