# `rain-lens-wipe` — Batch 44

- Motion: closed-form falling drop cells plus narrow downward water-streak packets.
- Interaction: the mouse wipes an advected clean-state mask, press completes the wipe, and clicks launch bounded wipe fronts.
- State: A remains `(clean state, 0, 0, 1)` with exact clamped C loads. B and `extraBuffer` remain unused.
- Safety: all sample UVs and output channels are clamped; spatial drop hashes are stable and never hash time/frame identity.
- Depth: input depth is passed through unchanged.
