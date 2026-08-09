# storage_manager/routes/system.py
import uuid
from datetime import datetime
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import HTMLResponse

from .. import config, state, models, utils

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
    for item_type, cfg in config.STORAGE_MAP.items():
        try:
            index_data = await state.run_io(utils._read_json_sync, cfg["index"])
            status_report[item_type] = {
                "count": len(index_data) if isinstance(index_data, list) else 0,
                "status": "connected"
            }
        except Exception as e:
            status_report[item_type] = {"count": 0, "status": "error", "error": str(e)}
    return {
        "status": "online",
        "gcs_connected": state.bucket is not None,
        "storage": status_report
    }


@router.post("/api/admin/sync-music")
async def sync_music_folder():
    """Scans the music/ folder and rebuilds the music index."""
    cfg = config.STORAGE_MAP["music"]
    report = {"added": 0, "removed": 0}

    async with state.get_resource_lock("music"):
        try:
            blobs = await state.run_io(lambda: list(state.bucket.list_blobs(prefix=cfg["folder"])))

            audio_files = []
            for b in blobs:
                fname = b.name.replace(cfg["folder"], "")
                if fname and not b.name.endswith(cfg["index"]):
                    lower = fname.lower()
                    if lower.endswith(('.flac', '.wav', '.mp3', '.ogg')):
                        audio_files.append({
                            "filename": fname,
                            "name": fname,
                            "size": b.size,
                            "url": b.public_url
                        })

            index_data = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index_data, list):
                index_data = []

            index_map = {item["filename"]: item for item in index_data}
            disk_set = set(f["filename"] for f in audio_files)

            new_index = [item for item in index_data if item["filename"] in disk_set]
            report["removed"] = len(index_data) - len(new_index)

            for file_info in audio_files:
                if file_info["filename"] not in index_map:
                    new_entry = {
                        "id": str(uuid.uuid4()),
                        "filename": file_info["filename"],
                        "name": file_info["name"],
                        "type": "music",
                        "date": datetime.now().strftime("%Y-%m-%d"),
                        "author": "Unknown",
                        "description": "",
                        "rating": None,
                        "genre": None,
                        "last_played": None,
                        "url": file_info["url"],
                        "size": file_info["size"]
                    }
                    new_index.insert(0, new_entry)
                    report["added"] += 1

            if report["added"] > 0 or report["removed"] > 0:
                await state.run_io(utils._write_json_sync, cfg["index"], new_index)

            await state.cache.delete("library:music")
            await state.cache.delete("library:all")

            report["total"] = len(new_index)
            return report

        except Exception as e:
            raise HTTPException(500, f"Failed to sync music: {str(e)}")


@router.post("/api/admin/seed-test-samples")
@router.post("/api/seed/test-samples")
async def seed_test_samples():
    """Creates test sample entries for development."""
    cfg = config.STORAGE_MAP["sample"]
    test_samples = [
        {
            "id": "test-flac-001",
            "name": "Test Ambient Track.flac",
            "filename": "test-flac-001.flac",
            "type": "sample",
            "author": "Test Artist",
            "date": "2024-02-09",
            "description": "Test ambient track",
            "rating": 8,
            "genre": "ambient"
        },
        {
            "id": "test-wav-002",
            "name": "Test Bass Line.wav",
            "filename": "test-wav-002.wav",
            "type": "sample",
            "author": "Test Artist",
            "date": "2024-02-09",
            "description": "Test bass line",
            "rating": 7,
            "genre": "bass"
        },
        {
            "id": "test-flac-003",
            "name": "Unrated Demo.flac",
            "filename": "test-flac-003.flac",
            "type": "sample",
            "author": "Unknown",
            "date": "2024-02-09",
            "description": "Demo without rating",
            "rating": None,
            "genre": None
        }
    ]

    async with state.get_resource_lock("sample"):
        try:
            index_data = await state.run_io(utils._read_json_sync, cfg["index"])
            if not isinstance(index_data, list):
                index_data = []

            existing_ids = {item.get("id") for item in index_data}
            added = 0
            for sample in test_samples:
                if sample["id"] not in existing_ids:
                    index_data.insert(0, sample)
                    added += 1

            await state.run_io(utils._write_json_sync, cfg["index"], index_data)
            await state.cache.delete("library:sample")
            await state.cache.delete("library:all")

            return {"success": True, "added": added, "total": len(index_data)}
        except Exception as e:
            raise HTTPException(500, f"Failed to seed: {str(e)}")


