// ═══════════════════════════════════════════════════════════════════
//  Liquid Metal — Phase A Upgrade
//  Category: liquid-effects
//  Features: mouse-driven, depth-aware, temporal, audio-reactive
//  Complexity: Medium
//  Chunks From: original liquid-metal.wgsl
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: viscosity        — how slowly the height field evolves
//  Param2: reflectivity     — F0 metallic base reflectance
//  Param3: chromatic_spread — RGB dispersion on reflections
//  Param4: flow_speed       — gravity-like flow toward depth attractor
//
//  dataTextureC.r = height field (persists across frames)

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
  zoom_params: vec4<f32>,  // x=Viscosity, y=Reflectivity, z=ChromaticSpread, w=FlowSpeed
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265;

// ─── Helpers ──────────────────────────────────────────────────────

fn hash1(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn vnoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash1(i), hash1(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash1(i + vec2<f32>(0.0, 1.0)), hash1(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// FBM height field for liquid surface
fn fbmHeight(p: vec2<f32>, t: f32) -> f32 {
    var v = 0.0; var amp = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) {
        v += amp * vnoise(pp + vec2<f32>(t * 0.07, t * 0.05));
        pp = pp * 2.1 + vec2<f32>(1.7, 9.2);
        amp *= 0.5;
    }
    return v;
}

// Schlick Fresnel reflectance
fn schlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Surface normal from height field gradient
fn heightNormal(uv: vec2<f32>, px: vec2<f32>, t: f32) -> vec3<f32> {
    let scale = 3.5;
    let hL = fbmHeight(uv * scale - vec2<f32>(px.x, 0.0), t);
    let hR = fbmHeight(uv * scale + vec2<f32>(px.x, 0.0), t);
    let hD = fbmHeight(uv * scale - vec2<f32>(0.0, px.y), t);
    let hU = fbmHeight(uv * scale + vec2<f32>(0.0, px.y), t);
    return normalize(vec3<f32>(hL - hR, hD - hU, 0.04));
}

// ─── Main ─────────────────────────────────────────────────────────

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv      = vec2<f32>(global_id.xy) / resolution;
    let time    = u.config.x;
    let px      = 1.0 / resolution;
    let aspect  = resolution.x / resolution.y;
    let mouse   = u.zoom_config.yz;

    // Params
    let viscosity      = u.zoom_params.x * 0.9 + 0.05;
    let reflectivity   = u.zoom_params.y;
    let chromaSpread   = u.zoom_params.z * 0.025;
    let flowSpeed      = u.zoom_params.w;

    // Audio
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass = select(0.0, plasmaBuffer[0].x, hasAudio);

    // Depth (1=near foreground, 0=far background)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ── Temporal height field ─────────────────────────────────────
    // Read previous height from dataTextureC, evolve toward FBM target
    let prevH = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;
    var targetH = fbmHeight(uv * 3.0, time);

    // Flow: height field drains toward high-depth (foreground) regions
    // Sample depth gradient to get flow direction
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(px.x, 0.0), 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(px.x, 0.0), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, px.y), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, px.y), 0.0).r;
    let depthGrad = vec2<f32>(dR - dL, dU - dD);
    let flowUV = uv + depthGrad * flowSpeed * 0.02;
    let flowH = textureSampleLevel(dataTextureC, non_filtering_sampler,
                                   clamp(flowUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;

    // Mouse pour: add height under cursor
    if (mouse.x >= 0.0) {
        let mDist = length((uv - mouse) * vec2<f32>(aspect, 1.0));
        if (mDist < 0.08) {
            let pour = (1.0 - smoothstep(0.0, 0.08, mDist)) * 0.6;
            targetH = max(targetH, pour);
        }
    }

    // Ripple impulses add height
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let r = u.ripples[ri];
        let elapsed = time - r.z;
        if (elapsed >= 0.0 && elapsed < 1.5) {
            let rDist = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
            let splash = exp(-rDist * 10.0) * exp(-elapsed * 3.0);
            targetH = max(targetH, splash * 0.8);
        }
    }

    // Audio pulses the surface
    targetH = targetH * (1.0 + bass * 0.3);

    // Viscosity: slow blend from prev to target (high viscosity = slow)
    let blendRate = (1.0 - viscosity) * 0.15 + 0.01;
    let newH = mix(mix(prevH, flowH, flowSpeed * 0.1), targetH, blendRate);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newH, depth, 0.0, 1.0));

    // ── Surface normal from height gradient ───────────────────────
    let effTime = time * (1.0 - viscosity * 0.7);
    let normal = heightNormal(uv, px, effTime);

    // ── Fresnel reflectance ───────────────────────────────────────
    let viewDir = normalize(vec3<f32>((uv - 0.5) * vec2<f32>(aspect, 1.0), 1.0));
    let cosTheta = clamp(dot(viewDir, normal), 0.0, 1.0);
    let F0 = mix(0.04, 0.95, reflectivity);
    let F  = schlick(cosTheta, F0);

    // ── Chromatic dispersion on refraction ────────────────────────
    // Normal displaces UV differently per channel (RGB split by wavelength)
    let refractBase = vec2<f32>(normal.xy) * (newH * 0.06 + 0.01);
    let rUV = clamp(uv + refractBase * (1.0 - chromaSpread), vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + refractBase,                        vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + refractBase * (1.0 + chromaSpread), vec2<f32>(0.0), vec2<f32>(1.0));

    let sampR = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let sampG = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let sampB = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let refractedColor = vec3<f32>(sampR, sampG, sampB);

    // ── Metallic reflection colour ────────────────────────────────
    // Silver-grey tinted by iridescence from height and time
    let iridPhase = newH * 4.0 + time * 0.3;
    let irid = vec3<f32>(
        0.75 + 0.25 * sin(iridPhase),
        0.80 + 0.20 * sin(iridPhase + 2.09),
        0.85 + 0.15 * sin(iridPhase + 4.19)
    );
    let metalColor = mix(vec3<f32>(0.8, 0.85, 0.9), irid, reflectivity * 0.7);

    // Specular highlight
    let halfV = normalize(viewDir + vec3<f32>(0.3, 0.5, 0.8));
    let spec = pow(max(dot(normal, halfV), 0.0), mix(16.0, 128.0, reflectivity));

    // Blend refracted image with metallic reflection via Fresnel
    var finalColor = mix(refractedColor, metalColor, F);
    finalColor += vec3<f32>(spec * reflectivity * (0.8 + bass * 0.4));

    // RGBA alpha: wetness / reflectivity drives opacity
    let wetness = F * (0.6 + newH * 0.4);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, wetness));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy),
                 vec4<f32>(depth * 0.7 + newH * 0.3, 0.0, 0.0, 1.0));
}
