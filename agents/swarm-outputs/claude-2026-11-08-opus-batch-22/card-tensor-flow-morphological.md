SHADER: tensor-flow-morphological (1st pass)
IDENTITY: depth-Hessian eigenwarp + erosion/dilation/gradient morphology
KEEP VERBATIM: eigen warp, laplacian detail, fbm warp, stress colour, mouse-anisotropic structuring element, params
ADD:
  1. Tensor-signed morphology — per-pixel erosion↔dilation from Hessian trace (compression erodes, tension dilates), as the header always claimed; flat depth = old 0.5
  2. Photoelastic isochromatic fringes — cosine rainbow bands on the morphological gradient, order from gradient + shear + mids
  3. Bass-pressed structuring element — radius 3→5 taps on bass
RESCUES:
  - kernel radius / erosion-dilation blend / gradient boost / morph blend read zoom_config.xyzw; .yz is the mouse → cursor drove morphology. Pinned at legacy defaults (JSON notes it).
  - Depth Weight slider dead → now scales tensor warp by near/far depth.
  - Alpha = raw top-hat (≈0, slightly negative) → near-invisible when composited; now 0.7 + 3·top-hat.
  - normalize(0,0) eigenvector on flat depth (defensive; SwiftShader returned finite).
  - No audio, dataTextureA unwritten, depth .w=1 → fixed.
Stats (256px, 20f, t=3, defaults): before meanL .407 meanA −.015 → after .428 / .708; click+bass: .439/−.016 → .430/.713.
Open: harness depth flat → warp/trace/shear inert there; fringes come from colour gradient only. Real-depth look unverified.
