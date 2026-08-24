# Shader Notes

| Shader | A/C packing | Key implementation result |
|---|---|---|
| Hyper Rainbow Vortex | raw HDR vortex display RGBA | normalized mouse fix, layered Rankine energy, click fronts, semantic vortex alpha/depth |
| Hyper-Refractive Rain Matrix | raw HDR refractive-rain display RGBA | bass drop energy, mids viscosity/refraction, treble caustics, pointer repulsion, input-aware depth |
| Hyper Warp | stabilized flow-advected raw HDR display RGBA | legacy filename retained, `.y/.z` audio repair, exact displaced C load, held warp |
| Hyperbolic Crystal Symbiosis | raw HDR crystals plus advected trail RGBA | ACES removed from history, crystal/edge alpha, hyperbolic competition preserved |
| Hyperbolic Tessellation | raw HDR tessellation display RGBA | live symmetry/depth-color/rotation/boundary controls; depth stores recursive level |
| Ice Crystal Lattice | raw HDR ice/frost display RGBA | hexagonal branches, Fresnel frost, held nucleation, click fracture waves |
| Interference Moire Field | raw HDR interference display RGBA | crossed line fields, warped phase beats, held optical lens, circular pulses |
| Iris Bloom Fractal | raw HDR iris display RGBA | recursive polar petals, pupil/aperture, audio veins, pointer gaze |
| Islamic Geometric Tiling | raw HDR ornament display RGBA | interlaced stars, recursive rosettes, held twist, gilded click fronts |
| Julia Set Classic | raw HDR Julia display RGBA | escape-time smoothing, orbit traps, held C control, requested classic defaults |

No target reads or writes `extraBuffer`; the declaration is retained solely as
part of the canonical renderer ABI. No target stores to `dataTextureB` or C.
The five greenfield effects use uniform ripple timestamps with positive-age and
finite-lifetime guards, so they add no auxiliary persistent state.
