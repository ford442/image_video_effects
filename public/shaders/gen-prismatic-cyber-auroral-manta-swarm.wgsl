// ----------------------------------------------------------------
// Prismatic Cyber-Auroral Manta-Swarm
// Category: generative
// ----------------------------------------------------------------
struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Shatter Threshold, y=Chime Density, z=Refraction Index, w=Transmission
    ripples: array<vec4<f32>, 50>,
};

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

// PRNG
fn hash1(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453123);
}

// 3D Simplex noise
fn snoise(p: vec3<f32>) -> f32 {
    let K1 = 0.333333333;
    let K2 = 0.166666667;
    let i = floor(p + (p.x + p.y + p.z) * K1);
    let d0 = p - i + (i.x + i.y + i.z) * K2;

    var e = step(vec3<f32>(0.0), d0 - d0.yzx);
    var i1 = e * (1.0 - e.zxy);
    var i2 = 1.0 - e.zxy * (1.0 - e);

    let d1 = d0 - (i1 - 1.0 * K2);
    let d2 = d0 - (i2 - 2.0 * K2);
    let d3 = d0 - (1.0 - 3.0 * K2);

    var h = max(0.6 - vec4<f32>(dot(d0, d0), dot(d1, d1), dot(d2, d2), dot(d3, d3)), vec4<f32>(0.0));
    var n = h * h * h * h * vec4<f32>(
        dot(d0, hash3(i + 0.0) - 0.5),
        dot(d1, hash3(i + i1) - 0.5),
        dot(d2, hash3(i + i2) - 0.5),
        dot(d3, hash3(i + 1.0) - 0.5)
    );
    return dot(n, vec4<f32>(52.0));
}

// Fractal Brownian Motion
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    var pp = p;
    for (var i = 0; i < 4; i++) {
        f += amp * snoise(pp * freq);
        freq *= 2.0;
        amp *= 0.5;
        pp = pp * 1.1 + vec3<f32>(0.1, 0.2, 0.3);
    }
    return f;
}

