import re
content = open("wasm_renderer/renderer.cpp").read()
content = content.replace("#ifdef WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal", "#if defined(WGPU_SURFACE_TEXTURE_INIT)")
open("wasm_renderer/renderer.cpp", "w").write(content)
