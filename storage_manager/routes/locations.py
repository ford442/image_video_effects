# storage_manager/routes/locations.py
import uuid
import logging
from datetime import datetime
from fastapi import APIRouter, HTTPException

from .. import config, state, models, utils

router = APIRouter()


@router.get("/api/locations")
async def list_locations():
    """List all saved locations from cloud storage."""
    cfg = config.STORAGE_MAP["location"]
    try:
        index = await state.run_io(utils._read_json_sync, cfg["index"])
        if not isinstance(index, list):
            index = []
        return index
    except Exception as e:
        logging.error(f"Failed to list locations: {e}")
        raise HTTPException(500, f"Failed to list locations: {str(e)}")


@router.post("/api/locations")
async def save_location(payload: models.LocationPayload):
    """Save a new location to cloud storage."""
    cfg = config.STORAGE_MAP["location"]
    location_id = str(uuid.uuid4())
    date_str = datetime.now().strftime("%Y-%m-%d")
    filename = f"{location_id}.json"
    full_path = f"{cfg['folder']}{filename}"

    data = {
        "id": location_id,
        "name": payload.name,
        "lat": payload.lat,
        "lng": payload.lng,
        "heading": payload.heading,
        "pitch": payload.pitch,
        "zoom": payload.zoom,
        "description": payload.description,
        "tags": payload.tags,
        "date": date_str,
        "type": "location",
        "filename": filename,
    }

    async with state.get_resource_lock("location"):
        try:
            await state.run_io(utils._write_json_sync, full_path, data)

            index = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index, list):
                index = []
            index.insert(0, data)
            await state.run_io(utils._write_json_sync, cfg["index"], index)

            await state.cache.delete("locations:list")
            return {"success": True, "id": location_id, "location": data}
        except Exception as e:
            logging.error(f"Failed to save location: {e}")
            raise HTTPException(500, f"Failed to save location: {str(e)}")


@router.get("/api/locations/{location_id}")
async def get_location(location_id: str):
    """Get a single location by ID."""
    cfg = config.STORAGE_MAP["location"]
    try:
        index = await state.run_io(utils._read_json_sync, cfg["index"])
        if not isinstance(index, list):
            raise HTTPException(500, "Location index corrupted")
        entry = next((item for item in index if item.get("id") == location_id), None)
        if not entry:
            raise HTTPException(404, "Location not found")
        return entry
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Failed to get location {location_id}: {e}")
        raise HTTPException(500, f"Failed to get location: {str(e)}")


@router.delete("/api/locations/{location_id}")
async def delete_location(location_id: str):
    """Delete a location from cloud storage."""
    cfg = config.STORAGE_MAP["location"]
    async with state.get_resource_lock("location"):
        try:
            index = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index, list):
                raise HTTPException(500, "Location index corrupted")

            entry = next((item for item in index if item.get("id") == location_id), None)
            if not entry:
                raise HTTPException(404, "Location not found")

            blob_path = f"{cfg['folder']}{entry['filename']}"
            blob = state.bucket.blob(blob_path)
            if await state.run_io(blob.exists):
                await state.run_io(blob.delete)

            index = [item for item in index if item.get("id") != location_id]
            await state.run_io(utils._write_json_sync, cfg["index"], index)
            await state.cache.delete("locations:list")

            return {"success": True, "id": location_id, "deleted": True}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to delete location {location_id}: {e}")
            raise HTTPException(500, f"Failed to delete location: {str(e)}")


@router.put("/api/locations/{location_id}")
async def update_location(location_id: str, payload: models.LocationPayload):
    """Update an existing location."""
    cfg = config.STORAGE_MAP["location"]
    async with state.get_resource_lock("location"):
        try:
            index = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index, list):
                raise HTTPException(500, "Location index corrupted")

            entry_idx = next((i for i, item in enumerate(index) if item.get("id") == location_id), -1)
            if entry_idx == -1:
                raise HTTPException(404, "Location not found")

            entry = index[entry_idx]
            entry["name"] = payload.name
            entry["lat"] = payload.lat
            entry["lng"] = payload.lng
            entry["heading"] = payload.heading
            entry["pitch"] = payload.pitch
            entry["zoom"] = payload.zoom
            entry["description"] = payload.description
            entry["tags"] = payload.tags
            entry["date"] = datetime.now().strftime("%Y-%m-%d")

            blob_path = f"{cfg['folder']}{entry['filename']}"
            await state.run_io(utils._write_json_sync, blob_path, entry)
            await state.run_io(utils._write_json_sync, cfg["index"], index)
            await state.cache.delete("locations:list")

            return {"success": True, "id": location_id, "location": entry}
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to update location {location_id}: {e}")
            raise HTTPException(500, f"Failed to update location: {str(e)}")
