// ═══════════════════════════════════════════════════════════════════
//  Kimi Nebula
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: Stromgren-sphere ionization stratification around the mouse O-star (R_s ~ (Q/n^2)^(1/3); [OIII] core, H-alpha shell, [SII] front, n^2 recombination glow); interstellar dust lanes with 1/lambda extinction that redden background stars plus photoevaporated bright rims on globule faces toward the star
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
  config: vec4<f32>,       // x=time, y=rippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=Detail
  ripples: array<vec4<f32>, 50>,
};

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

    // Gas and emission behind the lane are extinguished (partially: lanes
    // are mixed in depth with the gas).
    color = color * mix(vec3<f32>(1.0), extinction, 0.7) + emission * mix(vec3<f32>(1.0), extinction, 0.5);

    // Add stars — Detail slider sets the hash cutoff: higher Detail means
    // a higher threshold, i.e. fewer but crisper star points.
    let starNoise = hash3(vec3<f32>(floor(p * 100.0), time * 0.01));
    let star = select(0.0, 1.0, starNoise > ctl.starCutoff && nebulaDensity < 0.6);

    // Twinkling stars near mouse; background stars are reddened by dust.
    let starTwinkle = sin(time * 5.0 + starNoise * 10.0 + treble * 3.0) * 0.5 + 0.5;
    color += vec3<f32>(star) * extinction * (0.5 + starTwinkle * 0.5) * (1.0 + windStrength);

    // Soft halo around each star, tinted by the local gas color.
    let haloNoise = hash3(vec3<f32>(floor(p * 100.0) + vec2<f32>(1.0, 0.0), time * 0.01));
    let halo = select(0.0, 1.0, haloNoise > ctl.starCutoff) * 0.15;
    color += color4 * extinction * halo * (0.5 + starTwinkle * 0.5);

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
                      + star * 0.6 + shellGlow * 0.3, 0.02, 1.0);

    let outRGBA = vec4<f32>(display, alpha);
    textureStore(writeTexture, px, outRGBA);
    textureStore(dataTextureA, px, outRGBA);

    // Depth: dense gas and dust lanes sit nearer than the thin background.
    let gasDepth = clamp(0.3 + nebulaDensity * 0.3 + dustOpacity * 0.3, 0.0, 1.0);
    textureStore(writeDepthTexture, px, vec4<f32>(mix(inputDepth, gasDepth, opacity), 0.0, 0.0, 0.0));
}
