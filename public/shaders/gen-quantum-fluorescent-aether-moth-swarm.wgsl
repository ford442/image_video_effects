// ----------------------------------------------------------------
// Quantum-Fluorescent Aether-Moth Swarm
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Swarm Density, y=Curl Intensity, z=Glow Strength, w=Audio Sensitivity
    ripples: array<vec4<f32>, 50>,
};

// 3D Simplex noise
fn mod289(x: vec3<f32>) -> vec3<f32> {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}
fn mod289_4(x: vec4<f32>) -> vec4<f32> {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}
fn permute(x: vec4<f32>) -> vec4<f32> {
    return mod289_4(((x * 34.0) + 1.0) * x);
}
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> {
    return 1.79284291400159 - 0.85373472095314 * r;
}

fn snoise(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0/6.0, 1.0/3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);

    var i = floor(v + dot(v, vec3<f32>(C.y)));
    var x0 = v - i + dot(i, vec3<f32>(C.x));

    var g = step(x0.yzx, x0.xyz);
    var l = 1.0 - g;
    var i1 = min(g.xyz, l.zxy);
    var i2 = max(g.xyz, l.zxy);

    var x1 = x0 - i1 + vec3<f32>(C.x);
    var x2 = x0 - i2 + vec3<f32>(C.y);
    var x3 = x0 - 0.5;

    i = mod289(i);
    var p = permute(permute(permute(
                i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
            + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));

    var n_ = 0.142857142857;
    var ns = n_ * D.wyz - D.xzx;

    var j = p - 49.0 * floor(p * ns.z * ns.z);

    var x_ = floor(j * ns.z);
    var y_ = floor(j - 7.0 * x_);

    var x = x_ * ns.x + ns.yyyy;
    var y = y_ * ns.x + ns.yyyy;
    var h = 1.0 - abs(x) - abs(y);

    var b0 = vec4<f32>(x.xy, y.xy);
    var b1 = vec4<f32>(x.zw, y.zw);

    var s0 = floor(b0) * 2.0 + 1.0;
    var s1 = floor(b1) * 2.0 + 1.0;
    var sh = -step(h, vec4<f32>(0.0));

    var a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    var a1 = b1.xzyw + s1.xzyw * sh.zzww;

    var p0 = vec3<f32>(a0.xy, h.x);
    var p1 = vec3<f32>(a0.zw, h.y);
    var p2 = vec3<f32>(a1.xy, h.z);
    var p3 = vec3<f32>(a1.zw, h.w);

    var norm = taylorInvSqrt(vec4<f32>(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 = p0 * norm.x;
    p1 = p1 * norm.y;
    p2 = p2 * norm.z;
    p3 = p3 * norm.w;

    var m = max(0.6 - vec4<f32>(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), vec4<f32>(0.0));
    m = m * m;
    return 42.0 * dot(m * m, vec4<f32>(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

fn snoiseVec3(x: vec3<f32>) -> vec3<f32> {
    var s = snoise(vec3<f32>(x));
    var s1 = snoise(vec3<f32>(x.y - 19.1, x.z + 33.4, x.x + 47.2));
    var s2 = snoise(vec3<f32>(x.z + 74.2, x.x - 124.5, x.y + 99.4));
    return vec3<f32>(s, s1, s2);
}

fn curlNoise(p: vec3<f32>) -> vec3<f32> {
    let e = 0.1;
    let dx = vec3<f32>(e, 0.0, 0.0);
    let dy = vec3<f32>(0.0, e, 0.0);
    let dz = vec3<f32>(0.0, 0.0, e);

    let p_x0 = snoiseVec3(p - dx);
    let p_x1 = snoiseVec3(p + dx);
    let p_y0 = snoiseVec3(p - dy);
    let p_y1 = snoiseVec3(p + dy);
    let p_z0 = snoiseVec3(p - dz);
    let p_z1 = snoiseVec3(p + dz);

    let x = p_y1.z - p_y0.z - p_z1.y + p_z0.y;
    let y = p_z1.x - p_z0.x - p_x1.z + p_x0.z;
    let z = p_x1.y - p_x0.y - p_y1.x + p_y0.x;

    let divisor = 1.0 / (2.0 * e);
    return normalize(vec3<f32>(x, y, z) * divisor);
}

// Memory rule says: read from dataTextureC and write to dataTextureA
// (However, this is typically for ping-pong. For particle swarms on a screen, we compute a field and display it).
// The task requires: flocking behavior mimicking complex fluid dynamics,
// a persistent buffer if needed, audio-reactive fluorescence.

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let gid = vec2<i32>(global_id.xy);
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(gid) / res) * 2.0 - 1.0;
    let uv_scaled = uv * vec2<f32>(res.x / res.y, 1.0);

    let time = u.config.x;
    let audio = u.config.y;
    let mouse = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) / res) * 2.0 - 1.0;
    let mouse_scaled = mouse * vec2<f32>(res.x / res.y, 1.0);
    let click = select(0.0, 1.0, u.config.y > 0.5); // proxy for click or audio reactivity

    let swarm_density = u.zoom_params.x;
    let curl_intensity = u.zoom_params.y;
    let glow_strength = u.zoom_params.z;
    let audio_sens = u.zoom_params.w;

    // Read previous frame from dataTextureC (as per Memory rule)
    let old_color = textureLoad(dataTextureC, gid, 0).rgb;

    // Base particle space
    var p = vec3<f32>(uv_scaled * 3.0, time * 0.2);

    // Apply curl noise
    var vel = curlNoise(p * curl_intensity + time * 0.5);

    // Attraction to mouse / gravity nodes
    let dist_to_mouse = distance(uv_scaled, mouse_scaled);
    let force_dir = normalize(mouse_scaled - uv_scaled);
    let force_mag = (1.0 / (dist_to_mouse * dist_to_mouse + 0.1)) * 0.05;

    // Scatter on click/high audio
    let scatter = select(1.0, -2.0, u.zoom_config.y > 0.0); // Simple interaction model

    vel = vel + vec3<f32>(force_dir * force_mag * scatter, 0.0);

    // Advection style trails
    let advect_offset = vel.xy * 0.02;
    let advect_uv = (uv + advect_offset) * 0.5 + 0.5;
    let advect_gid = vec2<i32>(advect_uv * res);
    let trail = textureLoad(dataTextureC, advect_gid, 0).rgb;

    // Spawn particles (noise threshold)
    let particle_noise = snoise(vec3<f32>(uv_scaled * 20.0 * swarm_density, time));
    var spawn = smoothstep(0.7, 0.9, particle_noise);

    // Audio reactivity - spontaneous assembly
    if (audio > 0.5) {
        let mandala = sin(length(uv_scaled) * 20.0 - time * 5.0) * cos(atan2(uv_scaled.y, uv_scaled.x) * 8.0);
        spawn += smoothstep(0.8, 1.0, mandala) * audio * audio_sens;
    }

    // Color mapping
    let speed = length(vel);
    let col1 = vec3<f32>(0.0, 1.0, 1.0); // Cyan
    let col2 = vec3<f32>(1.0, 0.0, 1.0); // Magenta
    let col3 = vec3<f32>(0.2, 0.0, 0.8); // Indigo

    let vel_color = mix(col3, mix(col1, col2, speed), speed * 2.0);

    var final_color = trail * 0.92; // Decay
    final_color += vel_color * spawn * glow_strength;

    // Tone mapping
    final_color = final_color / (1.0 + final_color);

    textureStore(dataTextureA, gid, vec4<f32>(final_color, 1.0));
    textureStore(writeTexture, gid, vec4<f32>(final_color, 1.0));
}
