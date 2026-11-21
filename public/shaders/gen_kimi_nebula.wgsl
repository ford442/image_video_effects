// ═══════════════════════════════════════════════════════════════════
//  Kimi Nebula
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27, 2026-11-21
//  Ideas: Stromgren-sphere ionization stratification around the mouse O-star (R_s ~ (Q/n^2)^(1/3); [OIII] core, H-alpha shell, [SII] front, n^2 recombination glow); interstellar dust lanes with 1/lambda extinction that redden background stars plus photoevaporated bright rims on globule faces toward the star; PDR skin (UV/PAH layer just outside R_s); EGGs / cometary globules with tails pointing away from the star; blackbody star colour (§12.2F Rayleigh/blackbody) reddened by the same dust; Airy-disc star PSF with diffraction spikes on the brightest stars (§12.2F Airy disc)
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════
//
//  Slider contract (saved-preset safe — ids/defaults unchanged):
//    param1 Intensity -> gas density gain      (u.zoom_params.x)
//    param2 Speed     -> animation time scale  (u.zoom_params.y)
//    param3 Scale     -> noise spatial scale   (u.zoom_params.z)
//    param4 Detail    -> star density cutoff   (u.zoom_params.w)
//
//  Audio wiring (plasmaBuffer[0]):
//    bass   -> chromatic offset, gas breathing, ionizing photon rate Q
//    mids   -> drift speed of the mid-scale fbm density layer
//    treble -> drift speed of the fine-scale fbm density layer, star twinkle

#include "_prelude.wgsl"
// zoom_params: x=Intensity, y=Speed, z=Scale, w=Detail

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Kimi Nebula - Cosmic Cloud Swirls
// Ethereal gas clouds with twinkling stars and mouse-driven stellar winds

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    let n = i.x + i.y * 57.0 + i.z * 113.0;
    var res = mix(mix(mix(hash3(vec3<f32>(n)), hash3(vec3<f32>(n + 1.0)), f.x),
                      mix(hash3(vec3<f32>(n + 57.0)), hash3(vec3<f32>(n + 58.0)), f.x), f.y),
                 mix(mix(hash3(vec3<f32>(n + 113.0)), hash3(vec3<f32>(n + 114.0)), f.x),
                     mix(hash3(vec3<f32>(n + 170.0)), hash3(vec3<f32>(n + 171.0)), f.x), f.y), f.z);
    return res;
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        value += amplitude * noise3(p * freq);
        amplitude *= 0.5;
        freq *= 2.0;
    }
    return value;
}

// Real nebula control constants derived from the four slider params.
struct NebulaControls {
    gasGain: f32,        // param1 Intensity: multiplies raw gas density
    timeScale: f32,      // param2 Speed: multiplier on global animation time
    spatialScale: f32,   // param3 Scale: base frequency of the fbm field
    starCutoff: f32,     // param4 Detail: hash threshold for star spawning
};

fn nebulaControls() -> NebulaControls {
    var ctl: NebulaControls;
    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let speed = clamp(u.zoom_params.y, 0.0, 1.0);
    let scale = clamp(u.zoom_params.z, 0.0, 1.0);
    let detail = clamp(u.zoom_params.w, 0.0, 1.0);
    // Defaults (0.5) reproduce the legacy hard-coded constants.
    ctl.gasGain = mix(0.4, 2.0, intensity);
    ctl.timeScale = mix(0.0, 0.2, speed);
    ctl.spatialScale = mix(0.5, 2.5, scale);
    ctl.starCutoff = mix(0.99, 0.999, detail);
    return ctl;
}

// Dust column field: cold molecular lanes/globules, independent of the
// emitting gas so dark lanes can cross bright regions.
fn dustField(np: vec3<f32>, time: f32) -> f32 {
    return fbm3(np * 1.3 + vec3<f32>(-53.0, 21.0, time * 0.1), 4);
}

// ── _std copies (body-identical to public/shaders/_std/_std_color.wgsl) ──
fn srgbToLinear(c: vec3<f32>) -> vec3<f32> {
  let x = max(c, vec3<f32>(0.0));
  return select(pow((x + 0.055) / 1.055, vec3<f32>(2.4)), x / 12.92, x <= vec3<f32>(0.04045));
}

