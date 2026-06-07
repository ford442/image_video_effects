# GLITCH & RETRO SHADERS: Aesthetic/Technical Upgrade Plan

## Research Synthesis: Digital Artifacting & Signal Processing

---

## Executive Summary

This document outlines a comprehensive upgrade plan for glitch and retro-tech shader effects based on deep research into:
- Digital signal degradation mechanisms
- Compression artifact physics (JPEG, MPEG)
- Analog signal interference patterns
- CRT display physics and phosphor behavior
- VHS tape degradation characteristics
- Data corruption algorithms and bit manipulation
- Dithering patterns and error diffusion
- Glitch art theory and aesthetics

**Target Shaders for Enhancement:**
- `glitch-pixel-sort`, `signal-noise`
- `rgb-glitch-trail`, `static-reveal`
- `digital-glitch`, `scanline-tear`
- `vhs-tracking`, `waveform-glitch`
- `datamosh`, `byte-mosh`
- `scan-distort`, `scan-slice`
- `crt-tv`, `crt-phosphor-decay`
- `retro-gameboy`, `synthwave-grid-warp`

---

## Part 1: Real-World Signal Degradation to Simulate

### 1.1 Digital Signal Degradation

#### Bit Error Patterns
**Physical Basis:** Digital signals degrade through quantization noise, bit flips, and entropy loss.

**Mathematical Models:**
- **Gaussian Noise Model:** `n(x) = A * exp(-(x-μ)²/(2σ²))`
- **Salt & Pepper Noise:** Random bit flips with probability p at pixel positions
- **Burst Errors:** Correlated errors in contiguous bit regions

**Shader Implementation Strategies:**
```
Bit manipulation effects:
- XOR-based glitch: color ^ (noise << shift_amount)
- Bit-plane slicing: extract and manipulate individual bit planes
- Quantization artifacts: floor(color * levels) / levels
- Integer overflow/underflow simulation
```

**Visual Characteristics:**
- Color channel separation at bit boundaries
- Posterization artifacts from insufficient bit depth
- "Digital banding" in smooth gradients
- Sudden color inversions from sign bit flipping

#### Compression Artifacts

##### JPEG/DCT Blocking Artifacts
**Technical Foundation:**
- JPEG divides images into 8×8 pixel blocks
- Discrete Cosine Transform (DCT) converts spatial to frequency domain
- Quantization rounds coefficients, losing high-frequency data
- Block boundaries become visible at high compression ratios

**Artifact Types:**
1. **Blocking:** Visible grid at 8×8 block boundaries
2. **Ringing:** Oscillations near high-contrast edges (Gibbs phenomenon)
3. **Mosquito Noise:** Temporal flickering around moving edges in video
4. **Color Bleeding:** Chroma subsampling (4:2:0) causes color misalignment

**Shader Simulation Approach:**
```
DCT-based simulation:
- Simulate frequency domain representation
- Apply quantization matrix
- Reconstruct with visible blocking
- Add "mosquito" temporal noise near edges
```

**Artistic Reference:**
- Rosa Menkman's "Vernacular of File Formats" series
- Thomas Ruff's "Jpegs" photography collection
- Early 2000s internet image culture

##### MPEG Motion Compensation Errors
**Technical Foundation:**
- I-frames: Complete reference images
- P-frames: Store motion vectors from previous frames
- B-frames: Bidirectional prediction

**Datamoshing Mechanics:**
- Removing I-frames causes P-frames to apply motion to wrong base image
- Creates "melting" effect where pixels smear and bleed
- Motion vectors applied to mismatched visual data

**Shader Simulation:**
```
Datamosh approximation:
- Optical flow estimation for motion vectors
- Temporal displacement based on motion
- "Motion hijacking" - apply one region's motion to another
- Controlled I-frame dropping simulation
```

### 1.2 Analog Signal Interference

#### RF Interference Patterns
**Physical Sources:**
- Electromagnetic interference from power lines
- Radio frequency bleed-through
- Cross-talk between signal channels
- Ground loop hum (60Hz/50Hz interference)

**Visual Manifestations:**
- Horizontal drift bands
- Diagonal interference patterns
- "Venetian blind" effects
- Pulsing brightness modulation

