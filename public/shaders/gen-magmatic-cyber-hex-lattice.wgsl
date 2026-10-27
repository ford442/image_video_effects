// ----------------------------------------------------------------
// Magmatic Cyber-Hex Lattice
// Category: generative
// ----------------------------------------------------------------

#include "_prelude.wgsl"

// --- HELPER FUNCTIONS ---

// 2D Rotation matrix
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 2D Hash function
fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(p2) * 43758.5453);
}

// Voronoi Noise for magma displacement
fn voronoi(x: vec2<f32>) -> f32 {
    let n = floor(x);
    let f = fract(x);
    var md = 8.0;

    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = hash2(n + g);
            let p = g + 0.5 + 0.5 * sin(u.config.x * u.zoom_params.y + 6.2831 * o) - f;
            let d = dot(p, p);
            if (d < md) {
                md = d;
            }
        }
    }
    return md;
}

// FBM based on Voronoi for detailed magma
fn fbm(p: vec2<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var x = p;
    for (var i: i32 = 0; i < 4; i++) {
        f += w * voronoi(x);
        x *= 2.0;
        w *= 0.5;
    }
    return f;
}

// Smooth min/max for blending structures
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    return smin(a, b, -k);
}

// Distance to Hexagonal Prism
fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735); // (-sqrt(3)/2, 1/2, 1/sqrt(3))
    var p_abs = abs(p);
    p_abs.x -= 2.0 * min(dot(k.xy, p_abs.xy), 0.0) * k.x;
    p_abs.y -= 2.0 * min(dot(k.xy, p_abs.xy), 0.0) * k.y;
    let d = vec2<f32>(
        length(p_abs.xy - vec2<f32>(clamp(p_abs.x, -k.z * h.x, k.z * h.x), h.x)) * sign(p_abs.y - h.x),
        p_abs.z - h.y
    );
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// Distance to Hexagonal Grid (infinite)
// Returns vec4: (x, y) = local pos, (z, w) = cell id
fn opRepHex(p: vec2<f32>, s: f32) -> vec4<f32> {
    let r = vec2<f32>(1.0, 1.7320508) * s;
    let h = r * 0.5;
    let a = (p % r) - h;
    let b = ((p - h) % r) - h;
    let gv = select(b, a, dot(a, a) < dot(b, b));
    let id = p - gv;
    return vec4<f32>(gv, id);
}

// Map the scene distance
struct MapResult {
    d: f32,
    mat: i32, // 0 = grid, 1 = magma
    magma_height: f32,
}

fn map(pos: vec3<f32>) -> MapResult {
    let hex_scale = u.zoom_params.x * 2.0; // Slider: 0.1 to 5.0

    // Domain repetition for hex grid in XZ plane
    let rep = opRepHex(pos.xz, hex_scale);
    let local_xz = rep.xy;
    let cell_id = rep.zw;

    // Mouse Interaction: localized magnetic distortion
    var disp_y = 0.0;
    if (u.zoom_config.w > 0.5) {
        let mouse_ndc = (u.zoom_config.yz - 0.5) * 2.0;
        let mouse_world = vec2<f32>(mouse_ndc.x * 10.0, -mouse_ndc.y * 10.0);

        let d_mouse = length(cell_id - mouse_world);
        let well_radius = 5.0;
        if (d_mouse < well_radius) {
            disp_y -= (1.0 - d_mouse / well_radius) * 2.0;
        }
    }

    // Audio Reactivity
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    disp_y += sin(length(cell_id) * 0.5 - u.config.x * 2.0) * bass * 0.5;

    // The Grid: Hex prisms
    let hex_radius = hex_scale * 0.48; // Leave a gap
    let hex_height = 0.5 + disp_y;
    let p_hex = vec3<f32>(local_xz.x, pos.y, local_xz.y);
    var d_grid = sdHexPrism(p_hex, vec2<f32>(hex_radius, hex_height));

    // Hollow out the hex prisms (make them rims)
    let inner_radius = hex_radius * 0.8;
    let d_inner = sdHexPrism(p_hex, vec2<f32>(inner_radius, hex_height * 1.01));
    d_grid = smax(d_grid, -d_inner, 0.1);

    // The Magma: Wavy plane with Voronoi displacement
    let base_y = -1.0;
    let magma_noise = fbm(pos.xz * 0.2 + u.config.x * 0.1 * u.zoom_params.y);
    let d_magma = pos.y - (base_y + magma_noise * 1.5 + mids * 0.5);

    var res = MapResult(d_grid, 0, 0.0);
    if (d_magma < d_grid) {
        res.d = d_magma;
        res.mat = 1;
        res.magma_height = magma_noise;
    }

    return res;
}

// Calculate normal
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).d - map(p - e.xyy).d,
        map(p + e.yxy).d - map(p - e.yxy).d,
        map(p + e.yyx).d - map(p - e.yyx).d
    ));
}

// --- MAIN COMPUTE SHADER ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) {
        return;
    }
    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // Camera setup
    let ro = vec3<f32>(0.0, 6.0, -8.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var t = 0.0;
    var max_t = 30.0;
    var hit = false;
    var mat = 0;
    var magma_h = 0.0;

    for (var i: i32 = 0; i < 100; i++) {
        let p = ro + t * rd;
        let res = map(p);
        if (abs(res.d) < 0.001) {
            hit = true;
            mat = res.mat;
            magma_h = res.magma_height;
            break;
        }
        t += res.d * 0.7; // Step slightly conservatively
        if (t > max_t) {
            break;
        }
    }

    // Shading
    var col = vec3<f32>(0.0); // Background

    if (hit) {
        let p = ro + t * rd;
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);

        if (mat == 0) { // Grid
            col = vec3<f32>(0.1) * diff;
            let hex_scale = u.zoom_params.x * 2.0;
            let rep = opRepHex(p.xz, hex_scale);
            let local_xz = rep.xy;
            let hex_radius = hex_scale * 0.48;
            let inner_radius = hex_radius * 0.8;
            let dist_to_center = length(local_xz);

            let neon_color = vec3<f32>(0.0, 1.0, 1.0) * u.zoom_params.z;
            let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
            if (n.y > 0.8) {
                col += neon_color * (0.2 + treble * 0.8);
            }
        } else if (mat == 1) { // Magma
            let c1 = vec3<f32>(0.5, 0.0, 0.0);
            let c2 = vec3<f32>(1.0, 0.5, 0.0);
            let c3 = vec3<f32>(1.0, 1.0, 0.5);

            col = mix(c1, c2, smoothstep(0.0, 0.5, magma_h));
            col = mix(col, c3, smoothstep(0.5, 1.0, magma_h));
            col *= 1.5;
        }

        // Fog
        col = mix(col, vec3<f32>(0.0), 1.0 - exp(-0.02 * t * t));
    }

    let final_color = vec4<f32>(col, 1.0);
    textureStore(writeTexture, vec2<i32>(global_id.xy), final_color);
}
