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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = vec2<f32>(gid.xy) / res;
    let ps = 1.0 / res;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let time = u.config.x;

    // Read previous state
    let prevState = textureLoad(dataTextureC, coord, 0);
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
    let burnRate = mix(0.01, 0.08, u.zoom_params.x);
    let convectionStrength = mix(0.5, 3.0, u.zoom_params.y);
    let smokeRise = 0.02;

    // === DIFFUSION & CONVECTION ===
    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

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
    smoke += burning * 0.5;

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
        if (ageR < 0.5 && rDist < 0.05) {
            let spark = smoothstep(0.05, 0.0, rDist) * max(0.0, 1.0 - ageR * 2.0);
            temperature += spark * 1.5;
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
    let ember = smoothstep(0.5, 2.0, age) * 0.3;
    displayColor.r += ember;

    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(2.0));
    displayColor = displayColor / (1.0 + displayColor * 0.3); // Soft tone map
    displayColor = clamp(displayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coord, vec4<f32>(displayColor, temperature * 0.25));

    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
