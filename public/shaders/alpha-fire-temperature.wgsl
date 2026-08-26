// ═══════════════════════════════════════════════════════════════════
//  Alpha Fire Temperature
//  Category: simulation
//  Features: mouse-driven, temporal, rgba-state-machine
//  Complexity: High
//  RGBA Channels:
//    R = Fuel amount (what's burning, 0.0 to 1.0+)
//    G = Temperature (drives blackbody color, can exceed 1.0)
//    B = Smoke density (0.0 to 1.0)
//    A = Combustion age (how long pixel has been burning)
//  Why f32: Temperature follows blackbody radiation (Kelvin scale)
//  and requires values well above 1.0 for proper color mapping.
//  Fuel and smoke need sub-percent precision for stable flame fronts.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) /
        max(x * (2.43 * x + 0.59) + 0.14, vec3<f32>(0.001)),
        vec3<f32>(0.0), vec3<f32>(1.0));
}

fn stateAt(p: vec2<i32>, dims: vec2<i32>) -> vec4<f32> {
    return textureLoad(dataTextureC, clamp(p, vec2<i32>(0), dims - vec2<i32>(1)), 0);
}

// Blackbody approximation (simplified)
fn blackbodyColor(t: f32) -> vec3<f32> {
    // t is normalized 0-1, maps to temperature range
    let temp = t * 4.0;
    var color: vec3<f32>;
    if (temp < 1.0) {
        color = vec3<f32>(temp, 0.0, 0.0);
    } else if (temp < 2.0) {
        color = vec3<f32>(1.0, temp - 1.0, 0.0);
    } else if (temp < 3.0) {
        color = vec3<f32>(1.0, 1.0, temp - 2.0);
    } else {
        color = vec3<f32>(1.0, 1.0, 1.0) * (1.0 + (temp - 3.0) * 0.5);
    }
    return color;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let dims = vec2<i32>(res);
    let time = u.config.x;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));

    // Read previous state
    let prevState = stateAt(coord, dims);
    var fuel = prevState.r;
    var temperature = prevState.g;
    var smoke = prevState.b;
    var age = prevState.a;

    // Seed on first frame
    if (time < 0.1) {
        fuel = 0.0;
        temperature = 0.0;
        smoke = 0.0;
        age = 0.0;
        // Seed fuel at bottom center
        let dist = length(uv - vec2<f32>(0.5, 0.9));
        if (dist < 0.08) {
            fuel = 1.0;
            temperature = 0.5;
        }
    }

    // Clamp
    fuel = clamp(fuel, 0.0, 2.0);
    temperature = clamp(temperature, 0.0, 4.0);
    smoke = clamp(smoke, 0.0, 2.0);
    age = clamp(age, 0.0, 5.0);

    // === PARAMETERS ===
    let burnRate = mix(0.01, 0.08, u.zoom_params.x) * (1.0 + audio.x * 0.65);
    let convectionStrength = mix(0.5, 3.0, u.zoom_params.y) * (1.0 + audio.y * 0.3);
    let smokeDensity = mix(0.2, 1.8, u.zoom_params.z);
    let emberGlow = mix(0.2, 2.5, u.zoom_params.w);
    let smokeRise = 0.02;

    // === DIFFUSION & CONVECTION ===
    let left = stateAt(coord + vec2<i32>(-1, 0), dims);
    let right = stateAt(coord + vec2<i32>(1, 0), dims);
    let down = stateAt(coord + vec2<i32>(0, -1), dims);
    let up = stateAt(coord + vec2<i32>(0, 1), dims);

    // Heat rises: sample from below (advection upward)
    let below = down;
    let advectedTemp = mix(temperature, below.g, smokeRise * convectionStrength);
    let advectedSmoke = mix(smoke, below.b, smokeRise * convectionStrength);
    let advectedAge = mix(age, below.a, smokeRise * 0.5);

    temperature = advectedTemp;
    smoke = advectedSmoke;
    age = advectedAge;

    // Thermal diffusion
    let lapTemp = left.g + right.g + down.g + up.g - 4.0 * temperature;
    temperature += lapTemp * 0.05;

    // Smoke diffusion
    let lapSmoke = left.b + right.b + down.b + up.b - 4.0 * smoke;
    smoke += lapSmoke * 0.02;

    // === COMBUSTION ===
    // Fuel burns if temperature is high enough
    let ignitionTemp = 0.2;
    let burning = step(ignitionTemp, temperature) * fuel * burnRate;
    fuel -= burning;
    temperature += burning * 2.0;
    age += burning * 0.5;

    // Smoke generation from burning
    smoke += burning * smokeDensity * (0.35 + audio.y * 0.3);

    // === COOLING & DECAY ===
    temperature *= 0.97; // Radiative cooling
    smoke *= 0.995;      // Smoke dissipation
    age *= 0.99;
    fuel = clamp(fuel, 0.0, 2.0);

    // === MOUSE FUEL INJECTION ===
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.08, 0.0, mouseDist) * mouseDown;
    fuel += mouseInfluence * 0.5;
    temperature += mouseInfluence * 0.3;
    fuel = clamp(fuel, 0.0, 2.0);
    temperature = clamp(temperature, 0.0, 4.0);

    // === RIPPLE SPARKS ===
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rDist = length(uv - ripple.xy);
        let ageR = time - ripple.z;
        if (ageR >= 0.0 && ageR < 1.8) {
            let spark = exp(-abs(rDist - ageR * 0.21) * 58.0 - ageR * 1.7);
            temperature += spark * (1.2 + audio.z * 1.4);
            fuel += spark * 0.3;
        }
    }
    fuel = clamp(fuel, 0.0, 2.0);
    temperature = clamp(temperature, 0.0, 4.0);

    // === STORE STATE ===
    textureStore(dataTextureA, coord, vec4<f32>(fuel, temperature, smoke, age));

    // === VISUALIZATION (blackbody + smoke) ===
    let tempNorm = temperature / 3.0;
    let fireColor = blackbodyColor(tempNorm);

    // Smoke darkens and tints blue-gray
    let smokeColor = vec3<f32>(0.2, 0.25, 0.3);
    var displayColor = mix(fireColor, smokeColor, min(smoke, 0.9));

    // Age adds red ember glow
    let ember = smoothstep(0.5, 2.0, age) * emberGlow;
    displayColor += ember * vec3<f32>(1.8, 0.18 + audio.y * 0.18, 0.025);

    displayColor += audio * vec3<f32>(0.22, 0.08, 0.3) * temperature;

    let alpha = clamp(temperature * 0.2 + smoke * 0.36 + ember * 0.1, 0.0, 1.0);
    textureStore(writeTexture, coord, vec4<f32>(aces(displayColor), alpha));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
