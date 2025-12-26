// --- HEX PULSE ---
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Params
    let baseSize = mix(50.0, 200.0, 1.0 - u.zoom_params.x); // Param 1: Base Scale (Higher value = smaller hexes)
    let pulseStrength = u.zoom_params.y;                    // Param 2: Pulse intensity
    let radius = u.zoom_params.z;                           // Param 3: Influence Radius
    let speed = u.zoom_params.w;                            // Param 4: Pulse Speed

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);

    let d = distance(uv * aspectVec, mouse * aspectVec);

    // Calculate dynamic scale based on distance
    // Pulse wave emanating from mouse? Or just pulsing locally based on distance?
    // Let's make the hex size pulse.

    let pulse = sin(time * (speed * 10.0) - d * 20.0) * 0.5 + 0.5; // 0 to 1

    // Influence mask
    let mask = smoothstep(radius, 0.0, d); // 1 at mouse, 0 at radius

    // Dynamic grid scale
    // If mask is high (near mouse), we apply pulse to the scale.
    // If pulseStrength is high, the size variation is large.

    // Target scale varies between baseSize and baseSize * (1 - pulseStrength)
    let currentScale = baseSize * (1.0 - (mask * pulseStrength * pulse));

    // Hex Grid Logic
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;

    let uvScaled = uv * aspectVec * currentScale;

    let uvA = uvScaled / r;
    let idA = floor(uvA + 0.5);
    let uvB = (uvScaled - h) / r;
    let idB = floor(uvB + 0.5);

    let centerA = idA * r;
    let centerB = idB * r + h;

    let distA = distance(uvScaled, centerA);
    let distB = distance(uvScaled, centerB);

    let center = select(centerB, centerA, distA < distB);
    let centerUV = center / currentScale / aspectVec;

    // Sample
    var color = textureSampleLevel(readTexture, u_sampler, centerUV, 0.0);

    // Add grid lines
    // Distance to center of hex
    let localDist = min(distA, distB);
    // Edge of hex is approx 0.5 in this space (depending on math, but let's eyeball)
    // Hex inner radius is 0.5 * sqrt(3) ~= 0.866? No, r.x is 1.0.
    // Actually, max distance in hex is 1/sqrt(3) ~= 0.577.

    let edgeDist = 0.5;
    let lineSmooth = 0.05 * currentScale / 50.0; // constant visual width

    // Outline near mouse
    if (mask > 0.1) {
       // Simple outline logic, not perfect hex distance but close enough for visual
       if (localDist > 0.45 && localDist < 0.55) {
           color = mix(color, vec4<f32>(1.0) - color, mask * 0.5);
       }
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);

    // Passthrough Depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
