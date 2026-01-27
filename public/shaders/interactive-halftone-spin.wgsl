// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

// Interactive Halftone Spin
// Param1: Scale
// Param2: Rotation Speed (Mouse Influence)
// Param3: Spread (CMYK separation)
// Param4: Contrast

fn rgb2cmyk(c: vec3<f32>) -> vec4<f32> {
    let k = 1.0 - max(max(c.r, c.g), c.b);
    if (k >= 1.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let invK = 1.0 / (1.0 - k);
    let C = (1.0 - c.r - k) * invK;
    let M = (1.0 - c.g - k) * invK;
    let Y = (1.0 - c.b - k) * invK;
    return vec4<f32>(C, M, Y, k);
}

fn cmyk2rgb(cmyk: vec4<f32>) -> vec3<f32> {
    let k = cmyk.w;
    let invK = 1.0 - k;
    let r = 1.0 - (cmyk.x * invK + k);
    let g = 1.0 - (cmyk.y * invK + k);
    let b = 1.0 - (cmyk.z * invK + k);
    return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotatedGrid(uv: vec2<f32>, angle: f32, scale: f32) -> f32 {
    let s = sin(angle);
    let c = cos(angle);
    let mat = mat2x2<f32>(c, -s, s, c);
    let st = mat * uv * scale;
    // Dot pattern: distance from center of cell
    let cell = fract(st) - 0.5;
    return length(cell) * 2.0; // 0.0 to ~1.414
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let uv_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let mouse = u.zoom_config.yz;
    let mouse_aspect = vec2<f32>(mouse.x * aspect, mouse.y);

    let scaleParam = u.zoom_params.x * 200.0 + 20.0;
    let rotParam = u.zoom_params.y * 3.14159 * 2.0; // Max rotation influence
    let spreadParam = u.zoom_params.z;
    let contrastParam = u.zoom_params.w * 2.0 + 0.5;

    let dist = distance(uv_aspect, mouse_aspect);
    let influence = smoothstep(0.4, 0.0, dist);

    // Dynamic rotation based on mouse influence
    let extraRot = influence * rotParam;

    // Sample source color
    let texColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Boost contrast
    let contrastColor = (texColor - 0.5) * contrastParam + 0.5;
    let cmyk = rgb2cmyk(clamp(contrastColor, vec3<f32>(0.0), vec3<f32>(1.0)));

    // Standard Angles (in radians)
    // C: 15 deg = 0.261
    // M: 75 deg = 1.309
    // Y: 0 deg = 0.0
    // K: 45 deg = 0.785

    // Apply spread: Shift angles apart based on parameter + mouse
    let s = spreadParam + influence;

    let angC = 0.261 + extraRot * 1.0;
    let angM = 1.309 + extraRot * 1.5 * s;
    let angY = 0.0 + extraRot * 0.5;
    let angK = 0.785 - extraRot * 1.0 * s;

    // Pattern Values (0.0 center to 1.0 edge)
    let pC = rotatedGrid(uv_aspect, angC, scaleParam);
    let pM = rotatedGrid(uv_aspect, angM, scaleParam);
    let pY = rotatedGrid(uv_aspect, angY, scaleParam);
    let pK = rotatedGrid(uv_aspect, angK, scaleParam);

    // Thresholding (Halftone function)
    // If (pattern value) < (ink density), draw ink.
    // Invert logic: 1.0 - distance.
    // Let's use simple step: step(pattern, sqrt(density)) for circle area

    // sqrt for area correction
    let outC = step(pC, sqrt(cmyk.x));
    let outM = step(pM, sqrt(cmyk.y));
    let outY = step(pY, sqrt(cmyk.z));
    let outK = step(pK, sqrt(cmyk.w));

    // Combine (Subtractive mixing)
    // Start white. Multiply by (1 - Ink) if ink is present?
    // Wait, step returns 1.0 if ink is present.
    // Cyan absorbs Red. Magenta absorbs Green. Yellow absorbs Blue. Black absorbs All.

    var finalRGB = vec3<f32>(1.0);

    // Cyan ink subtracts Red
    finalRGB.r = finalRGB.r * (1.0 - outC);
    // Magenta ink subtracts Green
    finalRGB.g = finalRGB.g * (1.0 - outM);
    // Yellow ink subtracts Blue
    finalRGB.b = finalRGB.b * (1.0 - outY);

    // Black subtracts all
    finalRGB = finalRGB * (1.0 - outK);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalRGB, 1.0));

    // Depth pass
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
