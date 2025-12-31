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

fn get_luminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn character(uv: vec2<f32>, char_index: i32) -> f32 {
    let center = abs(uv - 0.5);
    let dist = length(uv - 0.5);
    var val = 0.0;

    // 0: Empty
    if (char_index == 0) {
        val = 0.0;
    }
    // 1: Dot
    else if (char_index == 1) {
        val = step(dist, 0.1);
    }
    // 2: Plus
    else if (char_index == 2) {
        val = step(max(center.x, center.y), 0.4) * step(min(center.x, center.y), 0.08); // Cross
    }
    // 3: Slash
    else if (char_index == 3) {
        val = step(abs((uv.x - 0.5) - (uv.y - 0.5)), 0.1) * step(abs(uv.x - 0.5), 0.4);
    }
    // 4: X
    else if (char_index == 4) {
        let d1 = abs((uv.x - 0.5) - (uv.y - 0.5));
        let d2 = abs((uv.x - 0.5) + (uv.y - 0.5));
        val = step(min(d1, d2), 0.08) * step(abs(uv.x - 0.5), 0.4);
    }
    // 5: Box
    else if (char_index >= 5) {
        val = step(max(center.x, center.y), 0.35); // Box outline?
        if (char_index > 5) {
             val = step(max(center.x, center.y), 0.4); // Solid block
        }
    }
    return val;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let gridSizeParam = 5.0 + u.zoom_params.x * 30.0; // 5 to 35
    let decodeRadius = u.zoom_params.y * 0.5; // 0 to 0.5 screen width
    let matrixSpeed = u.zoom_params.z;
    let globalMix = u.zoom_params.w; // 0 to 1

    let aspect = resolution.x / resolution.y;

    // Calculate Grid
    let gridUV = uv * vec2<f32>(resolution.x / gridSizeParam, resolution.y / gridSizeParam);
    let cellUV = fract(gridUV);
    let cellID = floor(gridUV);

    // Sample texture at center of cell for color/luminance
    let sampleUV = (cellID + 0.5) / vec2<f32>(resolution.x / gridSizeParam, resolution.y / gridSizeParam);
    let texColor = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).rgb;
    let lum = get_luminance(texColor);

    // Quantize luminance to char index (0-6)
    var charIdx = i32(lum * 6.99);

    // Add "Matrix" rain effect - shift char based on time and column
    let time = u.config.x * (1.0 + matrixSpeed * 5.0);
    let rain = fract(sin(cellID.x * 12.9898) * 43758.5453 + time * 0.5);
    if (rain > 0.9) {
        charIdx = (charIdx + 1) % 7;
        texColor = texColor * 1.5; // Highlight
    }

    let shape = character(cellUV, charIdx);

    // Matrix Color (Green/Black) or Tinted Original
    let matrixColor = vec3<f32>(0.0, 1.0, 0.2) * shape * lum;

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Decode Mask (smoothstep for soft edge)
    let decodeMask = smoothstep(decodeRadius, decodeRadius + 0.1, dist);

    // Final Mix:
    // If inside radius (dist < radius), decodeMask -> 0.0 (show original)
    // If outside, decodeMask -> 1.0 (show matrix)

    let originalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Mix based on globalMix param too. If globalMix is 0, show full matrix (masked by mouse).
    // If globalMix is 1, show full original.
    // Wait, let's make globalMix control the "Opacity of Matrix overlay".
    // Actually, let's make it "Decode Strength".

    // Let's stick to the prompt: Mouse responsive.
    // Base state: Matrix.
    // Mouse state: Clear.

    var finalColor = mix(originalColor, matrixColor, decodeMask);

    // Apply global opacity of effect
    // If globalMix is 0, effect is invisible (just original). If 1, effect is strong.
    // Let's map zoom_params.w to "Effect Strength"
    // finalColor = mix(originalColor, finalColor, globalMix);
    // Actually, usually W is "Mix" in my other shaders where 0 is original, 1 is effect.
    // So:
    finalColor = mix(originalColor, finalColor, u.zoom_params.w);

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));
}
