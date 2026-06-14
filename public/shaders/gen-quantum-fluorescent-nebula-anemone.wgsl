// ----------------------------------------------------------------
// Quantum-Fluorescent Nebula-Anemone
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn hash13(p3: vec3<f32>) -> f32 {
    var p = fract(p3 * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
  let d = abs(vec2<f32>(length(p.xz),p.y)) - vec2<f32>(h,r);
  return min(max(d.x,d.y),0.0) + length(max(d,vec2<f32>(0.0)));
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    var f = 0.0;
    var amp = 0.5;
    for(var i = 0; i < 4; i++) {
        f += amp * hash13(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(a-b)/k, 0.0, 1.0);
    return mix(b, a, h) + k*h*(1.0-h);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a-b), 0.0) / k;
    return min(a, b) - h*h*h*k*(1.0/6.0);
}

fn map(p: vec3<f32>) -> f32 {
    let time = u.config.x;
    let audio = u.config.y;
    let tentacle_density = u.zoom_params.y; // 0.0 to 1.0
    let mouse_y = u.zoom_config.y;
    let mouse_z = u.zoom_config.z;

    var pos = p;

    // Localized gravity well (mouse interaction)
    // Map mouse range
    let mPos = vec3<f32>(0.0, mouse_y * 10.0 - 5.0, mouse_z * 10.0 - 5.0);
    let distToMouse = length(pos - mPos);
    if(distToMouse < 4.0) {
        let pull = 1.0 - (distToMouse / 4.0);
        pos = mix(pos, mPos, pull * 0.3 * (1.0 + audio*2.0));
    }

    // Central Sphere Anemone Body
    var d = sdSphere(pos, 1.5 + audio * 0.5);

    // Tentacles (radial repetition)
    let num_tentacles = f32(10 + i32(tentacle_density * 40.0));
    let angle_step = 6.2831853 / num_tentacles;

    // Twist domain
    let a = atan2(pos.z, pos.x);
    let r = length(pos.xz);

    // Convert back to polar repetition domain
    let a_mod = a - angle_step * floor(a / angle_step) - angle_step * 0.5;

    // Reprojected local pos
    var tPos = vec3<f32>(r * cos(a_mod), pos.y, r * sin(a_mod));

    // Translate out
    tPos.x -= 1.5;

    // Domain warp twisting motion
    let freq = 1.5 + audio * 3.0;
    let amp = 0.5 + audio;

    tPos.y += sin(tPos.x * freq - time * 2.0) * amp;
    tPos.z += cos(tPos.x * freq * 0.8 + time * 1.5) * amp;

    // Tapering cylinder
    let h = 3.0 + fbm(pos * 0.5) * 2.0;
    let r_tentacle = 0.3 * (1.0 - clamp(tPos.x / h, 0.0, 1.0));

    let dt = sdCappedCylinder(vec3<f32>(tPos.x - h * 0.5, tPos.y, tPos.z), h * 0.5, r_tentacle);

    d = smin(d, dt, 0.8);

    // Small noise displacement on surface
    d -= fbm(pos * 4.0 + time) * 0.1 * (1.0 + audio);

    return d;
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy) - map(p - e.xyy),
        map(p + e.yxy) - map(p - e.yxy),
        map(p + e.yyx) - map(p - e.yyx)
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let id = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (global_id.x >= dims.x || global_id.y >= dims.y) {
        return;
    }

    let res = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = (id - 0.5 * res) / res.y;

    let time = u.config.x;
    let audio = u.config.y;

    let fl_intensity = u.zoom_params.x;
    let audio_reactivity = u.zoom_params.z;
    let nebula_density = u.zoom_params.w;

    // Camera
    let ro = vec3<f32>(cos(time * 0.2) * 8.0, sin(time * 0.1) * 3.0, sin(time * 0.2) * 8.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);

    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));

    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var dO = 0.0;
    var dS = 0.0;
    var p = vec3<f32>(0.0);

    for(var i=0; i<100; i++) {
        p = ro + rd * dO;
        dS = map(p);
        if(dS < 0.001 || dO > 20.0) { break; }
        dO += dS * 0.7; // slight step reduction for domain warping
    }

    var col = vec3<f32>(0.0);

    // Nebula Background (Volumetric rendering integration)
    var nebula = vec3<f32>(0.0);
    var dO_nebula = 0.0;
    for(var j=0; j<40; j++) {
        let p_neb = ro + rd * dO_nebula;
        let den = fbm(p_neb * 0.3 + time * 0.1);
        if(den > 0.4) {
            let n_col = mix(vec3<f32>(0.1, 0.0, 0.3), vec3<f32>(0.0, 0.5, 0.5), den);
            nebula += n_col * 0.02 * nebula_density * (1.0 + audio * audio_reactivity);
        }
        dO_nebula += 0.5;
    }

    col += nebula;

    if(dO < 20.0) {
        let n = getNormal(p);
        let l = normalize(vec3<f32>(2.0, 5.0, 3.0));

        let diff = max(dot(n, l), 0.0);
        let amb = 0.2;

        // Quantum-fluorescent bioluminescence (Subsurface approximation)
        var sss = 0.0;
        for(var s=1; s<5; s++) {
            let dist = f32(s) * 0.2;
            let sp = p + n * dist;
            sss += max(0.0, dist - map(sp)) / dist;
        }
        sss *= 0.1;

        // Color maps zoom_params.x to neon gradient
        let neon_color = mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.0, 1.0), fl_intensity);
        let base_color = mix(vec3<f32>(0.05, 0.0, 0.1), neon_color, audio * audio_reactivity);

        col = base_color * (diff + amb) + neon_color * sss * 2.0 * fl_intensity;

        // Fog
        col = mix(col, nebula, 1.0 - exp(-0.02 * dO * dO));
    }

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
