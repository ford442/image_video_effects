// ----------------------------------------------------------------
// Fractal Chrono-Dendrite Forge
// Category: generative
// ----------------------------------------------------------------

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=Param
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// CONSTANTS & UTILITIES
// ----------------------------------------------------------------
const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 120;
const MAX_DIST: f32 = 100.0;
const SURF_DIST: f32 = 0.001;

// Rotations, Hash, and Noise functions
fn rot(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

// ----------------------------------------------------------------
// SCENE SDF
// ----------------------------------------------------------------
fn map(p_in: vec3<f32>, time: f32, mouse_pos: vec2<f32>, complexity: f32, entropy: f32, gravity: f32, bass: f32) -> f32 {
    var p = p_in;

    // Spacetime Distortion (Mouse gravity)
    // The cursor position acts as a gravitational singularity.
    let m_dist = length(p.xy - mouse_pos);
    let twist_amt = exp(-m_dist * 0.5) * gravity * 2.0;
    p = vec3<f32>(rot(twist_amt * sin(time)) * p.xy, p.z);

    // Global rotation and movement
    p = vec3<f32>(rot(time * 0.1) * p.xy, p.z);
    p = vec3<f32>(p.x, rot(time * 0.15) * p.yz);

    var d = 1000.0;

    // Fractal Spanning Trees: L-system inspired 3D recursive paths
    var scale = 1.0;
    let iterations = i32(mix(2.0, 5.0, complexity));
    var p_fract = p;

    for (var i = 0; i < iterations; i++) {
        p_fract = abs(p_fract) - vec3<f32>(0.5, 0.4, 0.6) * (1.0 + sin(time * entropy + f32(i)) * 0.2);
        p_fract = vec3<f32>(rot(0.5 + f32(i) * 0.1) * p_fract.xy, p_fract.z);
        p_fract = vec3<f32>(p_fract.x, rot(0.7 - f32(i) * 0.15) * p_fract.yz);
        scale *= 1.5;
        p_fract *= 1.5;

        let cylinder = length(p_fract.xy) - (0.1 + bass * 0.2) * (1.0 - f32(i) / f32(iterations));
        d = min(d, cylinder / scale);
    }

    // Chronos Node Intersections (Apollonian gasket-like spheres at junctions)
    let node_dist = length(p_fract) - (0.3 + bass * 0.5);
    d = max(d, -node_dist / scale); // Subtraction for hollow intersections

    return d;
}

// ----------------------------------------------------------------
// NORMALS & SHADING
// ----------------------------------------------------------------
fn getNormal(p: vec3<f32>, time: f32, mouse_pos: vec2<f32>, complexity: f32, entropy: f32, gravity: f32, bass: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, mouse_pos, complexity, entropy, gravity, bass) - map(p - e.xyy, time, mouse_pos, complexity, entropy, gravity, bass),
        map(p + e.yxy, time, mouse_pos, complexity, entropy, gravity, bass) - map(p - e.yxy, time, mouse_pos, complexity, entropy, gravity, bass),
        map(p + e.yyx, time, mouse_pos, complexity, entropy, gravity, bass) - map(p - e.yyx, time, mouse_pos, complexity, entropy, gravity, bass)
    ));
}

// Spectral Interference colors for bismuth look
fn getBismuthColor(t: f32, dispersion: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0) * dispersion;
    let d = vec3<f32>(0.0, 0.33, 0.67);
    return a + b * cos(6.28318 * (c * t + d));
}

// ----------------------------------------------------------------
// MAIN RENDER LOOP
// ----------------------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // UI Sliders mapped to zoom_params
    let complexity = u.zoom_params.x; // Dendrite Complexity
    let entropy = u.zoom_params.y;    // Entropy Pulse Rate
    let dispersion = u.zoom_params.z; // Spectral Dispersion
    let gravity = u.zoom_params.w;    // Gravity Well Strength

    // Audio reaction
    let bass = plasmaBuffer[0].x;

    // Mouse Interaction
    // In our system, u.zoom_config.y and z typically hold mouse X/Y normalized coordinates or similar interaction data.
    // Let's interpret them as a position offset.
    let mouse_pos = (u.zoom_config.yz * 2.0 - 1.0) * vec2<f32>(resolution.x/resolution.y, 1.0);

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Raymarching
    var d0 = 0.0;
    var col = vec3<f32>(0.0);

    for(var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * d0;
        let d = map(p, time, mouse_pos, complexity, entropy, gravity, bass);

        if(d < SURF_DIST) {
            let n = getNormal(p, time, mouse_pos, complexity, entropy, gravity, bass);

            // Bismuth spectral dispersion shading
            let view_dir = -rd;
            let ndotv = max(dot(n, view_dir), 0.0);

            // Multiple layers of fractional noise control the thickness of an imaginary thin-film layer
            let interference_t = ndotv + sin(length(p) * 5.0 + time * entropy) * 0.2;
            let albedo = getBismuthColor(interference_t, dispersion);

            // Lighting
            let light_pos = vec3<f32>(2.0, 4.0, -3.0);
            let l = normalize(light_pos - p);
            let dif = max(dot(n, l), 0.0);
            let spec = pow(max(dot(reflect(-l, n), view_dir), 0.0), 32.0);

            // Audio-Reactive Synapses (glowing nodes)
            let synapse_glow = (0.5 + 0.5 * sin(p.z * 10.0 - time * 5.0)) * bass * 2.0;
            let glow_color = vec3<f32>(1.0, 0.5, 0.2) * synapse_glow;

            col = albedo * dif + vec3<f32>(1.0)*spec + glow_color;

            // Volumetric Caustics / Fog
            col = mix(col, vec3<f32>(0.05, 0.0, 0.1), 1.0 - exp(-0.1 * d0));
            break;
        }

        if(d0 > MAX_DIST) {
            // Background / Deep-void chronosphere
            let bg_uv = rot(time * 0.05) * uv;
            col = vec3<f32>(0.02, 0.01, 0.05) * (1.0 - length(bg_uv));
            break;
        }
        d0 += d;
    }

    // Output
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
