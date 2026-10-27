# Image-reactive fireworks batch notes

The four image-fireworks definitions form the batch. The generative fireworks
already have named visual upgrades and were left alone. This is deliberately
smaller than the usual 8–12 shader batch.

- `fireworks-depth-parade`: existing three-layer, depth-probed ballistic
  launches now use image-depth visibility and distance-dependent color, radius,
  and intensity for automatic and click shells.
- `fireworks-edge-ignite`: the existing image gradient sets a tangent-biased
  automatic shell spread; a continuous phase illuminates detected contours.
- `fireworks-patriotic-july4`: automatic shells have three radius/color
  groups; the existing twinkling sky stars gain crossed diffraction rays.
- `fireworks-portrait-burst`: the existing bright-probe core gains a brief
  broad bloom, and its stars cool toward the existing ember color with age.

All four preserve the saved `params` bytes, their existing slider roles,
interaction, ballistic shell pipeline, and feedback RGB. A stores ACES display
RGBA and C reads its RGB. Each shader already wrote a separate dimmed
display/previous-color auxiliary echo to B; that existing packing was kept.
The source-derived display alpha now also goes into A rather than a constant.

## Validation and closeout

- The Naga WASM validator passed each file and the four-file batch.
- The precommit gate passed binding, workgroup, prelude, and extraBuffer checks;
  its CLI Naga step was unavailable, so the WASM validator supplied that check.
- `audit:extrabuffer` and the four-file `audit:dead-sliders` passed.
- Generated shader lists and the production build succeeded.
- Saved parameter bytes and `x-meta.upgrade.params` alignment were checked.
- Scoped `upgrades:record` recorded all four IDs.
- `npm run test:ci` did not pass in this environment. With Node 26's built-in
  web storage disabled, 1,530 tests passed and two pre-existing semantic-search
  tests failed against the tracked search index (58 missing embeddings); two
  SidebarGroups asynchronous rejections were also reported during teardown.
  The build could not fetch the CLIP model to fill missing embeddings.
- Real-GPU visual review and refreshed thumbnails are still needed; WGSL
  validation is not a visual-quality assessment.
