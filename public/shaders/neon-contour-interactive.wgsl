// ────────────────────────────────────────────────────────────────────────────────
//  Neon Contour Interactive
//  Edge detection with neon glow that reacts to mouse proximity.
// ────────────────────────────────────────────────────────────────────────────────
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var feedbackOut: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var normalBuf:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var feedbackTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=time, y=mouseX, z=mouseY, w=click
  zoom_params: vec4<f32>,       // x=Threshold, y=Glow, z=CycleSpeed, w=Pulse
  ripples:     array<vec4<f32>, 50>,
};

// Sobel kernels
const gx: array<f32, 9> = array<f32, 9>(-1.0, 0.0, 1.0, -2.0, 0.0, 2.0, -1.0, 0.0, 1.0);
const gy: array<f32, 9> = array<f32, 9>(-1.0, -2.0, -1.0, 0.0, 0.0, 0.0, 1.0, 2.0, 1.0);

fn getLuminance(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let uv = vec2<f32>(gid.xy) / dims;
    let texelSize = 1.0 / dims;
    let time = u.config.x;

    // Params
    let threshold = u.zoom_params.x;
    let glowIntensity = u.zoom_params.y * 5.0;
    let cycleSpeed = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.w;

    let mouse = u.zoom_config.yz; // 0-1 normalized
    let mouseDown = u.zoom_config.w;

    // Correct aspect ratio for distance
    let aspect = dims.x / dims.y;
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Mouse interaction: Lower threshold near mouse
    let localThreshold = threshold * smoothstep(0.0, 0.4, dist);

    // Sobel Edge Detection
    var edgeX = 0.0;
    var edgeY = 0.0;

    for(var i = -1; i <= 1; i++) {
        for(var j = -1; j <= 1; j++) {
            let offset = vec2<f32>(f32(i), f32(j)) * texelSize;
            let c = textureSampleLevel(videoTex, videoSampler, uv + offset, 0.0).rgb;
            let luma = getLuminance(c);
            let idx = (j + 1) * 3 + (i + 1);
            edgeX += luma * gx[idx];
            edgeY += luma * gy[idx];
        }
    }

    let edge = sqrt(edgeX * edgeX + edgeY * edgeY);
    let isEdge = smoothstep(localThreshold, localThreshold + 0.05, edge);

    let original = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;

    // Neon Color Calculation
    // Base hue rotates with time
    let baseHue = fract(time * cycleSpeed * 0.1);
    // Hue shift based on edge direction or intensity
    let hue = fract(baseHue + edge * 2.0 + dist * 0.5);

    let pulse = sin(time * pulseSpeed * 5.0) * 0.5 + 0.5;
    let neonColor = hsv2rgb(vec3<f32>(hue, 1.0, 1.0));

    // Combine
    var finalColor = mix(original * 0.2, neonColor, isEdge * (glowIntensity + pulse));

    // Add extra glow near mouse
    if (dist < 0.2) {
        finalColor += neonColor * (0.2 - dist) * 2.0 * glowIntensity;
    }

    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
}
