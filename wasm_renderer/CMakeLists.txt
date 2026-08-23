cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

set(CMAKE_CXX_STANDARD 20)

add_executable(pixelocity_wasm
    main.cpp
    renderer.cpp
    device.cpp
    resources.cpp
    pipeline.cpp
    frame.cpp
    timing.cpp
    audio_depth.cpp
    wasm_internal.cpp
)

target_compile_features(pixelocity_wasm PUBLIC cxx_std_20)
target_compile_options(pixelocity_wasm PRIVATE -O2)

# ── emdawnwebgpu ──────────────────────────────────────────────────────────────
#
# CANONICAL BUILD: wasm_renderer/build.sh (single-pass emcc). CI and npm run
# wasm:build invoke build.sh only — do NOT use this CMake target in CI.
#
# cmake is kept here as a fallback/IDE convenience only.
# EXPORTED_FUNCTIONS / EXPORTED_RUNTIME_METHODS come from
# src/contracts/wasm_exports.json — do not paste a second list here.
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
    set(EM_CACHE_DIR "/tmp/emscripten_cache")
endif()

# The emdawnwebgpu port installs headers to <cache>/ports/emdawnwebgpu/include.
# build.sh runs `emcc --use-port=emdawnwebgpu -E /dev/null` first to populate it.
target_include_directories(pixelocity_wasm PRIVATE
    "${EM_CACHE_DIR}/ports/emdawnwebgpu/include"
)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../src/contracts/wasm_exports.json" WASM_EXPORTS_JSON)

string(JSON FUNC_COUNT LENGTH "${WASM_EXPORTS_JSON}" exportedFunctions)
math(EXPR FUNC_LAST "${FUNC_COUNT} - 1")
set(EXPORTED_STR "")
foreach(i RANGE ${FUNC_LAST})
    string(JSON FN GET "${WASM_EXPORTS_JSON}" exportedFunctions ${i})
    if(EXPORTED_STR STREQUAL "")
        set(EXPORTED_STR "${FN}")
    else()
        set(EXPORTED_STR "${EXPORTED_STR},${FN}")
    endif()
endforeach()

string(JSON RT_COUNT LENGTH "${WASM_EXPORTS_JSON}" exportedRuntimeMethods)
math(EXPR RT_LAST "${RT_COUNT} - 1")
set(RUNTIME_STR "")
foreach(i RANGE ${RT_LAST})
    string(JSON RN GET "${WASM_EXPORTS_JSON}" exportedRuntimeMethods ${i})
    if(RUNTIME_STR STREQUAL "")
        set(RUNTIME_STR "${RN}")
    else()
        set(RUNTIME_STR "${RUNTIME_STR},${RN}")
    endif()
endforeach()

# Port and all -s flags at link time only
target_link_options(pixelocity_wasm PRIVATE
    -O2
    --use-port=emdawnwebgpu
    "-sEXPORTED_FUNCTIONS=${EXPORTED_STR}"
    "-sEXPORTED_RUNTIME_METHODS=${RUNTIME_STR}"
    "-sALLOW_MEMORY_GROWTH=1"
    "-sGROWABLE_ARRAYBUFFERS=0"
    "-sNO_EXIT_RUNTIME=1"
    "-sMODULARIZE=1"
    "-sEXPORT_NAME=PixelocityWASM"
    "-sASYNCIFY"
)

set_target_properties(pixelocity_wasm PROPERTIES SUFFIX ".js")
