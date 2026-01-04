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
  config: vec4<f32>;       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>;  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>;  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>;
};

// Mapping notes: this shader expects mouse in `zoom_config.yz`,
// `zoom_config.x` may contain last click time, and `zoom_params` holds general floats:
// zoom_params.x = zoomRate, zoom_params.y = spiralTightness, zoom_params.z = colorShift, zoom_params.w = feedbackStrength

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv_raw = vec2<f32>(global_id.xy);
    let uv = (uv_raw - resolution * 0.5) / min(resolution.x, resolution.y);
    let time = u.config.x;
    let mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);

    // Polar coordinates from mouse focal point (centered)
    let focalOffset = uv - (mousePos - vec2<f32>(0.5, 0.5)) * 2.0;
    var polar = vec2<f32>(length(focalOffset), atan2(focalOffset.y, focalOffset.x));

    // Perpetual zoom and rotation
    let zoomRate = u.zoom_params.x + sin(time * 0.1) * 0.1;
    polar.x = fract(polar.x + time * zoomRate * 0.05);
    polar.y = polar.y + time * u.zoom_config.w * 0.2 + polar.x * u.zoom_params.y;

    // Convert back to cartesian
    let newUV = vec2<f32>(polar.x * cos(polar.y), polar.x * sin(polar.y));
    let sampleUV = newUV * 0.5 + 0.5;

    // Multi-layered spiral sampling
    var finalColor = vec3<f32>(0.0, 0.0, 0.0);
    for (var i: u32 = 0u; i < 3u; i = i + 1u) {
        let fi = f32(i);
        let layerUV = sampleUV + vec2<f32>(sin(time + fi), cos(time + fi)) * 0.1;
        let color = textureSampleLevel(readTexture, u_sampler, fract(layerUV), 0.0).rgb;
        let hueShift = u.zoom_params.z + fi * 0.33;
        finalColor = finalColor + color * (1.0 + sin(time * 2.0 + hueShift)) * 0.5;
    }

    // Mouse click creates shockwave distortion
    let timeSinceClick = time - u.zoom_config.x;
    if (timeSinceClick > 0.0 && timeSinceClick < 2.0) {
        let clickDist = length(uv - (mousePos - vec2<f32>(0.5, 0.5)) * 2.0);
        let shockwave = sin(clickDist * 20.0 - timeSinceClick * 10.0) * (1.0 - timeSinceClick * 0.5);
        finalColor = finalColor * (1.0 + shockwave * 0.5);
    }

    // Kaleidoscopic symmetry
    let angle = atan2(newUV.y, newUV.x);
    let segments = 6.0 + floor(sin(time * 0.5) * 3.0);
    let kaleidoAngle = floor(angle * segments / (2.0 * 3.14159)) * (2.0 * 3.14159) / segments;
    let symUV = vec2<f32>(cos(kaleidoAngle), sin(kaleidoAngle)) * length(newUV);
    let symColor = textureSampleLevel(readTexture, u_sampler, symUV * 0.5 + 0.5, 0.0).rgb;

    finalColor = mix(finalColor, symColor, 0.6);

    // Write final color
    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(finalColor, 1.0));

    // Write a simple depth value (near center = closer)
    let depth = 1.0 - clamp(length(newUV), 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}