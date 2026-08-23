// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotate2d(angle: f32) -> mat2x2<f32> {
    var s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn mod_val(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let pixel = vec2<i32>(global_id.xy);

    let scale_param = u.zoom_params.x;
    let rotation_param = u.zoom_params.y;
    let twist_param = u.zoom_params.z;
    let mix_param = u.zoom_params.w;

    // Depth awareness: nearer objects have smaller triangles
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let cells = (scale_param * 50.0 + 5.0) / (1.0 + depth * 1.5);

    // Audio reactivity: bass drives rotation speed, treble adds zoom jitter
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let time = u.config.x;
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(aspect, 1.0)) - age * 0.38) * 60.0);
    }
    let angle = rotation_param * 6.28
        + (1.0 - smoothstep(0.0, 0.5, distance(uv, mouse))) * twist_param * 3.14
        + bass * 1.5 + held * distance(uv, mouse) * 2.0;
    let jitter = 1.0 + treble * 0.2 * sin(time * 10.0) + clickFront * 0.12;

    // Triangle grid logic
    var p = uv;
    p.x *= aspect;

    let skew_mat = mat2x2<f32>(1.0, 0.0, -0.57735, 1.1547);
    let unskew_mat = mat2x2<f32>(1.0, 0.0, 0.5, 0.866025);

    let uv_scaled = p * cells * jitter;
    let skewed_uv = uv_scaled * skew_mat;
    let i_uv = floor(skewed_uv);
    let f_uv = fract(skewed_uv);

    var tri_offset = vec2<f32>(0.0);
    if (f_uv.x > f_uv.y) {
        tri_offset = vec2<f32>(0.66, 0.33);
    } else {
        tri_offset = vec2<f32>(0.33, 0.66);
    }

    let tri_center_skewed = i_uv + tri_offset;
    var tri_center = tri_center_skewed * unskew_mat;
    tri_center = tri_center / (cells * jitter);
    tri_center.x /= aspect;

    var sample_uv = tri_center;
    let uv_centered = sample_uv - 0.5;
    let rot_mat = rotate2d(angle);
    sample_uv = 0.5 + uv_centered * rot_mat;
    sample_uv = clamp(sample_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    // Chromatic aberration on triangle boundaries
    let boundaryDist = abs(f_uv.x - f_uv.y);
    let caStrength = (1.0 - smoothstep(0.0, 0.15, boundaryDist)) * 0.012 * (1.0 + depth);
    let rUV = clamp(sample_uv + vec2<f32>(caStrength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(sample_uv - vec2<f32>(caStrength, 0.0), vec2<f32>(0.0), vec2<f32>(1.0));

    let rSample = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let gSample = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).g;
    let bSample = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    var color = vec3<f32>(rSample, gSample, bSample);
    let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    color = mix(orig, color, mix_param);
    let seamRunner = sin((f_uv.x + f_uv.y) * 12.0 - time * (3.0 + mids * 5.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + seamRunner * 2.0 + time);
    color += spectral * ((1.0 - smoothstep(0.0, 0.12, boundaryDist)) * 0.12 + clickFront * 0.22);

    // Edge darkening toward triangle boundaries
    let edgeDarken = 1.0 - boundaryDist * 0.6;
    color = color * edgeDarken;

    // Temporal mosaic blending
    let prev = textureLoad(dataTextureC, pixel, 0).rgb;
    let decay = 0.8;
    color = mix(color, prev, decay * (1.0 - boundaryDist));

    // ACES tone mapping
    color = acesToneMap(color);

    // Semantic alpha: depth-based opacity with boundary transparency
    let alpha = mix(0.45, 1.0, depth) * mix(0.75, 1.0, 1.0 - boundaryDist * 3.0);

    let finalPixel = vec4<f32>(color, alpha);
    textureStore(writeTexture, pixel, finalPixel);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, finalPixel);
}
