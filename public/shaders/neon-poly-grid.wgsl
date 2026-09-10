// ═══════════════════════════════════════════════════════════════
//  Neon Poly Grid
//  A glowing hexagonal grid that lights up on mouse interaction
//  and leaves a fading trail.
//  Upgraded: 2026-09-10
//  Ideas: dual-lattice vertex glow; occupied-cell fill from the trail
//  A packing: trail in A.r (HEAD); ACES on writeTexture
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
    let dA = length(a);
    let dB = length(b);
    let gv = select(b, a, dA < dB);

    let x = hexDist(gv);
    let y = 0.5 - x; // Distance to edge
    let vertex = 1.0 - smoothstep(0.0, 0.04, abs(dA - dB));

    let id = uv * scale - gv;

    return vec4<f32>(y, vertex, id.x, id.y);
}

// Simple modulo for vec2
fn modulo(x: vec2<f32>, y: vec2<f32>) -> vec2<f32> {
    return x - y * floor(x / y);
}

fn soft_ceiling(color: vec3<f32>) -> vec3<f32> {
    let positive = max(color, vec3<f32>(0.0));
    let peak = max(positive.x, max(positive.y, positive.z));
    return positive / (1.0 + max(peak - 1.0, 0.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

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
    let distToEdge = hex.x;
    let vertex = hex.y;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        mouse = rawMouse;
        mouseVelocity = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 12.0;
    mouseVelocity += ((rawMouse - mouse) * (omega * omega) - mouseVelocity * (2.0 * omega)) * dt;
    mouse += mouseVelocity * dt;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = mouse.x;
        extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x;
        extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }
    let mouse_grid = vec2<f32>(mouse.x * aspect, mouse.y);
    let distToMouse = distance(uv_grid, mouse_grid);

    // Activation based on mouse distance
    let mouseRadius = 0.2;
    let activation = 1.0 - smoothstep(0.0, mouseRadius, distToMouse);

    var clickTrail = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 2.5) {
            let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
            let radius = length(delta);
            let ring = exp(-abs(radius - age * 0.14) * 70.0);
            let clickFill = 1.0 - smoothstep(0.0, 0.12, radius);
            clickTrail = max(clickTrail, max(ring, clickFill * exp(-age * 3.0)) * exp(-age * 0.8));
        }
    }

    let historyColor = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    let newTrail = clamp(max(historyColor.r * decay, max(activation, clickTrail)), 0.0, 1.0);

    // Store new trail state
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(newTrail, 0.0, 0.0, newTrail));

    // Render
    let sourceColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Grid Lines
    let lineGlow = 1.0 - smoothstep(0.0, lineWidth, distToEdge);

    // Combine trail with grid
    // Grid lights up where trail is active
    let activeGrid = lineGlow * newTrail * glowStrength;

    // Base grid (dim)
    let baseGrid = lineGlow * 0.1;

    let cellCode = u32(abs(hex.z * 17.0 + hex.w * 31.0));
    let fftVoice = clamp(plasmaBuffer[(cellCode % 8u) + 1u].x, 0.0, 1.0);
    let cyanVoice = vec3<f32>(0.0, 0.75 + fftVoice * 0.25, 1.0);
    let cellFill = (1.0 - lineGlow) * newTrail * 0.16;
    let vertexGlow = vertex * newTrail * glowStrength * 0.55;
    let gridColor = cyanVoice * activeGrid * (0.85 + fftVoice * 0.35)
        + vec3<f32>(0.2, 0.0, 0.5) * baseGrid
        + cyanVoice * cellFill
        + vec3<f32>(0.85, 0.95, 1.0) * vertexGlow;

    let finalColor = acesToneMap(soft_ceiling(sourceColor.rgb + gridColor));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, clamp(sourceColor.a + cellFill + vertexGlow * 0.2, 0.0, 1.0)));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let reliefDepth = clamp(depth_in + lineGlow * newTrail * 0.16, 0.0, 1.0);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(reliefDepth, 0.0, 0.0, 0.0));
}
