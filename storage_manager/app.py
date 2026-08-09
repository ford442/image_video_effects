# storage_manager/app.py - Thin Orchestrator & Barrel Module
import sys
import json
import types
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

from . import config, state, models, middleware, intents, utils
from .routes import system, locations, shaders, preset_packs, library, media, sync, ftp


@asynccontextmanager
async def lifespan(app_instance: FastAPI):
    if config.CREDENTIALS_JSON or config.BUCKET_NAME:
        try:
            state.gcs_client = state.get_gcs_client()
            if config.BUCKET_NAME:
                state.bucket = state.gcs_client.bucket(config.BUCKET_NAME)
        except Exception as e:
            logging.error(f"Failed to initialize GCS client: {e}")

    if config.CREDENTIALS_JSON:
        try:
            info = json.loads(config.CREDENTIALS_JSON)
            if "private_key" in info:
                state._has_signing_creds = True
        except Exception:
            state._has_signing_creds = False
    else:
        state._has_signing_creds = False

    state._media_semaphore = asyncio.Semaphore(config.MEDIA_STREAM_MAX_CONCURRENT)
    yield


app = FastAPI(title="Storage Manager API", lifespan=lifespan)

# Add Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=config.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(middleware.RateLimitMiddleware)

# OpenTelemetry
if state._OTEL_AVAILABLE:
    try:
        from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
        FastAPIInstrumentor.instrument_app(app)
    except Exception as e:
        logging.warning(f"OpenTelemetry instrumentation failed: {e}")

# Include Routers
app.include_router(system.router)
app.include_router(locations.router)
app.include_router(shaders.router)
app.include_router(preset_packs.router)
app.include_router(library.router)
app.include_router(media.router)
app.include_router(sync.router)
app.include_router(ftp.router)

_delegate_modules = (state, intents, config, utils, models, middleware)


class _AppModule(types.ModuleType):
    def __getattr__(self, name: str):
        for target in _delegate_modules:
            if hasattr(target, name):
                return getattr(target, name)
        raise AttributeError(f"module '{self.__name__}' has no attribute '{name}'")

    def __setattr__(self, name: str, value):
        for target in _delegate_modules:
            if hasattr(target, name):
                setattr(target, name, value)
                if name == "intent_store":
                    intents.INTENT_STORE = value
                elif name == "INTENT_STORE":
                    intents.intent_store = value
                return
        if name in ("bucket", "gcs_client", "io_executor", "_has_signing_creds", "_media_semaphore", "cache", "RESOURCE_LOCKS"):
            setattr(state, name, value)
        elif name in ("INTENT_STORE", "intent_store"):
            setattr(intents, name, value)
            if name == "intent_store":
                intents.INTENT_STORE = value
            elif name == "INTENT_STORE":
                intents.intent_store = value
        elif name in ("_rescan_shader_lists_sync", "_read_json_sync", "_write_json_sync", "_write_json_atomic_sync", "_run_subprocess_sync", "_compute_sync_diff_sync"):
            setattr(utils, name, value)
        else:
            super().__setattr__(name, value)

    def __delattr__(self, name: str):
        for target in _delegate_modules:
            if hasattr(target, name):
                try:
                    delattr(target, name)
                except AttributeError:
                    pass
                return
        try:
            super().__delattr__(name)
        except AttributeError:
            pass


_old_mod = sys.modules[__name__]
_new_mod = _AppModule(__name__, _old_mod.__doc__)
_new_mod.__dict__.update(_old_mod.__dict__)
sys.modules[__name__] = _new_mod


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=7860)
