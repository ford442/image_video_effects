// ═══════════════════════════════════════════════════════════════════
//  Ferrofluid Spikes
//  Category: simulation
//  Features: mouse-driven, audio-reactive, generative-surface, metallic-highlights, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-31
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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i = i + 1) {
        sum = sum + amp * noise(p * freq);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let mousePos = u.zoom_config.yz;

    let magnetStrength = u.zoom_params.x * (1.0 + bass * 0.5);
    let spikeDensity = u.zoom_params.y;
    let fluidViscosity = u.zoom_params.z;
    let highlightSharpness = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;
    let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
    let aspectMouse = vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = length(aspectUV - aspectMouse);

    // Magnetic field falls off with distance
    let field = smoothstep(0.5, 0.0, dist) * magnetStrength;

    // Base liquid surface
    let liquid = fbm(uv * (8.0 + spikeDensity * 20.0) + time * 0.1, 4);

    // Spikes rise toward mouse
    let spikeNoise = fbm(uv * 15.0 + vec2<f32>(time * 0.2, 0.0), 3);
    let spikeHeight = spikeNoise * field * 2.0 * fluidViscosity;

    // Metallic specular highlights on spike tips
    let lightDir = normalize(vec2<f32>(0.3, 0.7));
    let normal = normalize(vec2<f32>(spikeNoise - 0.5, 0.5));
    let spec = pow(max(dot(normal, lightDir), 0.0), 4.0 + highlightSharpness * 20.0);

    // Audio adds turbulence
    let turb = noise(uv * 30.0 + time * 2.0) * bass * 0.2;

    // Color: dark fluid with silver highlights
    var color = vec3<f32>(0.02, 0.02, 0.04) + vec3<f32>(0.08, 0.08, 0.12) * liquid;
    color = color + vec3<f32>(0.6, 0.65, 0.7) * spec * field;
    color = color + vec3<f32>(0.1, 0.05, 0.15) * mids * spikeHeight;
    color = color + vec3<f32>(turb, turb * 0.5, turb * 0.8);

    let alpha = clamp(0.6 + field * 0.4 + spec * 0.3 + bass * 0.05, 0.0, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    textureStore(dataTextureA, global_id.xy, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(field, 0.0, 0.0, 0.0));
}
