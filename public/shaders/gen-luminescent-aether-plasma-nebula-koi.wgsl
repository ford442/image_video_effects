// ----------------------------------------------------------------
// Luminescent Aether-Plasma Nebula-Koi
// Category: generative
// Visualist upgrade: multi-temperature lighting, volumetric quantum nebula,
// iridescent koi scales, Fresnel rim glow, god rays, ACES + hue clamp + dither.
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
    let audio = u.config.y;
    let mouse = (u.zoom_config.yz - 0.5) * vec2<f32>(f32(dims.x)/f32(dims.y), 1.0);

    let plasma_intensity = u.zoom_params.x;
    let koi_speed = u.zoom_params.y;
    let nebula_density = u.zoom_params.z;
    let tail_length = u.zoom_params.w;

    // Read previous frame for subtle persistence
    let prevUV = vec2<f32>(id.xy) / vec2<f32>(dims);
    let prev = textureSampleLevel(readTexture, u_sampler, prevUV, 0.0);

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
        let glow_col = vec3<f32>(0.95, 0.2, 0.85) * plasma_intensity * (1.0 + audio * 2.0);

        let diffKey = max(dot(n, keyLight), 0.0);
        let diffFill = max(dot(n, fillLight), 0.0) * 0.5;
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Iridescent scale shimmer
        fresnel = pow(1.0 - max(dot(-rd, n), 0.0), 2.5);
        let iris = iridescent_scale(fresnel, time) * fresnel * 2.0;

        // Subsurface plasma scattering
        sss = smoothstep(0.0, 0.05, -mapKoi(p + n * 0.05, time, koi_speed, tail_length)) * plasma_intensity;

        col = base_col * (keyColor * diffKey + fillColor * diffFill)
            + glow_col * scale_pattern
            + rimColor * rim * 1.6
            + iris
            + glow_col * sss * 0.5;
    }

    // Nebula Background (volumetric)
    var nebula_col = vec3<f32>(0.0);
    var nt = 0.0;
    var nebula_density_acc = 0.0;
    for(var i = 0; i < 40; i++) {
        let np = ro + rd * nt;
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
    col += vec3<f32>(0.25, 0.55, 1.0) * audio * plasma_intensity * (1.0 / (1.0 + t*t*0.1));

    // Temporal persistence
    col = mix(col, prev.rgb, 0.06);

    // HDR hue-preserving clamp
    col = hue_preserving_clamp(col, 8.0);

    // ACES tone mapping
    col = aces_tone_map(col);

    // IGN dither
    let dither = (ign_dither(vec2<f32>(id.xy)) - 0.5) / 255.0;
    col = clamp(col + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: emission + density + hit occlusion
    let alpha = clamp(0.2 + (select(0.0, sss + fresnel, hit) * 0.5) + nebula_density_acc, 0.0, 1.0);

    textureStore(writeTexture, id.xy, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(clamp(t * 0.08, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, id.xy, vec4<f32>(select(0.0, sss, hit), nebula_density_acc, select(0.0, fresnel, hit), alpha));
}
