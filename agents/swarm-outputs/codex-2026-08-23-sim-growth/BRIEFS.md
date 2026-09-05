# Remaining Simulation / Field / Growth / Decay Batch

Ten existing simulation effects were upgraded in place:

- Two materially distinct corrosion/decay systems.
- Hydraulic terrain erosion with live sediment capacity.
- Anisotropic phase-field crystal growth with impurity rejection.
- Fuel/temperature/smoke/combustion-age fire dynamics.
- Electric, magnetic, and charge-field propagation.
- Two ecosystem models: continuous competition/toxin and trophic cellular CA.
- Video-driven continuous Lenia.
- Four-channel digital moss colonization.

Every shader retains its original saved `params` array and uses the canonical
13 bindings, explicit 16×16×1 dispatch, exact bounded C feedback, A-only state
writeback, all three audio bands, held input, age-guarded click fronts, semantic
alpha, and ACES tone mapping.
