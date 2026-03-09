cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

set(CMAKE_CXX_STANDARD 20)

# Source files
set(SOURCES
    main.cpp
    renderer.cpp
)

set(HEADERS
    renderer.h
)

add_executable(pixelocity_wasm ${SOURCES} ${HEADERS})

# Use emdawnwebgpu port with modern Emscripten (5.0+)
target_compile_options(pixelocity_wasm PRIVATE --use-port=emdawnwebgpu)

target_link_options(pixelocity_wasm PRIVATE --use-port=emdawnwebgpu)

# Export all necessary functions for JavaScript interop
set(EXPORTED_FUNCTIONS "_main,_initWasmRenderer,_shutdownWasmRenderer,_loadShader,_setActiveShader,_updateUniforms,_addRipple,_clearRipples,_getFPS,_isRendererInitialized")

set_target_properties(pixelocity_wasm PROPERTIES 
  SUFFIX ".js"
  LINK_FLAGS "-sEXPORTED_FUNCTIONS=${EXPORTED_FUNCTIONS} -sEXPORTED_RUNTIME_METHODS=ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8 -sALLOW_MEMORY_GROWTH=1 -sNO_EXIT_RUNTIME=1 -sMODULARIZE=1 -sEXPORT_NAME=PixelocityWASM"
)
