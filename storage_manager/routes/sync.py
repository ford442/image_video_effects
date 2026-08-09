# storage_manager/routes/sync.py
import uuid
import time
import logging
from datetime import datetime
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import JSONResponse

from .. import config, state, models, utils, intents

router = APIRouter()


async def _plan_sync(resource_type: str, allowed_extensions: tuple) -> dict:
    """Run the read-only planning phase for *resource_type*. Returns the full response dict."""
    cfg = config.STORAGE_MAP[resource_type]
    t0 = time.monotonic()

    existing_index = await state.run_io(utils._read_json_sync, cfg["index"])
    if not isinstance(existing_index, list):
        existing_index = []

    diff_full, gcs_sha, index_sha = await state.run_io(
        utils._compute_sync_diff_sync, cfg, allowed_extensions, existing_index
    )

    diff_preview, truncated = utils._build_diff_preview(diff_full)

    now = time.time()
    intent_id = str(uuid.uuid4())
    expires_at = now + intents.INTENT_TTL_SECONDS
    doc = intents.SyncIntentDocument(
        intent_id=intent_id,
        resource_type=resource_type,
        status="PENDING",
        created_at=now,
        expires_at=expires_at,
        gcs_snapshot_sha=gcs_sha,
        index_snapshot_sha=index_sha,
        diff=diff_full,
        diff_preview=diff_preview,
    )
    intents.intent_store.put(doc)

    duration_ms = round((time.monotonic() - t0) * 1000, 1)
    state._log_event(
        "intent_planned",
        intent_id=intent_id,
        resource_type=resource_type,
        gcs_sha=gcs_sha,
        index_sha=index_sha,
        duration_ms=duration_ms,
        to_add=len(diff_full["to_add"]),
        to_remove=len(diff_full["to_remove"]),
        divergent=len(diff_full["divergent"]),
    )

    return {
        "intent_id": intent_id,
        "expires_at": datetime.utcfromtimestamp(expires_at).isoformat() + "Z",
        "gcs_snapshot_sha": gcs_sha,
        "index_snapshot_sha": index_sha,
        "diff": diff_preview,
        "diff_preview_truncated": truncated,
    }


async def _apply_sync(
    resource_type: str,
    allowed_extensions: tuple,
    media_type_label: str,
    payload: models.ApplyIntentPayload,
) -> dict:
    """Run the mutating apply phase for *resource_type*. Returns the response dict."""
    cfg = config.STORAGE_MAP[resource_type]
    cache_keys = [f"library:{resource_type}", "library:all"]

    doc = intents.intent_store.get(payload.intent_id)
    if doc is None or doc.status == "EXPIRED":
        raise HTTPException(
            410,
            detail={
                "error": "INTENT_NOT_FOUND",
                "message": "Intent has expired or does not exist. Run /plan again.",
                "intent_id": payload.intent_id,
            },
        )
    if doc.status == "EXECUTED":
        return {
            "intent_id": doc.intent_id,
            "status": "EXECUTED",
            "changes_applied": True,
            "duration_ms": doc.duration_ms,
            "backup_path": doc.backup_path,
            "diff": doc.diff_preview,
        }
    if doc.status == "EXECUTING":
        raise HTTPException(
            409,
            detail={"error": "EXECUTING", "message": "This intent is already being applied."},
        )

    if doc.diff.get("divergent") and not payload.acknowledge_divergence:
        raise HTTPException(
            409,
            detail={
                "error": "INDEX_DIVERGED",
                "message": (
                    "The index has entries that diverge from their _sync_base. "
                    "Re-submit with acknowledge_divergence=true to proceed."
                ),
                "divergent_count": len(doc.diff["divergent"]),
            },
        )

    async with state.get_resource_lock(resource_type):
        t0 = time.monotonic()

        existing_index = await state.run_io(utils._read_json_sync, cfg["index"])
        if not isinstance(existing_index, list):
            existing_index = []

        _, current_gcs_sha, current_index_sha = await state.run_io(
            utils._compute_sync_diff_sync, cfg, allowed_extensions, existing_index
        )

        if current_gcs_sha != doc.gcs_snapshot_sha or current_index_sha != doc.index_snapshot_sha:
            state._log_event(
                "intent_stale",
                intent_id=doc.intent_id,
                resource_type=resource_type,
                expected_gcs_sha=doc.gcs_snapshot_sha,
                actual_gcs_sha=current_gcs_sha,
                expected_index_sha=doc.index_snapshot_sha,
                actual_index_sha=current_index_sha,
            )
            raise HTTPException(
                409,
                detail={
                    "error": "STATE_CHANGED",
                    "message": "GCS or index state changed since plan was created. Run /plan again.",
                    "intent_id": payload.intent_id,
                },
            )

        doc.status = "EXECUTING"
        intents.intent_store.put(doc)

        try:
            diff = doc.diff
            remove_set = {r["filename"] for r in diff["to_remove"]}
            new_index = [item for item in existing_index if item["filename"] not in remove_set]

            for blob_info in diff["to_add"]:
                new_entry = {
                    "id": str(uuid.uuid4()),
                    "filename": blob_info["filename"],
                    "name": blob_info["filename"],
                    "type": resource_type,
                    "date": datetime.now().strftime("%Y-%m-%d"),
                    "author": "Unknown",
                    "description": "",
                    "rating": None,
                    "url": blob_info["url"],
                    "size": blob_info["size"],
                    "_sync_base": {"size": blob_info["size"], "url": blob_info["url"]},
                }
                new_index.insert(0, new_entry)

            backup_path = await state.run_io(utils._write_json_atomic_sync, cfg["index"], new_index)

            for key in cache_keys:
                await state.cache.delete(key)

            duration_ms = round((time.monotonic() - t0) * 1000, 1)
            doc.status = "EXECUTED"
            doc.applied_at = time.time()
            doc.duration_ms = duration_ms
            doc.backup_path = backup_path
            intents.intent_store.put(doc)

            state._log_event(
                "intent_applied",
                intent_id=doc.intent_id,
                resource_type=resource_type,
                gcs_sha=doc.gcs_snapshot_sha,
                index_sha=doc.index_snapshot_sha,
                duration_ms=duration_ms,
                added=len(diff["to_add"]),
                removed=len(diff["to_remove"]),
                backup_path=backup_path,
            )

        except Exception as exc:
            doc.status = "PENDING"
            doc.error = str(exc)
            intents.intent_store.put(doc)
            logging.error(f"apply_sync failed for {resource_type}: {exc}")
            raise HTTPException(500, f"Apply failed: {str(exc)}")

    return {
        "intent_id": doc.intent_id,
        "status": "EXECUTED",
        "changes_applied": True,
        "duration_ms": doc.duration_ms,
        "backup_path": doc.backup_path,
        "diff": doc.diff_preview,
    }


