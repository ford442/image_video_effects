# storage_manager/routes/library.py
import json
import uuid
import logging
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, HTTPException, Query

from .. import config, state, models, utils

router = APIRouter()


@router.get("/api/library")
@router.get("/api/songs", response_model=List[models.MetaData])
async def list_library(
    type: Optional[str] = Query(None),
    genre: Optional[str] = Query(None),
    min_rating: Optional[int] = Query(None, ge=1, le=10),
    sort_by: models.SortBy = Query(models.SortBy.date),
    sort_desc: bool = Query(True)
):
    cache_key = f"library:{type or 'all'}:{sort_by}:{sort_desc}:{genre}:{min_rating}"
    cached = await state.cache.get(cache_key)
    if cached:
        return cached

    search_types = [type] if type else ["song", "pattern", "bank", "sample", "music", "shader", "image", "video"]
    results = []

    for t in search_types:
        cfg = config.STORAGE_MAP.get(t, config.STORAGE_MAP["default"])
        try:
            items = await state.run_io(utils._read_json_sync, cfg["index"])
            if isinstance(items, list):
                if t == "shader":
                    for item in items:
                        if item.get("thumbnail"):
                            item["thumbnail_url"] = state.bucket.blob(
                                f"{config.STORAGE_MAP['shader']['folder']}{item['thumbnail']}"
                            ).public_url
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
    await state.cache.set(cache_key, results, ttl=30)
    return results


@router.post("/api/upload")
@router.post("/api/songs")
async def upload_item(payload: models.ItemPayload):
    item_id = str(uuid.uuid4())
    date_str = datetime.now().strftime("%Y-%m-%d")
    item_type = payload.type if payload.type in config.STORAGE_MAP else "song"
    cfg = config.STORAGE_MAP[item_type]
    filename = f"{item_id}.json"
    full_path = f"{cfg['folder']}{filename}"

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

    async with state.get_resource_lock(item_type):
        try:
            await state.run_io(utils._write_json_sync, full_path, payload.data)

            def _update_index():
                current = utils._read_json_sync(cfg["index"])
                current.insert(0, meta)
                utils._write_json_sync(cfg["index"], current)

            await state.run_io(_update_index)
            await state.clear_cache_for_type(item_type)
            return {"success": True, "id": item_id}
        except Exception as e:
            raise HTTPException(500, f"Upload failed: {str(e)}")


@router.put("/api/items/{item_id}")
@router.put("/api/songs/{item_id}")
async def update_item(item_id: str, payload: models.ItemPayload):
    item_type = payload.type if payload.type in config.STORAGE_MAP else "song"
    cfg = config.STORAGE_MAP[item_type]
    filename = f"{item_id}.json"
    full_path = f"{cfg['folder']}{filename}"
    date_str = datetime.now().strftime("%Y-%m-%d")

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

    async with state.get_resource_lock(item_type):
        try:
            await state.run_io(utils._write_json_sync, full_path, payload.data)

            def _update_index_logic():
                current = utils._read_json_sync(cfg["index"])
                if not isinstance(current, list):
                    current = []
                existing_index = next((i for i, item in enumerate(current) if item.get("id") == item_id), -1)
                if existing_index != -1:
                    current.pop(existing_index)
                current.insert(0, new_meta)
                utils._write_json_sync(cfg["index"], current)

            await state.run_io(_update_index_logic)
            await state.clear_cache_for_type(item_type)
            return {"success": True, "id": item_id, "action": "updated"}
        except Exception as e:
            raise HTTPException(500, f"Update failed: {str(e)}")


@router.get("/api/items/{item_id}/meta")
@router.get("/api/songs/{item_id}/meta")
async def get_item_metadata(item_id: str, type: Optional[str] = Query(None)):
    search_types = [type] if type else ["song", "pattern", "bank", "sample", "music", "shader", "image", "video"]
    for t in search_types:
        cfg = config.STORAGE_MAP.get(t)
        if not cfg:
            continue
        index_data = await state.run_io(utils._read_json_sync, cfg["index"])
        if isinstance(index_data, list):
            entry = next((item for item in index_data if item.get("id") == item_id), None)
            if entry:
                if t == "shader" and entry.get("thumbnail"):
                    entry["thumbnail_url"] = state.bucket.blob(
                        f"{config.STORAGE_MAP['shader']['folder']}{entry['thumbnail']}"
                    ).public_url
                return entry
    raise HTTPException(404, "Item not found")


@router.get("/api/items/{item_id}/data")
@router.get("/api/items/{item_id}")
@router.get("/api/songs/{item_id}")
async def get_item(item_id: str, type: Optional[str] = Query(None)):
    search_types = [type] if type else ["song", "pattern", "bank", "sample", "music", "shader", "image", "video"]
    for t in search_types:
        cfg = config.STORAGE_MAP.get(t)
        filepath = f"{cfg['folder']}{item_id}.json"
        blob = state.bucket.blob(filepath)
        exists = await state.run_io(blob.exists)
        if exists:
            data = await state.run_io(blob.download_as_text)
            return json.loads(data)
    raise HTTPException(404, "Item not found")


@router.patch("/api/songs/{item_id}")
async def patch_song(item_id: str, patch: models.MetaPatch):
    cfg = config.STORAGE_MAP["song"]
    index_path = cfg["index"]

    async with state.get_resource_lock("song"):
        try:
            index = await state.run_io(utils._read_json_sync, index_path)
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

            await state.run_io(utils._write_json_sync, index_path, index)
            await state.clear_cache_for_type("song")

            return {"status": "success", "item_id": item_id, "updated": updated}
        except Exception as e:
            logging.error(f"PATCH /songs/{item_id} failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))
