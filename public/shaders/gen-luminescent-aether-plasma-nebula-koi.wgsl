// ═══════════════════════════════════════════════════════════════════
//  Luminescent Aether-Plasma Nebula-Koi
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-13
//  Ideas: tail-fin Karman wake shed into the volumetric nebula (phase-locked to tail, bass);
//         half-offset scale rows with head-to-tail turning flash (mids) and rim sparkle (treble);
//         exact dataTextureC persistence that lingers longer inside the wake
//  A packing: ACES display RGBA (read back from C as display history)
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + vec3<f32>(33.33));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec3<f32>(8.0);
    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + g);
                let r = g - f + o;
                let d = dot(r, r);
                if (d < m.x) {
                    m = vec3<f32>(d, m.x, m.y);
                } else if (d < m.y) {
                    m = vec3<f32>(m.x, d, m.y);
                }
            }
        }
    }
    return vec2<f32>(sqrt(m.x), sqrt(m.y));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn mapKoi(p_in: vec3<f32>, time: f32, koi_speed: f32, tail_length: f32) -> f32 {
    var p = p_in;

    // Sinuous swimming motion
    let wave = sin(p.z * 2.0 - time * koi_speed * 3.0) * 0.5;
    p.x += wave;

    // Body (Capsule/spindle-like)
    let body_len = 2.0;
    let p_body = p - vec3<f32>(0.0, 0.0, 0.0);

    var clamped_z = p_body.z;
    if (clamped_z < -body_len) {
        clamped_z = -body_len;
    } else if (clamped_z > body_len) {
        clamped_z = body_len;
    }
    let dz = p_body.z - clamped_z;

    var body_radius = 0.4 * (1.0 - abs(p_body.z) / (body_len + 0.1));
    body_radius = max(0.01, body_radius);
    let d_body = length(vec2<f32>(p_body.x, p_body.y)) - body_radius + dz*dz;

    // Fins
    let fin_p = vec3<f32>(abs(p.x) - body_radius - 0.1, p.y, p.z);
    var d_fins = length(vec2<f32>(fin_p.x, fin_p.y)) - 0.02;
    d_fins = max(d_fins, abs(p.z) - 0.5);

    // Tail
    let tail_p = p - vec3<f32>(0.0, 0.0, -body_len - tail_length * 0.5);
    let tail_wave = sin(tail_p.z * 5.0 - time * koi_speed * 5.0) * 0.5;
    let d_tail = length(vec2<f32>(tail_p.x + tail_wave, tail_p.y)) - (0.3 - abs(tail_p.z)*0.2) + abs(tail_p.z)-tail_length*0.5;

    var d = smin(d_body, d_tail, 0.3);
    d = smin(d, d_fins, 0.2);

    return d;
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    var f = 0.0;
    var amp = 0.5;
    for(var i = 0; i < 4; i++) {
        f += amp * (voronoi(p).x * 2.0 - 1.0);
        p *= 2.0;
        amp *= 0.5;
    }
    return f;
}

// Idea 1: Karman vortex street behind the tail. Alternating puffs are shed at the tail tip,
// advect downstream with koi_speed, and fade with distance. Returns wake density at np.
fn koiWake(np: vec3<f32>, time: f32, koi_speed: f32, tail_length: f32, bass: f32) -> f32 {
    let tail_tip = -2.0 - tail_length;
    let s = tail_tip - np.z;                         // distance downstream of the tail tip
    let spacing = 0.55;
    let u_cell = (s - time * koi_speed * 0.45) / spacing;
    let k = floor(u_cell);
    let side = select(-1.0, 1.0, fract(k * 0.5) < 0.25);
    // puffs inherit the tail's lateral wave phase at the moment they were shed
    let shed_wave = sin((tail_tip - (k + 0.5) * spacing) * 5.0 - time * koi_speed * 5.0) * 0.25;
    let lateral = side * (0.35 + tail_length * 0.08) + shed_wave;
    let q = vec3<f32>(np.x - lateral, np.y, (fract(u_cell) - 0.5) * spacing);
    let r = 0.16 + clamp(bass, 0.0, 1.5) * 0.06;
    let puff = exp(-dot(q, q) / max(r * r, 0.0001));
    let downstream = step(0.0, s) * exp(-max(s, 0.0) * 0.35);
    return puff * downstream * (0.6 + clamp(bass, 0.0, 1.5) * 0.7);
}