**Mathematical Model:**
```
interference(x,y,t) = A * sin(2π * (fx*x + fy*y + ft*t) + φ)
- fx, fy: spatial frequencies
- ft: temporal frequency (often 60Hz for power interference)
- A: amplitude based on signal degradation
```

#### Signal-to-Noise Ratio Degradation
**Characteristics:**
- SNR measured in dB: higher is cleaner
- Analog TV: ~45dB SNR for good quality
- VHS: ~40-45dB theoretical, often 35-40dB in practice
- Noise increases with tape wear and head condition

**Noise Types:**
1. **White Noise:** Uniform spectral density
2. **Pink Noise:** 1/f frequency distribution (more natural)
3. **Impulse Noise:** Random spikes (dropouts)
4. **Chroma Noise:** Color signal specific noise

### 1.3 CRT Display Physics

#### Electron Beam Scanning
**Technical Specifications:**
- NTSC: ~15.734 kHz horizontal scan frequency
- PAL: ~15.625 kHz horizontal scan frequency
- Vertical refresh: 60Hz (NTSC) / 50Hz (PAL)
- Interlaced scanning: Odd/even fields alternate

**Visual Characteristics:**
- Rolling bar artifacts when sync is lost
- Horizontal hold instability
- Vertical collapse to line
- "Folding" at screen edges

#### Phosphor Persistence & Decay
**Physics:**
- Electron beam excites phosphor coating
- Phosphor emits light as it returns to ground state
- Decay follows exponential curve: `I(t) = I₀ * e^(-t/τ)`
- τ (time constant) varies by phosphor type:
  - P22 (standard TV): ~1-2ms
  - P44 (fast): ~0.1ms
  - Long persistence: >10ms

**Visual Effects:**
- Motion trails on bright objects
- Greenish phosphor afterglow (classic TV look)
- Flicker at low refresh rates
- Motion clarity superior to LCD (no sample-and-hold blur)

**Shader Implementation:**
```
Phosphor decay simulation:
- History buffer for previous frames
- Exponential decay based on luminance
- Separate RGB decay rates for color fringing
- Temporal accumulation for trail effects
```

#### Scanline Structure
**Physical Basis:**
- Visible gaps between scanned lines
- Thickness varies by CRT type and brightness
- More visible on brighter content
- Interlacing creates "combing" on motion

**Mathematical Model:**
```
scanline(y, intensity) = 1 - (scanline_strength * sin²(π * y * scanline_count))
- scanline_strength: 0.0-1.0 visibility
- scanline_count: lines per screen height
- Modulate by brightness for realistic variation
```

#### Moiré Patterns
**Cause:**
- Interference between scanline pattern and image content
- Most visible on fine repeating patterns
- Varies with image scaling

### 1.4 VHS Tape Characteristics

#### Magnetic Tape Physics
**Format Specifications:**
- Tape width: 12.7mm (1/2 inch)
- Video track angle: ~5-6 degrees (helical scan)
- Chroma signal: ~0.5MHz bandwidth (vs 4.2MHz luma)

**Degradation Modes:**
1. **Oxide Shedding:** Magnetic particles detach, causing dropouts
2. **Binder Hydrolysis:** "Sticky shed syndrome" - tape becomes sticky
3. **Print-Through:** Magnetic imprint from adjacent tape layers
4. **Edge Damage:** Physical tape edge wear

#### Tracking Errors
**Technical Cause:**
- Playback head misalignment with recorded tracks
- Can be caused by tape stretch, worn guides, or different VCR

**Visual Manifestations:**
- Horizontal noise bars at top/bottom of frame
- "Tracking noise" - rolling horizontal bands
- Picture tearing
- Audio buzz synchronous with tracking errors

**Shader Simulation:**
```
tracking_error(y, t) = noise * gaussian(y - y_error_position) * sin(2π * t * tracking_frequency)
- y_error_position: varies slowly over time
- tracking_frequency: ~2-5Hz typical
```

#### Chroma Characteristics
**VHS Color Limitations:**
- Chroma bandwidth severely limited (~0.5MHz)
- Color "smear" and bleeding
- Chroma noise much higher than luma noise
- Color "crawl" on saturated colors
- Chroma delay relative to luma

**Shader Implementation:**
```
VHS chroma simulation:
- Separate chroma/luma processing
- Blur chroma channels horizontally
- Add chroma-specific noise
- Temporal instability for "crawl"
- Delay chroma slightly for misalignment
```

