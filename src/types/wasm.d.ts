declare module '/wasm/pixelocity_wasm.js' {
  export interface PixelocityWASM {
    _initWasmRenderer: (width: number, height: number, agentCount: number) => void;
    _toggleRenderer: (useWasm: number) => void;
    _updateVideoFrame: (ctx: number) => void;
    _updateAudioData: (bass: number, mid: number, treble: number) => void;
    _updateMousePos: (x: number, y: number) => void;
    default?: () => Promise<void>;
  }
  
  const wasmModule: PixelocityWASM;
  export default wasmModule;
}
