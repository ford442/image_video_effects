#!/usr/bin/env python3
"""HISTORICAL — archived one-off patch (pre–June 2026 emdawnwebgpu).
See wasm_renderer/archive/README.md. Not used by build.sh or CI."""
import re
content = open("wasm_renderer/renderer.cpp").read()
content = content.replace("#ifdef WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal", "#if defined(WGPU_SURFACE_TEXTURE_INIT)")
open("wasm_renderer/renderer.cpp", "w").write(content)
