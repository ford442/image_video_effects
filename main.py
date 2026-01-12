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
from fastapi.responses import StreamingResponse, Response
from pydantic import BaseModel
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
    "song":     {"folder": "songs/",    "index": "songs/_songs.json"},
    "pattern":  {"folder": "patterns/", "index": "patterns/_patterns.json"},
    "bank":     {"folder": "banks/",    "index": "banks/_banks.json"},
    "sample":   {"folder": "samples/",  "index": "samples/_samples.json"},
    "note":     {"folder": "notes/",    "index": "notes/_notes.json"},
    "image":    {"folder": "images/",   "index": "images/_images.json"},
    "default":  {"folder": "misc/",     "index": "misc/_misc.json"}
}

# --- GLOBAL OBJECTS ---
gcs_client = None
bucket = None
io_executor = ThreadPoolExecutor(max_workers=20) # GCS handles high concurrency well
cache = Cache(Cache.MEMORY)
INDEX_LOCK = asyncio.Lock() # Prevents race conditions during index writes

# --- HELPERS ---

def get_gcs_client():
    """Initializes the GCS Client from environment variable string or file"""
    if CREDENTIALS_JSON:
        # Load credentials from the JSON string stored in secrets
        cred_info = json.loads(CREDENTIALS_JSON)
        creds = service_account.Credentials.from_service_account_info(cred_info)
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
    "http://localhost:3000",       # For your local testing
    "https://test.1ink.us", # &lt;--- REPLACE THIS with your actual site
    "https://go.1ink.us", # &lt;--- REPLACE THIS with your actual site
    "https://noahcohn.com", # &lt;--- REPLACE THIS with your actual site
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
    #    This handles cases where user types "song" but folder is "songs/"
    config = STORAGE_MAP.get(folder)
    prefix = config["folder"] if config else f"{folder}/"
    
    try:
        # 2. Run GCS List Blobs in a thread (to keep server fast)
        def _fetch_blobs():
            # 'delimiter' makes it behave like a folder (doesn't show sub-sub-files)
            blobs = bucket.list_blobs(prefix=prefix, delimiter="/")
            
            file_list = []
            for blob in blobs:
                # Remove the folder prefix (e.g. "songs/beat1.json" -&gt; "beat1.json")
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

class MetaData(BaseModel):
    id: str
    name: str
    author: str
    date: str
    type: str
    description: Optional[str] = ""
    filename: str
    url: Optional[str] = None

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

# --- 1. LISTING (Cached) ---
@app.get("/api/songs", response_model=List[MetaData])
async def list_library(type: Optional[str] = Query(None)):
    cache_key = f"library:{type or 'all'}"
    cached = await cache.get(cache_key)
    if cached: return cached

    search_types = [type] if type else ["song", "pattern", "bank", "image"]
    results = []

    for t in search_types:
        config = STORAGE_MAP.get(t, STORAGE_MAP["default"])
        try:
            # Fetch index file from GCS
            items = await run_io(_read_json_sync, config["index"])
            if isinstance(items, list):
                for item in items:
                    # Construct the public URL for each item
                    item['url'] = f"https://storage.googleapis.com/{BUCKET_NAME}/{config['folder']}{item['filename']}"
                results.extend(items)
        except Exception as e:
            print(f"Error listing {t}: {e}")

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
        "filename": filename 
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

# --- 3. FETCH JSON ITEM ---
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
async def upload_sample(file: UploadFile = File(...), author: str = Form(...), description: str = Form("")):
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
        "filename": storage_filename
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
        headers={"Content-Disposition": f"attachment; filename={entry['name']}"}
    )

@app.get("/image_suggestions.md")
async def get_suggestions():
    try:
        # We are assuming the python server is run from the root of the project
        with open("public/image_suggestions.md", "r") as f:
            content = f.read()
        return Response(content=content, media_type="text/markdown")
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="File not found")

# --- 5. SMART SYNC (The "Magic" Button) ---

@app.post("/api/admin/sync")
async def sync_gcs_storage():
    """
    Scans Google Cloud Storage to rebuild JSON indexes based on actual files.
    """
    report = {}
    
    async with INDEX_LOCK:
        for item_type, config in STORAGE_MAP.items():
            if item_type == "default": continue

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
                    if fname and not b.name.endswith(config["index"]): # Ensure it's not the index file
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
                            "id": str(uuid.uuid4()), # Generate new ID or parse from filename if possible
                            "filename": filename,
                            "type": item_type,
                            "date": datetime.now().strftime("%Y-%m-%d"),
                            "name": filename,
                            "author": "Unknown",
                            "description": "Auto-discovered via Sync"
                        }

                        # If JSON, peek inside for metadata
                        if filename.endswith(".json") and item_type in ["song", "pattern", "bank"]:
                            try:
                                b = bucket.blob(f"{config['folder']}{filename}")
                                content = json.loads(b.download_as_text())
                                if "name" in content: new_entry["name"] = content["name"]
                                if "author" in content: new_entry["author"] = content["author"]
                            except: pass

                        new_index.insert(0, new_entry)
                        added += 1

                # 4. Save if changed
                if added > 0 or removed > 0:
                    await run_io(_write_json_sync, config["index"], new_index)

                report[item_type] = {"added": added, "removed": removed, "status": "synced"}

            except Exception as e:
                report[item_type] = {"error": str(e)}

        await cache.clear()
        return report

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=7860)
