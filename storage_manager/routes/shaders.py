# storage_manager/routes/shaders.py
import json
import uuid
import logging
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Query, Body
from fastapi.responses import PlainTextResponse, StreamingResponse

from .. import config, state, models, utils

router = APIRouter()


@router.get("/api/shaders")
async def list_shaders(
    category: Optional[models.ShaderCategory] = Query(None),
    min_stars: float = Query(0.0, ge=0, le=5),
    sort_by: models.SortBy = Query(models.SortBy.rating)
):
    cache_key = f"shaders:list:{category}:{min_stars}:{sort_by}"
    cached = await state.cache.get(cache_key)
    if cached:
        return cached

    cfg = config.STORAGE_MAP["shader"]
    try:
        index = await state.run_io(utils._read_json_sync, cfg["index"])
        if not isinstance(index, list):
            index = []

        if category:
            index = [s for s in index if category.value in s.get("tags", []) or category.value.lower() in s.get("description", "").lower()]
        if min_stars > 0:
            index = [s for s in index if s.get("stars", 0) >= min_stars]

        reverse = sort_by in [models.SortBy.rating, models.SortBy.date, models.SortBy.last_played]
        if sort_by is models.SortBy.rating:
            index.sort(key=lambda s: s.get("stars", 0), reverse=reverse)
        elif sort_by is models.SortBy.date:
            index.sort(key=lambda s: s.get("date", ""), reverse=reverse)
        elif sort_by is models.SortBy.name:
            index.sort(key=lambda s: s.get("name", "").lower())
        elif sort_by is models.SortBy.coordinate:
            index.sort(key=lambda s: s.get("coordinate", 9999))

        for shader in index:
            shader.setdefault("stars", 0.0)
            shader.setdefault("rating_count", 0)
            shader.setdefault("play_count", 0)
            if shader.get("thumbnail"):
                thumbnail_path = f"{cfg['folder']}{shader['thumbnail']}"
                shader["thumbnail_url"] = state.bucket.blob(thumbnail_path).public_url

        await state.cache.set(cache_key, index, ttl=300)
        return index
    except Exception as e:
        raise HTTPException(500, f"Failed to list shaders: {str(e)}")


@router.get("/api/shaders/{shader_id}")
async def get_shader_meta(shader_id: str):
    """Get shader metadata including stars, rating_count, play_count, coordinate."""
    cfg = config.STORAGE_MAP["shader"]
    index = await state.run_io(utils._read_json_sync, cfg["index"])
    if not isinstance(index, list):
        raise HTTPException(500, "Shader index corrupted")

    entry = next((s for s in index if s.get("id") == shader_id), None)
    if not entry:
        raise HTTPException(404, "Shader not found")

    entry.setdefault("stars", 0.0)
    entry.setdefault("rating_count", 0)
    entry.setdefault("play_count", 0)
    entry.setdefault("coordinate", None)
    if entry.get("thumbnail"):
        thumbnail_path = f"{cfg['folder']}{entry['thumbnail']}"
        entry["thumbnail_url"] = state.bucket.blob(thumbnail_path).public_url

    return entry


