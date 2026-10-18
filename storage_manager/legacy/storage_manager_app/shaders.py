# scripts/storage_manager_app/shaders.py
import datetime
import logging
import uuid
from typing import Optional

from fastapi import APIRouter, File, Form, HTTPException, Query, UploadFile

from .config import (
    INDEX_LOCK,
    STORAGE_MAP,
    CoordinateSyncPayload,
    MetaPatch,
    ShaderCategory,
    SortBy,
    _read_json_sync,
    _write_json_sync,
    bucket,
    cache,
    run_io,
)

router = APIRouter()


@router.get("/api/shaders")
async def list_shaders(
    category: Optional[ShaderCategory] = Query(None),
    min_stars: float = Query(0.0, ge=0, le=5),
    sort_by: SortBy = Query(SortBy.rating)
):
    cache_key = f"shaders:list:{category}:{min_stars}:{sort_by}"
    cached = await cache.get(cache_key)
    if cached:
        return cached

    config = STORAGE_MAP["shader"]
    try:
        index = await run_io(_read_json_sync, config["index"])
        if not isinstance(index, list):
            index = []

        if category:
            index = [
                s for s in index
                if category.value in s.get("tags", []) or category.value.lower() in s.get("description", "").lower()
            ]
        if min_stars > 0:
            index = [s for s in index if s.get("stars", 0) >= min_stars]

        reverse = sort_by in ["rating", "date", "last_played"]
        if sort_by == "rating":
            index.sort(key=lambda s: s.get("stars", 0), reverse=reverse)
        elif sort_by == "date":
            index.sort(key=lambda s: s.get("date", ""), reverse=reverse)
        elif sort_by == "name":
            index.sort(key=lambda s: s.get("name", "").lower())
        elif sort_by == "coordinate":
            index.sort(key=lambda s: s.get("coordinate", 9999))

        for shader in index:
            shader.setdefault("stars", 0.0)
            shader.setdefault("rating_count", 0)
            shader.setdefault("play_count", 0)

        await cache.set(cache_key, index, ttl=300)
        return index
    except Exception as e:
        raise HTTPException(500, f"Failed to list shaders: {str(e)}")


@router.get("/api/shaders/{shader_id}")
async def get_shader_meta(shader_id: str):
    """Get shader metadata including stars, rating_count, play_count, coordinate."""
    config = STORAGE_MAP["shader"]
    index = await run_io(_read_json_sync, config["index"])
    if not isinstance(index, list):
        raise HTTPException(500, "Shader index corrupted")

    entry = next((s for s in index if s.get("id") == shader_id), None)
    if not entry:
        raise HTTPException(404, "Shader not found")

    entry.setdefault("stars", 0.0)
    entry.setdefault("rating_count", 0)
    entry.setdefault("play_count", 0)
    entry.setdefault("coordinate", None)

    return entry


@router.post("/api/shaders/{shader_id}/rate")
async def rate_shader(shader_id: str, stars: float = Form(...)):
    """Rate a shader 1-5 stars. Updates average and count."""
    if not 1 <= stars <= 5:
        raise HTTPException(400, "Stars must be between 1 and 5")

    config = STORAGE_MAP["shader"]
    index_path = config["index"]

    async with INDEX_LOCK:
        try:
            index = await run_io(_read_json_sync, index_path)
            if not isinstance(index, list):
                raise HTTPException(500, "Shader index corrupted")

            entry = next((s for s in index if s.get("id") == shader_id), None)
            if not entry:
                raise HTTPException(404, "Shader not found")

            current_stars = entry.get("stars", 0.0)
            current_count = entry.get("rating_count", 0)

            new_count = current_count + 1
            new_stars = ((current_stars * current_count) + stars) / new_count

            entry["stars"] = round(new_stars, 2)
            entry["rating_count"] = new_count

            await run_io(_write_json_sync, index_path, index)
            await cache.delete(f"shader:{shader_id}")
            await cache.delete("shaders:list")

            return {
                "id": shader_id,
                "stars": entry["stars"],
                "rating_count": entry["rating_count"],
                "your_rating": stars
            }

        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to rate shader {shader_id}: {e}")
            raise HTTPException(500, f"Rating failed: {str(e)}")


@router.post("/api/shaders/{shader_id}/play")
async def record_shader_play(shader_id: str):
    """Record that a shader was played. Increments play_count."""
    config = STORAGE_MAP["shader"]
    index_path = config["index"]
    now = datetime.datetime.now().isoformat()

    async with INDEX_LOCK:
        try:
            index = await run_io(_read_json_sync, index_path)
            if not isinstance(index, list):
                raise HTTPException(500, "Shader index corrupted")

            entry = next((s for s in index if s.get("id") == shader_id), None)
            if not entry:
                raise HTTPException(404, "Shader not found")

            entry["play_count"] = (entry.get("play_count") or 0) + 1
            entry["last_played"] = now

            await run_io(_write_json_sync, index_path, index)
            await cache.delete(f"shader:{shader_id}")
            await cache.delete("shaders:list")

            return {
                "success": True,
                "id": shader_id,
                "play_count": entry["play_count"],
                "last_played": now
            }

        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to record play for {shader_id}: {e}")
            raise HTTPException(500, f"Failed to record play: {str(e)}")


