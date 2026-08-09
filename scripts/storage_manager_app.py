# app.py - Storage Manager (Complete v3 with Shader Ratings)
# Structure score: 9/10 (fully featured)

import sys
from pathlib import Path

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

try:
    from .storage_manager_app.admin import router as admin_router
    from .storage_manager_app.config import (
        ALLOWED_ORIGINS,
        BUCKET_NAME,
        CREDENTIALS_JSON,
        INDEX_LOCK,
        STORAGE_MAP,
        CoordinateSyncPayload,
        ItemPayload,
        MetaData,
        MetaPatch,
        SampleMetaUpdatePayload,
        ShaderCategory,
        SortBy,
        _read_json_sync,
        _write_json_sync,
        bucket,
        cache,
        gcs_client,
        get_gcs_client,
        io_executor,
        lifespan,
        run_io,
    )
    from .storage_manager_app.media import router as media_router
    from .storage_manager_app.ratings_ui import router as ratings_router
    from .storage_manager_app.shaders import router as shaders_router
except ImportError:
    from storage_manager_app.admin import router as admin_router
    from storage_manager_app.config import (
        ALLOWED_ORIGINS,
        BUCKET_NAME,
        CREDENTIALS_JSON,
        INDEX_LOCK,
        STORAGE_MAP,
        CoordinateSyncPayload,
        ItemPayload,
        MetaData,
        MetaPatch,
        SampleMetaUpdatePayload,
        ShaderCategory,
        SortBy,
        _read_json_sync,
        _write_json_sync,
        bucket,
        cache,
        gcs_client,
        get_gcs_client,
        io_executor,
        lifespan,
        run_io,
    )
    from storage_manager_app.media import router as media_router
    from storage_manager_app.ratings_ui import router as ratings_router
    from storage_manager_app.shaders import router as shaders_router

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include sub-routers
app.include_router(admin_router)
app.include_router(ratings_router)
app.include_router(shaders_router)
app.include_router(media_router)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=7860)
