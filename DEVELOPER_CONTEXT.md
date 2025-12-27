# Developer Context & System Architecture

> **Agent Note:** Read this document first. It contains the "unwritten rules" and architectural intent that will save you from breaking the renderer or the synchronization logic.

## 1. High-Level Architecture & Intent

### Core Purpose
**Pixelocity** is a high-performance WebGPU playground designed to run complex compute shader effects (fluid simulations, reaction-diffusion, cellular automata) in real-time. Unlike standard WebGL wrappers, it exposes a raw "Universal BindGroup" architecture that allows shaders to be hot-swapped without recompiling the TypeScript host.

It features a **Dual-Window** mode where a secondary "Remote" window can control the main rendering window, synchronized via the BroadcastChannel API.

### Tech Stack
*   **Core:** React 18, TypeScript, WebGPU API (raw, no Three.js/Babylon.js abstraction for the core engine).
*   **AI/ML:** `@xenova/transformers` (local execution of DPT-Hybrid-MIDAS for depth estimation).
*   **Build/Tooling:** Webpack, Custom Node.js scripts for shader aggregation (`scripts/generate_shader_lists.js`).
*   **State Management:** React Context/State + BroadcastChannel for cross-window sync.

### Design Patterns
*   **Renderer Singleton (Functional):** The `Renderer` class acts as a localized singleton manager for the GPU device. It is instantiated once per canvas lifecycle but is **not** a global singleton (to allow cleanup/re-init).
*   **Ping-Pong Buffering:** Uses double-buffered textures (`pingPongTexture1`, `pingPongTexture2`) and history buffers (`dataTextureA`, `dataTextureC`) to support stateful simulations (sims that read the previous frame).
*   **Universal Interface:** A strict "Contract-First" design where the TypeScript engine defines a fixed BindGroup layout (Bindings 0-12), and *all* WGSL shaders must adhere to it.
*   **Command Pattern:** The Remote App sends command objects (`CMD_SET_MODE`, `CMD_SET_ZOOM`) to the Main App, which owns the state.

## 2. Feature Map

| Feature | Entry Point / Key File | Description |
| :--- | :--- | :--- |
| **Rendering Engine** | `src/renderer/Renderer.ts` | Manages WebGPU device, pipelines, and the render loop (`render()`). |
| **Shader Definition** | `shader_definitions/**/*.json` | Metadata for effects. Aggregated into `public/shader-lists/` at build time. |
| **Remote Control** | `src/RemoteApp.tsx` | The control-only UI. Triggered by `?mode=remote` URL param. |
| **State Sync** | `src/App.tsx`, `src/syncTypes.ts` | Handles `BroadcastChannel` messages to sync state between windows. |
| **Depth Estimation** | `src/App.tsx` (`loadModel`) | Runs the DPT-Hybrid-MIDAS model to generate a depth texture for the GPU. |
| **Video/Webcam** | `src/components/WebGPUCanvas.tsx` | Manages hidden `<video>` elements for texture sources. |
| **Hot-Swap** | `src/renderer/Renderer.ts` | `loadComputeShader()` compiles WGSL on-demand. |

## 3. Complexity Hotspots (The "Complex Parts")

### A. The "Universal BindGroup" Contract
**Why it's complex:** The `Renderer.ts` does not inspect shader code to determine bindings. It assumes *every* shader uses the exact same bind group layout.
**Agent Warning:** If you create a new shader, **YOU MUST** copy the standard 13-line header exactly. If you change the binding order in a shader, the GPU validation will fail silently or crash.
*   Binding 0-2: Sampler, Read Texture, Write Texture
*   Binding 3: Uniforms (Config, Mouse, etc.)
*   Binding 4-6: Depth Read, Linear Sampler, Depth Write
*   Binding 7-9: History Write (A), History Write (B), History Read (C)
*   Binding 10-12: Extra Buffers (Storage, Comparison Sampler, Plasma)

### B. Ping-Pong & History State
**Why it's complex:** The renderer supports a "Stack" of 3 compute shaders.
1.  **Chaining:** Output of Shader 1 -> Input of Shader 2.
2.  **History:** Shaders can read the *previous frame's* output via `dataTextureC` (Binding 9) and write to `dataTextureA` (Binding 7).
**Agent Warning:** The `dataTextureA` -> `dataTextureC` copy happens *once* at the end of the frame. If multiple shaders in the stack try to write to the history buffer (`dataTextureA`), they will overwrite each other. **Only one stateful shader should be active at a time.**

