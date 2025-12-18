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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

fn hash21(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)),
                   hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)),
                   hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Params
    let spikeScale = mix(10.0, 50.0, u.zoom_params.x);
    let attractionStrength = u.zoom_params.y;
    let viscosity = u.zoom_params.z;
    let colorShift = u.zoom_params.w;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Vector to mouse
    let toMouse = (mouse - uv);
    let dist = length(toMouse * vec2<f32>(aspect, 1.0));

    // Normalized direction (handle zero length)
    var dir = vec2<f32>(0.0);
    if (length(toMouse) > 0.001) {
        dir = normalize(toMouse);
    }

    // Spike pattern: based on angle towards mouse
    let angle = atan2(dir.y, dir.x);
    // Noise based on angle and distance rings
    let spikeNoise = noise(vec2<f32>(angle * 10.0, dist * spikeScale - time));

    // Displace UVs towards mouse, modulated by spikes
    let force = smoothstep(0.5, 0.0, dist) * attractionStrength; // Stronger near mouse
    let spikeForce = force * (0.5 + 0.5 * spikeNoise); // Modulate

    // Viscosity adds "lag" or smoothing (simulated by blurring the noise domain in real sim, here just intensity)
    let finalDisplacement = dir * spikeForce * 0.2;

    let distortedUV = uv - finalDisplacement;

    var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Ferrofluid look: Metallic, dark, shiny highlights
    // Desaturate
    let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Make it dark
    var fluidColor = vec3<f32>(gray * 0.5);

    // Add specular highlights on "ridges" (where noise gradient is high)
    let ridge = smoothstep(0.6, 0.8, spikeNoise) * force;
    fluidColor += vec3<f32>(ridge);

    // Mix with original based on distance (effect fades out far away)
    let effectMask = smoothstep(0.6, 0.3, dist);

    var finalColor = mix(color.rgb, fluidColor, effectMask);

    // Color shift param
    if (colorShift > 0.0) {
        finalColor = mix(finalColor, vec3<f32>(finalColor.b, finalColor.r, finalColor.g), colorShift);
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, 1.0));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
