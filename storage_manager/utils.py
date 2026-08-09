# storage_manager/utils.py
import io
import os
import json
import uuid
import base64
import hashlib
import logging
import subprocess
from ftplib import FTP
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple

from fastapi.responses import StreamingResponse

from . import config, state

# --- GCS I/O HELPERS ---
def _read_json_sync(blob_path: str):
    blob = state.bucket.blob(blob_path)
    if blob.exists():
        return json.loads(blob.download_as_text())
    return []


def _write_json_sync(blob_path: str, data):
    blob = state.bucket.blob(blob_path)
    blob.upload_from_string(
        json.dumps(data),
        content_type='application/json'
    )


# --- SHARED CHAIN VALIDATION (mirrors src/services/layerChainShare.ts) ---
MAX_SHARED_SLOTS = 6
SHARED_CHAIN_VERSION = 1


def _decode_shared_chain(chain_str: str) -> Optional[dict]:
    """Decode and validate a SharedChain wire string.

    The wire format is base64url(minified JSON) where the JSON bytes are
    UTF-8. Returns the parsed chain dict if valid, otherwise None.
    Mirrors encodeChain/decodeChain in src/services/layerChainShare.ts.
    """
    if not chain_str:
        return None

    # base64url → standard base64 padding
    padded = chain_str.replace("-", "+").replace("_", "/")
    pad_len = (-len(padded)) % 4
    if pad_len:
        padded += "=" * pad_len

    try:
        raw_bytes = base64.b64decode(padded, validate=True)
        json_str = raw_bytes.decode("utf-8")
        raw = json.loads(json_str)
    except Exception:
        return None

    if not isinstance(raw, dict):
        return None
    if raw.get("v") != SHARED_CHAIN_VERSION:
        return None
    slots = raw.get("slots")
    if not isinstance(slots, list):
        return None
    if len(slots) > MAX_SHARED_SLOTS:
        return None

    valid_slots = []
    for slot in slots:
        if not isinstance(slot, dict):
            return None
        shader_id = slot.get("shaderId")
        if shader_id is not None and not isinstance(shader_id, str):
            return None
        params = slot.get("params")
        if params is not None:
            if not isinstance(params, dict):
                return None
            for key, value in params.items():
                if not isinstance(key, str):
                    return None
                if not isinstance(value, (int, float)):
                    return None
        enabled = slot.get("enabled")
        if enabled is not None and not isinstance(enabled, bool):
            return None
        mode = slot.get("mode")
        if mode is not None and mode not in ("chained", "parallel"):
            return None
        valid_slots.append(slot)

    return {"v": SHARED_CHAIN_VERSION, "slots": valid_slots}


def _write_json_atomic_sync(blob_path: str, data) -> str:
    """Atomically overwrite *blob_path* with *data* and return the backup path.

    Steps:
    1. Upload JSON to ``<blob_path>.tmp.<uuid>``
    2. If the current blob exists, copy it to ``<blob_path>.backup.<ts>``
    3. Upload the new content directly to ``<blob_path>`` (GCS upload is atomic)
    4. Delete the temp blob
    Returns the backup blob path (or "" when no prior blob existed).
    """
    tmp_path = f"{blob_path}.tmp.{uuid.uuid4().hex}"
    ts = datetime.utcnow().strftime("%Y%m%dT%H%M%SZ")
    backup_path = f"{blob_path}.backup.{ts}"
    json_bytes = json.dumps(data).encode()

    # Upload to tmp
    tmp_blob = state.bucket.blob(tmp_path)
    tmp_blob.upload_from_string(json_bytes, content_type="application/json")

    # Backup current blob if it exists
    main_blob = state.bucket.blob(blob_path)
    actual_backup = ""
    if main_blob.exists():
        state.bucket.copy_blob(main_blob, state.bucket, backup_path)
        actual_backup = backup_path

    # Overwrite main blob (GCS upload is server-side atomic)
    main_blob.upload_from_string(json_bytes, content_type="application/json")

    # Remove temp blob
    try:
        tmp_blob.delete()
    except Exception:
        pass

    return actual_backup


