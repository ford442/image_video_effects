# Add these to your Storage Manager app.py

from fastapi.responses import HTMLResponse, FileResponse
from fastapi.staticfiles import StaticFiles
import os

# ========================= STATIC FILES =========================
# Mount static directory for serving the ratings UI
STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")
os.makedirs(STATIC_DIR, exist_ok=True)

# Serve static files (css, js, images)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# ========================= RATINGS UI ENDPOINTS =========================

@app.get("/ratings", response_class=HTMLResponse)
async def ratings_ui():
    """Serves the interactive star rating interface."""
    html_content = """<!DOCTYPE html>
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
      animation: spin 1s linear infinite;
      margin-bottom: 15px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    .sort-buttons {
      display: flex;
      gap: 8px;
      justify-content: center;
      margin-bottom: 20px;
    }
    .sort-btn {
      padding: 8px 16px;
      background: rgba(255,255,255,0.05);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 20px;
      color: #888;
      font-size: 13px;
      cursor: pointer;
      transition: all 0.2s;
    }
    .sort-btn:hover, .sort-btn.active {
      background: rgba(74, 158, 255, 0.2);
      border-color: rgba(74, 158, 255, 0.5);
      color: #4a9eff;
    }
    .coordinate-badge {
      display: inline-block;
      padding: 2px 6px;
      background: rgba(168, 85, 247, 0.15);
      border: 1px solid rgba(168, 85, 247, 0.3);
      border-radius: 4px;
      font-family: monospace;
      font-size: 11px;
      color: #a855f7;
      margin-left: 8px;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>⭐ Shader Ratings</h1>
    
    <div class="sort-buttons">
      <button class="sort-btn active" onclick="sortBy('rating')">⭐ By Rating</button>
      <button class="sort-btn" onclick="sortBy('date')">📅 By Date</button>
      <button class="sort-btn" onclick="sortBy('name')">🔤 By Name</button>
      <button class="sort-btn" onclick="sortBy('coordinate')">🔢 By Coordinate</button>
    </div>

    <div class="filters">
      <select id="categoryFilter" onchange="applyFilters()">
        <option value="">All Categories</option>
        <option value="generative">Generative</option>
        <option value="reactive">Reactive</option>
        <option value="transition">Transition</option>
        <option value="filter">Filter</option>
        <option value="distortion">Distortion</option>
      </select>
      <select id="minRating" onchange="applyFilters()">
        <option value="0">Any Rating</option>
        <option value="4.5">⭐⭐⭐⭐⭐ (4.5+)</option>
        <option value="4">⭐⭐⭐⭐ (4+)</option>
        <option value="3">⭐⭐⭐ (3+)</option>
      </select>
      <input type="text" id="search" placeholder="Search shaders..." onkeyup="applyFilters()">
    </div>

    <div id="shaderList" class="shader-grid">
      <div class="loading">
        <div class="spinner"></div>
        <div>Loading shaders...</div>
      </div>
    </div>
  </div>

  <div id="toast" class="toast"></div>

  <script>
    const API_URL = '';
    let shaders = [];
    let currentSort = 'rating';

    function getStarSvg(filled) {
      return `<svg class="star ${filled ? 'filled' : 'empty'}" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
        <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" 
              fill="none" stroke-width="1.5" stroke-linejoin="round"/>
      </svg>`;
    }

    function renderStars(rating, count, shaderId) {
      const fullStars = Math.floor(rating);
      let html = '<div class="stars-container">';
      
      for (let i = 1; i <= 5; i++) {
        html += `<div onclick="rateShader('${shaderId}', ${i})" title="Rate ${i} star${i>1?'s':''}">${getStarSvg(i <= fullStars)}</div>`;
      }
      
      html += '</div>';
      html += `
        <div class="rating-info">
          <span class="avg-rating">${rating > 0 ? rating.toFixed(1) : '—'}</span>
          <span class="vote-count">${count} vote${count !== 1 ? 's' : ''}</span>
        </div>
      `;
      return html;
    }

    function showToast(message) {
      const toast = document.getElementById('toast');
      toast.textContent = message;
      toast.classList.add('show');
      setTimeout(() => toast.classList.remove('show'), 2500);
    }

    async function rateShader(shaderId, stars) {
      try {
        const formData = new FormData();
        formData.append('stars', stars);
        
        const response = await fetch(`${API_URL}/api/shaders/${shaderId}/rate`, {
          method: 'POST',
          body: formData
        });
        
        if (!response.ok) throw new Error('Failed to rate');
        
        const data = await response.json();
        showToast(`⭐ Rated ${stars} stars! New average: ${data.stars.toFixed(1)}`);
        
        const shader = shaders.find(s => s.id === shaderId);
        if (shader) {
          shader.stars = data.stars;
          shader.rating_count = data.rating_count;
          renderShaders();
        }
      } catch (err) {
        showToast('❌ Failed to submit rating');
        console.error(err);
      }
    }

    function sortBy(field) {
      currentSort = field;
      document.querySelectorAll('.sort-btn').forEach(btn => btn.classList.remove('active'));
      event.target.classList.add('active');
      
      const sortFns = {
        rating: (a, b) => b.stars - a.stars,
        date: (a, b) => new Date(b.date || 0) - new Date(a.date || 0),
        name: (a, b) => (a.name || '').localeCompare(b.name || ''),
        coordinate: (a, b) => (a.coordinate || 0) - (b.coordinate || 0)
      };
      
      shaders.sort(sortFns[field]);
      applyFilters();
    }

    function applyFilters() {
      const category = document.getElementById('categoryFilter').value;
      const minRating = parseFloat(document.getElementById('minRating').value);
      const search = document.getElementById('search').value.toLowerCase();
      
      let filtered = shaders.filter(s => {
        if (category && !s.tags?.includes(category) && s.type !== category) return false;
        if (minRating > 0 && (s.stars || 0) < minRating) return false;
        if (search && !s.name?.toLowerCase().includes(search) && !s.id.toLowerCase().includes(search)) return false;
        return true;
      });
      
      renderShaders(filtered);
    }

    function renderShaders(shaderList = shaders) {
      const container = document.getElementById('shaderList');
      
      if (shaderList.length === 0) {
        container.innerHTML = '<div class="loading">No shaders found</div>';
        return;
      }
      
      container.innerHTML = shaderList.map(shader => `
        <div class="shader-card">
          <div class="shader-header">
            <div>
              <div class="shader-name">
                ${shader.name || shader.id}
                ${shader.coordinate ? `<span class="coordinate-badge">#${shader.coordinate}</span>` : ''}
              </div>
              <div class="shader-id">${shader.id}</div>
            </div>
            <span class="category-badge">${shader.type || 'shader'}</span>
          </div>
          ${renderStars(shader.stars || 0, shader.rating_count || 0, shader.id)}
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
</html>"""
    return html_content


