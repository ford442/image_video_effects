cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

# std / opt / port / -s flags come from src/contracts/wasm_compile_flags.json
# (same file build.sh reads via format-wasm-compile-flags.js) — do not paste flags here.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../src/contracts/wasm_compile_flags.json" WASM_FLAGS_JSON)
string(JSON WASM_STD GET "${WASM_FLAGS_JSON}" std)
string(REGEX REPLACE "^c\\+\\+" "" WASM_STD_NUM "${WASM_STD}")
set(CMAKE_CXX_STANDARD ${WASM_STD_NUM})

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

target_compile_features(pixelocity_wasm PUBLIC cxx_std_${WASM_STD_NUM})

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

string(JSON WASM_OPT GET "${WASM_FLAGS_JSON}" opt)
string(JSON WASM_USE_PORT GET "${WASM_FLAGS_JSON}" usePort)
string(JSON WASM_JS_OUTPUT GET "${WASM_FLAGS_JSON}" jsOutputName)
string(JSON S_COUNT LENGTH "${WASM_FLAGS_JSON}" sFlags)
math(EXPR S_LAST "${S_COUNT} - 1")
set(WASM_S_FLAGS "")
foreach(i RANGE ${S_LAST})
    string(JSON SF GET "${WASM_FLAGS_JSON}" sFlags ${i})
    list(APPEND WASM_S_FLAGS "-s${SF}")
endforeach()

target_compile_options(pixelocity_wasm PRIVATE ${WASM_OPT})

# Port and all -s flags at link time only
target_link_options(pixelocity_wasm PRIVATE
    ${WASM_OPT}
    "--use-port=${WASM_USE_PORT}"
    "-sEXPORTED_FUNCTIONS=${EXPORTED_STR}"
    "-sEXPORTED_RUNTIME_METHODS=${RUNTIME_STR}"
    ${WASM_S_FLAGS}
)

get_filename_component(WASM_OUTPUT_BASE "${WASM_JS_OUTPUT}" NAME_WE)
set_target_properties(pixelocity_wasm PROPERTIES OUTPUT_NAME "${WASM_OUTPUT_BASE}" SUFFIX ".js")
