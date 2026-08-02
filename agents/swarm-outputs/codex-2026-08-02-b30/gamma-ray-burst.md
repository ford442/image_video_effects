# Batch 30: gamma-ray-burst

- Bounded the stylized relativistic term (`beta² <= 0.98`, capped beaming/field writes) so distant pixels no longer explode numerically.
- Added a top-left-safe spring burst center in `extraBuffer[133..138]`, guarded click shells, and eight angular FFT voices.
- Preserved ACES display mapping, semantic alpha, real depth, and the existing `(burst, beaming, spiral, alpha)` A-field role.
- Source params are unchanged; metadata now truthfully advertises click/depth behavior with indexed `updatedParams`.
- Final size: 120 -> 158 lines. Focused Naga, slider, buffer, JSON/list, Jest, and production-build checks pass.
