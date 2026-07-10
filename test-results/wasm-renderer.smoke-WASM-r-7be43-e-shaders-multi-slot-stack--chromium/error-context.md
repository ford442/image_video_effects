# Instructions

- Following Playwright test failed.
- Explain why, be concise, respect Playwright best practices.
- Provide a snippet of code with the fix, if possible.

# Test info

- Name: wasm-renderer.smoke.spec.ts >> WASM renderer loads multiple shaders (multi-slot stack)
- Location: tests/wasm-renderer.smoke.spec.ts:198:5

# Error details

```
Error: page.evaluate: TypeError: Failed to execute 'decode' on 'TextDecoder': The provided ArrayBuffer value must not be resizable
    at UTF8ArrayToString (http://localhost:3457/wasm/pixelocity_wasm.js:1:10049)
    at UTF8ToString (http://localhost:3457/wasm/pixelocity_wasm.js:1:10600)
    at convertReturnValue (http://localhost:3457/wasm/pixelocity_wasm.js:1:63598)
    at onDone (http://localhost:3457/wasm/pixelocity_wasm.js:1:64033)
    at Object.ccall (http://localhost:3457/wasm/pixelocity_wasm.js:1:64187)
    at G (http://localhost:3457/static/js/main.9e0342ba.js:2:201657)
    at Module.l (http://localhost:3457/static/js/main.9e0342ba.js:2:201919)
    at dA.getDiagnostics (http://localhost:3457/static/js/main.9e0342ba.js:2:220054)
    at jA.getDiagnostics (http://localhost:3457/static/js/main.9e0342ba.js:2:269748)
    at eval (eval at evaluate (:303:30), <anonymous>:3:354)
```