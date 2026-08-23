// ═══════════════════════════════════════════════════════════════════
//  Digital Haze — Batch 59
//  Beer-Lambert haze, sprung clear window [133..137], capped ripples,
//  held widens clear radius, FFT cell bins, ACES + semantic alpha.
// ═══════════════════════════════════════════════════════════════════
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples:     array<vec4<f32>, 50>,
};

// Digital haze extinction coefficients
const SIGMA_T_HAZE: f32 = 1.2;          // Haze extinction (thick)
const SIGMA_T_CLEAR: f32 = 0.05;        // Clear area extinction (minimal)
const STEP_SIZE: f32 = 0.03;            // Ray step

// Sprung clear-window state lives in extraBuffer[133..137]
// ([0..4] reserved, [5..132] engine FFT bins — do not touch).
const SPRING_POS_X: u32 = 133u;
const SPRING_POS_Y: u32 = 134u;
const SPRING_VEL_X: u32 = 135u;
const SPRING_VEL_Y: u32 = 136u;
const SPRING_INITIALIZED: u32 = 137u;

// Critically-damped spring tuning: the clearing drags behind the
// cursor like a hand wiping fogged glass.
const SPRING_K: f32 = 40.0;             // stiffness
const SPRING_DT: f32 = 1.0 / 60.0;      // fixed integration step

// Click clear-pulse shape: ~0.2 aspect-corrected radius, ~1.5s life.
const PULSE_RADIUS: f32 = 0.2;
const PULSE_DECAY: f32 = 2.0;
const PULSE_LIFE: f32 = 1.5;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let aspect = dims.x / dims.y;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let held = u.zoom_config.w > 0.5;

    // ═══════════════════════════════════════════════════════════════
    //  Sprung Clear Window
    //  The raw mouse is the spring TARGET; the clear window follows a
    //  critically-damped spring so the wipe lags the cursor. Every
    //  thread integrates one deterministic step from the stored state;
    //  thread (0,0) persists the new state for the next frame.
    // ═══════════════════════════════════════════════════════════════
    let rawMouse = u.zoom_config.yz;
    var springPos = vec2<f32>(extraBuffer[SPRING_POS_X], extraBuffer[SPRING_POS_Y]);
    var springVel = vec2<f32>(extraBuffer[SPRING_VEL_X], extraBuffer[SPRING_VEL_Y]);
    let springInitialized = extraBuffer[SPRING_INITIALIZED] > 0.5;
    if (!springInitialized) {
        springPos = rawMouse;
        springVel = vec2<f32>(0.0);
    }
    let springC = 2.0 * sqrt(SPRING_K);   // critical damping coefficient
    let springAccel = (rawMouse - springPos) * SPRING_K - springVel * springC;
    springVel += springAccel * SPRING_DT;
    springPos += springVel * SPRING_DT;
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[SPRING_POS_X] = springPos.x;
        extraBuffer[SPRING_POS_Y] = springPos.y;
        extraBuffer[SPRING_VEL_X] = springVel.x;
        extraBuffer[SPRING_VEL_Y] = springVel.y;
        extraBuffer[SPRING_INITIALIZED] = 1.0;
    }
    let mouse = springPos;

    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);

    // Params; bass pulses the haze density, mids vary the noise texture
    let pixelStrength = u.zoom_params.x * 100.0 + 10.0;
    let clearRadius = (u.zoom_params.y * 0.4 + 0.05) * select(1.0, 1.3, held);
    let noiseAmt = u.zoom_params.z * (1.0 + mids * 0.4);

    var mask = smoothstep(clearRadius, clearRadius + 0.2, dist);

    let prevHaze = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0).r;
    mask = mix(mask, min(mask, prevHaze), 0.08);

    // ── Click clear pulses ──────────────────────────────────────────
    // Each live ripple punches a temporary clear hole at its click
    // point: the mask is reduced by exp(-age * 2.0) inside an
    // aspect-corrected ~0.2 radius for ~1.5s, so clicks wipe the fog.
    var clearPulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age > 0.0 && age < PULSE_LIFE) {
            let rDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            let hole = smoothstep(PULSE_RADIUS, 0.0, rDist) * exp(-age * PULSE_DECAY);
            clearPulse = max(clearPulse, hole);
        }
    }
    mask = mask * (1.0 - clearPulse);

    // Dynamic Pixelation
    let gridSize = vec2<f32>(pixelStrength * aspect, pixelStrength);
    let quantizedUV = floor(uv * gridSize) / gridSize;

    // Add digital noise to the quantized UV
    let seed = quantizedUV + vec2<f32>(time * 0.1, time * 0.05);
    var noiseVal = (hash(seed) - 0.5) * noiseAmt * 0.05;

    // ── Per-cell FFT static ─────────────────────────────────────────
    // Each pixel-cell's noise is modulated by its own spectrum bin so
    // the digital static flickers across the audio spectrum.
    let cellHash = hash(floor(uv * gridSize));
    let cellBin = plasmaBuffer[(u32(cellHash * 8.0) % 8u) + 1u].x;
    noiseVal = noiseVal * (1.0 + cellBin * 0.3);

    let hazeUV = clamp(quantizedUV + noiseVal, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample colors
    let colClear = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let colHaze = textureSampleLevel(readTexture, u_sampler, hazeUV, 0.0).rgb;

    // Apply a "digital" tint to the haze
    let greenTint = vec3<f32>(0.0, 0.1, 0.0) * noiseAmt;
    let finalHaze = colHaze + greenTint;

    // ═══════════════════════════════════════════════════════════════
    //  Volumetric Fog Calculation
    // ═══════════════════════════════════════════════════════════════

    // Calculate optical depth based on mask (haze density); bass pulses fog thickness
    var hazeDensity = (mask * SIGMA_T_HAZE + (1.0 - mask) * SIGMA_T_CLEAR) * (1.0 + bass * 0.5);

    // 'Haze Density' slider is live: 0.4x..1.6x extinction around the
    // default (0.5 -> exactly 1.0, bit-identical to the hardcoded fog).
    hazeDensity *= mix(0.4, 1.6, u.zoom_params.w);

    // Optical depth through the haze layer
    let opticalDepth = hazeDensity * STEP_SIZE * (1.0 + noiseAmt * 0.5);

    // Transmittance (Beer-Lambert): T = exp(-τ)
    let transmittance = exp(-opticalDepth);

    // In-scattered light (digital haze color)
    let hazeColor = vec3<f32>(0.1, 0.15, 0.1); // Digital green-grey haze
    let inScattered = hazeColor * mask * (1.0 - transmittance);

    // Volumetric composition
    // Final = in_scattered + transmitted_clear * T + transmitted_haze * (1-T)
    let transmittedClear = colClear * transmittance;
    let transmittedHaze = finalHaze * (1.0 - transmittance) * 0.3;

    let finalColor = acesToneMap(inScattered + transmittedClear + transmittedHaze);
    let alpha = clamp(1.0 - transmittance + mask * 0.15, 0.0, 1.0);
    let depthVal = textureLoad(readDepthTexture, vec2<i32>(gid.xy), 0).r;
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(mask, alpha, 0.0, 1.0));
}
