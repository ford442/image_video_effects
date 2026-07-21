// ═══════════════════════════════════════════════════════════════
//  Rainbow Vector Field
//  Psychedelic polar rainbow field with audio-driven spectral rings.
//  Features: generative, polar-rainbow, mouse-driven, audio-reactive, upgraded-rgba
//  Outputs: writeTexture (color), writeDepthTexture (displacement), dataTextureA (feedback)
//  Pass 1 of 2 — feeds prismatic-feedback-loop.wgsl
// ═══════════════════════════════════════════════════════════════

fn custom_custom_mod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}


fn custom_custom_custom_mod(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

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

// ═══════════════════════════════════════════════════════════════
//  Rainbow Vector Field - PASS 1 of 2
//  Generates a psychedelic rainbow pattern and computes a 
//  displacement field (stored in depth texture) for Pass 2. 
//  
//  Outputs: 
//    - writeTexture: Rainbow color pattern
//    - writeDepthTexture: Displacement strength field
//  
//  Next Pass: prismatic-feedback-loop.wgsl
// ═══════════════════════════════════════════════════════════════

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=mouseX, y=mouseX, z=mouseY, w=clickIntensity (mapped)
  zoom_params: vec4<f32>,  // x=frequency, y=saturation, z=brightness, w=displacementScale
  ripples: array<vec4<f32>, 50>,
};

// Mapping notes: mouse coords in zoom_config.yz; clickIntensity in zoom_config.x

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);
    let clickIntensity = u.zoom_config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Polar coordinates with center
    var center = vec2<f32>(0.5, 0.5);
    let delta = uv - center;
    let angle = atan2(delta.y, delta.x);
    let dist = length(delta);

    // Mouse wave interference
    let mouseDist = length(uv - mousePos);
    let mouseWave = sin(mouseDist * u.zoom_params.x - time * 4.0) * clickIntensity * 0.5;

    // Rainbow hue: angle + distance + time + mouse influence
    // Bass drives radial spectral rings travelling outward from centre
    let ringPhase = dist * (18.0 + mids * 12.0) - time * 2.0;
    let rings = sin(ringPhase) * 0.5 + 0.5;
    let ringBand = pow(rings, 3.0) * bass * 0.6;

    let freq = u.zoom_params.x * (1.0 + mids * 0.4);
    let hue = (angle + dist * freq * 2.0 + time * 0.5 + mouseWave + ringBand) / (2.0 * 3.14159);
    let hueFract = fract(hue);

    // HSV to RGB with psychedelic saturation/brightness
    let h = hueFract * 6.0;
    let c = u.zoom_params.z * (1.0 + bass * 0.4); // brightness, bass-pumped
    let x = c * (1.0 - abs(custom_custom_mod(h, 2.0) - 1.0));

    var rainbow = vec3<f32>(0.0);
    if (h < 1.0) { rainbow = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0) { rainbow = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0) { rainbow = vec3<f32>(0.0, c, x); }
    else if (h < 4.0) { rainbow = vec3<f32>(0.0, x, c); }
    else if (h < 5.0) { rainbow = vec3<f32>(x, 0.0, c); }
    else { rainbow = vec3<f32>(c, 0.0, x); }

    // Desaturate towards center for depth
    let saturation = mix(0.3, 1.0, u.zoom_params.y);
    rainbow = mix(vec3<f32>(length(rainbow)), rainbow, saturation);

    // Ring crests bloom as bright spectral filaments
    rainbow += vec3<f32>(ringBand * 0.9, ringBand * 0.5, ringBand) * (0.4 + bass * 0.8);

    let brightness = dot(rainbow, vec3<f32>(0.299, 0.587, 0.114));

    // Alpha carries field energy: bright, audio-hot regions are most opaque
    let alpha = clamp(brightness * (0.7 + bass * 0.5) + ringBand, 0.0, 1.0);
    let finalOut = vec4<f32>(rainbow, alpha);

    textureStore(writeTexture, vec2<u32>(global_id.xy), finalOut);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalOut);

    // Compute displacement strength from brightness and mouse
    let displacement = brightness * u.zoom_params.w * (1.0 + bass * 0.35) + mouseWave * 2.0;

    // Store displacement strength in depth texture (used by Pass 2)
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(displacement, 0.0, 0.0, 0.0));
}