# Pixelocity Glitch & Retro Shader Upgrade Plan

## Executive Summary

Analysis of 29 glitch/retro shaders reveals strong artistic foundations with significant opportunities for scientific authenticity upgrades. Current implementations excel at visual appeal but miss key computational behaviors of real signal degradation systems.

---

## Shader Inventory & Current State

### Category A: RGB Displacement Effects (8 shaders)
| Shader | Size | Current Technique | Missing Science |
|--------|------|-------------------|-----------------|
| rgb-glitch-trail | 2,683B | Data texture persistence, per-pixel RGB shift | Phosphor decay curves, beam velocity artifacts |
| rgb-split-glitch | 3,461B | Mouse-distance chromatic separation | Subsampling phase error, YUV channel misalignment |
| glitch-slice-mirror | 3,502B | Mirror seam with blocky noise | Sync pulse disruption, horizontal hold loss |
| waveform-glitch | 3,115B | Sine wave displacement with content reaction | Analog signal ringing, group delay distortion |
| signal-noise | 2,848B | Scanline band noise with RGB split | VHF interference patterns, carrier wave bleed |
| scanline-tear | 3,178B | Strip-indexed random displacement | Vertical sync interval corruption |
| glitch-cathedral | 4,161B | Geometric cells + RGB split + pixel sort | DCT blocking from compression |
| digital-glitch | 3,683B | Block displacement, scanline tearing | Quantization error propagation |

### Category B: Persistence/Feedback Effects (5 shaders)
| Shader | Size | Current Technique | Missing Science |
|--------|------|-------------------|-----------------|
| phantom-lag | 2,486B | Simple history blend with RGB rotation | Phosphor persistence by color (R>G>B) |
| glitch-ripple-drag | 4,347B | Feedback loop with ripple displacement | I-frame prediction error accumulation |
| static-reveal | 2,863B | Perlin-like noise mask reveal | RF static distribution, snow autocorrelation |
| sliding-tile-glitch | 4,279B | Grid state persistence with offset | Macroblock motion vector discontinuity |
| glitch-reveal | 4,373B | Block scatter with circular reveal | Error concealment artifacts |

### Category C: Scanline/CRT Effects (6 shaders)
| Shader | Size | Current Technique | Missing Science |
|--------|------|-------------------|-----------------|
| crt-tv | 3,242B | Curvature, scanlines, vignette | Aperture grille shadow mask, halation |
| crt-magnet | 3,228B | Radial displacement + aberration | Degaussing bloom, purity errors |
| scan-distort | 3,553B | Scanline bending around mouse | Horizontal linearity error |
| scan-distort-gpt52 | 3,234B | Barrel distortion + rolling | Field timing jitter (interlacing) |
| scanline-wave | 2,385B | Sine wave vertical displacement | Line frequency interference |
| scanline-sorting | 3,361B | Simulated pixel sort on bands | True row-wise sorting with luma threshold |

### Category D: VHS/Analog Effects (3 shaders)
| Shader | Size | Current Technique | Missing Science |
|--------|------|-------------------|-----------------|
| vhs-tracking | 3,077B | Horizontal shear at scan bands | Control track dropout, capstan jitter |
| vhs-tracking-mouse | 3,595B | Mouse-controlled tracking bar | Head switching noise, azimuth error |
| strip-scan-glitch | 4,045B | Vertical strips with jitter | Chrominance noise modulation |

### Category E: Data/Corruption Effects (5 shaders)
| Shader | Size | Current Technique | Missing Science |
|--------|------|-------------------|-----------------|
| byte-mosh | 8,030B | Bitwise XOR/AND/shift/rotate on RGB packed | Byte-order mark corruption, entropy coding errors |
| datamosh | 3,524B | Motion vector optical flow simulation | True P-frame prediction, I-frame removal |
| data-stream-corruption | 5,273B | Matrix rain + corruption mask | Packet loss patterns, Reed-Solomon error floors |
| glitch-pixel-sort | 3,548B | Brightness-based directional displacement | Bubble sort visualization, threshold hysteresis |
| pixel-sort-glitch | 2,787B | Luma threshold offset by blocks | Row-wise quicksort with discontinuity |

