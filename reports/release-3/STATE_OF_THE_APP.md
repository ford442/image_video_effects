# State of the App — Release 3/5 (Visual Polish & Cross-Viewport Audit)

> **Status: interim — acceptance (b) is NOT done.** Everything below was verified on a fresh production
> build served locally (`npm ci && npm run build`). Nothing was deployed: this environment has no SFTP
> credentials (see *Deferred*), so there is no deployed URL and the smoke suite has not run against one.

## Deployed URL / commit
- **Deployed URL:** none. The preview target (`https://test.1ink.us/image_video_effects-preview/`) currently
  answers `302` → a 404 page, i.e. nothing is deployed there.
- **Commit:** see the PR head SHA (stated in the issue comment).

## Gates (final tree, fresh `npm ci` + `npm run build`)
| Gate | Result |
|---|---|
| `npm run build` | ok |
| `verify:toolchain-foundation` | 13/13 |
| `lint` | 0 errors, 100/100 warnings (ratchet unchanged) |
| `typecheck`, `typecheck:scripts`, `tests/` tsc | clean |
| `verify:css`, `thumbs:check-regression`, `verify:no-client-secrets` | pass |
| `test:ci` (Vitest) | 227 files, 2040 passed, 1 skipped |
| `test:smoke` (Release 2 suite, both render threads, local `build/`) | **11/11**, 0 blocking console errors / page errors / failed requests, 2.0 min |
| `engine2-device-loss` swiftshader spec | 8/8 |

Browser used: Playwright's pinned Chromium 1228 on SwiftShader. The VM's pre-installed Chromium 1243 is
**not** usable for this suite: after boot every shader compile fails with `Instance dropped in popErrorScope`.

## Layout audit (final build)
No horizontal scroll, 0 clipped/unreachable controls, canvas square (CSS aspect 1.00 over a 1.00 buffer) at all five
viewports. Canvas CSS size: 365 / 387 / 719 / 999 / 1359 px. The drawing buffer is a fixed 2048² regardless of DPR, so
2× screens stay sharp and the working size never scales with the device.

## Screenshot matrix
Compositor screenshots of a WebGPU canvas are blank on SwiftShader in some runs; the UI chrome is always real.
Error-state rows 6–8 and row 4 were captured on the build just before the last three CSS/boot tweaks (colour tokens,
overlay padding, boot-default fallback); rows 1–3 and 5 were captured on the final build.

| Viewport | Startup (loading) | Ready | Empty: search, no results | Loading: lazy chunk (Graph Lab) | Error: WebGPU unavailable | Error: shader compile failure | Error: media unreachable | Error: device lost (recovering) |
|---|---|---|---|---|---|---|---|---|
| Phone 375×812 @2× | [img](screenshots/phone-375x812__1-loading-startup.webp) | [img](screenshots/phone-375x812__2-ready.webp) | [img](screenshots/phone-375x812__3-empty-search.webp) | [img](screenshots/phone-375x812__4-loading-lazy-chunk-graph-lab.webp) | [img](screenshots/phone-375x812__5-error-webgpu-unavailable.webp) | [img](screenshots/phone-375x812__6-error-shader-compile.webp) | [img](screenshots/phone-375x812__7-error-media-unreachable.webp) | [img](screenshots/phone-375x812__8-error-device-lost.webp) |
| Tablet 768×1024 @2× | [img](screenshots/tablet-768x1024__1-loading-startup.webp) | [img](screenshots/tablet-768x1024__2-ready.webp) | [img](screenshots/tablet-768x1024__3-empty-search.webp) | [img](screenshots/tablet-768x1024__4-loading-lazy-chunk-graph-lab.webp) | [img](screenshots/tablet-768x1024__5-error-webgpu-unavailable.webp) | [img](screenshots/tablet-768x1024__6-error-shader-compile.webp) | [img](screenshots/tablet-768x1024__7-error-media-unreachable.webp) | [img](screenshots/tablet-768x1024__8-error-device-lost.webp) |
| 1280×800 | [img](screenshots/laptop-1280x800__1-loading-startup.webp) | [img](screenshots/laptop-1280x800__2-ready.webp) | [img](screenshots/laptop-1280x800__3-empty-search.webp) | [img](screenshots/laptop-1280x800__4-loading-lazy-chunk-graph-lab.webp) | [img](screenshots/laptop-1280x800__5-error-webgpu-unavailable.webp) | [img](screenshots/laptop-1280x800__6-error-shader-compile.webp) | [img](screenshots/laptop-1280x800__7-error-media-unreachable.webp) | [img](screenshots/laptop-1280x800__8-error-device-lost.webp) |
| 1920×1080 | [img](screenshots/fhd-1920x1080__1-loading-startup.webp) | [img](screenshots/fhd-1920x1080__2-ready.webp) | [img](screenshots/fhd-1920x1080__3-empty-search.webp) | [img](screenshots/fhd-1920x1080__4-loading-lazy-chunk-graph-lab.webp) | [img](screenshots/fhd-1920x1080__5-error-webgpu-unavailable.webp) | [img](screenshots/fhd-1920x1080__6-error-shader-compile.webp) | [img](screenshots/fhd-1920x1080__7-error-media-unreachable.webp) | [img](screenshots/fhd-1920x1080__8-error-device-lost.webp) |
| 2560×1440 | [img](screenshots/qhd-2560x1440__1-loading-startup.webp) | [img](screenshots/qhd-2560x1440__2-ready.webp) | [img](screenshots/qhd-2560x1440__3-empty-search.webp) | [img](screenshots/qhd-2560x1440__4-loading-lazy-chunk-graph-lab.webp) | [img](screenshots/qhd-2560x1440__5-error-webgpu-unavailable.webp) | [img](screenshots/qhd-2560x1440__6-error-shader-compile.webp) | [img](screenshots/qhd-2560x1440__7-error-media-unreachable.webp) | [img](screenshots/qhd-2560x1440__8-error-device-lost.webp) |

