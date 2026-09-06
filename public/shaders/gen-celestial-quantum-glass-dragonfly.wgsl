// ═══════════════════════════════════════════════════════════════════
//  gen-celestial-quantum-glass-dragonfly
//  Category: generative
//  Features: dragonfly, quantum, fractal, audio-reactive, raymarching, crystalline
//  Ideas: Cauchy thin-film wing iridescence, quantum glass caustic core & photon emission, acoustic wing-tip vortex trails
//  A packing: display RGBA (RGB=ACES tone-mapped dragonfly scene, A=semantic wing/body alpha)
// ═══════════════════════════════════════════════════════════════════

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
    zoom_params: vec4<f32>,  // x=Wing Frequency, y=Fractal Density, z=Refraction Index, w=Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

fn rot3x(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}

fn rot3y(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn rot3z(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn noise3(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_pow = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(p + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), f_pow.x),
            mix(dot(hash3(p + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(p + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), f_pow.x), f_pow.y),
        mix(
            mix(dot(hash3(p + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(p + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), f_pow.x),
            mix(dot(hash3(p + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(p + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), f_pow.x), f_pow.y), f_pow.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var x = p;
    for (var i = 0; i < 4; i = i + 1) {
        f = f + w * noise3(x);
        x = x * 2.01;
        w = w * 0.5;
    }
    return f;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdCappedCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - vec2<f32>(r, h);
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

fn mapWings(p: vec3<f32>, audio_mod: f32) -> f32 {
    var p_w = p;
    let wing_freq = u.zoom_params.x;
    let time = u.config.x * wing_freq * (1.0 + audio_mod * 0.5);

    p_w.y -= sin(time + abs(p_w.x) * 1.5) * 0.4 * abs(p_w.x);
    p_w.z += cos(time + abs(p_w.x) * 1.5) * 0.2 * abs(p_w.x);

    let fractal_density = u.zoom_params.y;
    var p_f = p_w;
    var scale = 1.0;
    for (var i = 0; i < 4; i = i + 1) {
        p_f = abs(p_f) - vec3<f32>(0.5, 0.1, 0.2) / scale;
        let r_mat = rot3y(0.5 * audio_mod) * rot3z(0.3);
        p_f = r_mat * p_f;
        p_f *= 1.8;
        scale *= 1.8;
    }

    let base_wing = sdBox(p_w, vec3<f32>(2.5, 0.02, 0.6));
    let venation = sdBox(p_f, vec3<f32>(1.5, 0.1, 1.0)) / scale;

    return max(base_wing, -venation * fractal_density * 0.5);
}

fn mapBody(p: vec3<f32>, audio_mod: f32) -> f32 {
    var p_thorax = p;
    p_thorax.y += sin(p.z * 1.5) * 0.1;
    let thorax = sdCappedCylinder(p_thorax.xzy, 0.8, 0.3);

    let head = sdSphere(p - vec3<f32>(0.0, 0.1, 1.0), 0.35);

    var p_tail = p;
    p_tail.z -= -1.0;
    p_tail.y += sin(p_tail.z * 2.0 + u.config.x * 2.0) * 0.2;
    let tail_base = sdCappedCylinder(p_tail.xzy, 1.5, 0.15 - p_tail.z * 0.05);
    let tail_segments = cos(p_tail.z * 15.0) * 0.05;
    let tail = tail_base + tail_segments;

    var body = smin(thorax, head, 0.2);
    body = smin(body, tail, 0.3);
    return body;
}

fn mapScene(p: vec3<f32>, mouse_pos: vec3<f32>, audio: f32) -> vec2<f32> {
    var p_mod = p;
    let time = u.config.x;

    let dist_mouse = length(p_mod - mouse_pos);
    let vortex_strength = 2.0;
    if (dist_mouse > 0.001) {
        p_mod -= normalize(p_mod - mouse_pos) * exp(-dist_mouse * 2.0) * vortex_strength;
    }

    p_mod = rot3x(-0.3 + sin(time * 0.5) * 0.1) * rot3y(sin(time * 0.2) * 0.2) * p_mod;

    let body = mapBody(p_mod, audio);

    var p_wings1 = p_mod;
    p_wings1.z -= 0.2;
    var p_wings2 = p_mod;
    p_wings2.z += 0.4;

    let wings1 = mapWings(p_wings1, audio);
    let wings2 = mapWings(p_wings2, audio * 0.8);
    let wings = min(wings1, wings2);

    let isWing = select(0.0, 1.0, wings < body);
    return vec2<f32>(min(body, wings), isWing);
}

fn getNormal(p: vec3<f32>, mouse_pos: vec3<f32>, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        mapScene(p + e.xyy, mouse_pos, audio).x - mapScene(p - e.xyy, mouse_pos, audio).x,
        mapScene(p + e.yxy, mouse_pos, audio).x - mapScene(p - e.yxy, mouse_pos, audio).x,
        mapScene(p + e.yyx, mouse_pos, audio).x - mapScene(p - e.yyx, mouse_pos, audio).x
    ));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coord = vec2<i32>(id.xy);
    if (f32(coord.x) >= res.x || f32(coord.y) >= res.y) { return; }

    let uv = (vec2<f32>(coord) - 0.5 * res) / res.y;
    let time = u.config.x;
    
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio  = bass * 1.2 + mids * 0.6;

    // Single-writer spring-damper cursor for dragonfly agility in extraBuffer[133..138]
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var sprungMouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        sprungMouse = rawMouse;
        mouseVel = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 8.5;
    mouseVel += ((rawMouse - sprungMouse) * (omega * omega) - mouseVel * (2.0 * omega)) * dt;
    sprungMouse += mouseVel * dt;

    if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = sprungMouse.x;
        extraBuffer[134] = sprungMouse.y;
        extraBuffer[135] = mouseVel.x;
        extraBuffer[136] = mouseVel.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }

    let mx = (sprungMouse.x - 0.5) * 6.0;
    let my = (sprungMouse.y - 0.5) * 4.0;
    let mouse_pos = vec3<f32>(mx, my, 0.0);

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    let rd = normalize(vec3<f32>(uv, 1.0));

    // Volumetric Plasma Storm (Background) + IDEA 3: Acoustic wing-tip vortex trails
    var fog_col = vec3<f32>(0.0);
    var t_fog = 0.0;
    let fog_steps = 28;
    for (var i = 0; i < fog_steps; i = i + 1) {
        let p_fog = ro + rd * t_fog;
        let d = fbm(p_fog * 0.5 + vec3<f32>(time * 0.2, 0.0, time * 0.1)) * 0.5 + 0.5;
        let fog_density = smoothstep(0.4, 0.8, d) * 0.05;

        // Wingtip vortex swirls in the plasma
        let vortexWave = sin(length(p_fog.xy - mouse_pos.xy) * 4.0 - time * 8.0 * u.zoom_params.x);
        let vortexEmission = pow(max(vortexWave, 0.0), 6.0) * (0.4 + treble * 1.5);

        let pollen = pow(abs(sin(p_fog.x * 5.0 + time) * cos(p_fog.y * 5.0) * sin(p_fog.z * 5.0 - time)), 20.0);
        let glow = vec3<f32>(0.1, 0.5, 0.8) * fog_density
                 + vec3<f32>(0.8, 0.2, 0.9) * pollen * audio
                 + vec3<f32>(0.2, 0.9, 1.4) * vortexEmission * 0.08;

        fog_col += glow * exp(-t_fog * 0.1);
        t_fog += 0.55;
    }

    // Raymarching Object
    var t = 0.0;
    let max_steps = 80;
    var hit = false;
    var hitMat = 0.0;
    var p = ro;

    for (var i = 0; i < max_steps; i = i + 1) {
        p = ro + rd * t;
        let res = mapScene(p, mouse_pos, audio);
        let d = res.x;
        if (d < 0.001) { hit = true; hitMat = res.y; break; }
        if (t > 15.0) { break; }
        t += d * 0.8;
    }

    var col = fog_col;
    var semanticAlpha = 0.0;

    if (hit) {
        let n = getNormal(p, mouse_pos, audio);
        let v = -rd;

        let l1 = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let l2 = normalize(vec3<f32>(-1.0, -0.5, -0.5));

        let dif1 = max(dot(n, l1), 0.0);
        let dif2 = max(dot(n, l2), 0.0);
        let ndotv = max(dot(n, v), 0.0);
        let fre = pow(1.0 - ndotv, 3.0);

        // IDEA 1: Cauchy thin-film dragonfly wing iridescence
        let refr_idx = u.zoom_params.z;
        let etaR = refr_idx;
        let etaG = refr_idx * 1.08;
        let etaB = refr_idx * 1.16;

        let refr_dir_r = refract(rd, n, 1.0 / etaR);
        let refr_dir_g = refract(rd, n, 1.0 / etaG);
        let refr_dir_b = refract(rd, n, 1.0 / etaB);

        let refr_col = vec3<f32>(
            fbm(p + refr_dir_r * 0.5 + vec3<f32>(time, 0.0, 0.0)),
            fbm(p + refr_dir_g * 0.6 + vec3<f32>(0.0, time, 0.0)),
            fbm(p + refr_dir_b * 0.7 + vec3<f32>(0.0, 0.0, time))
        );

        let wingThinFilm = 0.5 + 0.5 * cos(ndotv * 16.0 + vec3<f32>(0.0, 2.094, 4.188));

        var mat_col = mix(vec3<f32>(0.05, 0.1, 0.2), vec3<f32>(0.2, 0.8, 0.9), fre);
        mat_col += refr_col * 0.5;
        mat_col = mix(mat_col, mat_col + wingThinFilm * 0.8, hitMat * (0.8 + treble * 0.4));

        let h1 = normalize(l1 + v);
        let spec = pow(max(dot(n, h1), 0.0), 64.0) * 2.0;

        // IDEA 2: Quantum glass caustic core & bioluminescent photon emission
        let glow_int = u.zoom_params.w;
        let pulse = sin(p.z * 6.0 - time * 12.0 * u.zoom_params.x) * 0.5 + 0.5;
        let lum = vec3<f32>(0.1, 0.85, 1.1) * pulse * audio * glow_int * smoothstep(0.3, 1.0, abs(p.z));
        let eyeGlow = vec3<f32>(1.2, 0.3, 0.9) * smoothstep(0.8, 1.1, p.z) * glow_int;

        col = mat_col * (dif1 * vec3<f32>(1.0) + dif2 * vec3<f32>(0.2, 0.3, 0.5)) + spec + lum + eyeGlow;
        col = mix(col, fog_col, smoothstep(6.0, 15.0, t));

        semanticAlpha = mix(0.95, 0.65, hitMat); // Body is solid 0.95, wing is glass 0.65
    } else {
        semanticAlpha = clamp(length(fog_col) * 0.3, 0.0, 0.4);
    }

    // Exact-integer textureLoad from dataTextureC previous frame feedback
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    let blended = mix(col, prev, 0.06);

    let displayRGB = acesFilm(max(blended, vec3<f32>(0.0)));
    let normDepth = select(1.0, clamp(t / 15.0, 0.0, 0.99), hit);

    textureStore(writeTexture, coord, vec4<f32>(displayRGB, semanticAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(normDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(displayRGB, semanticAlpha));
}