### C. Remote Synchronization (Race Conditions)
**Why it's complex:** The Main App is the "Source of Truth". The Remote App is a "Dumb Terminal".
*   **Flow:** Remote UI Interaction -> Send `CMD` -> Main App Receives `CMD` -> Update State -> Broadcast `STATE_FULL` -> Remote App Updates UI.
**Agent Warning:** Do not implement local state updates in `RemoteApp` that "predict" the outcome. Always wait for the `STATE_FULL` echo from Main to avoid desync/janky sliders.

### D. Lazy Shader Loading
**Why it's complex:** To speed up startup, `Renderer.init()` does not compile all 100+ shaders.
*   It fetches the JSON lists but only compiles the WGSL when the shader is first selected.
*   **Risk:** `Renderer.render()` filters out shaders that aren't loaded yet. If you select a shader and immediately try to screenshot it in a test, it might not be rendered for the first few frames.

## 4. Inherent Limitations & "Here be Dragons"

### Known Issues
*   **WebGPU Availability:** This app *requires* a browser with WebGPU enabled. It will not run in standard CI environments (headless Chrome/Linux) without mocking `navigator.gpu`.
*   **Video Texture Lifecycle:** `HTMLVideoElement` + WebGPU is fragile. The video element must be in the DOM (even if hidden) and playing for `copyExternalImageToTexture` to work reliably.
*   **Float32 Filtering:** The app relies on the `float32-filterable` feature. Some mobile GPUs or older drivers do not support this, causing `requestDevice` to fail.

### Technical Debt / Hacky Areas
*   **Shader Lists Generation:** We use a custom script (`scripts/generate_shader_lists.js`) to merge JSON files. This runs on `prestart`/`prebuild`. If you add a JSON file in `shader_definitions/` and it doesn't appear, you likely didn't run the build script or restart the server.
*   **Canvas Resolution:** The canvas resolution is hardcoded or loosely tied to window size/aspect ratio in ways that can cause stretching if the window is resized aggressively. `u.config.z/w` (Width/Height) should be used for aspect correction in shaders.

### Hard Constraints
*   **Do Not Change Binding Layout:** `Renderer.ts` -> `createBindGroups` is rigid. Changing it requires updating all 100+ WGSL files.
*   **Do Not Rename `Uniforms` Struct:** The struct member order (Time, RippleCount, Width, Height) is byte-aligned with `imageVideoUniformBuffer`.

## 5. Dependency Graph & Key Flows

### Critical Flow: Rendering a Frame
1.  **React State Update:** User selects "Liquid" mode in `App.tsx`.
2.  **Prop Propagation:** `modes={['liquid']}` passed to `WebGPUCanvas`.
3.  **Render Loop:** `requestAnimationFrame` triggers `renderer.render()`.
4.  **Lazy Load:** Renderer checks if `liquid` pipeline exists. If no, fetches `.wgsl` and compiles (async). Frame 0 renders "Pass-through".
5.  **Compute Pass:**
    *   `liquid` shader reads `InputTexture` (Binding 1).
    *   Writes to `WriteTexture` (Binding 2).
    *   Writes to `DataTextureA` (Binding 7) if stateful.
6.  **Screen Pass:** `liquid-render` pipeline draws `WriteTexture` to the Canvas.
7.  **History Copy:** `DataTextureA` copied to `DataTextureC` for the next frame.

### Critical Flow: Adding a New Shader
1.  Create `shader_definitions/<category>/my-shader.json`.
2.  Create `public/shaders/my-shader.wgsl` (Must include standard header).
3.  (Auto) `npm start` triggers `scripts/generate_shader_lists.js`.
4.  App loads `public/shader-lists/<category>.json`.
5.  Shader appears in `Controls` dropdown.

## 6. Testing Strategy
*   **Headless Limitations:** Since WebGPU is not available in standard headless CI, we cannot verify the *pixels* of the output.
*   **Verification:**
    1.  **Static:** Verify JSON syntax and WGSL header compliance.
    2.  **Integration:** Use Playwright with `navigator.gpu` mocked to ensure the UI loads, controls render, and no JS errors occur on init.
    3.  **Visual:** Manual verification is currently required for visual correctness of new shaders.
