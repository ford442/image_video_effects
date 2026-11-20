# Offline-render golden frames (#1401)

`tests/golden-frames.swiftshader.spec.ts` renders frames 0 / 30 / 120 (30 fps, 256², a fixed
procedural input, render quality `ultra`) of the six Physics Lab flagships and ten catalog
shaders through the stepped-clock `renderFrameAt` path, and compares them with this folder:

- `manifest.json` — size / fps / frames, the SHA-256 of every frame's RGBA pixels, optional
  per-shader `thresholds` (`dssim`, `deltaE`), and where the goldens were generated.
- `<shader>.f<frame>.png` — the frames themselves, for the tolerant comparison (DSSIM for
  structure, mean CIE76 ΔE for colour) when the hash differs, e.g. on another SwiftShader build.

A shader with no entry here is skipped, not failed. To create or refresh the goldens after an
intended change, on a host where SwiftShader WebGPU can present (see AGENTS.md):

```bash
npm run build && UPDATE_GOLDENS=1 npm run test:engine2 -- golden-frames
```

or run **Actions → GPU_REQUIRED (manual)** with suite `golden-frames-swiftshader` and
`update_goldens` ticked, then commit the `golden-frames` artifact into this folder.
