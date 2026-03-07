cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

set(CMAKE_CXX_STANDARD 20)

add_executable(pixelocity_wasm main.cpp)

# Use Emscripten's built-in WebGPU support (works with Emscripten 3.1.50+)
target_compile_options(pixelocity_wasm PRIVATE -sUSE_WEBGPU=1)

target_link_options(pixelocity_wasm PRIVATE -sUSE_WEBGPU=1)

set_target_properties(pixelocity_wasm PROPERTIES 
  SUFFIX ".js"
  LINK_FLAGS "-sEXPORTED_FUNCTIONS=_main,_initWasmRenderer -sEXPORTED_RUNTIME_METHODS=ccall,cwrap -sALLOW_MEMORY_GROWTH=1 -sNO_EXIT_RUNTIME=1"
)
