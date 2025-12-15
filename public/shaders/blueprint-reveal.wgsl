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

fn sobel(uv: vec2<f32>, res: vec2<f32>) -> f32 {
    let x = 1.0 / res.x;
    let y = 1.0 / res.y;

    // Sample neighbors (luminance)
    let tl = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x, -y), 0.0).rgb, vec3(0.333));
    let t  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( 0.0, -y), 0.0).rgb, vec3(0.333));
    let tr = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x, -y), 0.0).rgb, vec3(0.333));
    let l  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x,  0.0), 0.0).rgb, vec3(0.333));
    let r  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x,  0.0), 0.0).rgb, vec3(0.333));
    let bl = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x,  y), 0.0).rgb, vec3(0.333));
    let b  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( 0.0,  y), 0.0).rgb, vec3(0.333));
    let br = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x,  y), 0.0).rgb, vec3(0.333));

    let gx = tl * -1.0 + tr * 1.0 + l * -2.0 + r * 2.0 + bl * -1.0 + br * 1.0;
    let gy = tl * -1.0 + t * -2.0 + tr * -1.0 + bl * 1.0 + b * 2.0 + br * 1.0;

    return sqrt(gx * gx + gy * gy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let edgeStrength = mix(0.5, 5.0, u.zoom_params.x);
    let gridOpacity = u.zoom_params.y;
    let radius = mix(0.05, 0.6, u.zoom_params.z);
    let softness = mix(0.01, 0.3, u.zoom_params.w);

    // Mouse Info
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2(aspect, 1.0);
    let dist = length(distVec);

    // Reveal Mask (1.0 near mouse, 0.0 away)
    let revealMask = 1.0 - smoothstep(radius, radius + softness, dist);

    // Blueprint Effect
    let edgeVal = sobel(uv, resolution) * edgeStrength;
    // Blue background + White edges
    var blueprint = vec3(0.05, 0.1, 0.4) + vec3(0.8, 0.9, 1.0) * edgeVal;

    // Grid Overlay
    let gridSize = 40.0;
    let gridLineX = smoothstep(0.9, 0.95, sin(uv.x * gridSize * aspect * 3.14159));
    let gridLineY = smoothstep(0.9, 0.95, sin(uv.y * gridSize * 3.14159));
    let grid = max(gridLineX, gridLineY) * gridOpacity * 0.3;
    blueprint += vec3(grid);

    // Real Image
    let realColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Composite
    let finalColor = mix(blueprint, realColor, revealMask);

    textureStore(writeTexture, global_id.xy, vec4(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4(depth, 0.0, 0.0, 0.0));
}
