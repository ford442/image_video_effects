# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: wasm-renderer.smoke.spec.ts >> WASM renderer handles shader loading with minimal console errors
- Location: tests/wasm-renderer.smoke.spec.ts:234:5

# Error details

```
Error: page.evaluate: TextDecoder.decode: ArrayBufferView branch of (ArrayBufferView or ArrayBuffer) can't be a resizable ArrayBuffer or ArrayBufferView
UTF8ArrayToString@http://localhost:3457/wasm/pixelocity_wasm.js:1:10049
UTF8ToString@http://localhost:3457/wasm/pixelocity_wasm.js:1:10600
convertReturnValue@http://localhost:3457/wasm/pixelocity_wasm.js:1:63598
onDone@http://localhost:3457/wasm/pixelocity_wasm.js:1:64033
ccall@http://localhost:3457/wasm/pixelocity_wasm.js:1:64187
G@http://localhost:3457/static/js/main.9e0342ba.js:2:201657
l@http://localhost:3457/static/js/main.9e0342ba.js:2:201919
getDiagnostics@http://localhost:3457/static/js/main.9e0342ba.js:2:220054
getDiagnostics@http://localhost:3457/static/js/main.9e0342ba.js:2:269748
@debugger eval code line 303 > eval:3:349
evaluate@debugger eval code:305:16
@debugger eval code:1:44
@debugger eval code:1:62

```