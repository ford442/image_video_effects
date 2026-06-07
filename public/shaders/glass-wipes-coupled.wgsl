// ═══════════════════════════════════════════════════════════════════
//  Glass Wipes Coupled
//  Category: advanced-hybrid
//  Features: mouse-driven, fluid-simulation, temporal, rain-simulation
//  Complexity: Very High
//  Chunks From: glass-wipes, mouse-fluid-coupling
//  Created: 2026-04-18
//  By: Agent CB-24 — Glass & Reflection Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Rain on glass combined with viscous fluid coupling physics.
//  Rain drops add fluid density, mouse wiper clears streaks,
//  and fluid advection creates realistic water streak dynamics.
//  Vortex streets form from fast mouse movement.
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn sampleVelocity(tex: texture_2d<f32>, smp: sampler, uv: vec2<f32>) -> vec2<f32> {
    return textureSampleLevel(tex, smp, uv, 0.0).xy;
}

fn sampleDensity(tex: texture_2d<f32>, smp: sampler, uv: vec2<f32>) -> f32 {
    return textureSampleLevel(tex, smp, uv, 0.0).a;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Parameters
    let rainIntensity = 0.005 + u.zoom_params.x * 0.05;
    let viscosity = mix(0.92, 0.99, u.zoom_params.y);
    let wiperSize = 0.05 + u.zoom_params.z * 0.25;
    let vortexStrength = u.zoom_params.w * 2.0;

    var mousePos = u.zoom_config.yz;
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let mouseVel = (mousePos - prevMouse) * 60.0;
    let mouseSpeed = length(mouseVel);

    // Store current mouse position at (0,0)
    if (global_id.x == 0u && global_id.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
    }

    let px = vec2<f32>(1.0) / resolution;

    // Read previous fluid state from dataTextureC
    let prevVel = sampleVelocity(dataTextureC, non_filtering_sampler, uv);
    let prevDens = sampleDensity(dataTextureC, non_filtering_sampler, uv);

    // Advect velocity (semi-Lagrangian)
    let backUV = uv - prevVel * px * 2.0;
    let advectedVel = sampleVelocity(dataTextureC, non_filtering_sampler, backUV);
    let advectedDens = sampleDensity(dataTextureC, non_filtering_sampler, backUV);

    // Apply viscosity
    var vel = advectedVel * viscosity;
    var dens = advectedDens * viscosity;

    // Mouse force: stirring rod
    let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(toMouse);
    let influence = smoothstep(wiperSize, 0.0, dist);

    vel = vel + mouseVel * influence * 0.5;

    // Vortex force: perpendicular to mouse motion
    let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
    vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

    // Click ripples = fluid injection points
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let elapsed = time - ripple.z;
        if (elapsed > 0.0 && elapsed < 2.0) {
            let rToMouse = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let rDist = length(rToMouse);
            let rInfluence = smoothstep(0.2, 0.0, rDist) * exp(-elapsed * 1.5);
            let outward = select(vec2<f32>(0.0), normalize(rToMouse / vec2<f32>(aspect, 1.0)), rDist > 0.001);
            vel = vel + outward * rInfluence * 0.3;
            dens = dens + rInfluence * 0.5;
        }
    }

    // ═══ Rain simulation adds to fluid density ═══
    let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (noise > (1.0 - rainIntensity)) {
        dens = min(2.0, dens + 0.3);
    }

    // Natural evaporation
    dens = max(0.0, dens - 0.001);

    // Mouse wiper clears fluid
    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let wipeDist = length(vec2<f32>(dVec.x * aspect, dVec.y));
        if (wipeDist < wiperSize) {
            let wipeFactor = smoothstep(wiperSize, wiperSize * 0.5, wipeDist);
            dens = dens * (1.0 - wipeFactor);
        }
    }

    // Damping at edges
    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
    vel = vel * edgeDamp;

    // Clamp
    vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
    dens = clamp(dens, 0.0, 2.0);

    // ═══ Visual output: distortion and color shift ═══
    let distortionScale = 0.05;
    let distortion = vel * dens * distortionScale;
    let distortedUV = clamp(uv + distortion, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Water properties
    let waterColor = vec3<f32>(0.85, 0.95, 1.0);
    let normal = normalize(vec3<f32>(distortion * 100.0, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.02;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
    let thickness = dens * 0.05;
    let absorption = exp(-(1.0 - waterColor) * thickness * 1.5);
    let transmission = mix(1.0, (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0, dens * 0.5);

    color = vec4<f32>(mix(color.rgb, color.rgb * waterColor, dens * 0.25), transmission);

    // Specular highlight
    let specNoise = hash12(uv * 300.0 + time * 2.0);
    let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
    color = color + vec4<f32>(0.9, 0.95, 1.0, 0.0) * specular;

    // Store fluid state
    let vorticity = vel.x - vel.y;
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(vel, vorticity, dens));
    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Depth passthrough
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
