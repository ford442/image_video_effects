// ═══════════════════════════════════════════════════════════════════
//  chroma-vortex-coupled
//  Category: advanced-hybrid
//  Features: chroma-vortex, fluid-coupling, mouse-driven, temporal
//  Complexity: Very High
//  Chunks From: chroma-vortex, mouse-fluid-coupling
//  Created: 2026-04-18
//  By: Agent CB-12 — Chroma & Spectral Enhancer
// ═══════════════════════════════════════════════════════════════════
//  RGB vortex twist distorted by a live fluid velocity field.
//  Mouse movement stirs fluid that advects the chromatic swirl
//  sampling coordinates, creating viscous chromatic trails.
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

fn rotate(v: vec2<f32>, angle: f32) -> vec2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

fn sampleVelocity(tex: texture_2d<f32>, uv: vec2<f32>) -> vec2<f32> {
    return textureSampleLevel(tex, u_sampler, uv, 0.0).xy;
}

fn sampleDensity(tex: texture_2d<f32>, uv: vec2<f32>) -> f32 {
    return textureSampleLevel(tex, u_sampler, uv, 0.0).a;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let aspect = res.x / res.y;
    let time = u.config.x;

    let twist = u.zoom_params.x * 3.14159 * 2.0;
    let spread = u.zoom_params.y * 0.1;
    let radius = max(u.zoom_params.z, 0.01);
    let centerBias = u.zoom_params.w;

    let viscosity = mix(0.92, 0.99, u.zoom_params.x);
    let mouseRadius = mix(0.03, 0.15, u.zoom_params.y);
    let vortexStrength = u.zoom_params.w * 2.0;

    var mousePos = u.zoom_config.yz;
    let prevMouse = textureLoad(dataTextureC, vec2<i32>(0, 0), 0).xy;
    let mouseVel = (mousePos - prevMouse) * 60.0;
    let mouseSpeed = length(mouseVel);

    if (gid.x == 0u && gid.y == 0u) {
        textureStore(dataTextureA, vec2<i32>(0, 0), vec4<f32>(mousePos, 0.0, 0.0));
    }

    let px = vec2<f32>(1.0) / res;
    let prevVel = sampleVelocity(dataTextureC, uv);
    let prevDens = sampleDensity(dataTextureC, uv);

    let backUV = uv - prevVel * px * 2.0;
    let advectedVel = sampleVelocity(dataTextureC, backUV);
    let advectedDens = sampleDensity(dataTextureC, backUV);

    var vel = advectedVel * viscosity;
    var dens = advectedDens * viscosity;

    let toMouse = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let distMouse = length(toMouse);
    let influence = smoothstep(mouseRadius, 0.0, distMouse);

    vel = vel + mouseVel * influence * 0.5;
    let vortexDir = vec2<f32>(-mouseVel.y, mouseVel.x);
    vel = vel + vortexDir * influence * vortexStrength * mouseSpeed;

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

    let edgeDist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    let edgeDamp = smoothstep(0.05, 0.1, edgeDist);
    vel = vel * edgeDamp;
    vel = clamp(vel, vec2<f32>(-0.5), vec2<f32>(0.5));
    dens = clamp(dens, 0.0, 2.0);

    // Store fluid state
    let vorticity = vel.x - vel.y;
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(vel, vorticity, dens));

    // Apply fluid displacement to vortex sampling
    let fluidDisp = vel * dens * 0.05;
    let displacedUV = uv + fluidDisp;

    let diff = displacedUV - mousePos;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));
    var factor = smoothstep(radius, 0.0, dist);
    let power = centerBias * 4.8 + 0.2;
    factor = pow(factor, power);

    let angleBase = factor * twist;
    let angleR = angleBase - spread * factor * 10.0;
    let angleG = angleBase;
    let angleB = angleBase + spread * factor * 10.0;

    let diffSq = vec2<f32>(diff.x * aspect, diff.y);
    let rotR_sq = rotate(diffSq, angleR);
    let rotG_sq = rotate(diffSq, angleG);
    let rotB_sq = rotate(diffSq, angleB);

    let rotR = vec2<f32>(rotR_sq.x / aspect, rotR_sq.y);
    let rotG = vec2<f32>(rotG_sq.x / aspect, rotG_sq.y);
    let rotB = vec2<f32>(rotB_sq.x / aspect, rotB_sq.y);

    let uvR = clamp(mousePos + rotR, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(mousePos + rotG, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(mousePos + rotB, vec2<f32>(0.0), vec2<f32>(1.0));

    let colR = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let colG = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let colB = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    // Fluid tint
    let fluidTint = mix(vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(1.0, 0.85, 0.6), dens * 0.5);
    var outColor = vec3<f32>(colR, colG, colB) * fluidTint;

    // Specular highlight on fluid surface near mouse
    let specNoise = fract(sin(dot(uv * 300.0 + time * 2.0, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let specular = pow(specNoise, 20.0) * influence * dens * 3.0;
    outColor += vec3<f32>(0.9, 0.95, 1.0) * specular;

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(outColor, dens));

    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
