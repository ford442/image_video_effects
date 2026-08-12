# `reaction-diffusion` — Batch 44

- Motion: rotating state advection plus fast analytic feed packets move the two-channel chemistry.
- Interaction: mouse press seeds B locally; clicks launch bounded seed fronts.
- State: A remains `(A, B, 0, accumulated alpha)` and C uses exact clamped loads. B and `extraBuffer` remain unused.
- Controls: the four legacy saved-preset labels remain exact while driving diffusion, feed, kill, and accumulation respectively.
- Depth: input depth is passed through unchanged; metadata says Gray-Scott-inspired rather than physically exact.