fn blackbody(kelvin: f32) -> vec3<f32> {
  let k = clamp(kelvin, 1000.0, 40000.0) / 100.0;
  let hi = max(k - 60.0, 1e-3);
  let r = select(1.29293618606 * pow(hi, -0.1332047592), 1.0, k <= 66.0);
  let g = select(1.12989086089 * pow(hi, -0.0755148492), 0.39008157876 * log(k) - 0.63184144378, k <= 66.0);
  let b = select(select(0.54320678911 * log(max(k - 10.0, 1e-3)) - 1.19625408914, 0.0, k <= 19.0), 1.0, k >= 66.0);
  return srgbToLinear(clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0)));
}

// Airy disc (2 J1(x)/x)^2, J1 as a 6-term Maclaurin series (good to x ~ 4.3; first dark
// ring at x = 3.8317). Past the first zero the first ring is < 1.5 %, so it is faded out.
fn airy(x: f32) -> f32 {
    let xs = max(abs(x), 1e-4);
    let x2 = xs * xs;
    let j1 = xs * (0.5 - x2 * (0.0625 - x2 * (0.0026041667 - x2 * (5.4253e-5 - x2 * (6.7817e-7 - x2 * 5.6513e-9)))));
    let v = 2.0 * j1 / xs;
    return v * v * (1.0 - smoothstep(3.7, 4.3, xs));
}

// Star field as a telescope image. Per pixel: ONE faint-star call (this pixel's own HEAD
// hash cell, same hash and Detail cutoff) + FIVE bright-star calls (own 8x8-cell tile and its
// four axis neighbours; arms lie along the axes so diagonals never matter). Both return
// vec2(light, light * temperatureRank); the caller turns the light-weighted mean rank into ONE
// blackbody() colour, so the Planck evaluation is paid once per pixel, not once per star.

// Faint field stars: round compact dot, jittered inside its cell (HEAD drew a flat square).
fn faintStar(pc: vec2<f32>, cell: vec2<f32>, time: f32, cutoff: f32, treble: f32) -> vec2<f32> {
    let h = hash3(vec3<f32>(cell, time * 0.01));
    let on = select(0.0, 1.0, h > cutoff);
    let mag = clamp((h - cutoff) / max(1.0 - cutoff, 1e-4), 0.0, 1.0);
    let d = pc - (cell + vec2<f32>(0.4 + 0.2 * fract(h * 7919.0), 0.4 + 0.2 * fract(h * 3571.0)));
    let twinkle = 0.5 + 0.5 * (sin(time * 5.0 + h * 10.0 + treble * 3.0) * 0.5 + 0.5);
    // compact kernel: reaches exactly 0 at radius 0.4 cell, so the dot never clips at the cell edge
    let q = clamp(1.0 - dot(d, d) / 0.16, 0.0, 1.0);
    let light = on * (2.2 + 1.2 * mag) * twinkle * q * q;
    return vec2<f32>(light, light * fract(h * 1013.0));
}

