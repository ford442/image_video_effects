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
  zoom_params: vec4<f32>,  // x=Radius, y=Speed, z=Density, w=Glow
  ripples: array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mousePos = u.zoom_config.yz;
    let time = u.config.x;

    // Parameters
    let radius = max(0.01, u.zoom_params.x * 0.4);
    let speed = u.zoom_params.y * 2.0;
    let density = max(10.0, u.zoom_params.z * 150.0);
    let glow = u.zoom_params.w * 2.0;

    // Sample video
    let videoColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luminance = dot(videoColor, vec3<f32>(0.299, 0.587, 0.114));

    // Calculate Reveal Mask
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Mask: 1.0 inside radius (reveal), 0.0 outside (matrix)
    // Smooth transition between radius-0.05 and radius
    let mask = 1.0 - smoothstep(max(0.0, radius - 0.05), radius, dist);

    // Matrix Rain Effect
    // Grid columns
    let colIndex = floor(uv.x * density);
    let colUVX = colIndex / density;

    // Random speed per column
    let colRandom = hash12(vec2<f32>(colIndex, 0.0));
    let fallSpeed = (0.5 + 0.5 * colRandom) * speed;

    // Vertical flow
    let yFlow = uv.y + time * fallSpeed;

    // Grid rows (characters)
    let rowDensity = density * aspect; // Square cells
    let rowIndex = floor(yFlow * rowDensity);

    // Random character brightness/existence
    let charRandom = hash12(vec2<f32>(colIndex, rowIndex));

    // Glyph shape (simple box or pattern)
    // Sub-UV within cell
    let cellUV = fract(vec2<f32>(uv.x * density, yFlow * rowDensity));

    // Simple pixelated look
    let pixelCode = step(0.5, hash12(vec2<f32>(colIndex, rowIndex) + floor(cellUV * 3.0)));

    // Blink effect
    let blink = step(0.95, fract(time * 5.0 + charRandom * 10.0));

    // Base Matrix Color (Green)
    var matrixColor = vec3<f32>(0.0, 1.0, 0.4);

    // Modulate by video luminance
    let codeBrightness = pixelCode * luminance;

    // Make brighter spots have white text, darker have green
    matrixColor = mix(matrixColor, vec3<f32>(1.0), luminance * luminance);

    // Apply brightness
    let finalMatrix = matrixColor * codeBrightness * (1.0 + blink * glow);

    // Composite
    var finalColor = mix(finalMatrix, videoColor, mask);

    // Add edge glow (white ring)
    let ring = 1.0 - smoothstep(0.0, 0.02, abs(dist - radius));
    finalColor += vec3<f32>(0.5, 1.0, 0.8) * ring * glow;

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