// Idea 2: overlapping koi scale rows along the body axis, odd rows half-offset.
// Returns (rim, cell-centre) for the hit point.
fn koiScaleRows(p: vec3<f32>, time: f32, koi_speed: f32) -> vec2<f32> {
    let wave = sin(p.z * 2.0 - time * koi_speed * 3.0) * 0.5;
    let theta = atan2(p.y, p.x + wave);
    let rz = p.z * 9.0;
    let row = floor(rz);
    let off = select(0.0, 0.5, fract(row * 0.5) > 0.25);
    let cell = vec2<f32>(fract(rz), fract(theta * 5.0 / PI + off));
    let dsc = length((cell - vec2<f32>(1.0, 0.5)) * vec2<f32>(1.0, 1.3));
    let rim = smoothstep(0.62, 0.72, dsc) * (1.0 - smoothstep(0.8, 0.95, dsc));
    let centre = 1.0 - smoothstep(0.0, 0.7, dsc);
    return vec2<f32>(rim, centre);
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + k.xyz) * vec3<f32>(6.0) - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let v = max(c.r, max(c.g, c.b));
    let minc = min(c.r, min(c.g, c.b));
    let s = select(0.0, (v - minc) / v, v > 0.0);
    let delta = v - minc;
    var h = 0.0;
    if (delta > 0.0) {
        if (v == c.r) { h = (c.g - c.b) / delta; }
        else if (v == c.g) { h = 2.0 + (c.b - c.r) / delta; }
        else { h = 4.0 + (c.r - c.g) / delta; }
    }
    h = fract(h / 6.0 + 1.0);
    return vec3<f32>(h, s, v);
}

fn hue_preserving_clamp(c: vec3<f32>, max_val: f32) -> vec3<f32> {
    let hsv = rgb2hsv(c);
    return hsv2rgb(vec3<f32>(hsv.x, hsv.y, min(hsv.z, max_val)));
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51);
    let b = vec3<f32>(0.03);
    let c = vec3<f32>(2.43);
    let d = vec3<f32>(0.59);
    let e = vec3<f32>(0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign_dither(uv: vec2<f32>) -> f32 {
    let p = floor(uv);
    return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y));
}

