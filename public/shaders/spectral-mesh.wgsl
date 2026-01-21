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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GridDensity, y=DisplacementStrength, z=MouseRadius, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mouse = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let gridDensity = mix(20.0, 100.0, u.zoom_params.x);
    let heightScale = u.zoom_params.y * 2.0; // Strength of luma displacement
    let mouseRadius = u.zoom_params.z * 0.5; // Influence radius
    let colorShift = u.zoom_params.w; // Rotate hue

    // Base Sample
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Grid Logic
    // We want to displace the UV we check against the grid, NOT sample from displaced UV.
    // Actually, to make lines appear distorted, we usually distort the domain.

    // 1. Calculate Grid
    // Correct aspect for square grid cells
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);

    // Mouse Interaction
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let toMouse = uv_aspect - mouse_aspect;
    let dist = length(toMouse);
    let mouseForce = smoothstep(mouseRadius, 0.0, dist) * 0.2; // Push/Pull factor

    // Displace domain for grid check
    // "Pull" grid towards peaks (luminance) and mouse
    let displacement = vec2<f32>(0.0);

    // Simple fake normal for luma
    let eps = 0.01;
    let luma_x = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(eps, 0.0), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let luma_y = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, eps), 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
    let grad = vec2<f32>(luma_x - luma, luma_y - luma) / eps;

    var mouseDir = vec2<f32>(0.0);
    if (dist > 0.0001) {
        mouseDir = normalize(toMouse);
    }

    let distortedUV = uv_aspect - grad * heightScale * 0.05 - mouseDir * mouseForce;

    // Grid Lines
    let grid = fract(distortedUV * gridDensity);
    let lineThickness = 0.05 + 0.1 * luma; // Thicker lines at bright spots? Or constant?
    // Let's make lines constant thickness relative to cell, but smooth
    let lineAA = 0.1; // Softness

    // Check x and y lines
    let valX = smoothstep(lineThickness + lineAA, lineThickness, grid.x) + smoothstep(1.0 - (lineThickness + lineAA), 1.0 - lineThickness, grid.x);
    let valY = smoothstep(lineThickness + lineAA, lineThickness, grid.y) + smoothstep(1.0 - (lineThickness + lineAA), 1.0 - lineThickness, grid.y);

    let gridIntensity = clamp(valX + valY, 0.0, 1.0);

    // Height calculation for color
    // We base height on the luma at the current pixel + mouse influence
    let height = luma + mouseForce * 5.0;

    // Spectral Color
    let hue = height * 0.7 + colorShift + time * 0.1;
    let gridColor = hsv2rgb(vec3<f32>(hue, 0.8, 1.0));

    // Background
    // Darken original image
    let bg = color.rgb * 0.1;

    // Composite
    // Add grid on top
    let finalColor = mix(bg, gridColor, gridIntensity);

    // Add glowing dots at vertices
    let vertex = valX * valY; // Intersection
    finalColor += gridColor * vertex * 2.0;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(luma, 0.0, 0.0, 0.0));
}
