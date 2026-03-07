cmake_minimum_required(VERSION 3.20)
project(PixelocityWASM CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -sEXPORTED_FUNCTIONS=_main,_initWasmRenderer,_toggleRenderer,_updateVideoFrame,_updateAudioData,_updateMousePos -sEXPORTED_RUNTIME_METHODS=ccall,cwrap -sALLOW_MEMORY_GROWTH=1 -sERROR_ON_UNDEFINED_SYMBOLS=0")

# Use the official emdawnwebgpu port
set(EMSCRIPTEN_PORTS "emdawnwebgpu")

add_executable(pixelocity_wasm main.cpp)

target_link_options(pixelocity_wasm PRIVATE
  --use-port=emdawnwebgpu
  -sALLOW_MEMORY_GROWTH=1
  -sMAX_WEBGL_VERSION=2
  -sMODULARIZE=1
  -sEXPORT_NAME="PixelocityWASM"
)

set_target_properties(pixelocity_wasm PROPERTIES SUFFIX ".js")
