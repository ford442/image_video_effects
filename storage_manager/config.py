# storage_manager/config.py
import os

# --- GCS / GCP CONFIGURATION ---
BUCKET_NAME = os.environ.get("GCP_BUCKET_NAME")
CREDENTIALS_JSON = os.environ.get("GCP_CREDENTIALS")

# --- FTP CONFIGURATION ---
FTP_HOST = os.environ.get("FTP_HOST", "")
FTP_USER = os.environ.get("FTP_USER", "")
FTP_PASS = os.environ.get("FTP_PASS", "")
FTP_DIR = os.environ.get("FTP_DIR", "/shaders")
FTP_ENABLED = bool(FTP_HOST)

# --- STORAGE MAP ---
STORAGE_MAP = {
    "song": {"folder": "songs/", "index": "songs/_songs.json"},
    "pattern": {"folder": "patterns/", "index": "patterns/_patterns.json"},
    "bank": {"folder": "banks/", "index": "banks/_banks.json"},
    "sample": {"folder": "samples/", "index": "samples/_samples.json"},
    "music": {"folder": "music/", "index": "music/_music.json"},
    "note": {"folder": "notes/", "index": "notes/_notes.json"},
    "location": {"folder": "locations/", "index": "locations/_locations.json"},
    "shader": {"folder": "shaders/", "index": "shaders/_shaders.json"},
    "preset_pack": {"folder": "preset_packs/", "index": "preset_packs/_preset_packs.json"},
    "brainfuck": {
        "folder": "brainfuck/",
        "index": "brainfuck/_brainfuck.json"
    },
    "image": {"folder": "images/", "index": "images/_images.json"},
    "video": {"folder": "videos/", "index": "videos/_videos.json"},
    "default": {"folder": "misc/", "index": "misc/_misc.json"},
}

# --- REDIS CONFIGURATION ---
REDIS_URL = os.environ.get("REDIS_URL")
REDIS_HOST = os.environ.get("REDIS_HOST")
REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
REDIS_DB = int(os.environ.get("REDIS_DB", "0"))
REDIS_PASSWORD = os.environ.get("REDIS_PASSWORD")

# --- RATE LIMIT CONFIGURATION ---
RATE_LIMIT_REQUESTS = int(os.environ.get("RATE_LIMIT_REQUESTS", "120"))
RATE_LIMIT_WINDOW = int(os.environ.get("RATE_LIMIT_WINDOW", "60"))
RATE_LIMIT_PATHS = [path.strip() for path in os.environ.get("RATE_LIMIT_PATHS", "/api").split(",") if path.strip()]
RATE_LIMIT_IP_HEADER = os.environ.get("RATE_LIMIT_IP_HEADER", "X-Forwarded-For")

# --- MEDIA STREAMING CONFIGURATION ---
GCS_SIGNED_URL_MAX_SECONDS = 604800
GCS_SIGNED_URL_EXPIRATION_SECONDS: int = min(
    int(os.environ.get("GCS_SIGNED_URL_EXPIRATION_SECONDS", "3600")),
    GCS_SIGNED_URL_MAX_SECONDS,
)
MEDIA_STREAM_MAX_CONCURRENT: int = int(os.environ.get("MEDIA_STREAM_MAX_CONCURRENT", "10"))

# --- CORS & EXTENSIONS ---
ALLOWED_ORIGINS = [
    "http://localhost:3000",
    "http://localhost:5173",
    "https://test1.1ink.us",
    "https://test.1ink.us",
    "https://storage.1ink.us",
    "*"
]

_IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg"}
_VIDEO_EXTS = {".mp4", ".webm", ".mov", ".mkv", ".avi"}

# --- CATEGORY GROUPS ---
CATEGORY_GROUPS = {
    "interactive": {"label": "🖱️ Interactive", "description": "Mouse and touch-driven effects", "subcategories": ["interactive", "interactive-mouse"]},
    "generative": {"label": "✨ Generative", "description": "Procedural and algorithmic art", "subcategories": ["generative", "simulation"]},
    "distortion": {"label": "🔮 Distortion", "description": "Warp, bend, and transform space", "subcategories": ["distortion", "warp"]},
    "image": {"label": "🖼️ Image", "description": "Filters, color grading, adjustments", "subcategories": ["image", "filter"]},
    "artistic": {"label": "🎨 Artistic", "description": "Stylized looks and painterly effects", "subcategories": ["artistic"]},
    "retro": {"label": "📺 Retro & Glitch", "description": "Vintage, analog, digital corruption", "subcategories": ["retro-glitch", "glitch"]},
    "geometric": {"label": "📐 Geometric", "description": "Patterns, tessellation, shapes", "subcategories": ["geometric", "tessellation", "geometry"]},
    "visual": {"label": "🎬 Visual Effects", "description": "Particles, glow, overlays, VFX", "subcategories": ["visual-effects", "lighting"]},
    "liquid": {"label": "💧 Liquid", "description": "Fluid, water, oil, viscous effects", "subcategories": ["liquid", "liquid-effects"]},
    "other": {"label": "🔧 Other", "description": "Miscellaneous and specialized", "subcategories": ["transition", "feedback", "shader", "reactive"]}
}