### Category F: Retro Aesthetic (2 shaders)
| Shader | Size | Current Technique | Missing Science |
|--------|------|-------------------|-----------------|
| retro-gameboy | 5,467B | 4-color palette quantization | LCD response time, ghosting by color |
| synthwave-grid-warp | 2,967B | Grid distortion with neon glow | Vector monitor bloom, phosphor persistence |

---

## Scientific Concept Implementation Opportunities

### 1. Digital Signal Processing Errors

**Current State:** Most shaders use simple `floor()` or `step()` for quantization

**Upgrade Opportunities:**
- **Quantization Error Diffusion**: Implement Floyd-Steinberg or Bayer dithering matrices
  - Target: retro-gameboy, digital-glitch, glitch-cathedral
  - Mathematical model: Error distribution kernel `e * [0 0 0; 0 0 7; 3 5 1]/16`
  
- **Aliasing Artifacts**: Add sinc reconstruction error
  - Target: waveform-glitch, scanline-wave
  - Model: `sinc(x) = sin(πx)/(πx)` with truncation at Nyquist limit

- **Clipping/Overflow**: Implement soft knee compression with harmonic generation
  - Target: signal-noise, byte-mosh
  - Transfer function: `y = x < threshold ? x : threshold + (x-threshold)/(1+(x-threshold))`

### 2. MPEG Compression Artifacts

**Current State:** datamosh shader has placeholder optical flow; glitch-cathedral has geometric blocks

**Upgrade Opportunities:**
- **DCT Blocking**: Simulate 8x8 block boundaries with coefficient quantization
  - New shader candidate: `mpeg-block-ghost`
  - Implementation: 2D DCT basis function visualization, coefficient dropout
  
- **Motion Vector Discontinuity**: Visible at macroblock edges
  - Target: sliding-tile-glitch, datamosh
  - Model: `MV_smooth = lerp(MV_block, MV_neighbor, edge_distance < 2px)`

- **GOP Structure Visualization**: I/P/B frame type indication
  - Target: datamosh upgrade
  - Visual: Frame-type color coding, prediction error heat map

### 3. VHS Magnetic Signal Degradation

**Current State:** vhs-tracking uses simple horizontal shear

**Upgrade Opportunities:**
- **Chroma Noise Modulation**: VHS reduces chroma bandwidth
  - Target: vhs-tracking, vhs-tracking-mouse, strip-scan-glitch
  - Model: Chroma signal `C = (R-Y)cos(ωt) + (B-Y)sin(ωt)` with phase noise
  
- **Dropout Compensation**: White streaks from tape defects
  - New shader: `vhs-dropout`
  - Model: Random vertical lines with `length ~ Poisson(λ=2)` per frame

- **Control Track Errors**: Frame instability from servo loss
  - Target: vhs-tracking upgrade
  - Model: `jitter_y = AR(1) process` with α=0.9 for temporal correlation

### 4. CRT Phosphor Persistence

**Current State:** phantom-lag uses simple RGB rotation; crt-tv lacks phosphor simulation

**Upgrade Opportunities:**
- **Per-Phosphor Decay Rates**: P22 phosphor characteristics
  - Red: 1-2ms | Green: 0.5-1ms | Blue: 2-4ms
  - Target: phantom-lag, rgb-glitch-trail, crt-tv
  
- **Aperture Grille Shadow Mask**: RGB triplet structure
  - Target: crt-tv, crt-magnet
  - Model: `mask(x,y) = (sin(x*π/pitch) + sin(y*π/pitch)) > 0`

- **Halation**: Light scatter in glass faceplate
  - Target: crt-tv upgrade
  - Model: Gaussian blur with σ proportional to pixel brightness

