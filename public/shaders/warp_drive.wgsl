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
  config: vec4<f32>,       // x=Time, y=Ripples, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // Params
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Parameters
    // x: Warp Intensity (0.0 to 1.0)
    // y: Aberration Strength (0.0 to 1.0)
    // z: Center Brightness (0.0 to 1.0)
    // w: Samples (Step count) - mapped to e.g. 10 to 50

    let intensity = u.zoom_params.x * 0.2; // Max strength
    let aberration = u.zoom_params.y * 0.05;
    let brightness = u.zoom_params.z * 2.0;
    let samples = i32(u.zoom_params.w * 30.0 + 5.0); // 5 to 35 samples

    let mouse = u.zoom_config.yz;

    // Vector from pixel to mouse
    // We want to blur AWAY from the mouse (zoom blur)
    // So we sample along the line from uv to mouse.

    let dir = mouse - uv; // Direction towards mouse
    let dist = length(dir);

    var colorSum = vec3<f32>(0.0);
    var totalWeight = 0.0;

    // Dithering to break up banding
    let noise = fract(sin(dot(uv, vec2<f32>(12.9898, 78.233))) * 43758.5453);

    for (var i = 0; i < samples; i++) {
        let percent = (f32(i) + noise) / f32(samples);
        let weight = 1.0 - percent; // Samples closer to original pixel have more weight?
                                    // Or samples closer to mouse?
                                    // Standard radial blur: accumulate along the path.

        // We want the trail to be stronger near the source (uv) and fade as it goes to mouse?
        // Let's just average.

        let samplePos = uv + dir * percent * intensity; // Move towards mouse

        // Chromatic Aberration: sample channels at slightly different offsets
        let rPos = samplePos + dir * aberration * percent;
        let bPos = samplePos - dir * aberration * percent; // Opposite direction or just less/more?
        // Actually usually aberration scales with distance from center.
        // Here we just offset along the blur vector.

        let r = textureSampleLevel(readTexture, u_sampler, rPos, 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, bPos, 0.0).b;

        colorSum += vec3<f32>(r, g, b) * weight;
        totalWeight += weight;
    }

    var finalColor = colorSum / totalWeight;

    // Add center brightness (bloom/engine glow)
    // 1.0 at mouse, 0.0 far away
    let distAspect = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(mouse.x * aspect, mouse.y));
    let glow = exp(-distAspect * 5.0) * brightness;

    finalColor += vec3<f32>(glow * 0.8, glow * 0.9, glow * 1.0); // Blueish white tint

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