@router.post("/api/shaders/{shader_id}/rate")
async def rate_shader(shader_id: str, stars: float = Form(...)):
    """Rate a shader 1-5 stars. Updates average and count."""
    if not 1 <= stars <= 5:
        raise HTTPException(400, "Stars must be between 1 and 5")

    cfg = config.STORAGE_MAP["shader"]
    index_path = cfg["index"]

    async with state.get_resource_lock("shader"):
        try:
            index = await state.run_io(utils._read_json_sync, index_path)
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

            await state.run_io(utils._write_json_sync, index_path, index)
            await state.clear_cache_for_type("shader")

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
    cfg = config.STORAGE_MAP["shader"]
    index_path = cfg["index"]
    now = datetime.now().isoformat()

    async with state.get_resource_lock("shader"):
        try:
            index = await state.run_io(utils._read_json_sync, index_path)
            if not isinstance(index, list):
                raise HTTPException(500, "Shader index corrupted")

            entry = next((s for s in index if s.get("id") == shader_id), None)
            if not entry:
                raise HTTPException(404, "Shader not found")

            entry["play_count"] = (entry.get("play_count") or 0) + 1
            entry["last_played"] = now

            await state.run_io(utils._write_json_sync, index_path, index)
            await state.clear_cache_for_type("shader")

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
    thumbnail: UploadFile = File(None),
    name: str = Form(...),
    description: str = Form(""),
    tags: str = Form(""),
    author: str = Form("ford442"),
    coordinate: Optional[int] = Form(None),
    shader_id: Optional[str] = Form(None)
):
    """Upload a .wgsl shader file with metadata."""
    if not file.filename.endswith(".wgsl"):
        raise HTTPException(400, "Only .wgsl files allowed")
    if thumbnail is not None and not thumbnail.filename.lower().endswith(".png"):
        raise HTTPException(400, "Only .png thumbnails are supported")

    shader_id = (shader_id or "").strip() or str(uuid.uuid4())
    storage_filename = f"{shader_id}.wgsl"
    cfg = config.STORAGE_MAP["shader"]
    full_path = f"{cfg['folder']}{storage_filename}"

    meta = {
        "id": shader_id,
        "name": name,
        "author": author,
        "date": datetime.now().strftime("%Y-%m-%d"),
        "type": "shader",
        "description": description,
        "tags": [t.strip() for t in tags.split(",")] if tags else [],
        "filename": storage_filename,
        "coordinate": coordinate,
        "stars": 0.0,
        "rating_count": 0,
        "play_count": 0,
        "thumbnail": None,
        "thumbnail_url": None
    }

    async with state.get_resource_lock("shader"):
        try:
            blob = state.bucket.blob(full_path)
            await state.run_io(blob.upload_from_file, file.file, content_type="text/plain")

            if thumbnail is not None:
                thumb_path = f"{cfg['folder']}{shader_id}.png"
                thumb_blob = state.bucket.blob(thumb_path)
                await state.run_io(thumb_blob.upload_from_file, thumbnail.file, content_type="image/png")
                meta["thumbnail"] = f"{shader_id}.png"
                meta["thumbnail_url"] = thumb_blob.public_url

            index = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index, list):
                index = []
            index = [s for s in index if s.get("id") != shader_id]
            index.insert(0, meta)
            await state.run_io(utils._write_json_sync, cfg["index"], index)

            await state.clear_cache_for_type("shader")
            return {"success": True, "id": shader_id, "meta": meta}
        except Exception as e:
            raise HTTPException(500, f"Upload failed: {str(e)}")


@router.post("/api/admin/bulk-upload-shaders")
async def bulk_upload_shaders(
    files: List[UploadFile] = File(...),
    metadata_json: Optional[str] = Form(None)
):
    """Bulk upload multiple .wgsl shader files."""
    cfg = config.STORAGE_MAP["shader"]
    parsed_meta = {}
    if metadata_json:
        try:
            parsed_meta = json.loads(metadata_json)
        except json.JSONDecodeError:
            raise HTTPException(400, "metadata_json must be valid JSON")

    report = {"added": 0, "updated": 0, "failed": 0, "errors": []}

    async with state.get_resource_lock("shader"):
        index = await state.run_io(utils._read_json_sync, cfg["index"])
        if not isinstance(index, list):
            index = []

        for file in files:
            if not file.filename.endswith(".wgsl"):
                report["failed"] += 1
                report["errors"].append({"file": file.filename, "error": "Not a .wgsl file"})
                continue

            shader_id = file.filename.replace(".wgsl", "")
            meta_override = parsed_meta.get(shader_id, {})
            storage_filename = f"{shader_id}.wgsl"
            full_path = f"{cfg['folder']}{storage_filename}"

            meta = {
                "id": shader_id,
                "name": meta_override.get("name", shader_id.replace("-", " ").replace("_", " ").title()),
                "author": meta_override.get("author", "ford442"),
                "date": datetime.now().strftime("%Y-%m-%d"),
                "type": "shader",
                "description": meta_override.get("description", ""),
                "tags": meta_override.get("tags", []),
                "filename": storage_filename,
                "coordinate": meta_override.get("coordinate"),
                "stars": 0.0,
                "rating_count": 0,
                "play_count": 0,
                "thumbnail": None,
                "thumbnail_url": None
            }

            try:
                blob = state.bucket.blob(full_path)
                await state.run_io(blob.upload_from_file, file.file, content_type="text/plain")

                existed = any(s.get("id") == shader_id for s in index)
                index = [s for s in index if s.get("id") != shader_id]
                index.insert(0, meta)

                if existed:
                    report["updated"] += 1
                else:
                    report["added"] += 1
            except Exception as e:
                report["failed"] += 1
                report["errors"].append({"file": file.filename, "error": str(e)})

        try:
            await state.run_io(utils._write_json_sync, cfg["index"], index)
            await state.clear_cache_for_type("shader")
        except Exception as e:
            raise HTTPException(500, f"Failed to save index after bulk upload: {str(e)}")

    report["total_in_index"] = len(index)
    return report


