# scripts/storage_manager_app/media.py
import datetime
import json
import logging
import os
import uuid
from typing import List, Optional

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse

from .config import (
    INDEX_LOCK,
    STORAGE_MAP,
    ItemPayload,
    MetaData,
    MetaPatch,
    SampleMetaUpdatePayload,
    SortBy,
    _read_json_sync,
    _write_json_sync,
    bucket,
    cache,
    run_io,
)

router = APIRouter()


# ========================= SONGS =========================

@router.get("/api/songs", response_model=List[MetaData])
async def list_library(
    type: Optional[str] = Query(None),
    genre: Optional[str] = Query(None),
    min_rating: Optional[int] = Query(None, ge=1, le=10),
    sort_by: SortBy = Query(SortBy.date),
    sort_desc: bool = Query(True)
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
            items = await run_io(_read_json_sync, config["index"])
            if isinstance(items, list):
                results.extend(items)
        except Exception as e:
            logging.error(f"Error listing {t}: {e}")

    if genre:
        results = [r for r in results if r.get("genre") == genre]
    if min_rating is not None:
        results = [r for r in results if (r.get("rating") or 0) >= min_rating]

    def sort_key(item):
        val = item.get(sort_by.value)
        return (0, val) if val is not None else (1, "")

    results.sort(key=sort_key, reverse=sort_desc)
    await cache.set(cache_key, results, ttl=30)
    return results


@router.post("/api/songs")
async def upload_item(payload: ItemPayload):
    item_id = str(uuid.uuid4())
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")
    item_type = payload.type if payload.type in STORAGE_MAP else "song"
    config = STORAGE_MAP[item_type]
    filename = f"{item_id}.json"
    full_path = f"{config['folder']}{filename}"

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

    payload.data["_cloud_meta"] = meta

    async with INDEX_LOCK:
        try:
            await run_io(_write_json_sync, full_path, payload.data)

            def _update_index():
                current = _read_json_sync(config["index"])
                current.insert(0, meta)
                _write_json_sync(config["index"], current)

            await run_io(_update_index)
            await cache.clear()
            return {"success": True, "id": item_id}
        except Exception as e:
            raise HTTPException(500, f"Upload failed: {str(e)}")


@router.put("/api/songs/{item_id}")
async def update_item(item_id: str, payload: ItemPayload):
    item_type = payload.type if payload.type in STORAGE_MAP else "song"
    config = STORAGE_MAP[item_type]
    filename = f"{item_id}.json"
    full_path = f"{config['folder']}{filename}"
    date_str = datetime.datetime.now().strftime("%Y-%m-%d")

    new_meta = {
        "id": item_id,
        "name": payload.name,
        "author": payload.author,
        "date": date_str,
        "type": item_type,
        "description": payload.description,
        "filename": filename,
        "rating": payload.rating
    }

    payload.data["_cloud_meta"] = new_meta

    async with INDEX_LOCK:
        try:
            await run_io(_write_json_sync, full_path, payload.data)

            def _update_index_logic():
                current = _read_json_sync(config["index"])
                if not isinstance(current, list):
                    current = []
                existing_index = next((i for i, item in enumerate(current) if item.get("id") == item_id), -1)
                if existing_index != -1:
                    current.pop(existing_index)
                current.insert(0, new_meta)
                _write_json_sync(config["index"], current)

            await run_io(_update_index_logic)
            await cache.clear()
            return {"success": True, "id": item_id, "action": "updated"}
        except Exception as e:
            raise HTTPException(500, f"Update failed: {str(e)}")


@router.get("/api/songs/{item_id}/meta")
async def get_item_metadata(item_id: str, type: Optional[str] = Query(None)):
    search_types = [type] if type else ["song", "pattern", "bank"]
    for t in search_types:
        config = STORAGE_MAP.get(t)
        if not config:
            continue
        index_data = await run_io(_read_json_sync, config["index"])
        if isinstance(index_data, list):
            entry = next((item for item in index_data if item.get("id") == item_id), None)
            if entry:
                return entry
    raise HTTPException(404, "Item not found")


@router.get("/api/songs/{item_id}")
async def get_item(item_id: str, type: Optional[str] = Query(None)):
    search_types = [type] if type else ["song", "pattern", "bank"]
    for t in search_types:
        config = STORAGE_MAP.get(t)
        filepath = f"{config['folder']}{item_id}.json"
        blob = bucket.blob(filepath)
        exists = await run_io(blob.exists)
        if exists:
            data = await run_io(blob.download_as_text)
            return json.loads(data)
    raise HTTPException(404, "Item not found")


@router.patch("/api/songs/{item_id}")
async def patch_song(item_id: str, patch: MetaPatch):
    config = STORAGE_MAP["song"]
    index_path = config["index"]

    async with INDEX_LOCK:
        try:
            index = await run_io(_read_json_sync, index_path)
            if not isinstance(index, list):
                index = []

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
            await cache.clear()

            return {"status": "success", "item_id": item_id, "updated": updated}
        except Exception as e:
            logging.error(f"PATCH /songs/{item_id} failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))


# ========================= SAMPLES =========================

@router.post("/api/samples")
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
        "date": datetime.datetime.now().strftime("%Y-%m-%d"),
        "type": "sample",
        "description": description,
        "filename": storage_filename,
        "rating": rating
    }

    async with INDEX_LOCK:
        try:
            blob = bucket.blob(full_path)
            await run_io(blob.upload_from_file, file.file, content_type=file.content_type)

            def _update_idx():
                idx = _read_json_sync(config["index"])
                idx.insert(0, meta)
                _write_json_sync(config["index"], idx)

            await run_io(_update_idx)
            await cache.delete("library:sample")
            return {"success": True, "id": sample_id}
        except Exception as e:
            raise HTTPException(500, str(e))


@router.get("/api/samples/{sample_id}")
async def get_sample(sample_id: str):
    config = STORAGE_MAP["sample"]
    idx = await run_io(_read_json_sync, config["index"])
    entry = next((i for i in idx if i["id"] == sample_id), None)
    if not entry:
        raise HTTPException(404, "Sample not found")

    blob_path = f"{config['folder']}{entry['filename']}"
    blob = bucket.blob(blob_path)
    if not await run_io(blob.exists):
        raise HTTPException(404, "File missing")

    def iterfile():
        with blob.open("rb") as f:
            while chunk := f.read(1024 * 1024):
                yield chunk

    return StreamingResponse(
        iterfile(),
        media_type="application/octet-stream",
        headers={"Content-Disposition": f"attachment; filename={entry['name']}"}
    )


@router.post("/api/samples/{sample_id}/play")
async def record_play(sample_id: str):
    config = STORAGE_MAP["sample"]
    index_path = config["index"]
    now = datetime.datetime.now().isoformat()

    async with INDEX_LOCK:
        try:
            index_data = await run_io(_read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(500, "Index corrupted")

            entry = next((item for item in index_data if item.get("id") == sample_id), None)
            if not entry:
                raise HTTPException(404, "Sample not found")

            entry["last_played"] = now
            await run_io(_write_json_sync, index_path, index_data)
            await cache.delete("library:sample")
            await cache.delete("library:all")

            return {"success": True, "id": sample_id, "last_played": now}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to record play: {e}")
            raise HTTPException(500, f"Failed: {str(e)}")


@router.put("/api/samples/{sample_id}")
async def update_sample_metadata(sample_id: str, payload: SampleMetaUpdatePayload):
    config = STORAGE_MAP["sample"]
    index_path = config["index"]

    async with INDEX_LOCK:
        try:
            index_data = await run_io(_read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(500, "Index corrupted")

            entry_idx = next((i for i, item in enumerate(index_data) if item.get("id") == sample_id), -1)
            if entry_idx == -1:
                raise HTTPException(404, "Sample not found")

            entry = index_data[entry_idx]
            update_happened = False

            if payload.name is not None and payload.name != entry.get("name"):
                entry["name"] = payload.name
                update_happened = True
            if payload.description is not None:
                entry["description"] = payload.description
                update_happened = True
            if payload.rating is not None:
                entry["rating"] = payload.rating
                update_happened = True
            if payload.genre is not None:
                entry["genre"] = payload.genre
                update_happened = True
            if payload.last_played is not None:
                entry["last_played"] = payload.last_played
                update_happened = True

            if update_happened:
                await run_io(_write_json_sync, index_path, index_data)
                await cache.delete("library:sample")
                await cache.delete("library:all")

            return {"success": True, "id": sample_id, "action": "metadata_updated" if update_happened else "no_change"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update sample: {e}")
            raise HTTPException(500, f"Failed: {str(e)}")


# ========================= MUSIC =========================

@router.get("/api/music/{music_id}")
async def get_music_file(music_id: str):
    config = STORAGE_MAP["music"]
    idx = await run_io(_read_json_sync, config["index"])
    entry = next((i for i in idx if i["id"] == music_id), None)
    if not entry:
        raise HTTPException(404, "Music not found")

    blob_path = f"{config['folder']}{entry['filename']}"
    blob = bucket.blob(blob_path)
    if not await run_io(blob.exists):
        raise HTTPException(404, "File missing")

    def iterfile():
        with blob.open("rb") as f:
            while chunk := f.read(1024 * 1024):
                yield chunk

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


@router.put("/api/music/{music_id}")
async def update_music_metadata(music_id: str, payload: SampleMetaUpdatePayload):
    config = STORAGE_MAP["music"]
    index_path = config["index"]

    async with INDEX_LOCK:
        try:
            index_data = await run_io(_read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(500, "Index corrupted")

            entry_idx = next((i for i, item in enumerate(index_data) if item.get("id") == music_id), -1)
            if entry_idx == -1:
                raise HTTPException(404, "Music not found")

            entry = index_data[entry_idx]
            update_happened = False

            if payload.name is not None:
                entry["name"] = payload.name
                update_happened = True
            if payload.rating is not None:
                entry["rating"] = payload.rating
                update_happened = True
            if payload.genre is not None:
                entry["genre"] = payload.genre
                update_happened = True
            if payload.description is not None:
                entry["description"] = payload.description
                update_happened = True

            if update_happened:
                await run_io(_write_json_sync, index_path, index_data)
                await cache.delete("library:music")
                await cache.delete("library:all")

            return {"success": True, "id": music_id, "action": "updated" if update_happened else "no_change"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update music: {e}")
            raise HTTPException(500, f"Failed: {str(e)}")


@router.post("/api/admin/sync-music")
async def sync_music_folder():
    config = STORAGE_MAP["music"]
    report = {"added": 0, "removed": 0}

    async with INDEX_LOCK:
        try:
            blobs = await run_io(lambda: list(bucket.list_blobs(prefix=config["folder"])))
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

            index_data = await run_io(_read_json_sync, config["index"])
            if not isinstance(index_data, list):
                index_data = []

            index_map = {item["filename"]: item for item in index_data}
            disk_set = set(f["filename"] for f in audio_files)

            new_index = [item for item in index_data if item["filename"] in disk_set]
            report["removed"] = len(index_data) - len(new_index)

            for file_info in audio_files:
                if file_info["filename"] not in index_map:
                    new_entry = {
                        "id": str(uuid.uuid4()),
                        "filename": file_info["filename"],
                        "name": file_info["name"],
                        "type": "music",
                        "date": datetime.datetime.now().strftime("%Y-%m-%d"),
                        "author": "Unknown",
                        "description": "",
                        "rating": None,
                        "genre": None,
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
