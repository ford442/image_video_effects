// ═══════════════════════════════════════════════════════════════════
//  Kimi Spotlight
//  Category: interactive-mouse
//  Features: mouse-driven, interactive, spotlight, reveal, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Created: 2026-05-10
//  Upgraded: 2026-05-23
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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let aspect = resolution.x / resolution.y;
    let p = vec2<f32>(uv.x * aspect, uv.y);
    let mousePos = vec2<f32>(mouse.x * aspect, mouse.y);

    let dist = length(p - mousePos);

    let spotSize = (u.zoom_params.x * 0.5 + 0.1) * (1.0 + bass * 0.15 + mids * 0.05);
    let spotSoftness = max(u.zoom_params.y * 0.5 + 0.01, 0.001);
    let edgeDarkness = u.zoom_params.z * 0.9 + 0.1;
    let saturationBoost = u.zoom_params.w * 2.0 + 1.0;

    var spotlight = 1.0 - smoothstep(spotSize - spotSoftness, spotSize + spotSoftness, dist);

    let clickPulse = mouseDown * sin(time * 10.0) * 0.1;
    spotlight = clamp(min(1.0, spotlight + clickPulse), 0.0, 1.0);

    let original = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    let gray = dot(original, vec3<f32>(0.299, 0.587, 0.114));
    let desaturated = vec3<f32>(gray) * 0.3;

    let luminance = dot(original, vec3<f32>(0.299, 0.587, 0.114));
    let saturated = mix(vec3<f32>(luminance), original, saturationBoost);

    var color = mix(desaturated * edgeDarkness, saturated, spotlight);

    let beamWidth = max(spotSize * 0.1, 0.001);
    let beamDist = abs(dist - spotSize * 0.8);
    let beam = smoothstep(beamWidth, 0.0, beamDist) * 0.2 * spotlight;
    color = color + vec3<f32>(0.9, 0.95, 1.0) * beam;

    let hotspot = smoothstep(spotSize * 0.3, 0.0, dist) * 0.3;
    color = color + vec3<f32>(hotspot);

    let noise = fract(sin(dot(uv * max(time, 0.001), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    color = color + (noise - 0.5) * 0.02 * (1.0 - spotlight);

    color = clamp(color, vec3<f32>(0.0), vec3<f32>(1.0));

    let alpha = clamp(spotlight * 0.7 + hotspot * 0.2 + beam * 0.1 + 0.15 + treble * 0.05, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coords, finalRGBA);
    textureStore(dataTextureA, global_id.xy, finalRGBA);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
