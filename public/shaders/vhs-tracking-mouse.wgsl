// ═══════════════════════════════════════════════════════════════════
//  VHS Tracking (Mouse)
//  Category: interactive-mouse
//  Features: mouse-driven, click-reactive, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-28
//  Ideas: dash-noise texture (row-aligned dropout streaks); tracking knob on mouse X + held auto-track lock; AGC lift in the band
//  A packing: ACES display RGB + source alpha (no C read)
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn rand(co: vec2<f32>) -> f32 {
    let seed = max(dot(co, vec2<f32>(12.9898, 78.233)), 0.001);
    return fract(sin(seed) * 43758.5453);
}

fn ign_noise(p: vec2<i32>) -> f32 {
  let f = vec2<f32>(p);
  return fract(52.9829189 * fract(dot(f, vec2<f32>(0.06711056, 0.00583715))));
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.3 + mids * 0.1;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    // The tracking head follows the raw pointer (the old extraBuffer spring read re-zeroed state).
    let mousePos = u.zoom_config.yz;
    let heldDown = u.zoom_config.w > 0.5;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Each click punches a short tracking tear through the tape at its true
    // normalized position. Horizontal localization keeps separate clicks distinct.
    // The newest ripple timestamp doubles as the mouse-down time for the auto-track lock.
    let aspect = resolution.x / max(resolution.y, 0.001);
    var clickDamage = 0.0;
    var clickShear = 0.0;
    var lastPress = time - 1.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
      let rp = u.ripples[i];
      let age = time - rp.z;
      let safeAge = max(age, 0.0);
      let live = step(0.0, age) * (1.0 - step(1.35, age));
      let yBand = 1.0 - smoothstep(0.015, 0.12, abs(uv.y - rp.y));
      let xWindow = 1.0 - smoothstep(0.18, 0.7, abs(uv.x - rp.x) * aspect);
      let damage = yBand * (0.35 + xWindow * 0.65) * exp(-safeAge * 2.1) * live;
      clickDamage = max(clickDamage, damage);
      clickShear += damage * sin(uv.y * 170.0 + rp.x * 31.0 + safeAge * 22.0);
      if (age >= 0.0) { lastPress = max(lastPress, rp.z); }
    }

    // ── IDEA 2: tracking knob on mouse X + held auto-track ──
    // |X − 0.5| is the tracking knob: turning it off-centre detunes the head (band widens,
    // wobble grows, dashes lengthen). Holding the button engages auto-tracking: over ~1 s
    // from the press the band converges to a thin, quiet lock line and releases on mouse-up.
    // X = 0.5 unheld reproduces HEAD exactly.
    let detune = abs(mousePos.x - 0.5) * 2.0;
    let lockRaw = clamp((time - lastPress) / 1.0, 0.0, 1.0);
    let lock = select(0.0, lockRaw * lockRaw * (3.0 - 2.0 * lockRaw), heldDown);
    let detuneLive = detune * (1.0 - lock);

    let barHeight = (u.zoom_params.x * 0.3 + 0.05) * (1.0 + detuneLive * 1.2) * (1.0 - lock * 0.75);
    let strength = u.zoom_params.y * 0.1 * bass_env(bass, mids) * (1.0 + detuneLive * 1.5) * (1.0 - lock * 0.85);
    let noiseAmt = u.zoom_params.z * (1.0 - lock * 0.8);
    let colorShift = u.zoom_params.w * 0.02;

    let distY = abs(uv.y - mousePos.y);
    // Soft band gate: the old hard `distY < barHeight` cut is a smooth shoulder now.
    let bandGate = 1.0 - smoothstep(barHeight * 0.85, barHeight, distY);
    let bar_intensity = smoothstep(barHeight, 0.0, distY) * bandGate;

    // Tracking wobble + horizontal hold instability
    let wobble = sin(uv.y * 80.0 + time * 25.0) * strength * bar_intensity;
    let holdWobble = sin(time * 3.0 + bass * 5.0) * 0.008 * bar_intensity;
    let jitter = (rand(vec2<f32>(uv.y, floor(time * 60.0))) - 0.5) * strength * 3.0 * bar_intensity;
    let displacedUV = clamp(uv + vec2<f32>(wobble + jitter + holdWobble + clickShear * strength * 2.0, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let damageMix = clamp(bandGate + clickDamage * 50.0, 0.0, 1.0);
    let sampleUV = mix(uv, displacedUV, damageMix);

    // Chroma bleed: R/G/B sample at different horizontal offsets
    let bleedAmount = colorShift * (1.0 + bar_intensity * 3.0);
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(bleedAmount, 0.0), 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(bleedAmount * 0.3, 0.0), 0.0);
    let g = gSample.g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(bleedAmount * 0.8, 0.0), 0.0).b;
    var color = vec3<f32>(r, g, b);
    let srcAlpha = gSample.a;

    // ── IDEA 1: dash-noise texture ──
    // Tape dropouts run ALONG scan lines: the head loses the signal for a stretch of one row.
    // Each row is cut into hashed-length cells (with a per-row phase so cells never line up
    // into columns); a cell rolls bright (white streak), dark (lost carrier) or clean, and its
    // ends fade so the dash reads as a streak. Detune lengthens the dashes.
    let rowId = floor(uv.y * resolution.y);
    let dashLen = (18.0 + rand(vec2<f32>(rowId, 11.0)) * 30.0) * (1.0 + detuneLive * 2.0);
    let dashX = uv.x * resolution.x / dashLen + rand(vec2<f32>(rowId, 5.0)) * 4.0;
    let cellId = floor(dashX);
    let cellT = fract(dashX);
    let cellRoll = rand(vec2<f32>(cellId + rowId * 0.37, floor(time * 18.0)));
    let dashEnds = smoothstep(0.0, 0.12, cellT) * (1.0 - smoothstep(0.75, 1.0, cellT));
    let brightDash = step(0.80 - bar_intensity * 0.10, cellRoll);
    let darkDash = 1.0 - step(0.12 + bar_intensity * 0.04, cellRoll);
    let dashSignal = (brightDash - darkDash) * dashEnds;                      // -1 dark, +1 bright, 0 clean
    let dashGate = max(bandGate, clickDamage);
    // Dark dashes cut the picture to near-black (the old column dropouts, now row-shaped).
    color = mix(color, vec3<f32>(0.05), darkDash * dashEnds * dashGate);

    // Tape hiss / grain — dashes carry the band noise, fine grain fills between them
    let n = rand(uv + vec2<f32>(time, time));
    let ign = ign_noise(coords);
    let fineHiss = (n - 0.5) * 0.35;
    let noiseValue = (dashSignal * 0.5 + fineHiss) * noiseAmt * (bandGate + clickDamage) * (1.0 + treble * 0.35) + (ign - 0.5) * noiseAmt * 0.3;
    color = color + noiseValue;

    // ── IDEA 3: AGC lift in the band ──
    // Inside the damaged band the deck's automatic gain control chases the lost sync: blacks
    // lift toward grey and the colour-under carrier drains, so the band goes milky and flat.
    let agc = bar_intensity * (0.55 + detuneLive * 0.45) * (1.0 - lock * 0.7);
    let bandLuma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    color = mix(color, vec3<f32>(bandLuma), agc * 0.65);
    color = color * (1.0 - agc * 0.22) + vec3<f32>(agc * 0.16);

    // Tracking-loss flash on treble spikes
    let flash = step(0.75, treble) * bar_intensity * rand(vec2<f32>(time * 3.0, 0.0));
    color = mix(color, vec3<f32>(1.0), max(flash, clickDamage * (0.25 + treble * 0.25)));

    // Vignette darkening at edges
    let vig = 1.0 - dot(uv - 0.5, uv - 0.5) * 0.5;
    color = color * (0.7 + 0.3 * vig);

    // Semantic alpha: the tape carries the source's transparency.
    let alpha = clamp(srcAlpha, 0.0, 1.0);

    let finalRGBA = vec4<f32>(acesToneMap(max(color, vec3<f32>(0.0))), alpha);

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, global_id.xy, finalRGBA);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
