// ═══════════════════════════════════════════════════════════════════
//  Phosphor Decay
//  Category: retro-glitch
//  Features: audio-reactive, upgraded-rgba, mouse-driven, click-reactive, held-drag
//  Complexity: Medium
//  Upgraded: 2026-09-28
//  Ideas: burn-in (slow luma EMA in A.a lowers phosphor efficiency, leaving a dim negative ghost of static content); held static charge (electrostatic crackle sparks at the cursor + dust specks that cling to the glass and fade after release); blanking-interval flicker (Scan Blanking drives a per-frame vertical-blank dip on the bottom rows)
//  A packing: linear HDR phosphor RGB (post-blackbody, pre-vignette, pre-ACES) in .rgb + burn-in luma accumulator in .a; C read back as that HDR RGB and the accumulator
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Decay Rate, y=Bloom Spread, z=Shadow Mask, w=Scan Blanking

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn to_linear(c: vec3<f32>) -> vec3<f32> { return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2)); }
fn to_srgb(c: vec3<f32>) -> vec3<f32> { return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2)); }

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, max_lum / max(l, 1e-4));
}

// Cube roots are guarded with max(0): a negative LMS value would make pow() NaN, and a NaN
// written to A persists forever through C.
fn linear_srgb_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let l = max(0.4122214708*c.r + 0.5363325363*c.g + 0.0514459929*c.b, 0.0);
    let m = max(0.2119034982*c.r + 0.6806995451*c.g + 0.1073969566*c.b, 0.0);
    let s = max(0.0883024619*c.r + 0.2817188376*c.g + 0.6299787005*c.b, 0.0);
    let l_ = pow(l, 1.0/3.0); let m_ = pow(m, 1.0/3.0); let s_ = pow(s, 1.0/3.0);
    return vec3<f32>(
        0.2104542553*l_+0.7936177850*m_-0.0040720468*s_,
        1.9779984951*l_-2.4285922050*m_+0.4505937099*s_,
        0.0259040371*l_+0.7827717662*m_-0.8086757660*s_);
}

fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let l_ = c.x+0.3963377774*c.y+0.2158037573*c.z;
    let m_ = c.x-0.1055613458*c.y-0.0638541728*c.z;
    let s_ = c.x-0.0894841775*c.y-1.2914855480*c.z;
    let l = l_*l_*l_; let m = m_*m_*m_; let s = s_*s_*s_;
    return vec3<f32>(
        4.0767416621*l-3.3077115913*m+0.2309699292*s,
       -1.2684380046*l+2.6097574011*m-0.3413193965*s,
       -0.0041960863*l-0.7034186147*m+1.7076147010*s);
}

fn mixOkLab(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear_srgb(mix(linear_srgb_to_oklab(a), linear_srgb_to_oklab(b), t));
}

fn blackbodyRGB(T: f32) -> vec3<f32> {
    let t = clamp(T, 1000.0, 40000.0) / 100.0;
    var r = 0.0; var g = 0.0; var b = 0.0;
    if (t <= 66.0) { r = 1.0; }
    else { r = clamp(329.698727446 * pow(max(t - 60.0, 1e-3), -0.1332047592) / 255.0, 0.0, 1.0); }
    if (t <= 66.0) { g = clamp((99.4708025861 * log(t) - 161.1195681661) / 255.0, 0.0, 1.0); }
    else { g = clamp(288.1221695283 * pow(max(t - 60.0, 1e-3), -0.0755148492) / 255.0, 0.0, 1.0); }
    if (t >= 66.0) { b = 1.0; }
    else if (t <= 19.0) { b = 0.0; }
    else { b = clamp((138.5177312231 * log(max(t - 10.0, 1e-3)) - 305.0447927307) / 255.0, 0.0, 1.0); }
    return vec3<f32>(r, g, b);
}

fn vignette(uv: vec2<f32>, strength: f32) -> f32 {
    let d = length(uv - vec2<f32>(0.5));
    return pow(max(0.0, 1.0 - d * 2.0), strength);
}

fn chromatic_aberration(uv: vec2<f32>, amount: f32) -> vec3<f32> {
    let offset = (uv - vec2<f32>(0.5)) * amount;
    let r = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - offset, 0.0).b;
    return vec3<f32>(r, g, b);
}

fn box_bloom(uv: vec2<f32>, spread: f32) -> vec3<f32> {
    let off = vec2<f32>(spread, 0.0);
    var b = vec3<f32>(0.0);
    b += to_linear(textureSampleLevel(readTexture, u_sampler, uv + off, 0.0).rgb);
    b += to_linear(textureSampleLevel(readTexture, u_sampler, uv - off, 0.0).rgb);
    b += to_linear(textureSampleLevel(readTexture, u_sampler, uv + off.yx, 0.0).rgb);
    b += to_linear(textureSampleLevel(readTexture, u_sampler, uv - off.yx, 0.0).rgb);
    return b * 0.25;
}

fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Branchless RGB shadow mask: red column, green column, otherwise blue-ish.
fn shadow_mask(pixel_x: i32) -> vec3<f32> {
    let mx = pixel_x % 3;
    let red  = vec3<f32>(1.0, 0.6, 0.6);
    let green = vec3<f32>(0.6, 1.0, 0.6);
    let blue  = vec3<f32>(0.6, 0.6, 1.0);
    var mask = mix(blue, red, f32(mx == 0));
    mask = mix(mask, green, f32(mx == 1));
    return mask;
}

// Finite guard for values read back from C: NaN/Inf compare false, so they collapse to `fallback`.
fn finiteOr(x: f32, fallback: f32, lo: f32, hi: f32) -> f32 {
    return select(fallback, clamp(x, lo, hi), x >= lo && x <= hi);
}

// IDEA 2a — electrostatic crackle: radial spark filaments hashed per frame around the cursor.
// Returns spark intensity in [0,1] for the pixel at aspect-corrected offset `d` from the cursor.
fn staticCrackle(d: vec2<f32>, radius: f32, time: f32, treble: f32) -> f32 {
    let r = length(d);
    if (r > radius) { return 0.0; }
    let frame = floor(time * 30.0);
    let ang = atan2(d.y, d.x) / TAU + 0.5;
    let sectors = 28.0;
    let sector = floor(ang * sectors);
    let sh = hash12(vec2<f32>(sector, frame));
    // Only some sectors carry a filament this frame; treble strikes more of them.
    let live = step(0.82 - treble * 0.12, sh);
    let reach = radius * (0.35 + 0.65 * hash12(vec2<f32>(frame, sector + 7.0)));
    // Filament: thin around the sector centre, wiggling along its length.
    let wiggle = sin(r * 90.0 + sh * 40.0 + time * 60.0) * 0.12;
    let angDist = abs(fract(ang * sectors) - 0.5 + wiggle);
    let thin = 1.0 - smoothstep(0.02, 0.09, angDist);
    let along = smoothstep(reach, reach * 0.4, r) * smoothstep(0.0, radius * 0.08, r);
    return live * thin * along;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res   = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv   = (vec2<f32>(pixel) + 0.5) / res;
    let time = u.config.x;
    let aspect = res.x / max(res.y, 1.0);
    let held = u.zoom_config.w > 0.5;
    let mouse = u.zoom_config.yz;   // direct pointer (the old extraBuffer spring read zeroed state)

    let decayRateParam     = u.zoom_params.x;
    let bloomSpread        = u.zoom_params.y;
    let shadowMaskStrength = u.zoom_params.z;
    let scanBlanking       = u.zoom_params.w;

    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    // HEAD read plasmaBuffer[y%8+1] per row (never written -> always 0). Mids now drives the
    // scan-frequency wobble and click-bloom warmth that "row voice" was meant to.
    let rowVoice = mids;

    // ---- PASS 1: temporal accumulation (cached as linear radiance) ----
    // dataTextureC is the previous frame's copy of dataTextureA: HDR phosphor RGB + burn-in in .a.
    let prevRaw = textureLoad(dataTextureC, pixel, 0);
    let prevRGB = vec3<f32>(finiteOr(prevRaw.r, 0.0, 0.0, 16.0),
                            finiteOr(prevRaw.g, 0.0, 0.0, 16.0),
                            finiteOr(prevRaw.b, 0.0, 0.0, 16.0));
    let prevBurn = finiteOr(prevRaw.a, 0.0, 0.0, 1.0);

    // Per-channel phosphor decay on linear feedback state.
    let decay = vec3<f32>(
        0.95 - decayRateParam * 0.1,
        0.96 - decayRateParam * 0.1,
        0.98 - decayRateParam * 0.05
    );
    var history = prevRGB * decay;

    // Current input with audio-reactive chromatic aberration.
    let inputRGB  = chromatic_aberration(uv, 0.003 + treble * 0.001);
    var inputColor = to_linear(inputRGB);

    // Audio-reactive 4-tap box bloom, gated by input luma.
    let spread = bloomSpread * 0.02 * (1.0 + bass * 2.0);
    let bloom  = box_bloom(uv, spread);
    let inputLuma = dot(inputColor, vec3<f32>(0.299, 0.587, 0.114));
    let bloomAdd  = bloom * smoothstep(0.5, 1.0, inputLuma) * bloomSpread * (1.0 + bass * 2.0);
    inputColor += bloomAdd;

    // IDEA 1 — burn-in. A.a is a slow EMA of the phosphor luma (~200-frame memory). Where the
    // accumulator sits well above what the beam is drawing now, the phosphor has lost efficiency:
    // the excitation is attenuated, so content that sat still for a while lingers as a dim
    // negative once the picture moves on. Static bright areas only dim a little while they stay.
    let burn = clamp(prevBurn * 0.995 + clamp(inputLuma, 0.0, 1.0) * 0.005, 0.0, 1.0);
    let burnExcess = max(burn - inputLuma * 0.6, 0.0);
    let efficiency = 1.0 - smoothstep(0.02, 0.7, burnExcess) * 0.55;
    inputColor *= efficiency;

    // Merge through OkLab for smooth, hue-preserved phosphor trails.
    var state = mixOkLab(history, inputColor, 0.35 + bass * 0.15);
    state = max(state, history * 0.85);

    // Branchless CRT shadow mask and scan-line blanking.
    let mask = shadow_mask(pixel.x);
    state = mix(state, state * mask, shadowMaskStrength * (1.0 + mids * 0.6) * 0.5);

    // Integer-row scanline (HEAD's uv.y*res.y*0.5 == pixel.y*0.5), never a texel-centre constant.
    let scanLine = sin(f32(pixel.y) * 0.5 * (1.0 + rowVoice * 0.04)) * 0.5 + 0.5;
    state *= mix(1.0, scanLine, scanBlanking * (1.0 + treble * 0.4) * 0.4);

    // IDEA 3 — blanking-interval flicker. The vertical-blank dip rides the Scan Blanking slider:
    // the bottom rows dim by a per-frame hashed amount (the retrace catching the beam late), with
    // a faint retrace-timing shimmer on the last few lines.
    let frameHash = hash12(vec2<f32>(floor(time * 60.0), 3.7));
    let vblZone = smoothstep(0.86, 1.0, uv.y);
    let vblDip = vblZone * (0.35 + 0.65 * frameHash) * scanBlanking * 0.6;
    let retraceShimmer = smoothstep(0.96, 1.0, uv.y) * sin(f32(pixel.y) * 2.1 + time * 90.0) * 0.08 * scanBlanking;
    state *= clamp(1.0 - vblDip + retraceShimmer, 0.0, 1.0);

    let toMouse = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let mDist = length(toMouse);
    let mouseFalloff = 1.0 - smoothstep(0.0, 0.14, mDist);
    state += vec3<f32>(0.15, 0.35, 0.55) * mouseFalloff * (0.2 + treble * 0.3) * select(0.4, 1.0, held);

    // IDEA 2 — held static charge. While the pointer is held the glass charges: crackle sparks
    // (2a) fire around the cursor every frame, and dust specks (2b) are drawn onto the glass as
    // pale grey motes. Both are added to the phosphor state, so once the button is released
    // nothing new is drawn and the per-channel decay lets the specks fade over ~1 s.
    var crackle = 0.0;
    var dust = 0.0;
    if (held) {
        crackle = staticCrackle(toMouse, 0.22, time, treble);
        let dustCell = floor(vec2<f32>(pixel) / 2.0);
        let dh = hash12(dustCell + vec2<f32>(11.3, 5.1));
        let dustZone = 1.0 - smoothstep(0.08, 0.30, mDist);
        dust = step(0.986, dh) * dustZone * (0.5 + 0.5 * hash12(dustCell * 0.37));
    }
    state += vec3<f32>(0.75, 0.9, 1.0) * crackle * (0.9 + treble * 0.6);
    state += vec3<f32>(0.55, 0.52, 0.48) * dust * 0.6;

    var clickBloom = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.0) {
            let radius = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
            clickBloom = max(clickBloom, exp(-age * 2.5) * (1.0 - smoothstep(0.0, 0.12, radius)) + exp(-abs(radius - age * 0.1) * 60.0) * exp(-age * 1.1) * 0.6);
        }
    }
    state += vec3<f32>(1.0, 0.5 + rowVoice * 0.3, 0.25) * clickBloom * 0.5;

    // Depth haze + blackbody temperature grading.
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let hazeColor = vec3<f32>(0.08, 0.06, 0.04) * 1.5;
    state = mixOkLab(state, hazeColor, depth * 0.25);

    let temp = 3200.0 + mids * 3000.0 + depth * 1500.0;
    state *= blackbodyRGB(temp);

    // Feedback write: HDR phosphor RGB (clamped so nothing non-finite can enter C) + burn-in.
    state = clamp(state, vec3<f32>(0.0), vec3<f32>(16.0));
    textureStore(dataTextureA, pixel, vec4<f32>(state, burn));

    // ---- PASS 2: display output (vignette, tone-map, dither) ----
    let energy = clamp(max(state.r, max(state.g, state.b)), 0.0, 1.0);
    state *= vignette(uv, 1.2);

    state = hue_preserve_clamp(state, 2.0);
    var finalRGB = aces_tone_map(state);
    finalRGB = to_srgb(finalRGB);

    // Semantic alpha = phosphor emission coverage (dark glass is translucent, lit phosphor is
    // opaque). RGB is written straight, not premultiplied — HEAD's finalRGB*alpha with alpha≈0
    // below luma 0.55 rendered the effect near-black.
    let alpha = clamp(0.15 + smoothstep(0.0, 0.6, energy) * 0.85 + clickBloom * 0.2 + mouseFalloff * 0.1 + crackle * 0.3, 0.0, 1.0);
    let dither = (ign(vec2<f32>(pixel)) - 0.5) / 255.0;
    finalRGB = clamp(finalRGB + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, pixel, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