@router.post("/api/admin/seed-brainfuck-examples")
@router.post("/api/seed/brainfuck")
async def seed_brainfuck_examples():
    cfg = config.STORAGE_MAP["brainfuck"]
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

    async with state.get_resource_lock("brainfuck"):
        idx = await state.run_io(utils._read_json_sync, cfg["index"]) or []
        existing_ids = {item.get("id") for item in idx}
        added = 0
        for ex in examples:
            if ex["id"] not in existing_ids:
                idx.insert(0, ex)
                added += 1
        await state.run_io(utils._write_json_sync, cfg["index"], idx)
        await state.cache.delete("library:brainfuck")
        await state.cache.delete("library:all")
        return {"success": True, "added": added, "total": len(idx)}


@router.get("/api/storage/files")
@router.get("/api/gcs/folder")
async def list_gcs_folder(folder: str = Query(..., description="Folder name, e.g., 'songs' or 'samples'")):
    cfg = config.STORAGE_MAP.get(folder)
    prefix = cfg["folder"] if cfg else f"{folder}/"

    try:
        def _fetch_blobs():
            blobs = state.bucket.list_blobs(prefix=prefix, delimiter="/")
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

        files = await state.run_io(_fetch_blobs)
        return {"folder": prefix, "count": len(files), "files": files}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/api/shaders/categories")
async def list_categories():
    """Return the category hierarchy for UI rendering."""
    return {
        "groups": config.CATEGORY_GROUPS,
        "all_categories": [c.value for c in models.ShaderCategory]
    }