#### Signal Dropouts
**Physical Cause:**
- Missing magnetic material on tape
- Head clog
- Tape damage

**Visual Characteristics:**
- Brief white/black flashes
- Horizontal lines of noise
- Duration: 1-3 scan lines typical
- Random temporal distribution

---

## Part 2: Retro Hardware Characteristics

### 2.1 CRT Display Types

#### Shadow Mask CRTs
**Technology:**
- Triad arrangement of RGB phosphor dots
- Shadow mask metal grille ensures correct electron targeting
- Dot pitch: 0.2-0.4mm typical

**Visual Signature:**
- Visible RGB dot structure up close
- "Screen door" effect
- Moiré when image content aligns with dot pattern

**Shader Simulation:**
```
Shadow mask pattern:
- RGB triad texture
- Modulate brightness by mask aperture
- Distance-based falloff
- Angle-dependent visibility
```

#### Aperture Grille (Trinitron)
**Technology:**
- Vertical phosphor stripes instead of dots
- Tensioned wire grille (aperture grille)
- Higher brightness than shadow mask

**Visual Signature:**
- Horizontal "scanline" gaps more prominent
- Slightly different color blending
- Characteristic horizontal support wire shadows (1-2 lines)

#### Early Digital Displays
**LCD Early Generations:**
- Slow response time (16-25ms)
- Visible pixel grid
- Limited viewing angles
- Backlight bleed

**Plasma Displays:**
- Phosphor-based (similar to CRT)
- "Phosphor trail" motion artifacts
- Dithering for gray levels
- Cell structure visible

### 2.2 Early Digital Graphics Hardware

#### 8-bit Era (Game Boy, NES)
**Constraints:**
- 2-4 bits per pixel (4-16 colors)
- Hardware sprites with limitations
- Fixed palettes
- Visible tile boundaries

**Shader Simulation:**
```
Retro 8-bit effects:
- Palette quantization to 4-16 colors
- Dithering patterns for fake gradients
- Visible pixel grid
- Sprite multiplexing artifacts
```

#### 16-bit Era (SNES, Genesis)
**Characteristics:**
- More colors (256-32,768)
- Mode 7 rotation/scaling
- Multiple background layers
- Limited transparency

**Visual Signatures:**
- Dithering for transparency
- "Color math" effects
- Scanline-based effects

### 2.3 Analog Video Connections

#### Composite Video
**Technical:**
- Luma and chroma combined
- Chrominance subcarrier: 3.58MHz (NTSC), 4.43MHz (PAL)

**Artifacts:**
- Dot crawl on vertical color transitions
- Color bleeding on sharp edges
- Cross-color (rainbow) artifacts

#### S-Video (Y/C)
**Improvement:**
- Separates luma and chroma
- Eliminates most dot crawl
- Still limited chroma bandwidth

#### RGB/Component
**Characteristics:**
- Best analog quality
- No chroma/luma interference
- Still subject to analog noise

---

## Part 3: Glitch Aesthetics & "Controlled Chaos"

### 3.1 Glitch Art Theory

#### The Glitch Moment(um)
*Concept from Rosa Menkman's "The Glitch Moment(um)" (2011)*

**Definition:**
> "The glitch is a wonderful experience of an interruption that shifts an object away from its ordinary form and discourse, towards the ruins of destroyed meaning."

**Key Aspects:**
1. **Material Break:** The physical/technical failure
2. **Conceptual Investigation:** Understanding the system's limits
3. **Aesthetic Commodification:** When glitches become style

**Critical Framework:**
- Glitches reveal the normally invisible materiality of digital media
- They challenge techno-utopian narratives of digital perfection
- The "punctum" (Barthes) - the accidental detail that pricks the viewer
- Glitch as critique of digital capitalism's seamless interfaces

### 3.2 Types of Glitch Aesthetics

#### Data Bending
**Process:**
- Treat media files as raw data
- Open in "wrong" editors (text, audio, hex)
- Apply transformations
- Reinterpret as image/video

**Visual Characteristics:**
- Unexpected color shifts
- Geometric pattern disruptions
- Repetition artifacts
- Header corruption patterns

**Shader Simulation:**
```
Data bending approximation:
- Treat color values as indices into wrong lookup tables
- Byte-level operations on color channels
- Memory layout manipulation simulation
- "Wrong" interpretation of data structures
```

