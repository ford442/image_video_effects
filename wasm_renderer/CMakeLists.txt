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

# ── emdawnwebgpu port ──────────────────────────────────────────────────────────
#
# --use-port=emdawnwebgpu must only be passed at LINK time.  Passing it at
# compile time causes emdawnwebgpu.py's process_args() to run, which sets the
# internal USE_WEBGPU flag; newer Emscripten then rejects that deprecated flag
# with "invalid command line setting `-sUSE_WEBGPU=1`".
#
# For compilation we derive the header include path from the emscripten cache
# directory so that #include <webgpu/webgpu.h> resolves without needing the
# port flag at compile time.

# Ask emcc where its cache lives (falls back to $EM_CACHE / /tmp/emscripten_cache)
execute_process(
    COMMAND emcc --print-cache-dir
    OUTPUT_VARIABLE EM_CACHE_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if(NOT EM_CACHE_DIR)
    if(DEFINED ENV{EM_CACHE})
        set(EM_CACHE_DIR "$ENV{EM_CACHE}")
    else()
        set(EM_CACHE_DIR "/tmp/emscripten_cache")
    endif()
endif()

# emdawnwebgpu installs its headers under <cache>/ports/emdawnwebgpu/include
# The pre-build step (embuilder build emdawnwebgpu) in build.sh ensures this
# directory exists before cmake runs.
target_include_directories(pixelocity_wasm PRIVATE
    "${EM_CACHE_DIR}/ports/emdawnwebgpu/include"
)

# Port flag only at link time
target_link_options(pixelocity_wasm PRIVATE --use-port=emdawnwebgpu)

# ── Exported symbols ──────────────────────────────────────────────────────────
set(EXPORTED_FUNCTIONS
    "_main"
    "_initWasmRenderer"
    "_shutdownWasmRenderer"
    "_loadShader"
    "_setActiveShader"
    "_updateUniforms"
    "_addRipple"
    "_clearRipples"
    "_getFPS"
    "_isRendererInitialized"
    "_loadImageData"
    "_uploadVideoFrame"
    "_malloc"
    "_free"
)

string(JOIN "," EXPORTED_FUNCTIONS_STR ${EXPORTED_FUNCTIONS})

set_target_properties(pixelocity_wasm PROPERTIES
    SUFFIX ".js"
)

target_link_options(pixelocity_wasm PRIVATE
    "-sEXPORTED_FUNCTIONS=${EXPORTED_FUNCTIONS_STR}"
    "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8,HEAPU8"
    "-sALLOW_MEMORY_GROWTH=1"
    "-sNO_EXIT_RUNTIME=1"
    "-sMODULARIZE=1"
    "-sEXPORT_NAME=PixelocityWASM"
)
