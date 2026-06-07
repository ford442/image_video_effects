// ═══════════════════════════════════════════════════════════════════
//  Interactive Origami — Phase A Upgrade
//  Category: geometric
//  Features: mouse-driven, depth-aware, audio-reactive, temporal
//  Complexity: Medium
//  Created: 2026-05-23
//  By: Claude (Sonnet 4.6)
// ═══════════════════════════════════════════════════════════════════
//
//  Param1: fold_scale       — density/frequency of fold lines
//  Param2: fold_depth       — UV displacement magnitude at crease peaks
//  Param3: light_intensity  — facet shading contrast
//  Param4: depth_influence  — far objects (depth→0) fold more strongly

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
  zoom_params: vec4<f32>,  // x=FoldScale, y=FoldDepth, z=LightIntensity, w=DepthInfluence
  ripples: array<vec4<f32>, 50>,
};

// Triangle wave — creates sharper creases than sine
fn triWave(x: f32) -> f32 {
    return abs(fract(x * 0.5 + 0.25) * 4.0 - 2.0) - 1.0;
}

// Sum of 3 oriented fold planes radiating from mouse
fn foldHeight(p: vec2<f32>, mouse2: vec2<f32>, scale: f32, bass: f32) -> f32 {
    let d1 = dot(p - mouse2, normalize(vec2<f32>( 0.707,  0.707)));
    let d2 = dot(p - mouse2, normalize(vec2<f32>(-0.707,  0.707)));
    let d3 = dot(p - mouse2, normalize(vec2<f32>( 1.0,    0.0  )));
    let amp = 1.0 + bass * 0.4;
    return (triWave(d1 * scale) + triWave(d2 * scale * 0.73) + triWave(d3 * scale * 1.27)) * amp / 3.0;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let uv    = vec2<f32>(gid.xy) / resolution;
    let time  = u.config.x;
    let aspect = resolution.x / resolution.y;
    let aVec   = vec2<f32>(aspect, 1.0);

    // Params
    let foldScale  = mix(2.0, 18.0, u.zoom_params.x);
    let foldDepth  = u.zoom_params.y * 0.06;
    let lightInt   = u.zoom_params.z;
    let depthInfl  = u.zoom_params.w;

    // Audio
    let hasAudio = arrayLength(&plasmaBuffer) > 0u;
    let bass   = select(0.0, plasmaBuffer[0].x, hasAudio);
    let treble = select(0.0, plasmaBuffer[0].z, hasAudio);

    // Depth — far objects (depth→0) fold more
    let depth       = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthFactor = mix(1.0, 1.0 + depthInfl, 1.0 - depth);

    // Mouse influence — folds radiate from cursor, fall off at distance
    let mouse       = u.zoom_config.yz;
    let mDistVec    = (uv - mouse) * aVec;
    let mDist       = length(mDistVec);
    let influence   = smoothstep(0.85, 0.0, mDist);

    // Ripple-triggered crease rings
    let rippleCount = min(u32(u.config.y), 50u);
    var rippleFold  = 0.0;
    for (var i = 0u; i < rippleCount; i++) {
        let rp   = u.ripples[i].xy;
        let rt   = u.ripples[i].z;
        let rAge = time - rt;
        if (rAge < 0.0 || rAge > 3.5) { continue; }
        let rDist  = length((uv - rp) * aVec);
        let rFront = rAge * 0.4;
        rippleFold += exp(-abs(rDist - rFront) * 25.0) * exp(-rAge * 1.2);
    }

    // Finite-difference gradient of the fold surface
    let pUV  = uv * aVec;
    let mUV  = mouse * aVec;
    let dlt  = 0.005;
    let h0   = foldHeight(pUV,                          mUV, foldScale, bass);
    let hDx  = foldHeight(pUV + vec2<f32>(dlt, 0.0),   mUV, foldScale, bass);
    let hDy  = foldHeight(pUV + vec2<f32>(0.0, dlt),   mUV, foldScale, bass);
    let grad = vec2<f32>((hDx - h0) / dlt, (hDy - h0) / dlt);

    // UV displacement
    let rippleDisp = rippleFold * 0.015;
    let dispDir    = normalize(mDistVec + vec2<f32>(0.0001));
    let disp       = (grad * foldDepth + dispDir * rippleDisp) * influence * depthFactor;
    let sampleUV   = clamp(uv - disp / aVec, vec2<f32>(0.0), vec2<f32>(1.0));

    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;

    // Normal-map facet shading from gradient
    let normalXY = normalize(grad + vec2<f32>(0.0001)) * 0.4;
    let normalZ  = sqrt(max(0.0, 1.0 - dot(normalXY, normalXY)));
    let normal3  = vec3<f32>(normalXY, normalZ);
    let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
    let diffuse  = max(dot(normal3, lightDir), 0.0);
    // Specular ridges amplified by treble
    let ridgePeak = pow(abs(h0), 3.0) * (1.0 + treble * 0.5);
    let lighting  = (diffuse * 0.6 + ridgePeak * 0.4) * lightInt * influence;
    color = clamp(color + lighting, vec3<f32>(0.0), vec3<f32>(1.0));

    // Shadow inside fold valleys
    let shadow = smoothstep(-0.3, -0.8, h0) * 0.3 * lightInt * influence;
    color *= (1.0 - shadow);

    // Temporal persistence
    let prev  = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    color = mix(color, prev * 0.92, 0.08);

    let alpha = clamp(dot(color, vec3<f32>(0.33)) * 0.6 + 0.4 + depth * 0.1, 0.0, 1.0);

    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(color, alpha));
    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 1.0));
}