#### Compression Artifacts as Aesthetic
**DCT Block Aesthetics:**
- Visible 8×8 block structures
- "Macroblocking" at low bitrates
- Ringing around edges
- Color quantization bands

**MPEG Motion Glitches:**
- Datamosh "melting" transitions
- Motion vector misapplication
- Temporal prediction errors

#### Circuit Bending (Hardware Glitch)
**Process:**
- Physically modify electronic circuits
- Short components to create instability
- Feedback loops
- Power manipulation

**Visual Translation:**
- Sync loss patterns
- Color signal instability
- Horizontal/vertical collapse
- "Kaleidoscope" effects from memory addressing errors

### 3.3 Controlled Chaos Parameters

#### Intensity Mapping
**Glitch Progression:**
```
Level 1 (Subtle):
- Occasional single-pixel errors
- Minimal color shift
- Brief, rare artifacts
- 1-2% of frame affected

Level 2 (Moderate):
- Visible block corruption
- Color channel displacement
- Regular artifacting
- 5-10% of frame affected

Level 3 (Severe):
- Large-scale corruption
- Temporal persistence
- Significant image destruction
- 20-40% of frame affected

Level 4 (Extreme):
- Near-total image breakdown
- Heavy temporal artifacts
- Abstract patterns dominate
- 60%+ of frame affected
```

#### Temporal Control
**Glitch Timing:**
- Burst patterns: Short intense periods
- Rhythmic: Synced to audio or beat
- Random: Poisson distribution of events
- Threshold-based: Triggered by image content

#### Spatial Distribution
**Glitch Location:**
- Edge-focused: Corruption at frame boundaries
- Center-focused: Central image degradation
- Banding: Horizontal/vertical strip artifacts
- Scattered: Random pixel/pattern distribution
- Content-aware: Based on motion or edges

---

## Part 4: Digital Art Movements to Draw From

### 4.1 Net Art & Early Internet Aesthetics (1990s-2000s)

#### Characteristics:
- Low bandwidth constraints
- GIF animation limitations
- JPEG compression as aesthetic
- Under-construction pages
- Geocities visual language

**Relevant Techniques:**
- Limited color palettes (256 colors)
- Visible dithering patterns
- Heavy JPEG artifacts
- Tiling backgrounds
- Animated GIF "sparkles"

### 4.2 Vaporwave & Synthwave

#### Visual Language:
- 80s/90s corporate aesthetics
- Neon gradients
- Greek busts (ironic juxtapositions)
- Grid landscapes
- Scanlines and CRT simulation
- VHS degradation

**Technical Elements:**
- Chromatic aberration
- RGB channel shifting
- Anaglyph 3D effects
- Datamosh transitions
- "Outrun" grid geometry

### 4.3 Cyberpunk & Dystopian Tech

#### Visual Tropes:
- Rain-slicked neon streets
- CRT terminals
- Glitch as system failure
- Surveillance aesthetic
- Digital decay

**Shader Opportunities:**
- Terminal/cathode-ray glow
- Rolling code decryption effects
- Holographic glitch
- Surveillance distortion
- Rain-streaked distortion

### 4.4 Demoscene

**Aesthetics:**
- Real-time procedural generation
- Limit-driven creativity
- "Size coding" constraints
- Synthesis over samples

**Relevant Techniques:**
- XOR textures (classic demoscene pattern)
- Plasma effects
- Raymarching with glitch
- Minimalist geometry

### 4.5 Contemporary Glitch Art

#### Key Artists & Works:

**Rosa Menkman:**
- "Vernacular of File Formats" (2010-2011)
- "Beyond Resolution" (ongoing)
- DCT block aesthetics
- Compression artifact studies

**Takeshi Murata:**
- "Monster Movie" (2005)
- Datamosh in gallery context
- Smithsonian collection

**Sara Ludy:**
- Subtle glitch interventions
- Ambient digital textures
- Dreamlike distortions

**Antonio Roberts:**
- Real-time glitch performance
- Open-source tools
- Circuit bending aesthetics

---

## Part 5: Dithering & Pattern Systems

### 5.1 Error Diffusion Dithering

#### Floyd-Steinberg Algorithm (1976)
**Distribution Pattern:**
```
     Current Pixel
           X     7/16
    3/16  5/16  1/16
```