### 5. Analog Video Sync & Timing

**Current State:** scanline-tear has basic sync disruption; no true HSync/VSync simulation

**Upgrade Opportunities:**
- **Horizontal Sync Loss**: Rolling picture effect
  - Target: glitch-slice-mirror, scanline-tear
  - Model: `y_offset = (time % frame_period) * roll_speed` with color burst phase error
  
- **Vertical Hold Failure**: Picture tearing at fold point
  - New shader: `vertical-hold-failure`
  - Model: Discontinuity at `y = fold_position` with brightness modulation

- **Color Burst Phase Error**: Hue shift instability
  - Target: signal-noise, waveform-glitch
  - Model: `θ_error = ∫(Δf)dt` where Δf is instantaneous frequency offset

### 6. Datamoshing Physics

**Current State:** datamosh has placeholder motion vector; no true prediction error

**Upgrade Opportunities:**
- **P-Frame Prediction**: Motion-compensated residual visualization
  - Target: datamosh upgrade
  - Model: `Residual = Current - MotionCompensated(Previous)`
  
- **I-Frame Removal**: Complete prediction chain break
  - Target: datamosh upgrade
  - Visual: Smeared macroblocks with wrong reference

- **Motion Vector Overflow**: Integer overflow in MV coding
  - New shader: `motion-vector-explosion`
  - Model: `MV_actual = MV_coded % 2048` (MPEG-2 MV range)

### 7. Bit Corruption & Error Propagation

**Current State:** byte-mosh has excellent bitwise operations; missing error propagation

**Upgrade Opportunities:**
- **Byte Error Propagation**: Shift register error spread
  - Target: byte-mosh upgrade
  - Model: LFSR-based error pattern `e[n] = (e[n-1] << 1) ^ feedback`
  
- **Entropy Coding Errors**: Huffman/Arithmetic coding corruption
  - New shader: `entropy-breakdown`
  - Visual: Coded stream parsing error with symbol misalignment

- **Checkword Failure**: Reed-Solomon error correction overflow
  - Target: data-stream-corruption upgrade
  - Model: Burst error pattern with `length ~ Uniform(1, 16)` bytes

### 8. Scanline Interlacing

**Current State:** No true interlace simulation; only progressive scanline effects

**Upgrade Opportunities:**
- **Field-Based Rendering**: Temporal offset between even/odd fields
  - Target: scan-distort-gpt52, crt-tv
  - Model: Alternate line offset by `±1px` every 1/60s
  
- **Interline Twitter**: Flickering on fine horizontal detail
  - New shader: `interlace-twitter`
  - Model: `intensity = abs(sin(π*y/2 + π*field)) * contrast`

- **Kell Factor Attenuation**: Vertical resolution loss
  - Target: all scanline shaders
  - Model: Vertical blur with `σ = 0.5 * (1 - Kell_factor)`

### 9. Dithering Pattern Library

**Current State:** No systematic dithering; byte-mosh has some noise

**Upgrade Opportunities:**
- **Bayer Matrix**: Ordered dither with 4x4 or 8x8 threshold map
  - Target: retro-gameboy, digital-glitch
  - Matrix: `B_4 = [[0,8,2,10],[12,4,14,6],[3,11,1,9],[15,7,13,5]]/16`
  
- **Blue Noise**: Stochastic dither with low-frequency suppression
  - Target: glitch-cathedral, static-reveal
  - Implementation: Precomputed 64x64 blue noise texture

- **Floyd-Steinberg Error Diffusion**: Adaptive quantization
  - Target: retro-gameboy upgrade
  - Algorithm: Distribute error to unprocessed neighbors

### 10. Chromatic Subsampling

**Current State:** RGB split is geometric; no true color space transformation

**Upgrade Opportunities:**
- **4:2:0 Subsampling**: CbCr planes at half resolution
  - Target: rgb-split-glitch, rgb-glitch-trail
  - Model: `CbCr_sample = texture(CbCr_tex, uv * 0.5).rg`
  
