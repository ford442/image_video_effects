# storage_manager/routes/preset_packs.py
import uuid
import logging
from datetime import datetime
from fastapi import APIRouter, HTTPException, Query

from .. import config, state, models, utils

router = APIRouter()


@router.post("/api/preset_packs/publish")
@router.post("/api/preset-packs")
async def publish_preset_pack(payload: models.PresetPackPublishPayload):
    """Publish a shared shader chain as a community preset pack."""
    decoded = utils._decode_shared_chain(payload.chain)
    if decoded is None:
        raise HTTPException(400, "Invalid shared chain: could not decode or validate")

    pack_id = str(uuid.uuid4())
    now = datetime.now().strftime("%Y-%m-%d")
    entry = {
        "id": pack_id,
        "name": payload.name.strip(),
        "description": (payload.description or "").strip(),
        "author": (payload.author or "Anonymous").strip() or "Anonymous",
        "date": now,
        "chain": payload.chain,
        "play_count": 0,
    }

    cfg = config.STORAGE_MAP["preset_pack"]
    async with state.get_resource_lock("preset_pack"):
        try:
            index = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index, list):
                index = []
            index.insert(0, entry)
            await state.run_io(utils._write_json_sync, cfg["index"], index)
            await state.clear_cache_for_type("preset_pack")
            return {"success": True, "id": pack_id, "pack": entry}
        except Exception as e:
            logging.error(f"Failed to publish preset pack: {e}")
            raise HTTPException(500, f"Failed to publish preset pack: {str(e)}")


@router.get("/api/preset_packs")
@router.get("/api/preset-packs")
async def list_preset_packs(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    sort_by: str = Query("date", pattern="^(date|play_count)$"),
):
    """List published preset packs. Default sort is newest first; use play_count for popular packs."""
    cfg = config.STORAGE_MAP["preset_pack"]
    try:
        index = await state.run_io(utils._read_json_sync, cfg["index"])
        if not isinstance(index, list):
            index = []

        for pack in index:
            pack.setdefault("play_count", 0)

        if sort_by == "play_count":
            index = sorted(index, key=lambda p: p.get("play_count", 0), reverse=True)

        total = len(index)
        page = index[offset : offset + limit]
        return {"total": total, "limit": limit, "offset": offset, "packs": page}
    except Exception as e:
        logging.error(f"Failed to list preset packs: {e}")
        raise HTTPException(500, f"Failed to list preset packs: {str(e)}")


@router.get("/api/preset_packs/{pack_id}")
@router.get("/api/preset-packs/{pack_id}")
async def get_preset_pack(pack_id: str):
    """Fetch a single preset pack by id."""
    cfg = config.STORAGE_MAP["preset_pack"]
    try:
        index = await state.run_io(utils._read_json_sync, cfg["index"])
        if not isinstance(index, list):
            raise HTTPException(500, "Preset pack index corrupted")

        entry = next((p for p in index if p.get("id") == pack_id), None)
        if not entry:
            raise HTTPException(404, "Preset pack not found")

        entry.setdefault("play_count", 0)
        return entry
    except HTTPException:
        raise
    except Exception as e:
        logging.error(f"Failed to fetch preset pack {pack_id}: {e}")
        raise HTTPException(500, f"Failed to fetch preset pack: {str(e)}")


@router.post("/api/preset_packs/{pack_id}/play")
@router.post("/api/preset-packs/{pack_id}/play")
async def record_preset_pack_play(pack_id: str):
    """Increment the play count for a preset pack."""
    cfg = config.STORAGE_MAP["preset_pack"]
    now = datetime.now().isoformat()

    async with state.get_resource_lock("preset_pack"):
        try:
            index = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index, list):
                raise HTTPException(500, "Preset pack index corrupted")

            entry = next((p for p in index if p.get("id") == pack_id), None)
            if not entry:
                raise HTTPException(404, "Preset pack not found")

            entry["play_count"] = (entry.get("play_count") or 0) + 1
            entry["last_played"] = now

            await state.run_io(utils._write_json_sync, cfg["index"], index)
            await state.clear_cache_for_type("preset_pack")

            return {
                "success": True,
                "id": pack_id,
                "play_count": entry["play_count"],
                "last_played": now,
            }
        except HTTPException:
            raise
        except Exception as e:
            logging.error(f"Failed to record play for preset pack {pack_id}: {e}")
            raise HTTPException(500, f"Failed to record play: {str(e)}")