@router.get("/ratings", response_class=HTMLResponse)
async def ratings_ui():
    """Serves the interactive star rating interface."""
    return """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Shader Ratings</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #0a0a0f 0%, #1a1a2e 100%);
      min-height: 100vh;
      color: #e0e0e0;
      padding: 20px;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    h1 {
      text-align: center;
      margin-bottom: 30px;
      font-size: 28px;
      background: linear-gradient(90deg, #4a9eff, #a855f7);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
    }
    .filters {
      display: flex;
      gap: 15px;
      margin-bottom: 25px;
      flex-wrap: wrap;
      justify-content: center;
    }
    .filters select, .filters input {
      padding: 10px 15px;
      background: rgba(255,255,255,0.05);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 8px;
      color: #fff;
      font-size: 14px;
      outline: none;
    }
    .filters select option { background: #1a1a2e; }
    .shader-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
      gap: 20px;
    }
    .shader-card {
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 12px;
      padding: 20px;
      transition: all 0.3s ease;
    }
    .shader-card:hover {
      background: rgba(255,255,255,0.06);
      transform: translateY(-2px);
      box-shadow: 0 8px 32px rgba(0,0,0,0.3);
    }
    .shader-header {
      display: flex;
      justify-content: space-between;
      align-items: flex-start;
      margin-bottom: 12px;
    }
    .shader-name {
      font-size: 16px;
      font-weight: 600;
      color: #fff;
      line-height: 1.3;
    }
    .shader-id {
      font-size: 11px;
      color: #666;
      font-family: monospace;
      margin-top: 4px;
    }
    .category-badge {
      padding: 4px 10px;
      background: rgba(74, 158, 255, 0.15);
      border: 1px solid rgba(74, 158, 255, 0.3);
      border-radius: 20px;
      font-size: 11px;
      color: #4a9eff;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }
    .stars-container {
      display: flex;
      gap: 4px;
      margin: 15px 0;
    }
    .star {
      cursor: pointer;
      transition: all 0.2s;
      width: 28px;
      height: 28px;
    }
    .star:hover { transform: scale(1.15); }
    .star.filled path { fill: #ffd700; stroke: #ffd700; }
    .star.empty path { fill: transparent; stroke: #555; }
    .rating-info {
      display: flex;
      justify-content: space-between;
      align-items: center;
      font-size: 13px;
      color: #888;
    }
    .avg-rating {
      font-size: 18px;
      font-weight: 700;
      color: #ffd700;
    }
    .vote-count { color: #666; }
    .toast {
      position: fixed;
      bottom: 30px;
      left: 50%;
      transform: translateX(-50%) translateY(100px);
      background: rgba(30, 130, 76, 0.95);
      color: white;
      padding: 12px 24px;
      border-radius: 8px;
      font-size: 14px;
      opacity: 0;
      transition: all 0.3s ease;
      z-index: 1000;
    }
    .toast.show {
      opacity: 1;
      transform: translateX(-50%) translateY(0);
    }
    .loading {
      text-align: center;
      padding: 60px;
      color: #666;
    }
    .spinner {
      display: inline-block;
      width: 40px;
      height: 40px;
      border: 3px solid rgba(255,255,255,0.1);
      border-top-color: #4a9eff;
      border-radius: 50%;
      animation: spin 1s infinite linear;
    }
    @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="container">
    <h1>Shader Ratings & Analytics</h1>
    
    <div class="filters">
      <select id="categoryFilter">
        <option value="">All Categories</option>
        <option value="generative">Generative</option>
        <option value="reactive">Reactive</option>
        <option value="transition">Transition</option>
        <option value="filter">Filter</option>
        <option value="distortion">Distortion</option>
      </select>
      
      <select id="sortFilter">
        <option value="rating">Highest Rated</option>
        <option value="plays">Most Played</option>
        <option value="name">Name A-Z</option>
      </select>
      
      <input type="text" id="searchInput" placeholder="Search shaders...">
    </div>

    <div id="shaderList" class="shader-grid">
      <div class="loading">
        <div class="spinner"></div>
        <p style="margin-top: 15px;">Loading shaders...</p>
      </div>
    </div>
  </div>

  <div id="toast" class="toast">Rating saved!</div>

  <script>
    const API_URL = window.location.origin;
    let shaders = [];
    let currentCategory = '';
    let currentSort = 'rating';
    let searchQuery = '';

    document.getElementById('categoryFilter').addEventListener('change', (e) => {
      currentCategory = e.target.value;
      renderShaders();
    });

    document.getElementById('sortFilter').addEventListener('change', (e) => {
      currentSort = e.target.value;
      loadShaders();
    });

    document.getElementById('searchInput').addEventListener('input', (e) => {
      searchQuery = e.target.value.toLowerCase();
      renderShaders();
    });

    function showToast(msg) {
      const toast = document.getElementById('toast');
      toast.textContent = msg;
      toast.classList.add('show');
      setTimeout(() => toast.classList.remove('show'), 2000);
    }

    async function rateShader(id, stars) {
      try {
        const response = await fetch(`${API_URL}/api/shaders/${id}/rate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ rating: stars })
        });
        
        if (response.ok) {
          const data = await response.json();
          showToast(`Rated ${stars} stars!`);
          
          const shader = shaders.find(s => s.id === id);
          if (shader) {
            shader.stars = data.stars;
            shader.rating_count = data.rating_count;
            renderShaders();
          }
        }
      } catch (err) {
        console.error(err);
      }
    }

    function createStarSVG(filled) {
      return `
        <svg class="star ${filled ? 'filled' : 'empty'}" viewBox="0 0 24 24">
          <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
        </svg>
      `;
    }

    function renderShaders() {
      const filtered = shaders.filter(s => {
        const matchesCategory = !currentCategory || s.category === currentCategory;
        const matchesSearch = !searchQuery || 
          s.name.toLowerCase().includes(searchQuery) || 
          s.id.toLowerCase().includes(searchQuery);
        return matchesCategory && matchesSearch;
      });

      const container = document.getElementById('shaderList');
      if (filtered.length === 0) {
        container.innerHTML = '<div class="loading">No shaders found</div>';
        return;
      }

      container.innerHTML = filtered.map(s => `
        <div class="shader-card">
          <div class="shader-header">
            <div>
              <div class="shader-name">${s.name}</div>
              <div class="shader-id">${s.id}</div>
            </div>
            <span class="category-badge">${s.category || 'shader'}</span>
          </div>
          
          <div class="stars-container" onclick="event.stopPropagation()">
            ${[1,2,3,4,5].map(star => `
              <span onclick="rateShader('${s.id}', ${star})">
                ${createStarSVG(star <= Math.round(s.stars || 0))}
              </span>
            `).join('')}
          </div>
          
          <div class="rating-info">
            <div>
              <span class="avg-rating">${(s.stars || 0).toFixed(1)}</span>
              <span class="vote-count">(${s.rating_count || 0} votes)</span>
            </div>
            <div style="font-size: 12px; color: #555;">▶ ${s.play_count || 0} plays</div>
          </div>
        </div>
      `).join('');
    }

    async function loadShaders() {
      try {
        const response = await fetch(`${API_URL}/api/shaders?sort_by=${currentSort}`);
        if (!response.ok) throw new Error('Failed to load');
        
        shaders = await response.json();
        renderShaders();
      } catch (err) {
        document.getElementById('shaderList').innerHTML = `
          <div class="loading">
            <div style="color: #c0392b; margin-bottom: 10px;">Failed to load shaders</div>
            <div style="font-size: 13px;">${err.message}</div>
          </div>
        `;
        console.error(err);
      }
    }

    loadShaders();
  </script>
</body>
</html>
"""
