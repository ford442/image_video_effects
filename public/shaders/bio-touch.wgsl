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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Strength, y=Radius, z=Aberration, w=Darkness
  ripples: array<vec4<f32>, 50>,
};

// Includes from _hash_library.wgsl
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let k = vec2<f32>(
        dot(p, vec2<f32>(127.1, 311.7)),
        dot(p, vec2<f32>(269.5, 183.3))
    );
    return fract(sin(k) * 43758.5453);
}

fn voronoi(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);

    var minDist = 1.0;

    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let cellId = i + neighbor;
            let point = neighbor + hash22(cellId) - f;
            let dist = length(point);
            minDist = min(minDist, dist);
        }
    }

    return minDist;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    // Mouse Interaction
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w; // 1.0 if down

    // Correct aspect ratio for distance calculation
    let aspect = resolution.x / resolution.y;
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);

    // Params
    let glowRadius = u.zoom_params.x * 0.5; // 0.0 to 0.5
    let cellDensity = 10.0 + u.zoom_params.y * 50.0; // 10 to 60
    let colorShift = u.zoom_params.z;
    let pulseSpeed = u.zoom_params.w * 5.0;

    // Bio-Luminescence Logic
    // Only active near mouse
    let influence = smoothstep(glowRadius + 0.1, glowRadius, dist);

    // Animate voronoi
    let offset = vec2<f32>(sin(time * 0.5), cos(time * 0.4)) * 0.1;
    let v = voronoi((uv + offset) * cellDensity);

    // Invert voronoi for cell walls/nuclei
    let glow = 1.0 - smoothstep(0.0, 0.5, v);

    // Pulse
    let pulse = 0.5 + 0.5 * sin(time * pulseSpeed - dist * 10.0);

    // Combine
    let finalGlow = glow * influence * pulse * (1.0 + mouseDown * 2.0); // Boost on click

    // Sample Image
    let color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // Color Tinting
    var tint = vec3<f32>(0.2, 0.8, 0.6); // Default teal
    if (colorShift > 0.3) { tint = vec3<f32>(0.8, 0.2, 0.6); } // Pink
    if (colorShift > 0.6) { tint = vec3<f32>(0.2, 0.4, 0.9); } // Blue

    // Composite
    // Add glow to original color
    let outColor = color + tint * finalGlow;

    textureStore(writeTexture, global_id.xy, vec4<f32>(outColor, 1.0));
}
