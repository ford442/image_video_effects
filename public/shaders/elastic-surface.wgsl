// ═══════════════════════════════════════════════════════════════════
//  Elastic Surface — Phase A Upgrade
//  Category: distortion
//  Features: mouse-driven, depth-aware, temporal, ripple-reactive
//  Complexity: Medium
//  Chunks From: original elastic-surface.wgsl
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Elasticity, y=SurfaceTension, z=WaveSpeed, w=DepthInfluence
  ripples: array<vec4<f32>, 50>,
};

// ─── Noise helpers ────────────────────────────────────────────────

fn hash2(p: vec2<f32>) -> vec2<f32> {
    let q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = dot(hash2(i),                   f);
    let b = dot(hash2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0));
    let c = dot(hash2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0));
    let d = dot(hash2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>) -> vec2<f32> {
    var v = vec2<f32>(0.0);
    var amp = 0.5;
    var pp = p;
    for (var i = 0; i < 3; i++) {
        v += amp * vec2<f32>(vnoise(pp), vnoise(pp + vec2<f32>(5.2, 1.3)));
        pp = pp * 2.1 + vec2<f32>(1.7, 9.2);
        amp *= 0.5;
    }
    return v;
}

// ─── Surface normal from displacement gradient ────────────────────

fn surfaceNormal(dispE: vec2<f32>, dispW: vec2<f32>, dispN: vec2<f32>, dispS: vec2<f32>) -> vec3<f32> {
    let grad = vec2<f32>(dispE.x - dispW.x, dispN.y - dispS.y) * 4.0;
    return normalize(vec3<f32>(-grad.x, -grad.y, 1.0));
}

// ─── Main ─────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;
    let px = 1.0 / resolution;

    // Params
    let elasticity    = u.zoom_params.x * 0.08 + 0.005;  // spring stiffness
    let tension       = u.zoom_params.y * 0.6 + 0.1;      // neighbor coupling
    let waveSpeed     = u.zoom_params.z * 0.8 + 0.2;
    let depthInfluence = u.zoom_params.w;

    // Read current state from dataTextureC: RG=displacement, BA=velocity
    let self_ = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var disp = self_.rg;
    var vel  = self_.ba;

    // Sample neighbours for Laplacian (surface tension / wave coupling)
    let nN = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0,  px.y), 0.0).rg;
    let nS = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(0.0,  px.y), 0.0).rg;
    let nE = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(px.x, 0.0),  0.0).rg;
    let nW = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(px.x, 0.0),  0.0).rg;
    let laplacian = (nN + nS + nE + nW) * 0.25 - disp;

    // Depth: near objects (depth→1) deform more freely
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMod = 1.0 + depth * depthInfluence * 2.0;

    // Hooke restoring force + surface tension wave propagation
    var accel = -disp * elasticity / depthMod
              + laplacian * tension;

    // Ambient FBM perturbation — organic background rippling
    let noiseUV = uv * 4.0 + time * 0.08;
    let ambientForce = (fbm2(noiseUV) - 0.5) * 0.0004 * waveSpeed;
    accel += ambientForce;

    // Mouse push/pull
    let mousePos = u.zoom_config.yz;
    if (mousePos.x >= 0.0) {
        let dVec = uv - mousePos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));
        let radius = 0.12;
        if (dist < radius) {
            let dir = select(normalize(dVec), vec2<f32>(0.0), length(dVec) < 0.0001);
            let influence = 1.0 - smoothstep(0.0, radius, dist);
            let push = select(0.002, -0.003, u.zoom_config.w > 0.5); // hover=push, click=pull
            accel += dir * influence * push * depthMod;
        }
    }

    // Ripple impulses from mouse clicks
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let r = u.ripples[ri];
        let elapsed = time - r.z;
        if (elapsed > 0.0 && elapsed < 3.0) {
            let rVec = uv - r.xy;
            let rDist = length(vec2<f32>(rVec.x * aspect, rVec.y));
            let wave = sin(rDist * 40.0 - elapsed * 10.0)
                     * exp(-elapsed * 1.8)
                     * exp(-rDist * 8.0);
            let dir = select(normalize(rVec), vec2<f32>(0.0, 1.0), rDist < 0.0001);
            accel += dir * wave * 0.0025;
        }
    }

    // Verlet integration with damping
    let damping = 0.985;
    vel = (vel + accel * waveSpeed) * damping;
    disp += vel;

    // Clamp displacement to avoid runaway
    disp = clamp(disp, vec2<f32>(-0.15), vec2<f32>(0.15));

    // Persist state for next frame
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(disp, vel));

    // Sample image with displacement
    let distortedUV = clamp(uv - disp, vec2<f32>(0.0), vec2<f32>(1.0));
    let color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Fake surface lighting from displacement gradient (normal map)
    let normal = surfaceNormal(nE, nW, nN, nS);
    let light  = normalize(vec3<f32>(0.4, 0.6, 1.0));
    let diffuse  = max(dot(normal, light), 0.0);
    let specular = pow(max(dot(reflect(-light, normal), vec3<f32>(0.0, 0.0, 1.0)), 0.0), 32.0);
    let lighting = 0.7 + 0.25 * diffuse + 0.15 * specular;

    // RGBA alpha encodes stretch intensity
    let stretch = clamp(length(disp) * 12.0, 0.0, 1.0);

    let finalColor = vec4<f32>(color.rgb * lighting, color.a + stretch * 0.3);
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);

    // Write depth pass-through
    let depthOut = textureSampleLevel(readDepthTexture, non_filtering_sampler, distortedUV, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 1.0));
}