@router.post("/api/shaders/upload")
async def upload_shader(
    file: UploadFile = File(...),
    name: str = Form(...),
    description: str = Form(""),
    tags: str = Form(""),
    author: str = Form("ford442"),
    coordinate: Optional[int] = Form(None)
):
    """Upload a .wgsl shader file with metadata."""
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
        "date": datetime.datetime.now().strftime("%Y-%m-%d"),
        "type": "shader",
        "description": description,
        "tags": [t.strip() for t in tags.split(",")] if tags else [],
        "filename": storage_filename,
        "coordinate": coordinate,
        "stars": 0.0,
        "rating_count": 0,
        "play_count": 0
    }

    async with INDEX_LOCK:
        try:
            blob = bucket.blob(full_path)
            await run_io(blob.upload_from_file, file.file, content_type="text/plain")

            index = await run_io(_read_json_sync, config["index"])
            if not isinstance(index, list):
                index = []
            index.insert(0, meta)
            await run_io(_write_json_sync, config["index"], index)

            await cache.delete("shaders:list")
            return {"success": True, "id": shader_id, "meta": meta}
        except Exception as e:
            raise HTTPException(500, f"Upload failed: {str(e)}")


@router.get("/api/shaders/{shader_id}/code")
async def get_shader_code(shader_id: str):
    """Returns the actual .wgsl shader code."""
    config = STORAGE_MAP["shader"]

    index = await run_io(_read_json_sync, config["index"])
    entry = next((s for s in index if s.get("id") == shader_id), None)
    if not entry:
        raise HTTPException(404, "Shader not found")

    blob_path = f"{config['folder']}{entry['filename']}"
    blob = bucket.blob(blob_path)
    if not await run_io(blob.exists):
        raise HTTPException(404, "Shader file not found")

    code = await run_io(blob.download_as_text)
    return {"id": shader_id, "code": code, "name": entry.get("name")}


@router.put("/api/shaders/{shader_id}")
async def update_shader_metadata(shader_id: str, payload: MetaPatch):
    """Update shader metadata (name, rating, coordinate, etc)."""
    config = STORAGE_MAP["shader"]
    index_path = config["index"]

    async with INDEX_LOCK:
        try:
            index = await run_io(_read_json_sync, index_path)
            if not isinstance(index, list):
                raise HTTPException(500, "Index corrupted")

            entry_idx = next((i for i, s in enumerate(index) if s.get("id") == shader_id), -1)
            if entry_idx == -1:
                raise HTTPException(404, "Shader not found")

            entry = index[entry_idx]
            updated = {}

            if payload.name is not None:
                entry["name"] = payload.name
                updated["name"] = payload.name
            if payload.rating is not None:
                entry["rating"] = payload.rating
                updated["rating"] = payload.rating
            if payload.coordinate is not None:
                entry["coordinate"] = payload.coordinate
                updated["coordinate"] = payload.coordinate
            if payload.tags is not None:
                entry["tags"] = payload.tags
                updated["tags"] = payload.tags

            if updated:
                await run_io(_write_json_sync, index_path, index)
                await cache.delete(f"shader:{shader_id}")
                await cache.delete("shaders:list")

            return {"success": True, "id": shader_id, "updated": updated}

        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update shader {shader_id}: {e}")
            raise HTTPException(500, f"Update failed: {str(e)}")


@router.post("/api/admin/sync-coordinates")
async def sync_shader_coordinates(payload: CoordinateSyncPayload):
    """Sync coordinates from shader_coordinates.json."""
    config = STORAGE_MAP["shader"]
    index_path = config["index"]

    async with INDEX_LOCK:
        try:
            index = await run_io(_read_json_sync, index_path)
            if not isinstance(index, list):
                index = []

            updated = 0
            skipped = 0

            for entry in index:
                shader_id = entry.get("id")
                if shader_id in payload.coordinates:
                    existing_coord = entry.get("coordinate")
                    new_coord = payload.coordinates[shader_id]

                    if existing_coord is None or payload.overwrite:
                        entry["coordinate"] = new_coord
                        updated += 1
                    else:
                        skipped += 1

            if updated > 0:
                await run_io(_write_json_sync, index_path, index)
                await cache.delete("shaders:list")

            return {
                "success": True,
                "updated": updated,
                "skipped": skipped,
                "total": len(index)
            }

        except Exception as e:
            logging.error(f"Failed to sync coordinates: {e}")
            raise HTTPException(500, f"Sync failed: {str(e)}")
