cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

set(CMAKE_CXX_STANDARD 20)

add_executable(pixelocity_wasm main.cpp)

# Modern emdawnwebgpu port — NO -sUSE_WEBGPU=1
# compile flags are minimal; the link portion handles the port
# (O3 automatically applied by CMake generator if desired)
#
# NOTE: the build cache must be cleared if you ever switched from the
# old template since CMake preserves -sUSE_WEBGPU=1 in the cache.

# compile options left blank as we only need the port at link time
#target_compile_options(pixelocity_wasm PRIVATE
#  -O3
#)

# link against the emdawnwebgpu port and expose necessary exports
target_link_libraries(pixelocity_wasm PRIVATE emdawnwebgpu)

set_target_properties(pixelocity_wasm PROPERTIES 
  SUFFIX ".js"
  LINK_FLAGS "-sEXPORTED_FUNCTIONS=_main,_initWasmRenderer -sEXPORTED_RUNTIME_METHODS=ccall,cwrap -sALLOW_MEMORY_GROWTH=1 -sNO_EXIT_RUNTIME=1"
)

set_target_properties(pixelocity_wasm PROPERTIES SUFFIX ".js")
