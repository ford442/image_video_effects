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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Params
    let maxSep = u.zoom_params.x * 0.05; // Max 5% screen width
    let focusOffset = u.zoom_params.y;
    let glitchStr = u.zoom_params.z;
    // Remap 0.0-1.0 to -0.2 to 0.2 radians
    let lensRot = (u.zoom_params.w - 0.5) * 0.4;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Separation Logic
    // Mouse X creates a horizontal bias (convergence shift)
    // Vertical UV creates a fake "ground plane" depth gradient

    let mouseBias = (mouse.x - 0.5) * 2.0;
    let depth = (uv.y - focusOffset) + mouseBias;

    var sepOffset = vec2<f32>(depth * maxSep, 0.0);

    // Glitch Effect
    if (glitchStr > 0.0) {
        // High frequency jitter based on Y and Time
        let jitter = sin(uv.y * 200.0 + time * 30.0) * cos(time * 15.0);
        // Random blocky steps
        let block = floor(uv.y * 20.0);
        let blockNoise = fract(sin(block * 12.9898 + time) * 43758.5453);

        let glitchFactor = jitter * 0.5 + blockNoise * 0.5;
        sepOffset.x = sepOffset.x + glitchFactor * glitchStr * 0.02;
    }

    // Rotation
    if (abs(lensRot) > 0.001) {
        let c = cos(lensRot);
        let s = sin(lensRot);
        sepOffset = vec2<f32>(
            sepOffset.x * c - sepOffset.y * s,
            sepOffset.x * s + sepOffset.y * c
        );
    }

    // Anaglyph Sampling
    // Red channel (Left eye approximation)
    let redUV = uv - sepOffset;
    // Cyan channel (Right eye approximation)
    let cyanUV = uv + sepOffset;

    // Check bounds to avoid streaking if needed, but sampler usually clamps/repeats
    // Depending on sampler configuration. Standard usually clamps to edge.

    let redColor = textureSampleLevel(readTexture, u_sampler, redUV, 0.0).r;
    let cyanColor = textureSampleLevel(readTexture, u_sampler, cyanUV, 0.0).gb;

    var finalColor = vec4<f32>(redColor, cyanColor.x, cyanColor.y, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
}
