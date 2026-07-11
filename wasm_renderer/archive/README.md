# Historical one-off scripts

Scripts kept for archaeology — **not** part of the build or test pipeline.

| File | Purpose | Era |
|------|---------|-----|
| [`fix_renderer_cpp.py`](./fix_renderer_cpp.py) | One-line `renderer.cpp` preprocessor guard rename (`WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal` → `WGPU_SURFACE_TEXTURE_INIT`) | Pre–June 2026 emdawnwebgpu port |

Do not run these unless you understand the historical context. Current build uses `wasm_renderer/build.sh`.
