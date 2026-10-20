cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

# ── Thin wrapper around build.sh ──────────────────────────────────────────────
#
# CANONICAL BUILD: wasm_renderer/build.sh (single-pass em++ per variant). It
# reads src/contracts/wasm_compile_flags.json + wasm_exports.json and emits both
# artifacts: pixelocity_wasm.{js,wasm} (ASYNCIFY fallback) and
# pixelocity_wasm_jspi.{js,wasm} (JSPI primary).
#
# This file deliberately has NO add_executable and NO -s link options, so CMake
# cannot produce a third flag set (verify:wasm-invariants enforces this). The
# old executable target also leaked --use-port=emdawnwebgpu into per-TU
# compiles ("invalid command line setting `-sUSE_WEBGPU=1`").
#
#   cmake -S wasm_renderer -B wasm_renderer/build-cmake
#   cmake --build wasm_renderer/build-cmake --target pixelocity_wasm
#
# IDE indexing: this project compiles no TUs, so CMAKE_EXPORT_COMPILE_COMMANDS
# yields an empty database. Use `npm run wasm:compile-commands` instead — it
# renders compile_commands.json from the contract's std / opt / sources with the
# emdawnwebgpu headers on the include path (port stays link-time only).

# C++ standard for IDE indexing comes from the contract (same value build.sh uses).
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/../src/contracts/wasm_compile_flags.json" WASM_FLAGS_JSON)
string(JSON WASM_STD GET "${WASM_FLAGS_JSON}" std)
string(REGEX REPLACE "^c\\+\\+" "" WASM_STD_NUM "${WASM_STD}")

# Headers-only target for IDEs (include paths + std; compiles nothing).
if(DEFINED ENV{EM_CACHE})
    set(EM_CACHE_DIR "$ENV{EM_CACHE}")
else()
    set(EM_CACHE_DIR "/tmp/emscripten_cache")
endif()
add_library(pixelocity_wasm_headers INTERFACE)
target_include_directories(pixelocity_wasm_headers INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${EM_CACHE_DIR}/ports/emdawnwebgpu/emdawnwebgpu_pkg/webgpu/include"
)
target_compile_features(pixelocity_wasm_headers INTERFACE cxx_std_${WASM_STD_NUM})

add_custom_target(pixelocity_wasm
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/build.sh"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
    USES_TERMINAL
    COMMENT "Building WASM renderer via build.sh (both contract variants)"
)
