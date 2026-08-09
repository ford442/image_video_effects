# storage_manager/routes/ftp.py
import logging
from datetime import datetime
from fastapi import APIRouter, HTTPException

from .. import config, state, utils

router = APIRouter()


@router.get("/api/ftp/shaders/{filename}")
async def get_ftp_shader(filename: str):
    """Fetch a shader directly from FTP with cache. Returns JSON with code and metadata."""
    if not config.FTP_ENABLED:
        raise HTTPException(503, "FTP not configured")
    if not filename.endswith(".wgsl"):
        filename += ".wgsl"
    cache_key = f"ftp_shader_code:{filename}"
    cached = await state.cache.get(cache_key)
    if cached:
        return {"source": "cache", "filename": filename, "code": cached}
    try:
        code = await state.run_io(utils._fetch_ftp_file_sync, filename)
        await state.cache.set(cache_key, code, ttl=3600)
        return {"source": "ftp", "filename": filename, "code": code}
    except Exception as e:
        logging.error(f"FTP fetch failed for {filename}: {e}")
        raise HTTPException(404, f"FTP fetch failed: {str(e)}")


@router.post("/api/admin/sync-ftp-to-gcs")
async def sync_ftp_to_gcs():
    """Scan FTP directory and import missing .wgsl shaders into GCS bucket."""
    if not config.FTP_ENABLED:
        raise HTTPException(503, "FTP not configured")
    cfg = config.STORAGE_MAP["shader"]
    report = {"added": 0, "skipped": 0, "errors": []}

    async with state.get_resource_lock("shader"):
        try:
            ftp_files = await state.run_io(utils._list_ftp_files_sync)
            index = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index, list):
                index = []
            existing = {item.get("filename", "") for item in index}

            for fname in ftp_files:
                if fname in existing:
                    report["skipped"] += 1
                    continue
                try:
                    code = await state.run_io(utils._fetch_ftp_file_sync, fname)
                    blob = state.bucket.blob(f"{cfg['folder']}{fname}")
                    await state.run_io(blob.upload_from_string, code, content_type="text/plain")
                    shader_id = fname.replace(".wgsl", "")
                    index.insert(0, {
                        "id": shader_id,
                        "name": shader_id.replace("-", " ").title(),
                        "filename": fname,
                        "author": "ftp-import",
                        "date": datetime.now().strftime("%Y-%m-%d"),
                        "type": "shader",
                        "description": "Imported from FTP",
                        "tags": ["ftp-import"],
                        "stars": 0.0,
                        "rating_count": 0,
                        "play_count": 0
                    })
                    report["added"] += 1
                except Exception as e:
                    logging.error(f"Failed to import {fname} from FTP: {e}")
                    report["errors"].append({"file": fname, "error": str(e)})

            if report["added"] > 0:
                await state.run_io(utils._write_json_sync, cfg["index"], index)
            await state.clear_cache_for_type(None)
        except Exception as e:
            raise HTTPException(500, f"FTP sync failed: {str(e)}")

    report["total"] = len(index)
    return report
