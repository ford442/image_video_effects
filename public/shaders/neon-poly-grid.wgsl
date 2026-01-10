// ═══════════════════════════════════════════════════════════════
//  Neon Poly Grid
//  A glowing hexagonal grid that lights up on mouse interaction
//  and leaves a fading trail.
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GridScale, y=LineWidth, z=GlowStrength, w=DecaySpeed
  ripples: array<vec4<f32>, 50>,
};

// Hexagon distance function
fn hexDist(p: vec2<f32>) -> f32 {
    let p_abs = abs(p);
    return max(p_abs.x, p_abs.x * 0.5 + p_abs.y * 0.866025);
}

// Hexagon grid logic
fn hexGrid(uv: vec2<f32>, scale: f32) -> vec4<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let a = modulo(uv * scale, r) - h;
    let b = modulo(uv * scale + h, r) - h;

    let gv = select(b, a, length(a) < length(b));

    let x = hexDist(gv);
    let y = 0.5 - x; // Distance to edge

    // Calculate cell center for ID/Noise
    let id = uv * scale - gv;

    return vec4<f32>(x, y, id.x, id.y);
}

// Simple modulo for vec2
fn modulo(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Correct aspect ratio for grid
    let aspect = resolution.x / resolution.y;
    let uv_grid = vec2<f32>(uv.x * aspect, uv.y);

    // Params
    let scale = mix(10.0, 100.0, u.zoom_params.x);
    let lineWidth = mix(0.01, 0.1, u.zoom_params.y);
    let glowStrength = u.zoom_params.z * 2.0;
    let decay = mix(0.9, 0.99, u.zoom_params.w);

    // Hex Grid
    let hex = hexGrid(uv_grid, scale);
    let distToEdge = hex.y;

    // Mouse Interaction
    let mouse = u.zoom_config.yz;
    let mouse_grid = vec2<f32>(mouse.x * aspect, mouse.y);
    let distToMouse = distance(uv_grid, mouse_grid);

    // Activation based on mouse distance
    let mouseRadius = 0.2;
    let activation = smoothstep(mouseRadius, 0.0, distToMouse);

    // Add activation from clicks/ripples?
    // (Optional)

    // Persistence Logic (Trail)
    let historyColor = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let newTrail = max(historyColor.r * decay, activation);

    // Store new trail state
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newTrail, 0.0, 0.0, 1.0));

    // Render
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Grid Lines
    let lineGlow = smoothstep(lineWidth, 0.0, distToEdge);

    // Combine trail with grid
    // Grid lights up where trail is active
    let activeGrid = lineGlow * newTrail * glowStrength;

    // Base grid (dim)
    let baseGrid = lineGlow * 0.1;

    let gridColor = vec3<f32>(0.0, 1.0, 1.0) * activeGrid + vec3<f32>(0.2, 0.0, 0.5) * baseGrid;

    // Composite
    // Add grid on top of source, or multiply?
    // Let's add it.
    let finalColor = sourceColor.rgb + gridColor;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, 1.0));
}