- **4:1:1 Subsampling**: Horizontal-only chroma reduction (DV format)
  - New shader: `chroma-bleed-411`
  - Model: `CbCr_x = floor(uv.x * width / 4) * 4 / width`

- **Chroma Phase Error**: Hue shift from subcarrier instability
  - Target: vhs-tracking, strip-scan-glitch
  - Model: `HSL.hue += phase_error * chroma_amplitude`

---

## Shader-Specific Upgrade Recommendations

### High Priority (Maximum Impact)

#### 1. byte-mosh → bit-propagation-mosh
**Current:** 8,030B - Bitwise operations on packed RGB
**Upgrade:** Add error propagation chains and entropy coding simulation
**New Features:**
- LFSR-based error pattern generation
- Symbol-level Huffman tree corruption
- Burst error modeling with geometric distribution
- Cross-byte contamination probability
**Scientific Basis:** Reed-Solomon error correction, LFSR theory

#### 2. datamosh → motion-prediction-mosh
**Current:** 3,524B - Placeholder optical flow
**Upgrade:** True motion vector field simulation with prediction error
**New Features:**
- Block-matching motion estimation visualization
- Residual error accumulation
- I-frame removal simulation with reference frame persistence
- GOP structure visualization (I/P/B coloring)
**Scientific Basis:** MPEG-2/MPEG-4 motion compensation, DCT coding

#### 3. crt-tv → aperture-grille-crt
**Current:** 3,242B - Curvature, scanlines, vignette
**Upgrade:** Full CRT physics including shadow mask and phosphor response
**New Features:**
- Aperture grille shadow mask (slot/inline/dot patterns)
- Per-phosphor decay curves (R/G/B different time constants)
- Halation glow from high luminance
- Beam spot size variation with velocity
**Scientific Basis:** P22 phosphor characteristics, CRT electron optics

#### 4. phantom-lag → phosphor-persistence
**Current:** 2,486B - Simple history blend
**Upgrade:** Physically accurate phosphor decay with per-channel curves
**New Features:**
- Exponential decay: `I(t) = I₀ * exp(-t/τ)` with τ_R=1.5ms, τ_G=0.8ms, τ_B=3ms
- Stimulus-dependent persistence (brighter = longer decay)
- Phosphor afterglow color shift
**Scientific Basis:** P22 phosphor emission spectra, decay kinetics

### Medium Priority (Strong Visual Impact)

#### 5. vhs-tracking → magnetic-degradation
**Current:** 3,077B - Horizontal shear
**Upgrade:** Full VHS signal chain simulation
**New Features:**
- Chroma noise modulation (C signal degradation)
- Control track dropout with servo recovery
- Head switching noise at bottom of frame
- Azimuth error between tape heads
**Scientific Basis:** VHS helical scan mechanics, FM chroma recording

#### 6. retro-gameboy → lcd-response-simulation
**Current:** 5,467B - 4-color palette
**Upgrade:** Game Boy LCD physics including ghosting and response time
**New Features:**
- LCD pixel response time (rise/fall asymmetry)
- Ghosting from previous frame persistence
- Scanline blanking interval simulation
- Pixel grid with non-rectangular aperture
**Scientific Basis:** STN LCD response characteristics, passive matrix driving

#### 7. signal-noise → rf-interference
**Current:** 2,848B - Scanline band noise
**Upgrade:** VHF/UHF interference modeling
**New Features:**
- Carrier wave interference patterns
- Ghosting from multipath propagation
- Signal strength fading (Rician/Rayleigh)
- Adjacent channel interference
**Scientific Basis:** RF propagation, broadcast signal structure

#### 8. glitch-cathedral → dct-block-cathedral
**Current:** 4,161B - Geometric cells with RGB split
**Upgrade:** JPEG/MPEG DCT coefficient manipulation
**New Features:**
- 8x8 DCT basis function visualization
- Coefficient quantization matrices
- AC/DC coefficient separate handling
- Zigzag scan pattern visualization
**Scientific Basis:** JPEG/MPEG DCT compression, quantization tables