@router.get("/api/shaders/{shader_id}/thumbnail")
async def get_shader_thumbnail(shader_id: str):
    """Return the shader thumbnail image if available."""
    cfg = config.STORAGE_MAP["shader"]
    index = await state.run_io(utils._read_json_sync, cfg["index"])
    if not isinstance(index, list):
        raise HTTPException(500, "Shader index corrupted")

    entry = next((s for s in index if s.get("id") == shader_id), None)
    if not entry or not entry.get("thumbnail"):
        raise HTTPException(404, "Thumbnail not found")

    thumb_path = f"{cfg['folder']}{entry['thumbnail']}"
    blob = state.bucket.blob(thumb_path)
    if not await state.run_io(blob.exists):
        raise HTTPException(404, "Thumbnail not found")

    def iterfile():
        with blob.open("rb") as f:
            while chunk := f.read(1024 * 1024):
                yield chunk

    return StreamingResponse(iterfile(), media_type="image/png")


@router.get("/api/shaders/{shader_id}/code")
async def get_shader_code(shader_id: str):
    """Returns the actual .wgsl shader code."""
    cfg = config.STORAGE_MAP["shader"]

    index = await state.run_io(utils._read_json_sync, cfg["index"])
    entry = next((s for s in index if s.get("id") == shader_id), None)
    if not entry:
        raise HTTPException(404, "Shader not found")

    blob_path = f"{cfg['folder']}{entry['filename']}"
    blob = state.bucket.blob(blob_path)
    if not await state.run_io(blob.exists):
        raise HTTPException(404, "Shader file not found")

    code = await state.run_io(blob.download_as_text)
    return {"id": shader_id, "code": code, "name": entry.get("name")}


@router.patch("/api/shaders/{shader_id}/meta")
@router.put("/api/shaders/{shader_id}")
async def update_shader_metadata(shader_id: str, payload: models.MetaPatch):
    """Update shader metadata (name, rating, coordinate, etc)."""
    cfg = config.STORAGE_MAP["shader"]
    index_path = cfg["index"]

    async with state.get_resource_lock("shader"):
        try:
            index = await state.run_io(utils._read_json_sync, index_path)
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
            if payload.params is not None:
                entry["params"] = [p.dict() for p in payload.params]
                updated["params"] = f"{len(payload.params)} parameters"

            if updated:
                await state.run_io(utils._write_json_sync, index_path, index)
                await state.clear_cache_for_type("shader")

            return {"success": True, "id": shader_id, "updated": updated}

        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update shader {shader_id}: {e}")
            raise HTTPException(500, f"Update failed: {str(e)}")


@router.post("/api/admin/sync-coordinates")
@router.post("/api/shaders/coordinates")
async def sync_shader_coordinates(payload: models.CoordinateSyncPayload):
    """Sync coordinates from shader_coordinates.json."""
    cfg = config.STORAGE_MAP["shader"]
    index_path = cfg["index"]

    async with state.get_resource_lock("shader"):
        try:
            index = await state.run_io(utils._read_json_sync, index_path)
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
                await state.run_io(utils._write_json_sync, index_path, index)
                await state.clear_cache_for_type("shader")

            return {
                "success": True,
                "updated": updated,
                "skipped": skipped,
                "total": len(index)
            }

        except Exception as e:
            logging.error(f"Failed to sync coordinates: {e}")
            raise HTTPException(500, f"Sync failed: {str(e)}")


@router.post("/api/admin/rescan-shaders")
@router.post("/api/shaders/rescan")
async def rescan_shaders(payload: models.ShaderRescanPayload = Body(default_factory=models.ShaderRescanPayload)):
    try:
        result = await state.run_io(utils._rescan_shader_lists_sync, payload.pull_latest)
        await state.clear_cache_for_type(None)
        return result
    except Exception as e:
        logging.error("Shader list rescan failed: %s", e)
        raise HTTPException(500, f"Shader rescan failed: {str(e)}")


@router.head("/api/shaders/{shader_id}/wgsl")
@router.get("/api/shaders/{shader_id}/wgsl", response_class=PlainTextResponse)
async def get_shader_wgsl(shader_id: str):
    """Returns raw WGSL text for direct consumption by WebGPU renderer."""
    cache_key = f"shader_wgsl:{shader_id}"
    cached = await state.cache.get(cache_key)
    if cached:
        return PlainTextResponse(cached, media_type="text/plain")

    cfg = config.STORAGE_MAP["shader"]
    blob_path = f"{cfg['folder']}{shader_id}.wgsl"
    blob = state.bucket.blob(blob_path)
    if await state.run_io(blob.exists):
        code = await state.run_io(blob.download_as_text)
        await state.cache.set(cache_key, code, ttl=3600)
        return PlainTextResponse(code, media_type="text/plain")

    if config.FTP_ENABLED:
        try:
            code = await state.run_io(utils._fetch_ftp_file_sync, f"{shader_id}.wgsl")
            await state.cache.set(cache_key, code, ttl=3600)
            return PlainTextResponse(code, media_type="text/plain")
        except Exception:
            pass

    raise HTTPException(404, f"Shader {shader_id} not found")
