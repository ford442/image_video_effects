cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

set(CMAKE_CXX_STANDARD 20)

add_executable(pixelocity_wasm main.cpp)

# Compile options - use the old flag for header includes
target_compile_options(pixelocity_wasm PRIVATE
  -sUSE_WEBGPU=1
  -O3
)

target_link_options(pixelocity_wasm PRIVATE
  --use-port=emdawnwebgpu
  -sEXPORTED_FUNCTIONS=_main,_initWasmRenderer,_toggleRenderer,_updateVideoFrame,_updateAudioData,_updateMousePos
  -sEXPORTED_RUNTIME_METHODS=ccall,cwrap
  -sALLOW_MEMORY_GROWTH=1
  -sMAX_WEBGL_VERSION=2
  -sMODULARIZE=1
  -sEXPORT_NAME="PixelocityWASM"
  -sERROR_ON_UNDEFINED_SYMBOLS=0
  -O3
)

set_target_properties(pixelocity_wasm PROPERTIES SUFFIX ".js")