def _compute_sync_diff_sync(cfg: dict, allowed_extensions: tuple, existing_index: list) -> Tuple[dict, str, str]:
    """Stream-iterate GCS blobs and compute a three-way diff vs *existing_index*.

    Returns ``(diff_full, gcs_snapshot_sha, index_snapshot_sha)`` where
    *diff_full* contains the complete (uncapped) diff arrays.
    """
    index_map = {item["filename"]: item for item in existing_index}
    index_sha = hashlib.sha256(
        json.dumps(existing_index, sort_keys=True).encode()
    ).hexdigest()

    gcs_blobs: List[dict] = []          # lightweight: name + size + url only
    gcs_name_size: List[Tuple[str, int]] = []     # for deterministic SHA

    index_folder = cfg["index"].split("/")[-1]  # e.g. "_images.json"

    for blob in state.bucket.list_blobs(prefix=cfg["folder"]):
        fname = blob.name[len(cfg["folder"]):]
        if not fname or fname == index_folder or blob.name == cfg["index"]:
            continue
        # Skip backup/tmp blobs created by _write_json_atomic_sync
        if ".backup." in fname or ".tmp." in fname:
            continue
        if not any(fname.lower().endswith(ext) for ext in allowed_extensions):
            continue
        gcs_blobs.append({"filename": fname, "name": fname, "size": blob.size, "url": blob.public_url})
        gcs_name_size.append((fname, blob.size))

    # Deterministic SHA over sorted (name, size) pairs
    hasher = hashlib.sha256()
    for pair in sorted(gcs_name_size):
        hasher.update(f"{pair[0]}:{pair[1]}\n".encode())
    gcs_sha = hasher.hexdigest()

    gcs_filename_set = {b["filename"] for b in gcs_blobs}
    to_add: List[dict] = []
    divergent: List[dict] = []
    unchanged_count = 0

    for blob_info in gcs_blobs:
        fname = blob_info["filename"]
        if fname not in index_map:
            to_add.append(blob_info)
        else:
            idx_entry = index_map[fname]
            sync_base = idx_entry.get("_sync_base")
            if sync_base and (
                sync_base.get("size") != blob_info["size"]
                or sync_base.get("url") != blob_info["url"]
            ):
                divergent.append({"filename": fname, "gcs": blob_info, "index": idx_entry, "sync_base": sync_base})
            else:
                unchanged_count += 1

    to_remove: List[dict] = [
        {"filename": item["filename"], "id": item.get("id")}
        for item in existing_index
        if item["filename"] not in gcs_filename_set
    ]

    diff_full = {
        "to_add": to_add,
        "to_remove": to_remove,
        "divergent": divergent,
        "unchanged_count": unchanged_count,
    }
    return diff_full, gcs_sha, index_sha


def _build_diff_preview(diff_full: dict) -> Tuple[dict, bool]:
    """Return (diff_preview, diff_preview_truncated) capped at DIFF_PREVIEW_CAP items."""
    from .intents import DIFF_PREVIEW_CAP
    truncated = False
    preview = {}
    for key in ("to_add", "to_remove", "divergent"):
        items = diff_full[key]
        if len(items) > DIFF_PREVIEW_CAP:
            preview[key] = items[:DIFF_PREVIEW_CAP]
            truncated = True
        else:
            preview[key] = items
    preview["unchanged_count"] = diff_full["unchanged_count"]
    return preview, truncated


