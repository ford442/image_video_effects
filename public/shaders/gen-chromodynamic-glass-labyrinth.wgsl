// ----------------------------------------------------------------
// Chromodynamic Glass Labyrinth
// Category: generative
// ----------------------------------------------------------------

#include "_prelude.wgsl"
// zoom_params: .x = Structural Density, .y = Refraction Index, .z = Dispersion, .w = Chromatic Phase

const PI: f32 = 3.14159265359;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0);
    return mix(b, a, h) + k * h * (1.0 - h);
}

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Interaction for structural warping
    if (u.zoom_config.w > 0.0) {
        let mouse_offset = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
        let rot_xy = rot2D(mouse_offset.x * 2.0);
        let p_xy = p.xy * rot_xy;
        p = vec3<f32>(p_xy, p.z);
        // y axis warp expansion
        p *= (1.0 + mouse_offset.y * 0.5);
    }

    // Spatial folding
    let s_density = u.zoom_params.x;
    let cell_size = 4.0 / s_density;
    p.x = (fract(p.x / cell_size + 0.5) - 0.5) * cell_size;
    p.y = (fract(p.y / cell_size + 0.5) - 0.5) * cell_size;
    p.z = (fract(p.z / cell_size + 0.5) - 0.5) * cell_size;

    let p_xz = p.xz * rot2D(u.config.x * 0.2);
    p = vec3<f32>(p_xz.x, p.y, p_xz.y);
    let p_yz = p.yz * rot2D(u.config.x * 0.15);
    p = vec3<f32>(p.x, p_yz.x, p_yz.y);

    let d_box = length(max(abs(p) - vec3<f32>(cell_size * 0.3), vec3<f32>(0.0))) - cell_size * 0.05;
    let d_sphere = length(p) - cell_size * 0.35;

    // rounded intersection / subtraction
    let d = smax(d_box, -d_sphere, cell_size * 0.1);

    return d;
}

fn get_normal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p);
    let n = vec3<f32>(
        map(p + e.xyy) - d,
        map(p + e.yxy) - d,
        map(p + e.yyx) - d
    );
    return normalize(n);
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557) + u.zoom_params.w; // Chromatic Phase
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = u.config.zw;
    if (f32(id.x) >= dims.x || f32(id.y) >= dims.y) {
        return;
    }

    let uv = (vec2<f32>(id.xy) - 0.5 * dims) / dims.y;

    // Audio reactivity
    let audio_val = plasmaBuffer[0].x;

    var ro = vec3<f32>(0.0, 0.0, -3.0 + u.config.x * 2.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Mouse Interaction for perspective
    if (u.zoom_config.w > 0.0) {
        let mouse_offset = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
        let rd_xz = rd.xz * rot2D(-mouse_offset.x * PI);
        rd = vec3<f32>(rd_xz.x, rd.y, rd_xz.y);
        let rd_yz = rd.yz * rot2D(-mouse_offset.y * PI * 0.5);
        rd = vec3<f32>(rd.x, rd_yz.x, rd_yz.y);
    }

    var t = 0.0;
    var d = 0.0;
    var hit = false;
    var steps_taken: i32 = 0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        d = map(p);
        if (d < 0.001) {
            hit = true;
            steps_taken = i;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d * 0.8;
    }

    var color = vec3<f32>(0.0);
    var depth = 1.0;

    if (hit) {
        let p = ro + rd * t;
        let n = get_normal(p);
        let v = -rd;

        let ior = u.zoom_params.y; // Refraction Index
        let dispersion = u.zoom_params.z; // Dispersion

        let r_rd = refract(rd, n, 1.0 / ior);
        let r_rd_r = refract(rd, n, 1.0 / (ior - dispersion));
        let r_rd_b = refract(rd, n, 1.0 / (ior + dispersion));

        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        // Simulating internal refraction color lookup
        let refl = reflect(rd, n);

        let mat_color = palette(length(p) * 0.1 + u.config.x * 0.5);

        // Caustic highlight approx
        let spec = pow(max(dot(refl, normalize(vec3<f32>(1.0, 1.0, -1.0))), 0.0), 32.0);

        // Audio bump
        let audio_bump = audio_val * 0.5 * max(0.0, dot(n, vec3<f32>(0.0, 1.0, 0.0)));

        // Chromatic dispersion approx
        let c_r = palette(dot(r_rd_r, vec3<f32>(1.0))).r;
        let c_g = palette(dot(r_rd, vec3<f32>(1.0))).g;
        let c_b = palette(dot(r_rd_b, vec3<f32>(1.0))).b;
        let refr_color = vec3<f32>(c_r, c_g, c_b);

        color = mix(refr_color * mat_color, vec3<f32>(1.0) * spec + audio_bump, fresnel);

        // AO
        let ao = 1.0 - f32(steps_taken) / 100.0;
        color *= ao;

        depth = clamp(t / 20.0, 0.0, 1.0);
    } else {
        color = palette(rd.y + u.config.x * 0.1) * 0.1;
    }

    let final_color = vec4<f32>(color, 1.0);

    textureStore(writeTexture, id.xy, final_color);
    textureStore(dataTextureA, id.xy, final_color);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