**Shader Implementation:**
- Forward-only processing (challenging in parallel GPU)
- Approximation using multiple passes
- Serpentine scanning for reduced artifacts

**Visual Characteristics:**
- Organic, scattered patterns
- Good gradient reproduction
- Directional artifacts possible

#### Variants:
- **Jarvis-Judice-Ninke:** Smoother, uses 12 neighbors
- **Stucki:** Optimized for bit-shifting
- **Burkes:** Faster compromise
- **Sierra:** Balanced quality/performance
- **Atkinson:** 75% error distribution (Macintosh aesthetic)

### 5.2 Ordered Dithering

#### Bayer Matrix
**Construction:**
```
2×2:          4×4:
[0  2]        [ 0  8  2 10]
[3  1]        [12  4 14  6]
              [ 3 11  1  9]
              [15  7 13  5]
```

**Properties:**
- Recursive construction: `D₂ₙ = [4Dₙ + D₂(1,1)Uₙ, ...]`
- Even threshold distribution
- Fast, parallelizable
- Distinctive crosshatch pattern

**Shader Implementation:**
```
ordered_dither(pixel, threshold_matrix):
    x = pixel.x % matrix_size
    y = pixel.y % matrix_size
    threshold = matrix[y][x] / matrix_size²
    return pixel.value > threshold ? white : black
```

#### Blue Noise Dithering
**Characteristics:**
- More organic than Bayer
- Higher frequency patterns
- Less visible structure

### 5.3 Halftone Patterns

**Traditional Printing Simulation:**
- Dot patterns at various angles
- Clustered dots for stability
- AM (Amplitude Modulation) screening

**Digital Applications:**
- Newsprint aesthetic
- Comic book coloring
- Vintage advertising

---

## Part 6: Shader Upgrade Specifications

### 6.1 Core Parameter Framework

All glitch/retro shaders should support these parameter categories:

```
BASE_PARAMETERS:
  intensity: 0.0 - 1.0          // Overall effect strength
  temporal_speed: 0.0 - 2.0      // Animation speed multiplier
  seed: 0 - 65535               // Random seed for reproducibility
  
DEGRADATION_PARAMETERS:
  noise_amount: 0.0 - 1.0
  noise_type: [white|pink|impulse]
  compression_quality: 0.0 - 1.0  // JPEG-like quality setting
  bit_depth: 1 - 8               // Simulated color depth
  
ANALOG_PARAMETERS:
  scanline_strength: 0.0 - 1.0
  phosphor_decay: 0.0 - 1.0
  signal_noise: 0.0 - 1.0
  tracking_error: 0.0 - 1.0
  chroma_bleed: 0.0 - 1.0
  
SPATIAL_PARAMETERS:
  block_size: 1 - 64             // For block-based effects
  displacement_amount: 0.0 - 0.5
  channel_separation: 0.0 - 1.0   // RGB shift
```

### 6.2 Shader-Specific Recommendations

#### glitch-pixel-sort
**Current:** Basic pixel sorting by brightness

**Enhancements:**
- Add threshold-based sorting (only sort above threshold)
- Directional control (vertical/horizontal/diagonal)
- Multi-pass sorting with different criteria
- "Broken" sorting (random intervals)
- Integration with edge detection

**Technical Approach:**
```
pixel_sort(uv, threshold, direction, mode):
    edge = detect_edge(uv)
    if edge > threshold:
        sort_pixels_along_direction(uv, direction, mode)
```

#### signal-noise
**Current:** Basic noise overlay

**Enhancements:**
- Signal-to-noise ratio simulation
- Frequency-specific noise (chroma vs luma)
- Temporal coherence
- Impulse noise (dropouts)
- Interference patterns

**Noise Models:**
```
white_noise(uv, t): random(uv, t)
pink_noise(uv, t): sum(octaves of 1/f noise)
impulse_noise(uv, t): threshold(random) ? extreme : 0
interference(uv, t): sin(2π * (spatial + temporal_freq * t))
```

#### rgb-glitch-trail
**Current:** Simple RGB displacement

**Enhancements:**
- Velocity-based displacement
- Temporal persistence (motion blur-like)
- Color-specific decay rates
- Warping along motion vectors
- "Ghost frame" compositing

#### static-reveal
**Current:** Static with reveal pattern