def _run_subprocess_sync(args: List[str], cwd: Path, timeout_seconds: int = 600) -> dict:
    """Run a trusted subprocess command for shader-list maintenance tasks."""
    allowed_commands = {
        ("git", "pull", "--ff-only"),
        ("node", "scripts/generate_shader_lists.js"),
    }
    if tuple(args) not in allowed_commands:
        logging.warning("Rejected unsupported subprocess command: %s", " ".join(args))
        raise RuntimeError(f"Unsupported command: {' '.join(args)}")

    try:
        completed = subprocess.run(
            args,
            cwd=str(cwd),
            shell=False,
            capture_output=True,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError(f"Command timed out after {timeout_seconds}s: {' '.join(args)}")

    max_output_chars = 20000
    stdout = (completed.stdout or "")[:max_output_chars]
    stderr = (completed.stderr or "")[:max_output_chars]
    if completed.returncode == 0:
        logging.info(
            "Command succeeded: %s | stdout=%s | stderr=%s",
            " ".join(args),
            stdout.strip(),
            stderr.strip(),
        )
    else:
        logging.warning(
            "Command failed: %s (code=%s) | stdout=%s | stderr=%s",
            " ".join(args),
            completed.returncode,
            stdout.strip(),
            stderr.strip(),
        )
    return {
        "command": " ".join(args),
        "returncode": completed.returncode,
        "stdout": stdout,
        "stderr": stderr,
    }


def _rescan_shader_lists_sync(pull_latest: bool = True) -> dict:
    """Regenerate shader-list JSON files in-repo and upload them to storage."""
    repo_root = Path(
        os.environ.get(
            "IMAGE_VIDEO_EFFECTS_REPO_PATH",
            str(Path(__file__).resolve().parent.parent),
        )
    ).resolve()
    output_dir = repo_root / "public" / "shader-lists"
    generator_script = repo_root / "scripts" / "generate_shader_lists.js"

    if not repo_root.exists():
        raise RuntimeError(f"Repository path not found: {repo_root}")
    if not (repo_root / ".git").exists():
        raise RuntimeError(f"Repository path is missing .git metadata: {repo_root}")
    if not generator_script.exists():
        raise RuntimeError(f"Generator script not found: {generator_script}")
    if not output_dir.exists():
        raise RuntimeError(f"Output directory not found: {output_dir}")

    commands: List[List[str]] = []
    if pull_latest:
        commands.append(["git", "pull", "--ff-only"])
    # Generate shader lists with absolute URLs pointing to the static file server
    # where WGSL files are hosted (test.1ink.us/image_video_effects).
    commands.append(
        [
            "node",
            "scripts/generate_shader_lists.js",
            "--base-url=https://test.1ink.us/image_video_effects",
        ]
    )

    command_results = []
    for args in commands:
        result = _run_subprocess_sync(args, repo_root)
        command_results.append(result)
        if result["returncode"] != 0:
            stderr = (result["stderr"] or "").strip()
            stdout = (result["stdout"] or "").strip()
            details = stderr or stdout or "No output"
            raise RuntimeError(f"Command failed: {result['command']}. {details}")

    uploaded_files: List[str] = []
    upload_errors: List[str] = []
    for json_path in sorted(output_dir.glob("*.json")):
        storage_path = f"shader-lists/{json_path.name}"
        try:
            blob = state.bucket.blob(storage_path)
            blob.upload_from_filename(str(json_path), content_type="application/json")
        except Exception as e:
            upload_errors.append(f"{json_path} -> {storage_path}: {str(e)}")
            continue
        uploaded_files.append(json_path.name)

    if not uploaded_files:
        raise RuntimeError(
            f"No shader list JSON files found in {output_dir}. "
            "Verify generate_shader_lists.js succeeded and outputs files to public/shader-lists."
        )
    if upload_errors:
        raise RuntimeError("Some shader lists failed to upload: " + "; ".join(upload_errors))

    return {
        "success": True,
        "pull_latest": pull_latest,
        "uploaded_count": len(uploaded_files),
        "uploaded_files": uploaded_files,
        "commands": [
            {"command": item["command"], "returncode": item["returncode"]}
            for item in command_results
        ],
    }


def _parse_range_header(range_header: str, total_size: int) -> Optional[Tuple[int, int]]:
    """Parse a 'bytes=start-end' Range header.

    Returns (start, end) integers (inclusive, 0-based) or None if the header
    is absent, malformed, or unsatisfiable.  ``end`` may be ``total_size - 1``
    when not specified by the client.
    """
    if not range_header or not range_header.startswith("bytes="):
        return None
    try:
        byte_range = range_header[6:]
        start_str, _, end_str = byte_range.partition("-")
        start = int(start_str) if start_str else 0
        end = int(end_str) if end_str else total_size - 1
        if start < 0 or end >= total_size or start > end:
            return None
        return start, end
    except (ValueError, AttributeError):
        return None


async def _proxy_media_response(
    blob,
    media_type: str,
    filename: str,
    range_header: Optional[str],
) -> StreamingResponse:
    """Hardened proxy fallback: download blob bytes in a bounded thread, return
    a StreamingResponse (200) or partial-content response (206 for Range requests).

    Uses ``_media_semaphore`` to cap concurrent proxy threads so a small VPS
    cannot be overwhelmed.  The GCS client's built-in ``DEFAULT_RETRY`` is
    applied to the download, so transient auth/network hiccups are retried
    automatically without hand-rolled refresh logic.
    """
    from google.cloud.storage.retry import DEFAULT_RETRY

    blob_size = blob.size  # may be None if metadata not loaded

    range_parsed = None
    if range_header and blob_size is not None:
        range_parsed = _parse_range_header(range_header, blob_size)

    async with state._media_semaphore:
        if range_parsed is not None:
            start, end = range_parsed
            # GCS download_as_bytes end is *exclusive*
            data = await state.run_io(
                blob.download_as_bytes,
                start=start,
                end=end + 1,
                retry=DEFAULT_RETRY,
            )
        else:
            data = await state.run_io(blob.download_as_bytes, retry=DEFAULT_RETRY)

    if range_parsed is not None:
        start, end = range_parsed
        content_length = end - start + 1
        headers = {
            "Content-Disposition": f'inline; filename="{filename}"',
            "Accept-Ranges": "bytes",
            "Content-Range": f"bytes {start}-{end}/{blob_size}",
            "Content-Length": str(content_length),
            "Cache-Control": "private, max-age=0",
        }
        return StreamingResponse(
            iter([data]),
            status_code=206,
            media_type=media_type,
            headers=headers,
        )

    headers = {
        "Content-Disposition": f'inline; filename="{filename}"',
        "Accept-Ranges": "bytes",
        "Cache-Control": "private, max-age=0",
    }
    return StreamingResponse(
        iter([data]),
        media_type=media_type,
        headers=headers,
    )


def _fetch_ftp_file_sync(filename: str) -> str:
    """Connect to FTP, download a .wgsl file, return as UTF-8 string."""
    ftp = FTP(config.FTP_HOST)
    try:
        ftp.login(config.FTP_USER, config.FTP_PASS)
        ftp.cwd(config.FTP_DIR)
        buffer = io.BytesIO()
        ftp.retrbinary(f"RETR {filename}", buffer.write)
        buffer.seek(0)
        return buffer.read().decode("utf-8")
    finally:
        try:
            ftp.quit()
        except Exception:
            ftp.close()


def _list_ftp_files_sync() -> list:
    """List all .wgsl files on the FTP server."""
    ftp = FTP(config.FTP_HOST)
    try:
        ftp.login(config.FTP_USER, config.FTP_PASS)
        ftp.cwd(config.FTP_DIR)
        files = ftp.nlst()
        return [f for f in files if f.endswith(".wgsl")]
    finally:
        try:
            ftp.quit()
        except Exception:
            ftp.close()
