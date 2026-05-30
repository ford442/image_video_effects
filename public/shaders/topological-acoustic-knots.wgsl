// ═══════════════════════════════════════════════════════════════════
//  Topological Acoustic Knots
//  Category: generative
//  Features: topological-defects, nematic-fields, audio-driven, mouse-pinning, defect-dynamics
//  Complexity: High
//  Chunks From: orientation field simulation + defect tracking
//  Created: 2026-05-31
//  By: Grok (creative technical artist)
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
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = vec2<f32>(gid.xy) / res;
    let time = u.config.x * 0.8;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Read previous orientation field
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let prevAngle = prev.r;
    let prevDefect = prev.g;

    // Audio-driven parameters
    let defectBirth = bass * 0.7 + treble * 0.5;      // Bass + treble create defects
    let mobility = 0.4 + mids * 0.9;                   // Mids make defects move
    let pairing = 0.3 + bass * 0.4;                    // Bass encourages defect pairing/annihilation

    // Sample neighbors for orientation field evolution
    let ps = 1.0 / res;
    let n1 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>( ps.x, 0.0), 0.0).r;
    let n2 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>( ps.x, 0.0), 0.0).r;
    let n3 = textureSampleLevel(dataTextureC, u_sampler, uv + vec2<f32>(0.0,  ps.y), 0.0).r;
    let n4 = textureSampleLevel(dataTextureC, u_sampler, uv - vec2<f32>(0.0,  ps.y), 0.0).r;

    // Simple relaxation of orientation field
    var angle = (prevAngle * 0.6 + (n1 + n2 + n3 + n4) * 0.1);

    // Add noise driven by audio
    let noise = hash12(uv * 12.0 + time * 0.3) - 0.5;
    angle += noise * (0.02 + defectBirth * 0.06);

    // Mouse pinning / creation of defects
    let mouseDist = length(uv - mouse);
    let mouseEffect = smoothstep(0.15, 0.0, mouseDist) * mouseDown;

    // Mouse can pin orientation or create defect
    if (mouseDown > 0.5) {
        angle = mix(angle, atan2(uv.y - mouse.y, uv.x - mouse.x), mouseEffect * 0.8);
    }

    // Detect defects (sudden angle changes)
    let angleDiff = abs(atan2(sin(angle - prevAngle), cos(angle - prevAngle)));
    let defect = smoothstep(0.8, 2.2, angleDiff);

    // Store field + defect map
    textureStore(dataTextureA, gid.xy, vec4<f32>(angle, defect, 0.0, 0.0));

    // Visualization: flowing directional field with defect highlights
    let dir = vec2<f32>(cos(angle), sin(angle));
    let flow = vec3<f32>(0.5 + dir.x * 0.5, 0.5 + dir.y * 0.5, 0.6);

    // Defects glow
    let defectGlow = defect * (1.0 + treble * 0.8);
    let col = flow * (0.7 + defectGlow * 0.8);

    // Add subtle color shift based on audio
    let hueShift = mids * 0.3;
    let finalCol = mix(col, col * vec3<f32>(0.8, 1.1, 1.3), hueShift);

    let alpha = clamp(0.6 + defect * 0.7 + length(dir) * 0.2, 0.3, 1.15);
    let a = clamp(alpha, 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(finalCol * a, a));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(defect * 0.8 + 0.2, 0.0, 0.0, 0.0));
}