### Lower Priority (Niche but Authentic)

#### 9. scan-distort-gpt52 → interlace-simulation
**Current:** 3,234B - Barrel distortion
**Upgrade:** True interlaced video behavior
**New Features:**
- Even/odd field temporal offset
- Interline flicker on fine detail
- Field-based motion blur
- Deinterlacing artifacts
**Scientific Basis:** ITU-R BT.601, interlaced scanning

#### 10. sliding-tile-glitch → macroblock-discontinuity
**Current:** 4,279B - Grid state persistence
**Upgrade:** MPEG macroblock motion vector visualization
**New Features:**
- 16x16 macroblock grid overlay
- Motion vector arrow visualization
- Reference frame indication
- Skip/block pattern display
**Scientific Basis:** MPEG-2 macroblock structure, motion vectors

---

## New Shader Proposals

### 1. `quantization-error-diffusion`
**Scientific Basis:** Floyd-Steinberg, Jarvis-Judice-Ninke dithering
**Technique:** Error diffusion dithering with adjustable kernel
**Visual:** Classic halftone patterns with artistic control
**Parameters:** Kernel type, threshold, error attenuation

### 2. `chroma-subsampling-bleed`
**Scientific Basis:** 4:2:0, 4:2:2, 4:1:1 subsampling formats
**Technique:** YUV separation with independent resolution scaling
**Visual:** Color fringing on edges, classic "DV look"
**Parameters:** Subsampling mode, chroma phase, bandwidth limit

### 3. `dropout-compensation`
**Scientific Basis:** VHS/UMatic tape dropouts
**Technique:** Random vertical white streaks with line replacement
**Visual:** Classic tape damage aesthetic
**Parameters:** Dropout rate, average length, compensation mode

### 4. `sync-pulse-disruption`
**Scientific Basis:** Analog video sync signals
**Technique:** HSync/VSync pulse manipulation
**Visual:** Rolling, tearing, color loss
**Parameters:** Sync loss type, recovery time, noise injection

### 5. `entropy-corruption`
**Scientific Basis:** Huffman/Arithmetic coding
**Technique:** Bitstream parsing with symbol misalignment
**Visual:** Blocky corruption spreading from error point
**Parameters:** Error position, code table, propagation rate

---

## Implementation Notes

### Data Texture Utilization
Current shaders use dataTextureA/B/C for persistence. Upgrades should leverage:
- **dataTextureA**: Motion vector field (for datamosh upgrades)
- **dataTextureB**: Previous frame chroma planes (for subsampling effects)
- **dataTextureC**: Phosphor excitation state (for CRT persistence)

### Performance Considerations
- DCT operations: Use precomputed basis functions, not runtime DCT
- Blue noise: Precomputed texture, not procedural generation
- Motion estimation: Simplified block matching, not full ME

### Parameter Mapping Standardization
```
zoom_params.x: Effect intensity/strength
zoom_params.y: Temporal/speed factor
zoom_params.z: Detail/frequency control
zoom_params.w: Error rate/corruption level
zoom_config.yz: Mouse position for localized effects
```

---

## Artistic Vision Statement

The goal of these upgrades is not merely technical accuracy, but **amplified aesthetic through understanding**. Each scientific phenomenon encodes a visual poetry:

- Phosphor persistence speaks to memory and fading
- Bit corruption embodies digital fragility
- VHS tracking errors map time onto physical space
- DCT blocks reveal the compression of reality itself

By grounding our glitch aesthetics in computational truth, we make the invisible visible—the algorithms that mediate our digital experience become material for artistic expression.

---

*Document Version: 1.0*
*Analysis Date: 2026-03-14*
*Shader Count Analyzed: 29*
*Scientific Concepts Mapped: 10*
*Upgrade Recommendations: 20*
*New Shader Proposals: 5*
