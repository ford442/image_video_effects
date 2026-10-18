# scripts/storage_manager_app/admin.py
import datetime
import json
import uuid

from fastapi import APIRouter, HTTPException, Query

from .config import (
    INDEX_LOCK,
    STORAGE_MAP,
    _read_json_sync,
    _write_json_sync,
    bucket,
    cache,
    run_io,
)

router = APIRouter()


@router.get("/")
def home():
    return {
        "status": "online",
        "provider": "Google Cloud Storage",
        "benchmark_ready": True,
        "features": ["shader_ratings", "play_tracking", "coordinate_system"],
        "endpoints": {
            "ratings_ui": "/ratings",
            "shaders": "/api/shaders",
            "shader_rate": "/api/shaders/{id}/rate",
            "shader_play": "/api/shaders/{id}/play",
            "sync_coords": "/api/admin/sync-coordinates"
        }
    }


@router.get("/api/health")
async def health_check():
    status_report = {}
    for item_type, config in STORAGE_MAP.items():
        try:
            index_data = await run_io(_read_json_sync, config["index"])
            status_report[item_type] = {
                "count": len(index_data) if isinstance(index_data, list) else 0,
                "status": "connected"
            }
        except Exception as e:
            status_report[item_type] = {"count": 0, "status": "error", "error": str(e)}
    return {
        "status": "online",
        "gcs_connected": bucket is not None,
        "storage": status_report
    }


@router.post("/api/admin/sync")
async def sync_gcs_storage():
    report = {}
    async with INDEX_LOCK:
        for item_type, config in STORAGE_MAP.items():
            if item_type == "default" or item_type == "music":
                continue

            added = 0
            removed = 0

            try:
                blobs = await run_io(lambda: list(bucket.list_blobs(prefix=config["folder"])))
                actual_files = []
                for b in blobs:
                    fname = b.name.replace(config["folder"], "")
                    if fname and not b.name.endswith(config["index"]):
                        actual_files.append(fname)

                index_data = await run_io(_read_json_sync, config["index"])
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
                            "date": datetime.datetime.now().strftime("%Y-%m-%d"),
                            "name": filename,
                            "author": "Unknown",
                            "description": "Auto-discovered",
                            "genre": None,
                            "last_played": None
                        }

                        if filename.endswith(".json") and item_type in ["song", "pattern", "bank"]:
                            try:
                                b = bucket.blob(f"{config['folder']}{filename}")
                                content = json.loads(b.download_as_text())
                                if "name" in content:
                                    new_entry["name"] = content["name"]
                                if "author" in content:
                                    new_entry["author"] = content["author"]
                            except Exception:
                                pass

                        new_index.insert(0, new_entry)
                        added += 1

                if added > 0 or removed > 0:
                    await run_io(_write_json_sync, config["index"], new_index)

                report[item_type] = {"added": added, "removed": removed, "status": "synced"}
            except Exception as e:
                report[item_type] = {"error": str(e)}

        await cache.clear()
        return report


@router.post("/api/admin/seed-test-samples")
async def seed_test_samples():
    config = STORAGE_MAP["sample"]
    test_samples = [
        {"id": "test-flac-001", "name": "Test Ambient Track.flac", "filename": "test-flac-001.flac",
         "type": "sample", "author": "Test Artist", "date": "2024-02-09", "description": "Test ambient", "rating": 8, "genre": "ambient"},
        {"id": "test-wav-002", "name": "Test Bass Line.wav", "filename": "test-wav-002.wav",
         "type": "sample", "author": "Test Artist", "date": "2024-02-09", "description": "Test bass", "rating": 7, "genre": "bass"},
        {"id": "test-flac-003", "name": "Unrated Demo.flac", "filename": "test-flac-003.flac",
         "type": "sample", "author": "Unknown", "date": "2024-02-09", "description": "Demo", "rating": None, "genre": None}
    ]

    async with INDEX_LOCK:
        try:
            index_data = await run_io(_read_json_sync, config["index"])
            if not isinstance(index_data, list):
                index_data = []

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


@router.post("/api/admin/seed-brainfuck-examples")
async def seed_brainfuck_examples():
    config = STORAGE_MAP["brainfuck"]
    examples = [
        {"id": "bf-mandelbrot", "name": "Mandelbrot Set", "type": "brainfuck", "author": "Classic BF",
         "date": "2026-03-07", "description": "bf2wasm + -O3", "filename": "mandelbrot.bf",
         "execution_time_ms": 1247, "cells": 30000, "relative_to_cpp": 0.26, "relative_to_js": 1.48},
        {"id": "bf-fib", "name": "Fibonacci n=40", "type": "brainfuck", "author": "Classic BF",
         "date": "2026-03-07", "description": "fuck compiler", "filename": "fib.bf",
         "execution_time_ms": 47, "cells": 30000, "relative_to_cpp": 0.17, "relative_to_js": 2.1},
        {"id": "bf-sieve", "name": "Prime Sieve n=1M", "type": "brainfuck", "author": "Classic BF",
         "date": "2026-03-07", "description": "brainfuck2wasm", "filename": "sieve.bf",
         "execution_time_ms": 184, "cells": 16384, "relative_to_cpp": 0.22, "relative_to_js": 1.9}
    ]

    async with INDEX_LOCK:
        idx = await run_io(_read_json_sync, config["index"]) or []
        existing_ids = {item.get("id") for item in idx}
        added = 0
        for ex in examples:
            if ex["id"] not in existing_ids:
                idx.insert(0, ex)
                added += 1
        await run_io(_write_json_sync, config["index"], idx)
        await cache.delete("library:brainfuck")
        await cache.delete("library:all")
        return {"success": True, "added": added, "total": len(idx)}


@router.get("/api/storage/files")
async def list_gcs_folder(folder: str = Query(..., description="Folder name, e.g., 'songs' or 'samples'")):
    config = STORAGE_MAP.get(folder)
    prefix = config["folder"] if config else f"{folder}/"

    try:
        def _fetch_blobs():
            blobs = bucket.list_blobs(prefix=prefix, delimiter="/")
            file_list = []
            for blob in blobs:
                name = blob.name.replace(prefix, "")
                if name:
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