# ========================= PLAY COUNT TRACKING =========================

@app.post("/api/shaders/{shader_id}/play")
async def record_shader_play(shader_id: str):
    """Records that a shader was viewed/played. Increments play_count."""
    config = STORAGE_MAP["shader"]
    index_path = config["index"]
    now = datetime.now().isoformat()
    
    async with INDEX_LOCK:
        try:
            index_data = await run_io(_read_json_sync, index_path)
            if not isinstance(index_data, list):
                raise HTTPException(status_code=500, detail="Shader index corrupted")
            
            entry = next((item for item in index_data if item.get("id") == shader_id), None)
            if not entry:
                raise HTTPException(status_code=404, detail="Shader not found")
            
            # Increment play count
            entry["play_count"] = (entry.get("play_count") or 0) + 1
            entry["last_played"] = now
            
            await run_io(_write_json_sync, index_path, index_data)
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
            raise HTTPException(status_code=500, detail=f"Failed to record play: {str(e)}")


# ========================= COORDINATE SYNC ENDPOINT =========================

class CoordinateSyncPayload(BaseModel):
    coordinates: dict  # {shader_id: coordinate_number}
    overwrite: bool = False


@app.post("/api/admin/sync-coordinates")
async def sync_shader_coordinates(payload: CoordinateSyncPayload):
    """
    Syncs shader coordinates from shader_coordinates.json.
    Call this after running assign_coordinates.py
    """
    config = STORAGE_MAP["shader"]
    index_path = config["index"]
    
    async with INDEX_LOCK:
        try:
            index_data = await run_io(_read_json_sync, index_path)
            if not isinstance(index_data, list):
                index_data = []
            
            updated = 0
            skipped = 0
            
            for i, entry in enumerate(index_data):
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
                await run_io(_write_json_sync, index_path, index_data)
                await cache.delete("shaders:list")
            
            return {
                "success": True,
                "updated": updated,
                "skipped": skipped,
                "total_in_index": len(index_data)
            }
            
        except Exception as e:
            logging.error(f"Failed to sync coordinates: {e}")
            raise HTTPException(status_code=500, detail=f"Sync failed: {str(e)}")
