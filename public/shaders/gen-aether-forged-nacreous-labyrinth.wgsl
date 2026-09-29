// ----------------------------------------------------------------
// Aether-Forged Nacreous Labyrinth
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (y=0 top), .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Crystal Sharpness, .y = Flow Speed, .z = Aether Density, .w = Iridescence Shift
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

// Simplex/Gradient Noise (simplified)
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// Curl noise
fn curlNoise(p: vec3<f32>) -> vec3<f32> {
    let e = 0.05;
    let dx = vec3<f32>(e, 0.0, 0.0);
    let dy = vec3<f32>(0.0, e, 0.0);
    let dz = vec3<f32>(0.0, 0.0, e);

    let x = noise(p + dy) - noise(p - dy) - (noise(p + dz) - noise(p - dz));
    let y = noise(p + dz) - noise(p - dz) - (noise(p + dx) - noise(p - dx));
    let z = noise(p + dx) - noise(p - dx) - (noise(p + dy) - noise(p - dy));

    return vec3<f32>(x, y, z) / (2.0 * e);
}

// fBM
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var pos = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(pos);
        pos = pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Cosine palette for iridescence
fn pal(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(2.0 * PI * (c * t + d));
}

// Gyroid
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let p_scaled = p * scale;
    return abs(dot(sin(p_scaled), cos(p_scaled.zxy)) + bias) / scale - thickness;
}

// KIFS fractal lattice
fn sdKIFS(p: vec3<f32>, sharp: f32) -> f32 {
    var q = p;
    let s = 1.2;
    var d = 1000.0;
    for(var i = 0; i < 4; i++) {
        q = abs(q) - vec3<f32>(0.5, 0.5, 0.5) * sharp;

        let rot1 = rot(PI / 4.0 + 0.1 * f32(i));
        let qxy = rot1 * q.xy;
        q = vec3<f32>(qxy.x, qxy.y, q.z);

        let rot2 = rot(PI / 3.0);
        let qxz = rot2 * vec2<f32>(q.x, q.z);
        q = vec3<f32>(qxz.x, q.y, qxz.y);

        q *= s;
        d = min(d, length(max(abs(q) - 0.2, vec3<f32>(0.0))) / pow(s, f32(i+1)));
    }
    return d;
}


// Spatial distortion based on mouse
fn applyGravityWell(p: vec3<f32>, ro: vec3<f32>) -> vec3<f32> {
    if (u.zoom_config.w <= 0.0) {
        return p;
    }

    // Map mouse UV to world space approx
    let mouse_uv = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let ndc = (mouse_uv * 2.0 - 1.0) * vec2<f32>(u.config.z / u.config.w, -1.0);

    // Construct ray direction for mouse (simplified)
    let cd = normalize(vec3<f32>(0.0, 0.0, 1.0));
    let cu = normalize(vec3<f32>(0.0, 1.0, 0.0));
    let cr = normalize(cross(cd, cu));
    let m_rd = normalize(ndc.x * cr + ndc.y * cu + 2.0 * cd);

    // Assume mouse intersects a plane at z = 3.0
    let t = (3.0 - ro.z) / m_rd.z;
    let gravity_center = ro + m_rd * t;

    let d = length(p - gravity_center);
    let pull = 1.0 / (1.0 + d * d * 0.5);

    var q = p;
    // Radial contraction
    q = mix(q, gravity_center, pull * 0.5);

    // Twist
    let twist = pull * 2.0;
    let r = rot(twist);
    let qxy = r * (q.xy - gravity_center.xy);
    q = vec3<f32>(qxy.x + gravity_center.xy.x, qxy.y + gravity_center.xy.y, q.z);

    return q;
}

// Scene SDF
fn map(pos_in: vec3<f32>, ro: vec3<f32>, audio: f32) -> vec2<f32> {
    var p = applyGravityWell(pos_in, ro);

    let time = u.config.x;
    let sharp = u.zoom_params.x;     // Crystal Sharpness
    let flowSpeed = u.zoom_params.y; // Flow Speed
    let aetherDen = u.zoom_params.z; // Aether Density

    let flowOffset = vec3<f32>(0.0, 0.0, time * 0.5 * flowSpeed);
    p += flowOffset;

    // Deform space with curl noise
    let curl = curlNoise(p * 0.5 + time * 0.2);
    let p_org = p + curl * 0.2 * aetherDen;

    // Organic Labyrinth (Gyroid + fBM)
    let d_org = sdGyroid(p_org, 2.0, 0.05 + audio * 0.05, 0.0) + fbm(p_org * 4.0) * 0.05;

    // Rigid KIFS Lattice
    let d_kifs = sdKIFS(p, sharp);

    // Blend
    let d_final = smin(d_org, d_kifs, 0.2);

    // Material ID: 0.0 for organic, 1.0 for crystal
    let mat = smoothstep(0.0, 0.1, d_org - d_kifs);

    return vec2<f32>(d_final, mat);
}

