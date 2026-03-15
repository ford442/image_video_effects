cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

set(CMAKE_CXX_STANDARD 20)

# ARCH: [Critical] Target 'pixelocity_wasm' is defined here...
add_executable(pixelocity_wasm main.cpp)

# Compile options - use the old flag for header includes
target_compile_options(pixelocity_wasm PRIVATE
  -sUSE_WEBGPU=1
  -O3
)

# ARCH: [Critical] ...but then redefined here without the source files!
# This overwrites the previous add_executable, losing main.cpp.
# The ${SOURCES} and ${HEADERS} variables are never defined.
# Result: Build will fail with undefined symbol errors.
add_executable(pixelocity_wasm ${SOURCES} ${HEADERS})

# ── emdawnwebgpu ──────────────────────────────────────────────────────────────
#
# NOTE: the canonical build path is build.sh (direct emcc invocation).
# cmake is kept here as a fallback/IDE convenience only.
#
# --use-port=emdawnwebgpu must NOT be passed as a compile option.  In cmake's
# Emscripten toolchain each TU compile command goes through emcc and the port
# system runs process_args(), which on recent Emscripten triggers:
#   "invalid command line setting `-sUSE_WEBGPU=1`"
# Safe approach: provide the include path directly; port at link time only.

# Ask emcc where its cache lives (set by emcmake via EM_CACHE env var)
if(DEFINED ENV{EM_CACHE})
    set(EM_CACHE_DIR "$ENV{EM_CACHE}")
else()
    execute_process(
        COMMAND emcc --print-cache-dir
        OUTPUT_VARIABLE EM_CACHE_DIR
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
endif()
if(NOT EM_CACHE_DIR)
    # ARCH: [Medium] Hardcoded fallback path may not work on all systems.
    # Use cmake_path or file(TO_CMAKE_PATH) for cross-platform compatibility.
    set(EM_CACHE_DIR "/tmp/emscripten_cache")
endif()

# The emdawnwebgpu port installs headers to <cache>/ports/emdawnwebgpu/include.
# build.sh runs `emcc --use-port=emdawnwebgpu -E /dev/null` first to populate it.
target_include_directories(pixelocity_wasm PRIVATE
    "${EM_CACHE_DIR}/ports/emdawnwebgpu/include"
)

# Port and all -s flags at link time only
# ARCH: [Medium] Exported functions list is hardcoded and incomplete.
# Several working functions in main.cpp are not exported:
# - updateMousePos
# - updateAudioData
# - toggleRenderer
set(EXPORTED_FUNCTIONS
    "_main,_initWasmRenderer,_shutdownWasmRenderer,_loadShader,_setActiveShader"
    ",_updateUniforms,_addRipple,_clearRipples,_getFPS,_isRendererInitialized"
    ",_loadImageData,_uploadVideoFrame,_malloc,_free"
)
string(CONCAT EXPORTED_STR ${EXPORTED_FUNCTIONS})

target_link_options(pixelocity_wasm PRIVATE
    --use-port=emdawnwebgpu
    "-sEXPORTED_FUNCTIONS=${EXPORTED_STR}"
    "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap,getValue,setValue,UTF8ToString,stringToUTF8,HEAPU8"
    "-sALLOW_MEMORY_GROWTH=1"
    "-sNO_EXIT_RUNTIME=1"
    "-sMODULARIZE=1"
    "-sEXPORT_NAME=PixelocityWASM"
)

# ARCH: [Critical] Missing source file: renderer.cpp is not included!
# The add_executable only lists main.cpp, but WebGPURenderer class
# is defined in renderer.cpp. This will cause linker errors.

# ARCH: [Medium] No target_sources() to properly organize source files.
# No source_group() for IDE organization.

# ARCH: [Medium] No installation rules (install() commands).
# Cannot use cmake --install for deployment.

# ARCH: [Low] No testing setup (enable_testing(), add_test()).
# Cannot run automated tests on the renderer.

# ARCH: [Medium] Missing compile features declaration:
# target_compile_features(pixelocity_wasm PUBLIC cxx_std_20)
# This would ensure C++20 is actually required, not just requested.

set_target_properties(pixelocity_wasm PROPERTIES SUFFIX ".js")

# ARCH: OVERALL SUMMARY FOR CMakeLists.txt:
# This build file has critical errors that prevent it from working:
# 1. Double add_executable() with the second one using undefined variables
# 2. Missing renderer.cpp from source list
# 3. Incomplete exported functions list
# 
# RECOMMENDATION: Use build.sh (which works) instead of CMake,
# or fix the CMakeLists.txt with proper source definitions.
