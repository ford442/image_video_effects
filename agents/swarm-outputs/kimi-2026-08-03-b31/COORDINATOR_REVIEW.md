# Batch 31 coordinator review

The 13 Kimi shader drafts were integrated after a focused contract and runtime-safety pass.

## Corrections applied

- Rewrote reversed smoothstep falloffs without changing their intended masks.
- Guarded the Bismuth FFT tail read before indexing an empty buffer.
- Standardized generated ray depth to near-is-one and miss-is-zero.
- Bounded click-ripple deformation and protected the Urchin mouse-direction normalization at zero distance.
- Restored all existing parameters, params, and updatedParams objects byte-for-byte, then kept Batch 31 metadata additive.
- Synchronized every public shader/definition with its swarm output copy.

## Structural proof

All 13 shaders pass focused WGSL/Naga parsing, canonical bind-group checks, workgroup checks, and strict extraBuffer ownership checks. Real-GPU visual QA remains external to this VM.
