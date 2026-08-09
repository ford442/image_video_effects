# storage_manager/routes/media.py
import os
import uuid
import logging
from datetime import datetime, timedelta
from typing import Optional

from fastapi import APIRouter, HTTPException, UploadFile, File, Form, Request
from fastapi.responses import StreamingResponse, RedirectResponse

from .. import config, state, models, utils

router = APIRouter()


@router.post("/api/samples/upload")
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
    cfg = config.STORAGE_MAP["sample"]
    full_path = f"{cfg['folder']}{storage_filename}"

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

    async with state.get_resource_lock("sample"):
        try:
            blob = state.bucket.blob(full_path)
            await state.run_io(blob.upload_from_file, file.file, content_type=file.content_type)

            def _update_idx():
                idx = utils._read_json_sync(cfg["index"])
                idx.insert(0, meta)
                utils._write_json_sync(cfg["index"], idx)

            await state.run_io(_update_idx)
            await state.cache.delete("library:sample")
            return {"success": True, "id": sample_id}
        except Exception as e:
            raise HTTPException(500, str(e))


@router.get("/api/samples/{sample_id}")
async def get_sample(sample_id: str):
    cfg = config.STORAGE_MAP["sample"]
    idx = await state.run_io(utils._read_json_sync, cfg["index"])
    entry = next((i for i in idx if i["id"] == sample_id), None)
    if not entry:
        raise HTTPException(404, "Sample not found")

    blob_path = f"{cfg['folder']}{entry['filename']}"
    blob = state.bucket.blob(blob_path)
    if not await state.run_io(blob.exists):
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
    cfg = config.STORAGE_MAP["sample"]
    index_path = cfg["index"]
    now = datetime.now().isoformat()

    async with state.get_resource_lock("sample"):
        try:
            index_data = await state.run_io(utils._read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(500, "Index corrupted")

            entry = next((item for item in index_data if item.get("id") == sample_id), None)
            if not entry:
                raise HTTPException(404, "Sample not found")

            entry["last_played"] = now
            await state.run_io(utils._write_json_sync, index_path, index_data)
            await state.cache.delete("library:sample")
            await state.cache.delete("library:all")

            return {"success": True, "id": sample_id, "last_played": now}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to record play: {e}")
            raise HTTPException(500, f"Failed: {str(e)}")


@router.put("/api/samples/{sample_id}")
@router.patch("/api/samples/{sample_id}/meta")
async def update_sample_metadata(sample_id: str, payload: models.SampleMetaUpdatePayload):
    cfg = config.STORAGE_MAP["sample"]
    index_path = cfg["index"]

    async with state.get_resource_lock("sample"):
        try:
            index_data = await state.run_io(utils._read_json_sync, index_path)
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

            if update_happened:
                await state.run_io(utils._write_json_sync, index_path, index_data)
                await state.cache.delete("library:sample")
                await state.cache.delete("library:all")

            return {"success": True, "id": sample_id, "action": "metadata_updated" if update_happened else "no_change"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update sample: {e}")
            raise HTTPException(500, f"Failed: {str(e)}")


@router.get("/api/music/{music_id}")
async def get_music_file(music_id: str):
    cfg = config.STORAGE_MAP["music"]
    idx = await state.run_io(utils._read_json_sync, cfg["index"])
    entry = next((i for i in idx if i["id"] == music_id), None)
    if not entry:
        raise HTTPException(404, "Music not found")

    blob_path = f"{cfg['folder']}{entry['filename']}"
    blob = state.bucket.blob(blob_path)
    if not await state.run_io(blob.exists):
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
@router.patch("/api/music/{music_id}/meta")
async def update_music_metadata(music_id: str, payload: models.SampleMetaUpdatePayload):
    cfg = config.STORAGE_MAP["music"]
    index_path = cfg["index"]

    async with state.get_resource_lock("music"):
        try:
            index_data = await state.run_io(utils._read_json_sync, index_path)
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
            if payload.description is not None:
                entry["description"] = payload.description
                update_happened = True

            if update_happened:
                await state.run_io(utils._write_json_sync, index_path, index_data)
                await state.cache.delete("library:music")
                await state.cache.delete("library:all")

            return {"success": True, "id": music_id, "action": "updated" if update_happened else "no_change"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update music metadata: {e}")
            raise HTTPException(status_code=500, detail=f"Failed to update: {str(e)}")


@router.get("/api/images/{image_id}")
async def get_image_file(image_id: str, request: Request):
    cfg = config.STORAGE_MAP["image"]
    idx = await state.run_io(utils._read_json_sync, cfg["index"])
    entry = next((i for i in idx if i["id"] == image_id), None)
    if not entry:
        raise HTTPException(404, "Image not found")

    blob_path = f"{cfg['folder']}{entry['filename']}"
    blob = state.bucket.blob(blob_path)
    if not await state.run_io(blob.exists):
        raise HTTPException(404, "File missing")

    if state._has_signing_creds:
        try:
            signed_url = await state.run_io(
                blob.generate_signed_url,
                version="v4",
                expiration=timedelta(seconds=config.GCS_SIGNED_URL_EXPIRATION_SECONDS),
                method="GET",
            )
            return RedirectResponse(
                url=signed_url,
                status_code=302,
                headers={"Cache-Control": "private, max-age=0"},
            )
        except Exception as exc:
            logging.error("Signed-URL generation failed for image %s: %s; falling back to proxy", image_id, exc)

    lower_name = entry['filename'].lower()
    if lower_name.endswith('.png'):
        media_type = 'image/png'
    elif lower_name.endswith(('.jpg', '.jpeg')):
        media_type = 'image/jpeg'
    elif lower_name.endswith('.webp'):
        media_type = 'image/webp'
    elif lower_name.endswith('.gif'):
        media_type = 'image/gif'
    else:
        media_type = 'application/octet-stream'

    return await utils._proxy_media_response(
        blob,
        media_type=media_type,
        filename=entry["name"],
        range_header=request.headers.get("Range"),
    )


@router.put("/api/images/{image_id}")
@router.patch("/api/images/{image_id}/meta")
async def update_image_metadata(image_id: str, payload: models.SampleMetaUpdatePayload):
    cfg = config.STORAGE_MAP["image"]
    index_path = cfg["index"]

    async with state.get_resource_lock("image"):
        try:
            index_data = await state.run_io(utils._read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(500, "Index corrupted")

            entry_idx = next((i for i, item in enumerate(index_data) if item.get("id") == image_id), -1)
            if entry_idx == -1:
                raise HTTPException(404, "Image not found")

            entry = index_data[entry_idx]
            update_happened = False

            if payload.name is not None:
                entry["name"] = payload.name
                update_happened = True
            if payload.rating is not None:
                entry["rating"] = payload.rating
                update_happened = True
            if payload.description is not None:
                entry["description"] = payload.description
                update_happened = True

            if update_happened:
                await state.run_io(utils._write_json_sync, index_path, index_data)
                await state.cache.delete("library:image")
                await state.cache.delete("library:all")

            return {"success": True, "id": image_id, "action": "updated" if update_happened else "no_change"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update image: {e}")
            raise HTTPException(500, f"Failed: {str(e)}")


@router.get("/api/videos/{video_id}")
async def get_video_file(video_id: str, request: Request):
    cfg = config.STORAGE_MAP["video"]
    idx = await state.run_io(utils._read_json_sync, cfg["index"])
    entry = next((i for i in idx if i["id"] == video_id), None)
    if not entry:
        raise HTTPException(404, "Video not found")

    blob_path = f"{cfg['folder']}{entry['filename']}"
    blob = state.bucket.blob(blob_path)
    if not await state.run_io(blob.exists):
        raise HTTPException(404, "File missing")

    if state._has_signing_creds:
        try:
            signed_url = await state.run_io(
                blob.generate_signed_url,
                version="v4",
                expiration=timedelta(seconds=config.GCS_SIGNED_URL_EXPIRATION_SECONDS),
                method="GET",
            )
            return RedirectResponse(
                url=signed_url,
                status_code=302,
                headers={"Cache-Control": "private, max-age=0"},
            )
        except Exception as exc:
            logging.error("Signed-URL generation failed for video %s: %s; falling back to proxy", video_id, exc)

    lower_name = entry['filename'].lower()
    if lower_name.endswith('.mp4'):
        media_type = 'video/mp4'
    elif lower_name.endswith('.webm'):
        media_type = 'video/webm'
    elif lower_name.endswith('.mov'):
        media_type = 'video/quicktime'
    else:
        media_type = 'application/octet-stream'

    return await utils._proxy_media_response(
        blob,
        media_type=media_type,
        filename=entry["name"],
        range_header=request.headers.get("Range"),
    )


@router.put("/api/videos/{video_id}")
@router.patch("/api/videos/{video_id}/meta")
async def update_video_metadata(video_id: str, payload: models.SampleMetaUpdatePayload):
    cfg = config.STORAGE_MAP["video"]
    index_path = cfg["index"]

    async with state.get_resource_lock("video"):
        try:
            index_data = await state.run_io(utils._read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(500, "Index corrupted")

            entry_idx = next((i for i, item in enumerate(index_data) if item.get("id") == video_id), -1)
            if entry_idx == -1:
                raise HTTPException(404, "Video not found")

            entry = index_data[entry_idx]
            update_happened = False

            if payload.name is not None:
                entry["name"] = payload.name
                update_happened = True
            if payload.rating is not None:
                entry["rating"] = payload.rating
                update_happened = True
            if payload.description is not None:
                entry["description"] = payload.description
                update_happened = True

            if update_happened:
                await state.run_io(utils._write_json_sync, index_path, index_data)
                await state.cache.delete("library:video")
                await state.cache.delete("library:all")

            return {"success": True, "id": video_id, "action": "updated" if update_happened else "no_change"}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update video: {e}")
            raise HTTPException(500, f"Failed: {str(e)}")
