# naga_wasm

GPU-less WGSL validation for the shader catalog.

A thin Rust crate wrapping [`naga`](https://crates.io/crates/naga)'s WGSL front-end
and validator, compiled to `wasm32-unknown-unknown`. Node, CI and the browser all
run the same compiler the host `naga` CLI runs — in-process, with no GPU, no
adapter and no device.

| | |
|---|---|
| Contract | `src/contracts/wgsl_validation.json` |
| Artifact | `public/wasm/naga_wasm.wasm` (committed, ~805 KB) |
| JS loader | `public/wasm/naga_wasm.js` (hand-written, shared by Node and the browser) |
| TS wrapper | `src/utils/nagaWasm.ts` (browser; dynamic import, stays out of the bundle) |
| Gate | `npm run verify:naga-wasm` / `npm run verify:naga-wasm:all` |
| Tests | `npm run naga-wasm:test` |

## Why this exists

`scripts/wgsl_precommit_gate.py` shelled out to a `naga` binary, so CI had to
`cargo install naga-cli` on every run — minutes of wall clock — and each file cost
a process spawn. That made a full-catalog naga scan unaffordable, so `--full-tree`
skipped naga entirely and only files changed against `origin/main` were validated.

Anything that landed before the gate, or through a merge, was never checked. When
the full catalog was first scanned with this crate, **40 shaders on `main` failed**.
They are recorded in the contract's `knownFailures` and ratcheted downward.

In-process, the whole catalog validates in about 7 seconds.

## Rebuilding

```bash
npm run naga-wasm:build      # or: bash tools/naga_wasm/build.sh
```

Requires a Rust toolchain and the `wasm32-unknown-unknown` target (the script adds
it if missing). **Nothing else does** — the artifact is committed, exactly like
`public/wasm/pixelocity_wasm.wasm`, so `npm start`, the gate and CI all work
without Rust installed.

`scripts/validate_wasm_artifacts.js` fails if the artifact is older than
`Cargo.toml` or any `src/*.rs`, so a Rust edit cannot silently ship stale.

## No wasm-bindgen

The module exports a hand-written C ABI instead:

```
wgsl_alloc(len) -> ptr              caller writes `len` UTF-8 bytes at ptr
wgsl_validate(ptr, len) -> i32      0 = valid, 1 = parse error, 2 = validation error
wgsl_result_ptr() / wgsl_result_len()   JSON diagnostic for the last call
wgsl_free(ptr, len)
```

It is small enough to write by hand, which keeps `wasm-pack` and `wasm-bindgen`
off CI and off agent VMs. `public/wasm/naga_wasm.js` is the only supported caller;
keep the two in sync.

The result buffer is owned by the module and is overwritten by the next
`wgsl_validate`, so JS copies it out before calling again.

## The naga pin

`Cargo.toml` pins naga to the minor recorded in
`src/contracts/wgsl_validation.json` → `nagaCratePin`, and
`scripts/validate_wasm_artifacts.js` fails if the two disagree.

Bumping the minor can change which shaders parse. A bump must be accompanied by
a `npm run verify:naga-wasm:all` run and any resulting change to
`knownFailures` — otherwise the catalog dialect drifts silently.

## The known-failure ratchet

`verify:naga-wasm` fails in both directions:

- a shader that fails naga and is **not** in `knownFailures.ids` — a new break;
- a shader that **is** in `knownFailures.ids` but now passes — remove it and lower
  `ratchet`, so the count can only go down.

`ratchet` must always equal `ids.length`.