fn iridescent_scale(cosTheta: f32, time: f32) -> vec3<f32> {
    let t = 1.0 - cosTheta;
    let hue = fract(0.52 + 0.22 * sin(t * 7.0 + time * 0.5) + 0.14 * cos(t * 4.0 - time * 0.3));
    return hsv2rgb(vec3<f32>(hue, 0.8, 1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (id.x >= dims.x || id.y >= dims.y) { return; }

    let uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * vec2<f32>(f32(dims.x), f32(dims.y))) / f32(dims.y);

    let time = u.config.x;
    // Real audio (HEAD read config.y = ripple count as "audio")
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(f32(dims.x)/f32(dims.y), 1.0);

    let plasma_intensity = u.zoom_params.x;
    let koi_speed = u.zoom_params.y;
    let nebula_density = u.zoom_params.z;
    let tail_length = u.zoom_params.w;

    // Previous display frame — exact load, no filtering on rgba32float history
    let prev = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);

    let ro = vec3<f32>(0.0, 0.0, 5.0);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Mouse interaction - bend rays (gravitational ripple)
    let mouse_dist = length(uv - mouse);
    if (mouse_dist < 0.5) {
        let pull = (0.5 - mouse_dist) * 0.5;
        rd = normalize(rd + vec3<f32>(normalize(uv - mouse + 0.0001) * pull, 0.0));
    }

    // Light sources
    let keyLight = normalize(vec3<f32>(1.0, 1.0, -0.5));
    let fillLight = normalize(vec3<f32>(-1.0, 0.4, -0.3));
    let rimLightDir = normalize(vec3<f32>(0.0, -1.0, 1.0));
    let keyColor = vec3<f32>(1.25, 0.7, 0.3);  // warm aether sun
    let fillColor = vec3<f32>(0.2, 0.55, 1.3); // cool nebula fill
    let rimColor = vec3<f32>(1.0, 0.3, 1.5);   // violet rim

    // Raymarch Koi
    var col = vec3<f32>(0.0);
    var t = 0.0;
    var hit = false;
    var p = vec3<f32>(0.0);
    var fresnel = 0.0;
    var sss = 0.0;

    for(var i = 0; i < 80; i++) {
        p = ro + rd * t;
        let d = mapKoi(p, time, koi_speed, tail_length);
        if (d < 0.005) {
            hit = true;
            break;
        }
        t += d * 0.5;
        if (t > 10.0) { break; }
    }

    if (hit) {
        // Approximate normal via central differences on SDF
        let e = vec2<f32>(0.002, 0.0);
        let n = normalize(vec3<f32>(
            mapKoi(p + e.xyy, time, koi_speed, tail_length) - mapKoi(p - e.xyy, time, koi_speed, tail_length),
            mapKoi(p + e.yxy, time, koi_speed, tail_length) - mapKoi(p - e.yxy, time, koi_speed, tail_length),
            mapKoi(p + e.yyx, time, koi_speed, tail_length) - mapKoi(p - e.yyx, time, koi_speed, tail_length)
        ));

        let v = voronoi(p * 5.0 + vec3<f32>(0.0, 0.0, time));
        let scale_pattern = v.y - v.x;

        let base_col = vec3<f32>(0.1, 0.35, 0.75);
        let glow_col = vec3<f32>(0.95, 0.2, 0.85) * plasma_intensity * (1.0 + clamp(bass, 0.0, 1.5) * 0.6);

        let diffKey = max(dot(n, keyLight), 0.0);
        let diffFill = max(dot(n, fillLight), 0.0) * 0.5;
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Iridescent scale shimmer
        fresnel = pow(1.0 - max(dot(-rd, n), 0.0), 2.5);
        let iris = iridescent_scale(fresnel, time) * fresnel * 2.0;

        // Subsurface plasma scattering
        sss = smoothstep(0.0, 0.05, -mapKoi(p + n * 0.05, time, koi_speed, tail_length)) * plasma_intensity;

        // Idea 2: scale rows — turning flash travels head (+z) to tail across the rows
        let rows = koiScaleRows(p, time, koi_speed);
        let flash_z = 2.2 - fract(time * 0.3 * koi_speed) * (4.4 + tail_length);
        let fz = p.z - flash_z;
        let flash = exp(-fz * fz * 4.0) * (0.35 + clamp(mids, 0.0, 1.5) * 0.9);
        let sheen = iridescent_scale(1.0 - rows.y * 0.6, time + p.z) * rows.y * flash * 1.4;
        let sparkle = vec3<f32>(1.0, 0.95, 0.85) * rows.x * (0.12 + clamp(treble, 0.0, 1.5) * 0.8) * (0.3 + diffKey);

        col = base_col * (keyColor * diffKey + fillColor * diffFill) * (0.8 + rows.y * 0.35)
            + sheen + sparkle
            + glow_col * scale_pattern
            + rimColor * rim * 1.6
            + iris
            + glow_col * sss * 0.5;
    }

    // Nebula Background (volumetric)
    var nebula_col = vec3<f32>(0.0);
    var nt = 0.0;
    var nebula_density_acc = 0.0;
    var wake_acc = 0.0;
    for(var i = 0; i < 40; i++) {
        let np = ro + rd * nt;
        let wk = koiWake(np, time, koi_speed, tail_length, bass);
        wake_acc += wk * 0.25;
        nebula_col += mix(vec3<f32>(0.1, 0.6, 0.9), vec3<f32>(0.9, 0.3, 0.95), wk) * wk * 0.05 * (0.4 + plasma_intensity);
        let den = fbm(np * 0.5 + vec3<f32>(time * 0.1, 0.0, time * 0.2));
        if (den > 0.0) {
            let nc = mix(vec3<f32>(0.12, 0.0, 0.25), vec3<f32>(0.0, 0.45, 0.65), den);
            nebula_col += nc * den * 0.08 * nebula_density;
            nebula_density_acc += den * 0.02;
        }
        nt += 0.25;
    }

    col += nebula_col;

    // God rays from above
    let rayAngle = atan2(rd.y, rd.x);
    let rays = pow(max(0.0, sin(rayAngle * 6.0 + time * 0.15)), 10.0) * 0.5;
    col += vec3<f32>(1.2, 0.8, 1.4) * rays * nebula_density;

    // Apply bloom from audio
    col += vec3<f32>(0.25, 0.55, 1.0) * (bass * 0.5 + mids * 0.2) * plasma_intensity * (1.0 / (1.0 + t*t*0.1));

    // HDR hue-preserving clamp
    col = hue_preserving_clamp(col, 8.0);

    // ACES tone mapping
    col = aces_tone_map(col);

    // Idea 3: temporal persistence from exact C history; wake regions linger like disturbed water
    let persist = clamp(0.06 + wake_acc * 0.25, 0.06, 0.35);
    col = mix(col, prev.rgb, persist);

    // IGN dither
    let dither = (ign_dither(vec2<f32>(id.xy)) - 0.5) / 255.0;
    col = clamp(col + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: emission + density + hit occlusion
    let alpha = clamp(0.2 + (select(0.0, sss + fresnel, hit) * 0.5) + nebula_density_acc + wake_acc * 0.1, 0.0, 1.0);

    // Depth: koi geometry near = 1, open nebula = 0
    let depth = select(0.0, clamp(1.0 - t * 0.1, 0.0, 1.0), hit);

    textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(col, alpha));
}
