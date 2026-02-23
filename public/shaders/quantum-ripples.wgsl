// ---------------------------------------------------------------
//  Quantum Ripples – Mouse-driven wave simulation
// ---------------------------------------------------------------
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

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,       // x=Freq, y=Speed, z=Amp, w=Color
  ripples:     array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w; // 1.0 if down

    // Params
    let freq = u.zoom_params.x * 20.0 + 2.0; // 2 to 22
    let speed = u.zoom_params.y * 5.0;       // 0 to 5
    let amp = u.zoom_params.z * 0.1;         // 0 to 0.1
    let colorShift = u.zoom_params.w;

    // Calculate distance from mouse, corrected for aspect ratio
    let aspect = resolution.x / resolution.y;
    let dx = (uv.x - mousePos.x) * aspect;
    let dy = uv.y - mousePos.y;
    let dist = sqrt(dx*dx + dy*dy);

    // Wave calculation
    // Continuous waves radiating from mouse
    let wave = sin(dist * freq - time * speed);
    let waveFalloff = 1.0 / (1.0 + dist * 5.0); // Decay with distance

    // Displacement
    let dir = normalize(vec2<f32>(dx, dy));
    // If very close to center, dir might be NaN, but dist is small so displacement small.
    // Safe normalize:
    let safeDir = select(dir, vec2<f32>(0.0, 0.0), dist < 0.001);

    let displacement = safeDir * wave * amp * waveFalloff;

    // Boost effect if mouse is down
    let activeAmp = select(1.0, 2.0, mouseDown > 0.5);
    let finalDisplacement = displacement * activeAmp;

    let srcUV = uv - finalDisplacement;

    // Sample texture
    let color = textureSampleLevel(readTexture, u_sampler, srcUV, 0.0);

    // Color shift based on wave
    var outCol = color.rgb;
    if (colorShift > 0.0) {
        let shift = wave * colorShift * waveFalloff;
        outCol.r += shift;
        outCol.b -= shift;
    }

    // Store
    textureStore(writeTexture, gid.xy, vec4<f32>(outCol, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