## Defects fixed in this PR
1. **Phone layout (≤640px) was broken**: header buttons ran off-screen (7 controls clipped), the fixed 380px sidebar
   consumed the whole width so the canvas rendered 0×0. Added a phone breakpoint (stacked layout).
2. **Renderer errors were console-only.** Shader-compile and media-load failures left the UI saying "Ready." with no
   explanation. New dismissible `role="alert"` notice with recovery actions (Try another effect / Try another image /
   Use generative source). A shader failing bind-group validation (silently replaced by a pass-through) now reports too.
3. **No-WebGPU overlay**: plain-language guidance + **Reload page**; browser warnings corrected (Safari/iOS 26 ship
   WebGPU; Firefox no longer told to use Firefox). On phones the log is collapsed so the recovery actions stay on screen.
4. **App booted with an empty Slot 1** whenever the remote catalog lacks `liquid-original` (it does until `sync:shaders`
   runs; the catalog is served from storage). Boot now falls back to `liquid`.
5. **Misleading startup status**: "Ready." over a black canvas → "Starting renderer…".
6. **Contrast**: input placeholders / `--text-muted` were ~2.9:1 → ≥5.4:1 (axe cannot test placeholders or gradients;
   measured from rendered pixels).
7. **`prefers-reduced-motion`** was not honoured anywhere (15 stylesheets animate) → global reduced-motion rule.
8. Duplicate clear button in the filter box; header logo (hot-linked 4.3 MB GIF) now falls back to a text wordmark.
9. **Thumbnails**: `liquid-original` had none (the thumbnail regression gate was failing on `main`) → generated;
   13 black/flat thumbnails recaptured. Integrity audit flags 21 → 8.
10. **Test infra**: 11 test files still waited for `liquid` after the boot default changed (each smoke test burned a 60 s
    timeout: suite 10.9 min → 2.0 min). Smoke allow-list covers the logo host for local runs.

## Verified OK, no change needed
Startup shows the UI shell immediately (never blank) · Graph Lab lazy chunk shows "Loading Graph Lab…" · empty search shows
"No controls or effects match …" · device-loss recovers at all five viewports · axe WCAG 2 A/AA: 0 violations · 45/45 tab
stops have a visible focus indicator, none off-screen · Firefox 151 (no WebGPU) shows the overlay with 0 page errors ·
28 shaders sampled (2 per category) render with healthy dynamic range, no black / flat / NaN frames.

## Deferred / not done
- **(b) Preview deploy + smoke against it — blocked.** Needs SFTP credentials (`DEPLOY_USER`+`DEPLOY_PASS`, or
  `DEPLOY_KEY`); the only credential present, `DEPLOY_TOKEN`, is not read by `tools/deploy`. To finish:
  `npm run sync:shaders` (so `liquid-original` exists in storage), `npm run deploy:preview`, then dispatch
  *App smoke* (`.github/workflows/app-smoke.yml`) with `base_url=https://test.1ink.us/image_video_effects-preview/`.
- **Safari / WebKit**: Playwright WebKit cannot launch here (missing system libraries). Safari WebGPU is unverified.
  Firefox WebGPU rendering is also unverified (only its no-WebGPU path).
- **8 shaders render black/flat on SwiftShader** even after 40 frames and need a real GPU to judge:
  `gen-cybernetic-ferro-coral` (timeout), `gen-lenia-2`, `gen-psychedelic-time-warp-kaleidoscope`,
  `gen-temporal-motion-smear`, `gen-velocity-bloom`, `magnetic-flux-garden` (black) and
  `gen-thermal-rainbow-topography`, `recursive-ancestral-terrains` (solid white from frame 3 — suspect feedback
  state read before tone-map; not diagnosed).
- `tests/css-regression.spec.ts` baselines predate the sidebar restructuring and already mismatch (not run in CI); regenerate on the CI image.
- Header logo is a 4.3 MB GIF hot-linked from the production origin → Release 4.
- Tablet portrait (768 wide) keeps side-by-side layout, so the canvas is 387 px; consider stacking up to ~900 px.
- Thumbnail coverage 1306/1419 (92.0%), 101 missing, 12 deferrals.
- Environment notes: VM runs Node 22 (repo wants ≥24; `npm ci` warns only); `AGENTS.md` says media hosts are blocked, but
  `storage.noahcohn.com` was reachable here (1432 shaders fetched).
