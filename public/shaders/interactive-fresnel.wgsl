// ═══════════════════════════════════════════════════════════════════
//  Interactive Fresnel
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, chromatic-aberration, depth-mass, upgraded-rgba
//  Complexity: High
//  Chunks From: interactive-fresnel, bass_env, depth-aware-fog
//  Created: 2024-01-01
//  Upgraded: 2026-05-31
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
  config: vec4<f32>,       // x=Time, y=ClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.4 + mids * 0.15;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let resolution = u.config.zw;
    let mouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthMass = mix(0.3, 1.8, depth);

    let effectStrength = u.zoom_params.x * bass_env(bass, mids) * depthMass;
    let ringCount = u.zoom_params.y * 8.0;
    let ringThickness = u.zoom_params.z * 0.1;
    let rainbowIntensity = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    let diff = uv - mouse;
    let dist = length(vec2<f32>(diff.x * aspect, diff.y));

    let lenD = length(diff);
    let viewDir = select(vec2<f32>(0.0), diff / max(lenD, 0.0001), lenD > 0.0001);

    let numRings = max(1.0, ringCount * bass_env(bass, mids));
    let totalShift = vec2<f32>(0.0);

    for (var i = 0.0; i < 5.0; i = i + 1.0) {
        let ringIdx = i;
        let ringRadius = (ringIdx + 1.0) / numRings;
        let ringProximity = abs(dist - ringRadius);
        let ringInfluence = smoothstep(ringThickness * (1.0 + treble * 0.5), 0.0, ringProximity);
        let ringDirection = select(-1.0, 1.0, ringIdx % 2.0 < 0.5);
        totalShift = totalShift + viewDir * ringDirection * ringInfluence * effectStrength;
    }

    let chromaShift = effectStrength * 0.03 * (1.0 + treble);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv - totalShift - vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv - totalShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv - totalShift + vec2<f32>(chromaShift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    let base = textureSampleLevel(readTexture, u_sampler, clamp(uv - totalShift, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let hueShift = rainbowIntensity * dist * 6.28318 * (1.0 + bass * 0.3);
    let hueRot = mat3x3<f32>(
        0.299 + 0.701 * cos(hueShift) + 0.168 * sin(hueShift),
        0.587 - 0.587 * cos(hueShift) + 0.330 * sin(hueShift),
        0.114 - 0.114 * cos(hueShift) - 0.497 * sin(hueShift),
        0.299 - 0.299 * cos(hueShift) - 0.328 * sin(hueShift),
        0.587 + 0.413 * cos(hueShift) + 0.035 * sin(hueShift),
        0.114 - 0.114 * cos(hueShift) + 0.292 * sin(hueShift),
        0.299 - 0.3 * cos(hueShift) + 1.25 * sin(hueShift),
        0.587 - 0.588 * cos(hueShift) - 1.05 * sin(hueShift),
        0.114 + 0.886 * cos(hueShift) - 0.203 * sin(hueShift)
    );

    let shifted = hueRot * vec3<f32>(r, g, b);
    let luma = dot(shifted, vec3<f32>(0.299, 0.587, 0.114));

    let fresnel = pow(1.0 - clamp(dot(viewDir, vec2<f32>(0.0, 1.0)), 0.0, 1.0), 2.0) * effectStrength * 0.3;

    let finalRGB = mix(shifted, vec3<f32>(1.0, 0.9, 0.6), fresnel);
    let alpha = clamp(base.a * 0.85 + effectStrength * 0.3 + bass * 0.1, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
