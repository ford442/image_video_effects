# `viscous-drag` — Batch 44

- Motion: velocity-biased RG-state advection plus traveling vortex packets create coherent liquid jets.
- Interaction: held mouse creates radial/tangential pressure smears and clicks launch bounded pressure fronts.
- State: A remains `(offset x, offset y, 0, 0)` with exact clamped C loads. B and `extraBuffer` remain unused.
- Safety: sample UV, state offsets, RGB, and alpha are bounded; specular no longer adds into alpha.
- Depth: input depth is passed through unchanged.
