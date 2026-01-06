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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Glitch Reveal
// P1: Block Size
// P2: Scatter Amount (Chaos)
// P3: Reveal Radius
// P4: Glitch Jitter Speed

fn hash12(p: vec2<f32>) -> f32 {
	var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let mousePos = u.zoom_config.yz;

    // Parameters
    let blockSize = u.zoom_params.x * 0.2 + 0.01; // 0.01 to 0.21 UV size
    let scatter = u.zoom_params.y; // 0 to 1
    let revealRadius = u.zoom_params.z * 0.5 + 0.05;
    let speed = u.zoom_params.w * 10.0;

    // Grid Coordinates
    // Quantize UV to blocks
    let gridUV = floor(uv / blockSize);

    // Determine offset for this block
    // Add time to seed if speed > 0
    let seed = gridUV + floor(u.config.x * speed);
    let rand = hash22(seed);

    // Default Offset is random direction * scatter
    var blockOffset = (rand - 0.5) * scatter;

    // Check distance to mouse
    // Adjust mouse pos to aspect?
    // We want the REVEAL to be circular in screen space.
    let dVec = uv - mousePos;
    let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

    // Reveal Logic
    // If inside radius, reduce offset to 0.
    var mask = 0.0;
    if (dist < revealRadius) {
        // smooth edge
        mask = smoothstep(revealRadius * 0.8, revealRadius, dist);
    } else {
        mask = 1.0;
    }

    // Apply mask to offset
    // Inside (mask=0), offset is 0. Outside (mask=1), offset is full.
    blockOffset = blockOffset * mask;

    // Sample
    // Clamp to prevent wrapping artifacts
    let sampleUV = clamp(uv + blockOffset, vec2<f32>(0.0), vec2<f32>(1.0));

    // Color Glitch: occasionally swap channels on scattered blocks
    var color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    if (mask > 0.01 && scatter > 0.0) {
         if (rand.x > 0.8) {
             // Simple channel shift
             let r = textureSampleLevel(readTexture, u_sampler, clamp(sampleUV + vec2<f32>(0.01 * mask, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
             color = vec4<f32>(r, color.g, color.b, color.a);
         } else if (rand.x < 0.2) {
             // Invert?
             // color = vec4<f32>(1.0 - color.rgb, color.a);
         }
    }

    // Add a digital border around the revealed area
    let border = smoothstep(revealRadius, revealRadius + 0.01, dist) - smoothstep(revealRadius + 0.01, revealRadius + 0.02, dist);
    if (border > 0.0 && mask < 0.9) {
        color = mix(color, vec4<f32>(0.0, 1.0, 0.5, 1.0), border * 0.5);
    }

    textureStore(writeTexture, global_id.xy, color);
}
