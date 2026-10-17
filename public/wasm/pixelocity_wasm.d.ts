// TypeScript bindings for emscripten-generated code.  Automatically generated at compile time.
declare namespace RuntimeExports {
    /**
     * @param {string|null=} returnType
     * @param {Array=} argTypes
     * @param {Array=} args
     * @param {Object=} opts
     */
    function ccall(ident: any, returnType?: string, argTypes?: any[], args?: any[], opts?: any): any;
    /**
     * @param {string=} returnType
     * @param {Array=} argTypes
     * @param {Object=} opts
     */
    function cwrap(ident: any, returnType?: string, argTypes?: any[], opts?: any): any;
    /**
     * @param {number} ptr
     * @param {string} type
     */
    function getValue(ptr: number, type?: string): any;
    /**
     * @param {number} ptr
     * @param {number} value
     * @param {string} type
     */
    function setValue(ptr: number, value: number, type?: string): void;
    /**
     * Given a pointer 'ptr' to a null-terminated UTF8-encoded string in the
     * emscripten HEAP, returns a copy of that string as a Javascript String object.
     *
     * @param {number} ptr
     * @param {number=} maxBytesToRead - An optional length that specifies the
     *   maximum number of bytes to read. You can omit this parameter to scan the
     *   string until the first 0 byte. If maxBytesToRead is passed, and the string
     *   at [ptr, ptr+maxBytesToReadr[ contains a null byte in the middle, then the
     *   string will cut short at that byte index.
     * @param {boolean=} ignoreNul - If true, the function will not stop on a NUL character.
     * @return {string}
     */
    function UTF8ToString(ptr: number, maxBytesToRead?: number, ignoreNul?: boolean): string;
    function lengthBytesUTF8(str: any): number;
    function stringToUTF8(str: any, outPtr: any, maxBytesToWrite: any): any;
    let HEAPU8: Uint8Array;
    let HEAPF32: Float32Array;
}
interface WasmModule {
  _initWasmRenderer(_0: number, _1: number, _2: number): number;
  _shutdownWasmRenderer(): void;
  _loadShader(_0: number, _1: number, _2: number, _3: number, _4: number): number;
  _reloadShader(_0: number, _1: number, _2: number, _3: number, _4: number): number;
  _setActiveShader(_0: number): void;
  _setSlotShader(_0: number, _1: number): void;
  _setSlotParams(_0: number, _1: number, _2: number, _3: number, _4: number): void;
  _setSlotMode(_0: number, _1: number): void;
  _setColorFormat(_0: number): void;
  _getColorFormat(): number;
  _loadImageData(_0: number, _1: number, _2: number): void;
  _loadImageExternal(_0: number, _1: number): number;
  _uploadVideoFrame(_0: number, _1: number, _2: number): void;
  _uploadVideoExternal(_0: number, _1: number): number;
  _updateDepthMap(_0: number, _1: number, _2: number): void;
  _setInputSource(_0: number): void;
  _updateUniforms(): void;
  _setTime(_0: number): void;
  _setZoomParams(_0: number, _1: number, _2: number, _3: number): void;
  _updateMousePos(_0: number, _1: number): void;
  _setMouseDown(_0: number): void;
  _updateAudioData(_0: number, _1: number, _2: number): void;
  _updateAudioFrequencyBins(_0: number, _1: number): void;
  _addRipple(_0: number, _1: number): void;
  _clearRipples(): void;
  _isRendererInitialized(): number;
  _getFPS(): number;
  _getSupportsDeepWorkgroup(): number;
  _getSlotShaderId(_0: number): number;
  _getSlotEnabled(_0: number): number;
  _getSlotMode(_0: number): number;
  _getMaxShaderSlots(): number;
  _getCanvasCopySrcSupported(): number;
  _setCanvasCopySrc(_0: number): number;
  _getGPUTimings(_0: number, _1: number, _2: number, _3: number): void;
  _getPassTimingsJson(): number;
  _requestWorkDoneMark(): number;
  _getLastError(): number;
  _getErrorRingJson(): number;
  _clearErrorRing(): void;
  _setRecording(_0: number): void;
  _isRecording(): number;
  _getAdapterSummary(): number;
  _getLastInitErrorStage(): number;
  _getLastInitErrorMessage(): number;
  _resizeCanvas(_0: number, _1: number): number;
  _beginFrameCapture(): void;
  _getFrameCaptureState(): number;
  _readCapturedFrame(_0: number, _1: number): number;
  _endFrameCapture(): void;
  _getCanvasWidth(): number;
  _getCanvasHeight(): number;
  _main(_0: number, _1: number): number;
  _free(_0: number): void;
  _malloc(_0: number): number;
}

export type MainModule = WasmModule & typeof RuntimeExports;
export default function MainModuleFactory (options?: unknown): Promise<MainModule>;
