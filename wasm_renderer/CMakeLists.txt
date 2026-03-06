cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

set(CMAKE_CXX_STANDARD 20)

add_executable(pixelocity_wasm main.cpp)
set_target_properties(pixelocity_wasm PROPERTIES SUFFIX ".js")

target_compile_options(pixelocity_wasm PRIVATE 
  -sUSE_WEBGPU=1 
  -O3
)

target_link_options(pixelocity_wasm PRIVATE
  -sUSE_WEBGPU=1
  -sEXPORTED_FUNCTIONS=_main,_initWasmRenderer
  -sEXPORTED_RUNTIME_METHODS=ccall,cwrap
  -sMODULARIZE=1
  -sEXPORT_NAME="PixelocityWASM"
  -O3
)