// Bright stars: Airy core + glare wing + thin 4-point diffraction cross (spider vanes).
// `cc` is an 8x8-cell tile; density = ~20 % of HEAD's star density (pB tracks the Detail cutoff,
// so higher Detail still means fewer, crisper stars). role = (core+wing, horizontal arm, vertical arm).
fn brightStar(pc: vec2<f32>, cc: vec2<f32>, pB: f32, cellPx: f32, time: f32, treble: f32,
              role: vec3<f32>) -> vec2<f32> {
    let hb = hash3(vec3<f32>(cc + vec2<f32>(11.3, 4.7), 6.1));
    let on = select(0.0, 1.0, hb > 1.0 - pB);
    let mag = clamp((hb - (1.0 - pB)) / max(pB, 1e-4), 0.0, 1.0);
    let bright = 1.3 + 1.1 * mag * mag;
    let centre = (cc + vec2<f32>(0.15 + 0.7 * fract(hb * 7919.0), 0.15 + 0.7 * fract(hb * 3571.0))) * 8.0;
    let d = pc - centre;
    let adx = abs(d.x);
    let ady = abs(d.y);
    let twinkle = 0.6 + 0.4 * (sin(time * 5.0 + hb * 40.0 + treble * 3.0) * 0.5 + 0.5);
    // ── Idea 4: Airy-disc PSF + diffraction spikes (§12.2F Airy disc) ─
    // Core: first dark ring at 0.9 cell. Wing: soft glare. Spikes: thin cross, >= 0.8 px wide.
    let r = length(d);
    let core = airy(r * 4.26) + 0.12 * exp(-r * r / 1.28);
    let sw = max(0.12, 0.8 / max(cellPx, 0.5));
    let armH = exp(-ady * ady / (2.0 * sw * sw)) * (1.0 - smoothstep(2.5, 5.5, adx)) / (1.0 + 1.5 * adx);
    let armV = exp(-adx * adx / (2.0 * sw * sw)) * (1.0 - smoothstep(2.5, 5.5, ady)) / (1.0 + 1.5 * ady);
    let light = on * bright * twinkle * (role.x * core + 0.55 * (role.y * armH + role.z * armV));
    return vec2<f32>(light, light * fract(hb * 1013.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let px = vec2<i32>(global_id.xy);

    // Slider-derived nebula constants (see NebulaControls above)
    let ctl = nebulaControls();
    let time = u.config.x * ctl.timeScale;

    // Audio bands (plasmaBuffer[0])
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    // Mouse interaction
    var mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspect = resolution.x / resolution.y;

    // Create swirling nebula effect
    var p = uv * 2.0 - 1.0;
    p.x *= aspect;

    // Mouse creates stellar wind
    var mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= aspect;
    let dist = length(p - mousePos);
    let windStrength = smoothstep(0.8, 0.0, dist) * (0.5 + mouseDown * 0.5);

    // Click ripples: supernova-remnant shells sweeping outward. The shock
    // compresses the gas it passes, and the shell glows in filaments.
    var shellGlow = 0.0;
    var shellCompress = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = u.config.x - rp.z;
        if (age >= 0.0 && age < 5.0) {
            var rpos = rp.xy * 2.0 - 1.0;
            rpos.x *= aspect;
            // Sedov-Taylor-like deceleration: R ~ t^(2/5)
            let shellR = 0.55 * pow(max(age, 1e-3), 0.4);
            let sd = length(p - rpos) - shellR;
            let fade = exp(-age * 0.6);
            let fil = 0.55 + 0.45 * noise3(vec3<f32>((p - rpos) * 14.0, age * 0.7 + f32(i)));
            shellGlow += exp(-sd * sd * 260.0) * fil * fade;
            shellCompress += exp(-sd * sd * 60.0) * fade;
        }
    }

    // Animated 3D noise for gas clouds (spatial scale is slider-driven)
    var noisePos = vec3<f32>(p * ctl.spatialScale, time * 0.2);

    // Add swirling motion from mouse
    let angle = windStrength * 2.0;
    let rot = vec2<f32>(
        noisePos.x * cos(angle) - noisePos.y * sin(angle),
        noisePos.x * sin(angle) + noisePos.y * cos(angle)
    );
    noisePos.x = mix(noisePos.x, rot.x, windStrength);
    noisePos.y = mix(noisePos.y, rot.y, windStrength);

    // Extra domain warp for more turbulent, billowing gas structures.
    let warp = fbm3(noisePos * 0.8 + vec3<f32>(31.4, -17.2, time * 0.15), 3);
    let warpVec = vec3<f32>(warp - 0.5, 0.5 - warp, (warp - 0.5) * 0.5);
    noisePos = noisePos + warpVec * 0.7;

    // Multi-octave nebula density. mids push the mid-scale layer, treble
    // pushes the fine layer, so the strata disaggregate with the music.
    let midsDrift = vec3<f32>(0.0, time * mids * 0.6, time * mids * 0.3);
    let trebleDrift = vec3<f32>(time * treble * 0.9, 0.0, time * treble * 0.5);

    let density1 = fbm3(noisePos, 4);
    let density2 = fbm3(noisePos * 2.0 + vec3<f32>(100.0) + midsDrift, 3);
    let density3 = fbm3(noisePos * 4.0 + vec3<f32>(200.0) + trebleDrift, 2);

    // Intensity slider = gas density gain, applied before palette mapping
    let nebulaDensity = (density1 * 0.5 + density2 * 0.3 + density3 * 0.2) * ctl.gasGain
                      * (1.0 + shellCompress * 0.5);

    // Color palette - deep purples, blues, and pink accents
    let color1 = vec3<f32>(0.1, 0.05, 0.2);  // Deep purple
    let color2 = vec3<f32>(0.2, 0.1, 0.4);   // Purple
    let color3 = vec3<f32>(0.4, 0.2, 0.6);   // Magenta
    let color4 = vec3<f32>(0.8, 0.6, 0.9);   // Pink highlight
    let color5 = vec3<f32>(0.1, 0.3, 0.5);   // Blue

    var color = color1;
    color = mix(color, color2, smoothstep(0.2, 0.4, nebulaDensity));
    color = mix(color, color3, smoothstep(0.4, 0.6, nebulaDensity));
    color = mix(color, color4, smoothstep(0.7, 0.9, nebulaDensity + windStrength * 0.3));
    color = mix(color, color5, smoothstep(0.5, 0.8, density3 * ctl.gasGain));

    // ── Idea 1: Stromgren-sphere ionization stratification ──────────
    // The star at the mouse emits Q ionizing photons/s. Balance against
    // recombination (alpha_B n^2) gives R_s = (3Q / 4 pi alpha_B n^2)^(1/3):
    // denser gas holds a smaller ionized bubble. Inside, emission scales
    // with n^2. High-ionization [OIII] 501nm (35 eV) lives in the inner core,
    // H-alpha 656nm fills the sphere and [SII] 672nm hugs the front.
    let Q = (0.55 + mouseDown * 0.9) * (1.0 + bass * 0.45);
    let nLocal = max(nebulaDensity, 0.08);
    let Rs = clamp(0.5 * pow(Q, 1.0 / 3.0) * pow(nLocal / 0.5, -2.0 / 3.0), 0.05, 1.6);
    let ionized = smoothstep(Rs, Rs * 0.82, dist);
    let oiiiZone = smoothstep(Rs * 0.5, Rs * 0.25, dist);
    let frontX = (dist - Rs * 0.95) / (Rs * 0.08);
    let front = exp(-frontX * frontX);
    let recomb = nLocal * nLocal;
    let hAlpha = vec3<f32>(0.95, 0.12, 0.22);
    let oiii = vec3<f32>(0.1, 0.85, 0.72);
    let sii = vec3<f32>(0.6, 0.03, 0.08);
    var emission = hAlpha * recomb * ionized * 1.4
                 + oiii * recomb * oiiiZone * 1.1
                 + sii * nLocal * front * 0.9;

    // ── Idea 2: dust extinction, reddening and bright rims ──────────
    // Dust optical depth follows A_lambda ~ 1/lambda: blue is absorbed most,
    // so light passing through lanes is dimmed and reddened. Globule faces
    // toward the star are photoevaporated and glow as bright rims.
    let dustRaw = dustField(noisePos, time);
    let tau = smoothstep(0.52, 0.75, dustRaw) * 2.2 * mix(0.6, 1.4, clamp(u.zoom_params.x, 0.0, 1.0));
    let extinction = exp(-tau * vec3<f32>(0.55, 0.8, 1.25));
    let toStar = (mousePos - p) / max(dist, 1e-3);
    let dustTowardStar = dustField(noisePos + vec3<f32>(toStar * 0.06 * ctl.spatialScale, 0.0), time);
    let rimFace = clamp((dustRaw - dustTowardStar) * 14.0, 0.0, 1.0)
                * smoothstep(0.48, 0.62, dustRaw) * smoothstep(Rs * 1.3, Rs * 0.6, dist);
    emission += vec3<f32>(1.0, 0.55, 0.45) * rimFace * 0.8 * (1.0 + bass * 0.3);
    emission += (oiii * 0.6 + hAlpha * 0.4) * shellGlow * 0.9;

    // Idea 1 — PDR skin: thin UV/PAH layer just outside the Stromgren radius.
    let pdrX = (dist - Rs) / max(Rs * 0.055, 0.001);
    let pdr = exp(-pdrX * pdrX) * (1.0 - ionized);
    let pah = vec3<f32>(0.55, 0.22, 0.95);
    emission += pah * pdr * nLocal * 0.75 * (0.7 + treble * 0.4);

    // Idea 2 — EGGs / cometary globules: dense knots with tails AWAY from the star.
    let away = (p - mousePos) / max(dist, 1e-3);
    let knot = smoothstep(0.68, 0.90, dustRaw);
    let tailDust = dustField(noisePos - vec3<f32>(away * 0.09 * ctl.spatialScale, 0.0), time);
    let eggTail = knot * smoothstep(0.52, 0.78, tailDust) * (1.0 - ionized);

    // Gas and emission behind the lane are extinguished (partially: lanes
    // are mixed in depth with the gas).
    color = color * mix(vec3<f32>(1.0), extinction, 0.7) + emission * mix(vec3<f32>(1.0), extinction, 0.5);
    color = color * (1.0 - eggTail * 0.28) + vec3<f32>(0.32, 0.16, 0.10) * eggTail * 0.4;

    // Add stars — Detail slider sets the hash cutoff: higher Detail means
    // a higher threshold, i.e. fewer but crisper star points. Faint stars keep HEAD's hash
    // cell, now round and jittered; the brightest ~20 % are drawn as Airy discs with
    // diffraction spikes (Ideas 3-4).
    let pc = p * 100.0;
    let cellPx = resolution.y / 200.0;
    let pB = 12.8 * (1.0 - ctl.starCutoff);                      // 64 cells/tile * 20 % of HEAD density
    let tile = floor(pc / 8.0);
    var st = faintStar(pc, floor(pc), time, ctl.starCutoff, treble);
    st += brightStar(pc, tile, pB, cellPx, time, treble, vec3<f32>(1.0, 1.0, 1.0));
    st += brightStar(pc, tile + vec2<f32>(1.0, 0.0), pB, cellPx, time, treble, vec3<f32>(0.0, 1.0, 0.0));
    st += brightStar(pc, tile - vec2<f32>(1.0, 0.0), pB, cellPx, time, treble, vec3<f32>(0.0, 1.0, 0.0));
    st += brightStar(pc, tile + vec2<f32>(0.0, 1.0), pB, cellPx, time, treble, vec3<f32>(0.0, 0.0, 1.0));
    st += brightStar(pc, tile - vec2<f32>(0.0, 1.0), pB, cellPx, time, treble, vec3<f32>(0.0, 0.0, 1.0));
    // ── Idea 3: blackbody star colour (§12.2F Rayleigh/blackbody) ────
    // Temperature rank is skewed (many cool K/M dwarfs, few hot blue-white B stars); the colour
    // is the Planck colour of the light-weighted mean rank. The caller then multiplies by the
    // dust `extinction`, reddening it further behind lanes.
    let tRank = clamp(st.y / max(st.x, 1e-4), 0.0, 1.0);
    let tint = mix(vec3<f32>(1.0), blackbody(2800.0 + 9500.0 * pow(tRank, 1.8)), 0.9);
    // Stars hide behind dense gas (HEAD: hard cut at density 0.6; now a short fade so the
    // spikes do not clip at a hard edge). Background stars are reddened by dust.
    let gasClear = 1.0 - smoothstep(0.55, 0.65, nebulaDensity);
    let starLight = st.x * gasClear;
    color += tint * starLight * extinction * (1.0 + windStrength);
    let starCov = clamp(starLight, 0.0, 1.0);

    // Bright core near mouse (the ionizing star itself)
    color += vec3<f32>(0.6, 0.8, 1.0) * windStrength * 0.5;

    // Gentle bass-reactive shimmer: low-end pulses make the gas breathe.
    color *= 1.0 + bass * 0.12 * smoothstep(0.3, 0.8, nebulaDensity);

    // Gamma correction and intensity
    color = pow(max(color, vec3<f32>(0.0)), vec3<f32>(0.8)) * 1.2;

    // ═══ SAMPLE INPUT FROM PREVIOUS LAYER ═══
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Opacity control: the previous layer sits behind the dust too.
    let opacity = 0.85;
    let finalColor = mix(inputColor.rgb * extinction, color, opacity);

    // Bass drives the chromatic offset
    let caStr = 0.003 * (1.0 + bass) + inputDepth * 0.001;
    let chromaticColor = vec3<f32>(finalColor.r + caStr, finalColor.g, finalColor.b - caStr * 0.5);
    let display = acesToneMap(max(chromaticColor, vec3<f32>(0.0)) * 1.1);

    // Alpha: emission measure + gas column + dust column + star coverage.
    let emissionLum = dot(emission, vec3<f32>(0.333));
    let dustOpacity = 1.0 - dot(extinction, vec3<f32>(0.333));
    let alpha = clamp(nebulaDensity * 0.6 + emissionLum * 0.5 + dustOpacity * 0.35
                      + starCov * 0.6 + shellGlow * 0.3 + pdr * 0.2 + eggTail * 0.25, 0.02, 1.0);

    let outRGBA = vec4<f32>(display, alpha);
    textureStore(writeTexture, px, outRGBA);
    textureStore(dataTextureA, px, outRGBA);

    // Depth: dense gas and dust lanes sit nearer than the thin background.
    let gasDepth = clamp(0.3 + nebulaDensity * 0.3 + dustOpacity * 0.3, 0.0, 1.0);
    textureStore(writeDepthTexture, px, vec4<f32>(mix(inputDepth, gasDepth, opacity), 0.0, 0.0, 0.0));
}
