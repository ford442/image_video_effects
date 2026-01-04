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
  config: vec4<f32>;       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>;  // x=mouseX, y=mouseX, z=mouseY, w=clickIntensity (mapped)
  zoom_params: vec4<f32>;  // x=frequency, y=saturation, z=brightness, w=displacementScale
  ripples: array<vec4<f32>, 50>;
};

// Mapping notes: mouse coords in zoom_config.yz; clickIntensity in zoom_config.x

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);
    let clickIntensity = u.zoom_config.x;

    // Polar coordinates with center
    let center = vec2<f32>(0.5, 0.5);
    let delta = uv - center;
    let angle = atan2(delta.y, delta.x);
    let dist = length(delta);

    // Mouse wave interference
    let mouseDist = length(uv - mousePos);
    let mouseWave = sin(mouseDist * u.zoom_params.x - time * 4.0) * clickIntensity * 0.5;

    // Rainbow hue: angle + distance + time + mouse influence
    let hue = (angle + dist * u.zoom_params.x * 2.0 + time * 0.5 + mouseWave) / (2.0 * 3.14159);
    let hueFract = fract(hue);

    // HSV to RGB with psychedelic saturation/brightness
    let h = hueFract * 6.0;
    let c = u.zoom_params.z; // brightness
    let x = c * (1.0 - abs(mod(h, 2.0) - 1.0));

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

    // Store rainbow color
    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(rainbow, 1.0));

    // Compute displacement strength from brightness and mouse
    let brightness = dot(rainbow, vec3<f32>(0.299, 0.587, 0.114));
    let displacement = brightness * u.zoom_params.w + mouseWave * 2.0;

    // Store displacement strength in depth texture (used by Pass 2)
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(displacement, 0.0, 0.0, 0.0));
}