def _intent_to_summary(doc: intents.SyncIntentDocument) -> dict:
    return {
        "intent_id": doc.intent_id,
        "resource_type": doc.resource_type,
        "status": doc.status,
        "created_at": datetime.utcfromtimestamp(doc.created_at).isoformat() + "Z",
        "expires_at": datetime.utcfromtimestamp(doc.expires_at).isoformat() + "Z",
        "applied_at": (
            datetime.utcfromtimestamp(doc.applied_at).isoformat() + "Z"
            if doc.applied_at else None
        ),
        "duration_ms": doc.duration_ms,
        "backup_path": doc.backup_path,
        "diff_summary": {
            "to_add": len(doc.diff.get("to_add", [])),
            "to_remove": len(doc.diff.get("to_remove", [])),
            "divergent": len(doc.diff.get("divergent", [])),
            "unchanged_count": doc.diff.get("unchanged_count", 0),
        },
        "gcs_snapshot_sha": doc.gcs_snapshot_sha,
        "index_snapshot_sha": doc.index_snapshot_sha,
    }


@router.post("/api/admin/sync-images/plan")
async def plan_sync_images():
    """Phase 1 (read-only): compute GCS vs index diff and store an intent."""
    try:
        return await _plan_sync("image", config._IMAGE_EXTS)
    except Exception as e:
        raise HTTPException(500, f"Plan failed: {str(e)}")


@router.post("/api/admin/sync-images/apply")
async def apply_sync_images(payload: models.ApplyIntentPayload):
    """Phase 2 (mutating): apply a previously-created plan intent atomically."""
    return await _apply_sync("image", config._IMAGE_EXTS, "image", payload)


@router.get("/api/admin/sync-images/intents")
async def list_image_intents(limit: int = Query(20, ge=1, le=100)):
    """Return recent sync intents for images (newest first)."""
    docs = intents.intent_store.list_recent("image", limit=limit)
    return {"intents": [_intent_to_summary(d) for d in docs]}


@router.get("/api/admin/sync-images/intents/{intent_id}")
async def get_image_intent(intent_id: str):
    """Return detail for a single image sync intent."""
    doc = intents.intent_store.get(intent_id)
    if doc is None or doc.resource_type != "image":
        raise HTTPException(404, "Intent not found")
    result = _intent_to_summary(doc)
    result["diff"] = doc.diff_preview
    return result