// Normal calculation
fn calcNormal(p: vec3<f32>, ro: vec3<f32>, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, ro, audio).x;
    let n = vec3<f32>(
        map(p + e.xyy, ro, audio).x - d,
        map(p + e.yxy, ro, audio).x - d,
        map(p + e.yyx, ro, audio).x - d
    );
    return normalize(n);
}

// Fake Subsurface Scattering (Soft Shadow / Blur)
fn calcSSS(p: vec3<f32>, ro: vec3<f32>, n: vec3<f32>, l: vec3<f32>, audio: f32) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for(var i = 0; i < 5; i++) {
        let hr = 0.01 + 0.12 * f32(i) / 4.0;
        let aopos = n * hr + p;
        let dd = map(aopos, ro, audio).x;
        occ += -(dd - hr) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(dims.x) || coord.y >= i32(dims.y)) { return; }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;
    uv.y = -uv.y;

    // Audio extraction
    let bass = extraBuffer[0];
    let fft_mid = extraBuffer[10];

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 2.0));

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var mat_id = 0.0;
    let max_steps = 100;
    let max_dist = 20.0;

    var p = ro;
    var steps = 0;

    for (var i = 0; i < max_steps; i++) {
        steps = i;
        p = ro + rd * t;
        let res = map(p, ro, bass);
        d = res.x;
        mat_id = res.y;
        if (d < 0.001 || t > max_dist) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var depth = 1.0;

    if (t < max_dist) {
        let n = calcNormal(p, ro, bass);
        let v = -rd;
        let l = normalize(vec3<f32>(1.0, 2.0, -2.0));
        let h = normalize(v + l);

        let ndotv = max(dot(n, v), 0.0);
        let ndotl = max(dot(n, l), 0.0);
        let ndoth = max(dot(n, h), 0.0);

        // Material parameters
        let iridescenceShift = u.zoom_params.w;

        // Base Ambient/SSS
        let sss = calcSSS(p, ro, n, l, bass);

        if (mat_id < 0.5) {
            // Organic Nacreous
            let iridescence_t = ndotv + iridescenceShift + p.z * 0.1;
            let iri_col = pal(iridescence_t, vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5), vec3<f32>(1.0,1.0,1.0), vec3<f32>(0.0,0.33,0.67));

            let diffuse = ndotl * iri_col;
            let specular = pow(ndoth, 16.0) * vec3<f32>(1.0);

            col = diffuse * 0.8 + specular * 0.5 + iri_col * sss * 0.5;

            // Bioluminescent glow from audio
            col += iri_col * fft_mid * 2.0 * sss;

        } else {
            // Rigid Crystalline
            let metallic_col = vec3<f32>(0.7, 0.8, 0.9);
            let diffuse = ndotl * metallic_col * 0.2;
            let specular = pow(ndoth, 64.0) * vec3<f32>(1.0, 1.0, 1.0);

            // Chromatic aberration at grazing angles
            let fresnel = pow(1.0 - ndotv, 5.0);
            let r = pow(ndoth, 32.0);
            let g = pow(max(dot(n, normalize(l + vec3<f32>(0.1, 0.0, 0.0))), 0.0), 32.0);
            let b = pow(max(dot(n, normalize(l + vec3<f32>(-0.1, 0.0, 0.0))), 0.0), 32.0);
            let chromatic = vec3<f32>(r, g, b);

            col = diffuse + specular + fresnel * metallic_col + chromatic * 0.5;
        }

        // Fake AO based on steps
        col *= 1.0 - f32(steps) / f32(max_steps);

        // Fog
        col = mix(col, vec3<f32>(0.02, 0.05, 0.1), 1.0 - exp(-0.05 * t * t));
        depth = t / max_dist;
    } else {
        // Aether Background
        let bg_dir = rd;
        let bg_noise = fbm(bg_dir * 10.0 + u.config.x * 0.1);
        col = vec3<f32>(0.02, 0.05, 0.1) * bg_noise * (1.0 + bass);
    }

    // Tonemapping and gamma
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    let current_frame = vec4<f32>(col, 1.0);

    // Temporal blending (history)
    let history_coord = vec2<i32>(coord);
    let history = textureLoad(readTexture, history_coord, 0);
    let blend_factor = 0.8;
    let final_color = mix(current_frame, history, blend_factor);

    textureStore(writeTexture, coord, final_color);
    textureStore(dataTextureA, coord, final_color);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