// Rotation matrices
fn rotX(a: f32) -> mat3x3<f32> {
    let c = cos(a); let s = sin(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(a: f32) -> mat3x3<f32> {
    let c = cos(a); let s = sin(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(a: f32) -> mat3x3<f32> {
    let c = cos(a); let s = sin(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// Smooth min/max
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Manta ray SDF
fn sdf_manta(p_in: vec3<f32>, time: f32, audio_react: f32, id: f32) -> f32 {
    var p = p_in;

    // Wing flapping animation based on time, position, and audio
    let flap_speed = 2.0 + audio_react * 2.0 + hash1(id) * 1.5;
    let flap_amp = 0.3 + audio_react * 0.2;

    // Flapping
    let flap = sin(time * flap_speed - abs(p.x) * 2.0) * flap_amp * p.x * p.x;
    p.y -= flap;

    // Body (flattened ellipsoid)
    let body_r = vec3<f32>(0.8, 0.15, 1.2);
    let body_d = length(p / body_r) - 1.0;
    var d = body_d * min(min(body_r.x, body_r.y), body_r.z);

    // Wings
    let wing_w = 2.5;
    let wing_l = 1.0;
    let wing_t = 0.05 * (1.0 - min(abs(p.x) / wing_w, 1.0)); // Taper towards tips

    // Swept back wing shape
    var wp = p;
    wp.z += abs(wp.x) * 0.5; // Sweep back

    // Wing bounding box/shape
    let d_x = abs(wp.x) - wing_w;
    let d_y = abs(wp.y) - wing_t;
    let d_z = abs(wp.z) - wing_l * (1.0 - min(abs(wp.x) / wing_w, 1.0));

    let wing_dist = length(max(vec3<f32>(d_x, d_y, d_z), vec3<f32>(0.0))) + min(max(d_x, max(d_y, d_z)), 0.0);

    // Tail
    let tail_l = 2.0;
    let tail_t = 0.02;
    var tp = p;
    tp.z -= 1.0; // Start at back of body
    // Tail whipping
    tp.x += sin(time * flap_speed * 1.5 + tp.z * 2.0) * 0.1 * tp.z;

    // Tail cylinder
    let d_tx = abs(tp.x) - tail_t;
    let d_tz = max(0.0, tp.z) - tail_l; // only go backwards
    var tail_dist = length(vec2<f32>(tp.x, tp.y)) - tail_t;
    tail_dist = max(tail_dist, -tp.z); // Start at z=0
    tail_dist = max(tail_dist, tp.z - tail_l); // End at tail_l

    // Smooth union of parts
    d = smin(d, wing_dist, 0.2);
    d = smin(d, tail_dist, 0.1);

    return d;
}

// Swarm SDF
fn map(p_in: vec3<f32>, time: f32, audio_react: f32, mouse_pos: vec3<f32>, swarm_cohesion: f32) -> f32 {
    var min_d = 1000.0;

    // Render a few manta rays
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);

        // Base orbit
        let orbit_r = 4.0 + hash1(fi) * 2.0;
        let orbit_s = 0.2 + hash1(fi + 10.0) * 0.2;

        var base_pos = vec3<f32>(
            cos(time * orbit_s + fi * 2.0) * orbit_r,
            sin(time * orbit_s * 1.3 + fi * 3.0) * orbit_r * 0.5,
            sin(time * orbit_s + fi * 2.0) * orbit_r
        );

        // Mouse gravity influence
        let m_dist = length(mouse_pos - base_pos);
        let m_pull = 1.0 / (m_dist * m_dist + 1.0) * 10.0;
        let pull_dir = normalize(mouse_pos - base_pos);

        // Cohesion pull (towards center of swarm)
        let center_pull = -base_pos * swarm_cohesion * 0.1;

        // Final position
        var pos = base_pos + pull_dir * m_pull * 0.5 + center_pull;

        // Calculate orientation (facing direction of movement)
        // Approximate velocity by looking at next frame position
        let t_next = time + 0.1;
        var next_pos = vec3<f32>(
            cos(t_next * orbit_s + fi * 2.0) * orbit_r,
            sin(t_next * orbit_s * 1.3 + fi * 3.0) * orbit_r * 0.5,
            sin(t_next * orbit_s + fi * 2.0) * orbit_r
        );
        let m_dist_next = length(mouse_pos - next_pos);
        let m_pull_next = 1.0 / (m_dist_next * m_dist_next + 1.0) * 10.0;
        let pull_dir_next = normalize(mouse_pos - next_pos);
        next_pos = next_pos + pull_dir_next * m_pull_next * 0.5 - next_pos * swarm_cohesion * 0.1;

        let vel = normalize(next_pos - pos);

        // Create rotation matrix to align with velocity
        let up = vec3<f32>(0.0, 1.0, 0.0);
        let right = normalize(cross(up, vel));
        let new_up = cross(vel, right);
        let rot = mat3x3<f32>(right, new_up, vel);

        // Transform point to manta local space
        var lp = (p_in - pos);
        // Multiply by inverse rotation (transpose for orthogonal matrix)
        let inv_rot = mat3x3<f32>(
            rot[0][0], rot[1][0], rot[2][0],
            rot[0][1], rot[1][1], rot[2][1],
            rot[0][2], rot[1][2], rot[2][2]
        );
        lp = inv_rot * lp;

        // Get distance
        let d = sdf_manta(lp, time, audio_react, fi);
        min_d = smin(min_d, d, 0.5); // Merge them softly if they get close
    }

    return min_d;
}

// Calculate normal
fn calcNormal(p: vec3<f32>, time: f32, audio_react: f32, mouse_pos: vec3<f32>, swarm_cohesion: f32) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audio_react, mouse_pos, swarm_cohesion) - map(p - e.xyy, time, audio_react, mouse_pos, swarm_cohesion),
        map(p + e.yxy, time, audio_react, mouse_pos, swarm_cohesion) - map(p - e.yxy, time, audio_react, mouse_pos, swarm_cohesion),
        map(p + e.yyx, time, audio_react, mouse_pos, swarm_cohesion) - map(p - e.yyx, time, audio_react, mouse_pos, swarm_cohesion)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) { return; }

    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * res) / res.y;

    let time = u.config.x * 0.5;
    let audio = u.config.y;

    // Parameters mapped from UI sliders
    let swarm_cohesion = u.zoom_params.x;
    let aurora_intensity = u.zoom_params.y;
    let audio_react = audio * u.zoom_params.z;

    // Mouse coords
    let mouse_ndc = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -10.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slight camera drift
    let cam_rot = rotY(sin(time * 0.1) * 0.2) * rotX(cos(time * 0.15) * 0.1);
    rd = cam_rot * rd;

    // 3D Mouse position (projected into scene)
    let mouse_pos = vec3<f32>(mouse_ndc.x * 8.0, -mouse_ndc.y * 8.0, 0.0);

    // Background / Aurora Volumetrics
    var col = vec3<f32>(0.0);
    var transmittance = 1.0;
    var t_vol = 0.0;

    // Raymarch Volumetric Aurora
    for (var i = 0; i < 40; i++) {
        let p = ro + rd * t_vol;

        // Aurora density based on noise and height
        var density = fbm(p * 0.2 + vec3<f32>(time * 0.1, 0.0, time * 0.2)) * 2.0 - 1.0;

        // Modulate with audio
        density += fbm(p * 0.5 - vec3<f32>(0.0, time * audio_react * 0.5, 0.0)) * audio_react * 0.5;

        // Confine to a band
        density *= smoothstep(6.0, 2.0, abs(p.y));
        density = max(0.0, density);

        if (density > 0.0) {
            // Color mapping based on height and density
            let aurora_col = mix(
                vec3<f32>(0.1, 0.0, 0.8), // Deep neon indigo
                vec3<f32>(0.0, 0.8, 0.6), // Brilliant cyan
                smoothstep(-2.0, 2.0, p.y + density)
            );

            // Add magenta spikes on audio
            let spike = pow(max(0.0, sin(p.x * 2.0 + time) * cos(p.z * 2.0 - time)), 4.0) * audio_react;
            let final_aurora = mix(aurora_col, vec3<f32>(1.0, 0.0, 0.5), spike);

            let absorption = density * 0.1 * aurora_intensity;
            let emission = final_aurora * density * 0.5 * aurora_intensity;

            col += emission * transmittance;
            transmittance *= exp(-absorption);
        }

        if (transmittance < 0.01) { break; }

        t_vol += 0.5; // Step size
    }

    // Raymarch Manta Rays (Solid geometry)
    var t = 0.0;
    var d = 0.0;
    var hit = false;
    var p = ro;

    for (var i = 0; i < 64; i++) {
        p = ro + rd * t;
        d = map(p, time, audio_react, mouse_pos, swarm_cohesion);
        if (d < 0.01) {
            hit = true;
            break;
        }
        t += d;
        if (t > 20.0) { break; }
    }

    if (hit && transmittance > 0.1) { // Only render if not fully obscured by thick aurora
        let n = calcNormal(p, time, audio_react, mouse_pos, swarm_cohesion);

        // Lighting
        let l_dir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(0.0, dot(n, l_dir));
        let fresnel = pow(1.0 - max(0.0, dot(n, -rd)), 3.0);

        // Subsurface scattering / glowing edge effect
        let thickness = map(p - n * 0.1, time, audio_react, mouse_pos, swarm_cohesion);
        let sss = smoothstep(0.0, 0.1, thickness);

        // Manta Color (glass-like, refractive, glowing edges)
        var manta_col = vec3<f32>(0.05, 0.1, 0.2); // Base dark glass

        // Add neon glow to edges (fresnel + sss)
        let edge_glow = vec3<f32>(0.0, 0.8, 1.0) * fresnel * 2.0;

        // Add audio reactive chromatic bloom
        let bloom = vec3<f32>(1.0, 0.2, 0.8) * sss * audio_react;

        manta_col += edge_glow + bloom;

        // Blend solid object with volumetric background based on transmittance
        // The solid object occludes what's behind it, but is dimmed by what's in front
        col = mix(col, manta_col * transmittance, transmittance);
    }

    // Tone mapping and gamma
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