@router.post("/api/admin/sync-videos/plan")
async def plan_sync_videos():
    """Phase 1 (read-only): compute GCS vs index diff and store an intent."""
    try:
        return await _plan_sync("video", config._VIDEO_EXTS)
    except Exception as e:
        raise HTTPException(500, f"Plan failed: {str(e)}")


@router.post("/api/admin/sync-videos/apply")
async def apply_sync_videos(payload: models.ApplyIntentPayload):
    """Phase 2 (mutating): apply a previously-created plan intent atomically."""
    return await _apply_sync("video", config._VIDEO_EXTS, "video", payload)


@router.get("/api/admin/sync-videos/intents")
async def list_video_intents(limit: int = Query(20, ge=1, le=100)):
    """Return recent sync intents for videos (newest first)."""
    docs = intents.intent_store.list_recent("video", limit=limit)
    return {"intents": [_intent_to_summary(d) for d in docs]}


@router.get("/api/admin/sync-videos/intents/{intent_id}")
async def get_video_intent(intent_id: str):
    """Return detail for a single video sync intent."""
    doc = intents.intent_store.get(intent_id)
    if doc is None or doc.resource_type != "video":
        raise HTTPException(404, "Intent not found")
    result = _intent_to_summary(doc)
    result["diff"] = doc.diff_preview
    return result


@router.post("/api/admin/sync-images")
async def sync_images_folder_gone():
    return JSONResponse(
        status_code=410,
        content={
            "error": "ENDPOINT_RETIRED",
            "message": (
                "POST /api/admin/sync-images has been replaced by a two-phase plan/apply flow. "
                "Use POST /api/admin/sync-images/plan to create an intent, "
                "then POST /api/admin/sync-images/apply with the returned intent_id."
            ),
            "plan_endpoint": "/api/admin/sync-images/plan",
            "apply_endpoint": "/api/admin/sync-images/apply",
        },
    )


@router.post("/api/admin/sync-videos")
async def sync_videos_folder_gone():
    return JSONResponse(
        status_code=410,
        content={
            "error": "ENDPOINT_RETIRED",
            "message": (
                "POST /api/admin/sync-videos has been replaced by a two-phase plan/apply flow. "
                "Use POST /api/admin/sync-videos/plan to create an intent, "
                "then POST /api/admin/sync-videos/apply with the returned intent_id."
            ),
            "plan_endpoint": "/api/admin/sync-videos/plan",
            "apply_endpoint": "/api/admin/sync-videos/apply",
        },
    )


@router.post("/api/admin/sync")
async def sync_gcs_storage():
    report = {}
    for item_type, cfg in config.STORAGE_MAP.items():
        if item_type == "default" or item_type == "music":
            continue

        added = 0
        removed = 0

        try:
            async with state.get_resource_lock(item_type):
                blobs = await state.run_io(lambda: list(state.bucket.list_blobs(prefix=cfg["folder"])))
                actual_files = []
                for b in blobs:
                    fname = b.name.replace(cfg["folder"], "")
                    if fname and not b.name.endswith(cfg["index"]):
                        actual_files.append(fname)

                index_data = await state.run_io(utils._read_json_sync, cfg["index"])
                if not isinstance(index_data, list):
                    index_data = []

                index_map = {item["filename"]: item for item in index_data}
                disk_set = set(actual_files)

                new_index = [item for item in index_data if item["filename"] in disk_set]
                removed = len(index_data) - len(new_index)

                for filename in actual_files:
                    if filename not in index_map:
                        new_entry = {
                            "id": str(uuid.uuid4()),
                            "filename": filename,
                            "type": item_type,
                            "date": datetime.now().strftime("%Y-%m-%d"),
                            "name": filename,
                            "author": "Unknown",
                            "description": "Auto-discovered",
                            "genre": None,
                            "last_played": None
                        }

                        if filename.endswith(".json") and item_type in ["song", "pattern", "bank"]:
                            try:
                                b = state.bucket.blob(f"{cfg['folder']}{filename}")
                                content = json.loads(b.download_as_text())
                                if "name" in content:
                                    new_entry["name"] = content["name"]
                                if "author" in content:
                                    new_entry["author"] = content["author"]
                            except Exception as meta_err:
                                logging.debug("Could not extract metadata for %s: %s", filename, meta_err)

                        new_index.insert(0, new_entry)
                        added += 1

                if added > 0 or removed > 0:
                    await state.run_io(utils._write_json_sync, cfg["index"], new_index)

                report[item_type] = {"added": added, "removed": removed, "status": "synced"}
        except Exception as e:
            report[item_type] = {"error": str(e)}

    await state.clear_cache_for_type(None)
    return report
