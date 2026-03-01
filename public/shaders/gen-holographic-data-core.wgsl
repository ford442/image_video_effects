// ═══════════════════════════════════════════════════════════════
//  Holographic Data Core
//  Category: generative
//  Features: mouse-driven
//  Description: An infinite journey through a quantum lattice of glowing data nodes and pulsing circuits.
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// ---------------------------------------------------------
// SDF Primitives
// ---------------------------------------------------------

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - c;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// ---------------------------------------------------------
// Map Function
// ---------------------------------------------------------

struct MapResult {
    d: f32,
    mat_id: f32, // 0.0: none, 1.0: base nodes, 2.0: active pulses, 3.0: circuits
};

fn opU(d1: MapResult, d2: MapResult) -> MapResult {
    if (d1.d < d2.d) { return d1; }
    return d2;
}

fn map(p: vec3<f32>) -> MapResult {
    var res = MapResult(1000.0, 0.0);

    let node_density = u.zoom_params.x;
    let spacing = 4.0 / max(node_density, 0.1);

    // Domain repetition
    let c = vec3<f32>(spacing);
    let q = (p + 0.5 * c) % c - 0.5 * c;

    // Cell ID for variation
    let cell_id = floor((p + 0.5 * c) / c);

    // Base Node (Box)
    let box_d = sdBox(q, vec3<f32>(0.6));

    // Inner Floating Core (Subtractive/Additive details)
    let inner_d = sdBox(q, vec3<f32>(0.3));

    // Active Data Pulse logic
    let time = u.config.x;
    let pulse_rate = u.zoom_params.z;
    // create a moving pattern based on cell position and time
    let pulse_val = sin(cell_id.x * 12.3 + cell_id.y * 45.6 + cell_id.z * 78.9 + time * pulse_rate * 5.0);

    var node_res = MapResult(max(box_d, -sdBox(q, vec3<f32>(0.4))), 1.0); // Hollow box
    if (pulse_val > 0.8) {
        node_res.mat_id = 2.0; // Highlight
    }

    node_res = opU(node_res, MapResult(inner_d, 2.0)); // Inner core always glowing

    res = opU(res, node_res);

    // Circuits (Connecting cylinders)
    let cyl_radius = 0.05;

    // X-axis connections
    let cx = sdCylinder(vec3<f32>(q.y, q.x, q.z), vec2<f32>(cyl_radius, spacing * 0.5));
    // Y-axis connections
    let cy = sdCylinder(q, vec2<f32>(cyl_radius, spacing * 0.5));
    // Z-axis connections
    let cz = sdCylinder(vec3<f32>(q.x, q.z, q.y), vec2<f32>(cyl_radius, spacing * 0.5));

    let circuit_d = min(cx, min(cy, cz));

    var circuit_res = MapResult(circuit_d, 3.0);
    if (pulse_val > 0.6 && pulse_val < 0.8) {
        circuit_res.mat_id = 2.0; // Circuit pulses
    }

    res = opU(res, circuit_res);

    return res;
}

// ---------------------------------------------------------
// Raymarching
// ---------------------------------------------------------

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    ));
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + vec3<f32>(dot(p3, p3.yzx + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

// ---------------------------------------------------------
// Main
// ---------------------------------------------------------

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }

    let time = u.config.x;

    let glitch_intensity = u.zoom_params.w;
    let travel_speed = u.zoom_params.y;

    var uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Holographic Glitch (chromatic aberration & scanlines base)
    let glitch_hash = hash21(vec2<f32>(floor(time * 20.0), uv.y));
    if (glitch_intensity > 0.0 && glitch_hash < glitch_intensity * 0.1) {
        uv.x += (hash21(uv + vec2<f32>(time)) - 0.5) * 0.1 * glitch_intensity;
    }

    // Camera setup
    let cam_z = time * travel_speed * 2.0;

    // Mouse interaction for look around
    let mouse = u.zoom_config.yz;
    let mouse_ang_x = (mouse.x - 0.5) * 3.14;
    let mouse_ang_y = (mouse.y - 0.5) * 3.14;

    let ro = vec3<f32>(0.0, 0.0, cam_z);

    // Gentle wobble
    let look_at = ro + vec3<f32>(
        sin(time * 0.5) * 0.5 + sin(mouse_ang_x)*2.0,
        cos(time * 0.3) * 0.5 - sin(mouse_ang_y)*2.0,
        1.0
    );

    let fw = normalize(look_at - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fw));
    let up = cross(fw, right);

    var rd = normalize(fw + uv.x * right + uv.y * up);

    // Raymarching
    var t = 0.0;
    let max_steps = 80;
    let max_dist = 40.0;

    var col = vec3<f32>(0.0);
    var glow = vec3<f32>(0.0);

    for (var i = 0; i < max_steps; i++) {
        let p = ro + rd * t;
        let res = map(p);

        let d = res.d;

        // Volumetric Glow Accumulation
        if (d > 0.0) {
            let g_dist = max(d, 0.001);
            if (res.mat_id == 1.0) {
                glow += vec3<f32>(0.0, 0.5, 1.0) * (0.01 / g_dist); // Cyan base
            } else if (res.mat_id == 2.0) {
                glow += vec3<f32>(1.0, 0.2, 0.5) * (0.02 / g_dist); // Magenta/Orange pulses
            } else if (res.mat_id == 3.0) {
                glow += vec3<f32>(0.0, 0.8, 0.8) * (0.005 / g_dist); // Faint cyan circuits
            }
        }

        if (d < 0.01) {
            let n = getNormal(p);

            // Basic rim lighting / fresnel for structure
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

            if (res.mat_id == 1.0) {
                col += vec3<f32>(0.1, 0.5, 0.8) * fresnel;
            } else if (res.mat_id == 2.0) {
                col += vec3<f32>(1.0, 0.5, 0.2) * (1.0 + fresnel);
            } else if (res.mat_id == 3.0) {
                col += vec3<f32>(0.2, 0.8, 1.0) * 0.5 * fresnel;
            }
            break;
        }

        if (t > max_dist) {
            break;
        }

        t += d * 0.7; // Step size multiplier to avoid missing thin structures
    }

    // Add glow
    col += glow * 0.15;

    // Depth fade (fog)
    let fog = 1.0 - exp(-t * t * 0.002);
    col = mix(col, vec3<f32>(0.0, 0.02, 0.05), fog);

    // Chromatic aberration / scanline post-process
    if (glitch_intensity > 0.0) {
        let scanline = sin(uv.y * 800.0) * 0.04 * glitch_intensity;
        col -= vec3<f32>(scanline);

        // Simple radial chromatic aberration based on glitch
        let dist_center = length(uv);
        let ca_shift = dist_center * 0.05 * glitch_intensity;
        // In a single pass compute shader, true CA by resampling is hard without a separate pass,
        // but we can fake a color shift based on screen position
        col.r *= 1.0 + ca_shift;
        col.b *= 1.0 - ca_shift;
    }

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));

    // Pass through depth (mock)
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(global_id.xy)/resolution, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
