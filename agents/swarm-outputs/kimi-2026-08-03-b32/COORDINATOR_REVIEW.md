# Batch 32 coordinator review

The five partial Kimi drafts were completed alongside the three missing targets,
then integrated as one eight-shader cohort.

## Corrections applied

- Reserved config.y for rippleCount and used zoom_config.w for mouseDown.
- Replaced filtering-sampler reads of rgba32float feedback and unfilterable depth.
- Restricted audio to plasmaBuffer[0].xyz and guarded all FFT reads.
- Bounded accumulated ripple deformation and geometry radii.
- Standardized generated geometry depth to near-is-one and miss-is-zero.
- Fixed inverted falloffs, dead facet mapping, float modulus, and illegal audio indices.
- Kept every existing params/parameters/updatedParams object byte-for-byte and
  made descriptions/tags/features additive and truthful.

## Scope note

The five inherited drafts exceeded the brief's suggested +60..+90 line envelope
after adding their required geometry. They were retained at 235–259 lines rather
than cosmetically minified; the three newly completed shaders land inside the
requested range at +62, +84, and +86 lines.

## Structural proof

All eight shaders pass WGSL/Naga parsing, canonical bind-group and workgroup
checks, strict extraBuffer ownership, four-control liveness, JSON preservation,
and output/public synchronization. The full Batch 31+32 repository test and
production-build gates are green. Real-GPU visual QA remains external.
