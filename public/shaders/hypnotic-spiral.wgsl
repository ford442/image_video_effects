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
  config: vec4<f32>;
  zoom_config: vec4<f32>;
  zoom_params: vec4<f32>;
  ripples: array<vec4<f32>, 50>;
};

// Mapping notes: mouse in zoom_config.yz; zoom_params hold spiral_params: x=arms, y=rotationSpeed, z=colorCycle, w=warpIntensity

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv_raw = vec2<f32>(global_id.xy);
    let uv = (uv_raw - resolution * 0.5) / min(resolution.x, resolution.y);
    let time = u.config.x;
    let mousePos = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) - resolution * 0.5) / min(resolution.x, resolution.y);

    // Breathing radius
    let breathe = sin(time * u.zoom_config.w) * 0.3 + 1.0;
    let radius = length(uv) * breathe;

    // Spiral angle with mouse twist
    let baseAngle = atan2(uv.y, uv.x);
    let twist = 1.0 / (length(uv - mousePos) * u.zoom_params.w + 0.1);
    let twistedAngle = baseAngle + radius * u.zoom_params.y * u.zoom_config.w * twist;

    // Multi-armed spiral
    let arms = max(1.0, u.zoom_params.x);
    let spiralPattern = sin(arms * twistedAngle - time * u.zoom_params.y + radius * 10.0);
    let spiralMask = smoothstep(-0.2, 0.2, spiralPattern);

    // Color cycling based on angle and radius
    let hue = (twistedAngle + time * u.zoom_params.z) / (2.0 * 3.14159);
    let saturation = 1.0 - radius * 0.5;
    let value = spiralMask * (1.0 - radius * 0.3);

    let rgb = hsv2rgb(fract(hue), saturation, value);

    // Add center glow
    let centerDist = length(uv);
    let glow = exp(-centerDist * 3.0) * sin(time * 5.0) * 0.5 + 0.5;
    var color = rgb + vec3<f32>(1.0, 0.8, 0.5) * glow * (1.0 - radius);

    // Sample texture with spiral distortion
    let distortedUV = vec2<f32>(
        spiralMask * cos(twistedAngle) * 0.5 + 0.5,
        spiralMask * sin(twistedAngle) * 0.5 + 0.5
    );
    let texColor = textureSampleLevel(readTexture, u_sampler, clamp(distortedUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;

    let finalColor = mix(color, texColor, 0.3);

    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    let depth = 1.0 - clamp(radius, 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}