**Enhancements:**
- VCR tracking noise simulation
- Horizontal hold instability
- "Snow" patterns with correct distribution
- Signal acquisition phases (search, acquisition, lock)
- Chrominance signal-specific noise

#### digital-glitch
**Current:** Block-based displacement

**Enhancements:**
- DCT-block-aware corruption
- Quantization simulation
- Motion vector errors
- I-frame/P-frame differential corruption
- Entropy coding errors

#### scanline-tear
**Current:** Simple scanline displacement

**Enhancements:**
- V-sync loss simulation
- Rolling bar artifacts
- Horizontal tearing with variable position
- Phase distortion
- Interlace field misalignment

#### vhs-tracking
**Current:** Basic tracking lines

**Enhancements:**
- Dynamic tracking adjustment simulation
- Tracking noise bands that move/change
- Chroma noise specific to tracking errors
- Audio buzz correlation
- Tape speed variation (wow/flutter)

#### waveform-glitch
**Current:** Wave-based distortion

**Enhancements:**
- Oscilloscope-style rendering
- Vector display simulation (Atari-style)
- Lissajous patterns
- Signal aliasing
- Beat frequency effects

#### datamosh
**Current:** Motion-based smearing

**Enhancements:**
- Optical flow integration
- Motion vector visualization
- I-frame/P-frame differential treatment
- "Motion hijacking" from different regions
- Controlled corruption of prediction

#### byte-mosh
**Current:** Bit manipulation effects

**Enhancements:**
- Byte-level operations (XOR, AND, OR)
- Bit shifting with rotation
- Bit-plane extraction and manipulation
- Byte swap effects
- Integer overflow simulation

#### scan-distort
**Current:** Scanline displacement

**Enhancements:**
- Sine-based horizontal displacement
- Time-varying distortion
- Edge displacement attenuation
- Multi-frequency interference

#### scan-slice
**Current:** Vertical slice displacement

**Enhancements:**
- Variable slice width
- Slice-based processing (different effect per slice)
- Horizontal banding integration
- "Jitter" between slices

#### crt-tv
**Current:** Basic CRT simulation

**Enhancements:**
- Shadow mask/aperture grille patterns
- Phosphor decay with RGB differential
- Curvature/barrel distortion
- Reflection/glare simulation
- Bloom from bright areas

#### crt-phosphor-decay
**Current:** Simple persistence

**Enhancements:**
- Separate RGB decay rates
- Exponential decay curves
- History buffer integration
- Variable persistence by brightness
- "Strobing" at low persistence

#### retro-gameboy
**Current:** 4-color palette

**Enhancements:**
- Correct Game Boy color palette
- LCD "ghosting" effect
- Pixel grid simulation
- Sprite artifact simulation
- Dithering patterns for intermediate shades

#### synthwave-grid-warp
**Current:** Grid with perspective

**Enhancements:**
- "Outrun" aesthetic elements
- Sun with gradient banding
- Grid perspective with Z-movement
- Chromatic aberration on edges
- VHS-style degradation overlay

---

## Part 7: Implementation Architecture

### 7.1 Shared Utilities Library

Create a shared WGSL utility library for glitch effects:

```wgsl
// noise.wgsl - Shared noise functions
fn hash2(p: vec2<f32>) -> f32
fn hash3(p: vec3<f32>) -> f32
fn value_noise(p: vec2<f32>) -> f32
fn gradient_noise(p: vec2<f32>) -> f32
fn fbm(p: vec2<f32>, octaves: i32) -> f32
fn voronoi(p: vec2<f32>) -> vec2<f32>

// dither.wgsl - Dithering patterns
fn bayer_2x2(uv: vec2<i32>) -> f32
fn bayer_4x4(uv: vec2<i32>) -> f32
fn bayer_8x8(uv: vec2<i32>) -> f32
fn blue_noise(uv: vec2<i32>) -> f32

// analog.wgsl - Analog signal simulation
fn scanline(y: f32, intensity: f32) -> f32
fn phosphor_decay(color: vec3<f32>, decay_rate: f32) -> vec3<f32>
fn chroma_bleed(uv: vec2<f32>, amount: f32) -> vec2<f32>
fn tracking_noise(uv: vec2<f32>, t: f32, amount: f32) -> f32

// digital.wgsl - Digital artifact simulation
fn quantize(value: f32, levels: i32) -> f32
fn dct_block_artifact(uv: vec2<f32>, quality: f32) -> f32
fn bit_crush(color: vec3<f32>, bits: i32) -> vec3<f32>
fn xor_glitch(a: f32, b: f32, shift: i32) -> f32
```

