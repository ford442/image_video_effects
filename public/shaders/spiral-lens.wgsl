// ═══════════════════════════════════════════════════════════════════
//  Spiral Lens — Interactivist Upgrade
//  Category: image
//  Features: mouse-driven, audio-reactive, temporal, depth-aware
//  Chunks From: spiral-lens (original)
//  Created: 2026-05-03
//  By: Interactivist Agent
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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Radius, y=Mag, z=Twist, w=Aberration
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / res;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let md = u.zoom_config.w;
    let audio = plasmaBuffer[0];
    let bass = audio.x;
    let treble = audio.z;

    let r = u.zoom_params.x * 0.5 * (1.0 + bass * 0.4);
    let mag = u.zoom_params.y * 3.0 + 0.1 + bass * 0.5;
    let tw = (u.zoom_params.z - 0.5) * 20.0 * (1.0 + bass * 0.3);
    let ab = u.zoom_params.w * 0.05 * (1.0 + treble * 0.5);

    let asp = res.x / res.y;
    let dvec = (uv - mouse) * vec2<f32>(asp, 1.0);
    let dist = length(dvec);
    let mask = smoothstep(r, 0.0, dist);

    let wave = sin(dist * 40.0 - time * 10.0) * 0.03 * md * smoothstep(r * 1.5, 0.0, dist);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let a = tw * mask * mask * (1.0 + depth * 0.5);
    let s = sin(a);
    let c = cos(a);
    let rot = mat2x2<f32>(c, -s, s, c);

    var p = (uv - mouse) * vec2<f32>(asp, 1.0);
    p = rot * p;
    p = p / vec2<f32>(asp, 1.0);
    p = p * mix(1.0, 1.0 / mag, mask);

    let dir = select(vec2<f32>(0.0), dvec / max(dist, 0.0001), dist > 0.0001);
    let fuv = mouse + p + dir * wave;

    let drift = vec2<f32>(sin(time * 0.7 + uv.y * 4.0), cos(time * 0.5 + uv.x * 4.0)) * 0.003 * bass;
    let ruv = fuv + (mouse - fuv) * ab * mask + drift;
    let buv = fuv - (mouse - fuv) * ab * mask - drift;

    let col = vec3<f32>(
        textureSampleLevel(readTexture, u_sampler, ruv, 0.0).r,
        textureSampleLevel(readTexture, u_sampler, fuv + drift * 0.5, 0.0).g,
        textureSampleLevel(readTexture, u_sampler, buv, 0.0).b
    );

    let spark = 1.0 + treble * mask * 0.4;
    var out = col * spark;

    let fb = 0.15 * bass * mask;
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv + drift * 0.3, 0.0).rgb;
    out = mix(out, prev, fb);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(out, 1.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(out, 1.0));

    let dep = textureSampleLevel(readDepthTexture, non_filtering_sampler, fuv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(dep, 0.0, 0.0, 0.0));
}
