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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;

    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Parameters
    let cellSizeBase = mix(10.0, 100.0, u.zoom_params.x);
    let cellSize = cellSizeBase * (1.0 + bass * 0.3);
    let spread = u.zoom_params.y * 2.0 * (1.0 + mids * 0.4);
    let aberration = u.zoom_params.z * 0.1 * (1.0 + treble * 0.5);
    let tint = u.zoom_params.w;

    // Mouse state
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let clickCount = u.config.y;

    // Gravity well: pull UV toward mouse
    let toMouse = (mouse - uv) * vec2<f32>(aspect, 1.0);
    let mouseDist = length(toMouse);
    let gravity = select(0.12, 0.35, mouseDown);
    let warp = normalize(toMouse) * gravity / (1.0 + mouseDist * 3.0);
    let warpedUV = uv + warp * 0.025;

    // Mosaic grid with audio jitter
    let gridUV = floor(warpedUV * cellSize) / cellSize;
    let cellCenter = gridUV + (0.5 / cellSize);
    let jitter = vec2<f32>(
        sin(time * 3.0 + gridUV.y * 12.0),
        cos(time * 2.5 + gridUV.x * 12.0)
    ) * mids * 0.015;
    let sampleCenter = cellCenter + jitter;

    // Projector direction from mouse to cell
    let vecToCell = (sampleCenter - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(vecToCell);
    var dir = normalize(vecToCell);
    if (dist < 0.0001) { dir = vec2<f32>(1.0, 0.0); }

    // Chromatic offsets with FFT multi-band splitting
    let baseOffset = dir * dist * spread * 0.1;
    let rOff = baseOffset + dir * aberration * (1.0 + bass);
    let gOff = baseOffset + dir * aberration * 0.3 * mids;
    let bOff = baseOffset - dir * aberration * (1.0 + treble * 0.6);

    let r = textureSampleLevel(readTexture, u_sampler, sampleCenter + rOff, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleCenter + gOff, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleCenter + bOff, 0.0).b;
    var color = vec3<f32>(r, g, b);

    // Cell vignette pulsing with bass
    let cellUV = fract(warpedUV * cellSize);
    let cellDist = distance(cellUV, vec2<f32>(0.5));
    let shape = smoothstep(0.5, 0.4 - bass * 0.06, cellDist);
    color = color * shape;

    // Light falloff + click shockwave
    let falloff = 1.0 / (1.0 + dist * 2.0);
    let shock = sin(mouseDist * 25.0 - clickCount * 1.5) * 0.5 + 0.5;
    let shockFade = exp(-mouseDist * 3.5);
    let light = falloff * (1.0 + shock * shockFade * 0.6);
    color = color * light;

    // Tint and audio brightness boost
    let tintColor = vec3<f32>(1.0, 0.85, 0.6) * tint;
    color = mix(color, color * tintColor + vec3<f32>(bass * 0.15, mids * 0.08, treble * 0.05), tint);
    color = color * (1.0 + bass * 0.25);

    // Depth parallax separation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthShift = (1.0 - depth) * 0.025;
    let depthOffset = dir * depthShift;
    let depthSample = textureSampleLevel(readTexture, u_sampler, sampleCenter + depthOffset, 0.0).rgb;
    color = mix(color, depthSample * shape * light, depth * 0.25);

    // Temporal feedback trail
    let feedbackUV = uv + warp * 0.008;
    let prev = textureSampleLevel(dataTextureC, u_sampler, feedbackUV, 0.0).rgb;
    let feedbackAmt = 0.12 + bass * 0.08;
    color = mix(color, prev * 0.96, feedbackAmt);

    let out = vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.5)), 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), out);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, global_id.xy, out);
}