### 7.2 Multi-Pass Architecture

For complex effects, implement multi-pass shaders:

```
Pass 1: Noise/Signal Generation
  - Generate noise textures
  - Calculate motion vectors
  - Prepare distortion maps

Pass 2: Primary Effect
  - Apply main glitch/retro effect
  - Generate artifacts

Pass 3: Post-Processing
  - Apply dithering
  - Add scanlines/CRT effects
  - Final color grading
```

### 7.3 Temporal Coherence

Maintain temporal state for:
- Phosphor decay trails
- Noise evolution
- Glitch progression
- Signal instability accumulation

```wgsl
// Uniform buffer for temporal state
struct TemporalState {
    frame_count: u32,
    accumulated_noise: f32,
    glitch_phase: f32,
    last_glitch_time: f32,
}
```

---

## Part 8: Artistic Guidelines

### 8.1 The "Controlled Chaos" Principle

**Guideline:** Glitch shaders should feel "broken but beautiful"

**Implementation:**
- Provide seed-based reproducibility
- Allow "chaos" parameter for unpredictability
- Implement glitch "presets" (subtle, moderate, extreme)
- Enable selective application (masks, keying)

### 8.2 Historical Accuracy vs. Artistic License

**Approach:**
- Research authentic technical characteristics
- Document deviations for artistic effect
- Provide "authentic" and "stylized" modes
- Allow mixing of different era characteristics

### 8.3 User Control Philosophy

**Parameters should:**
- Have intuitive names
- Show meaningful range (0-100% rather than 0-1)
- Include presets for common looks
- Allow automation/animation
- Support MIDI/controller mapping

---

## Part 9: Reference Materials

### Key Texts:
- Menkman, Rosa. "The Glitch Moment(um)" (2011)
- Moradi, Iman. "Glitch Aesthetics" (2004)
- Menkman, Rosa. "A Vernacular of File Formats" (2010)

### Technical References:
- JPEG ISO/IEC 10918-1 standard
- MPEG-2/H.264 specifications
- CRT physics: Chen, J. "Physics of Cathode Ray Tubes"
- VHS specifications: IEC 60774

### Artistic References:
- Rosa Menkman's "Beyond Resolution" series
- Takeshi Murata's "Monster Movie"
- Kanye West "Welcome to Heartbreak" (music video)
- Charli XCX "2099" (music video)
- Stranger Things title sequence

---

## Part 10: Development Priorities

### Phase 1: Core Infrastructure
1. Shared noise/dither utility library
2. Temporal state management
3. Parameter standardization

### Phase 2: Digital Glitch Suite
1. glitch-pixel-sort enhancements
2. digital-glitch with DCT simulation
3. datamosh with optical flow
4. byte-mosh bit manipulation

### Phase 3: Analog/Retro Suite
1. crt-tv comprehensive simulation
2. vhs-tracking authentic artifacts
3. signal-noise multi-model
4. retro-gameboy accuracy

### Phase 4: Synthesis Effects
1. Combined analog+digital pipelines
2. Preset system
3. Performance optimization

---

## Appendix A: Mathematical Formulas

### Gaussian Distribution
```
f(x) = (1/σ√(2π)) * e^(-(x-μ)²/(2σ²))
```

### 2D DCT (Discrete Cosine Transform)
```
DCT(u,v) = α(u)α(v) ΣΣ f(x,y)cos[(2x+1)uπ/2N]cos[(2y+1)vπ/2N]
where α(u) = √(1/N) for u=0, √(2/N) otherwise
```

### Phosphor Decay
```
I(t) = I₀ * e^(-t/τ)
```

### Bayer Matrix Generation
```
M₂ = [[0, 2], [3, 1]]
M₂ₙ = [[4Mₙ + M₂(0,0)Uₙ, 4Mₙ + M₂(0,1)Uₙ],
       [4Mₙ + M₂(1,0)Uₙ, 4Mₙ + M₂(1,1)Uₙ]]
```

---

*Document Version: 1.0*
*Research Date: March 2026*
*Author: Shader Research Agent - Glitch & Retro Effects Specialist*
