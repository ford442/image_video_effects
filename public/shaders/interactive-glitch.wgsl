@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;

struct Uniforms {
  config: vec4<f32>,              // time, rippleCount, resolutionX, resolutionY
  zoom_config: vec4<f32>,         // time, mouseX, mouseY, mouseDown
  zoom_params: vec4<f32>,         // param1, param2, param3, param4
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(3) var<uniform> u: Uniforms;

// Hash functions from library
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let k = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(k) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Params
    let intensity = u.zoom_params.x;      // Base Glitch Intensity
    let radius = u.zoom_params.y;         // Mouse Influence Radius
    let speed = u.zoom_params.z;          // Glitch Speed
    let blockScale = u.zoom_params.w;     // Block Size

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Calculate influence based on mouse distance
    var influence = 0.0;
    if (radius > 0.0) {
        influence = 1.0 - smoothstep(0.0, radius, dist);
    }

    // Amplify if mouse is down
    if (mouseDown > 0.5) {
        influence *= 2.0;
    }

    // Combine base intensity and mouse influence
    let totalIntensity = mix(intensity * 0.2, 1.0, influence * intensity); // Mouse heavily boosts intensity

    if (totalIntensity < 0.01) {
        let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
        textureStore(writeTexture, global_id.xy, color);
        return;
    }

    // Generate glitch blocks
    let blockSize = max(0.01, blockScale * 0.2);
    let blockGrid = floor(uv / blockSize);
    let blockTime = floor(time * (speed * 10.0 + 1.0));

    let noise = hash21(blockGrid + vec2<f32>(blockTime * 0.1));

    var offset = vec2<f32>(0.0);
    var colorShift = 0.0;

    if (noise < totalIntensity) {
        // Random offset for this block
        let shift = (hash22(blockGrid + vec2<f32>(blockTime)) - 0.5) * 0.1 * totalIntensity;
        offset = shift;

        // Random color channel shift
        if (hash21(blockGrid + vec2<f32>(12.34)) < 0.5) {
            colorShift = totalIntensity * 0.05;
        }
    }

    // Additional horizontal scanline tears near mouse
    let scanLine = floor(uv.y * 50.0 + time * speed * 20.0);
    let scanNoise = hash21(vec2<f32>(scanLine, floor(time * 10.0)));
    if (scanNoise < totalIntensity * 0.5) {
        offset.x += (scanNoise - 0.5) * 0.2 * totalIntensity;
    }

    // Apply chromatic aberration with offset
    let r = textureSampleLevel(readTexture, u_sampler, uv + offset + vec2<f32>(colorShift, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + offset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + offset - vec2<f32>(colorShift, 0.0), 0.0).b;

    textureStore(writeTexture, global_id.xy, vec4<f32>(r, g, b, 1.0));
}
