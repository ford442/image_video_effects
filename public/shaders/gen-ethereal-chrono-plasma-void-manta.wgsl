// ----------------------------------------------------------------
// Ethereal Chrono-Plasma Void-Manta
// Category: generative
// Visualist upgrade: dual auroral light sources, volumetric dark-matter fog,
// Fresnel-iridescent wing membranes, god rays, ACES + hue clamp + IGN dither.
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

// Custom Parameters Mapping:
// zoom_params.x = Manta Speed
// zoom_params.y = Bio-Luminescence Intensity
// zoom_params.z = Wing Ripple Frequency
// zoom_params.w = Dark Matter Density

const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash(p: vec3<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x * 0.1031, p.y * 0.1030, p.z * 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_new = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let f_final = f_new;
    return mix(mix(mix(hash(p + vec3<f32>(0.0, 0.0, 0.0)),
                        hash(p + vec3<f32>(1.0, 0.0, 0.0)), f_final.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 0.0)),
                        hash(p + vec3<f32>(1.0, 1.0, 0.0)), f_final.x), f_final.y),
               mix(mix(hash(p + vec3<f32>(0.0, 0.0, 1.0)),
                        hash(p + vec3<f32>(1.0, 0.0, 1.0)), f_final.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 1.0)),
                        hash(p + vec3<f32>(1.0, 1.0, 1.0)), f_final.x), f_final.y), f_final.z);
}

fn fbm3(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(pp);
        pp = pp * 2.0 + vec3<f32>(f32(i) * 12.34);
        a *= 0.5;
    }
    return v;
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
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

fn iridescence(cosTheta: f32, time: f32) -> vec3<f32> {
    let t = 1.0 - cosTheta;
    let hue = 0.55 + 0.25 * sin(t * 6.0 + time * 0.7) + 0.15 * cos(t * 9.0 - time * 0.4);
    return hsv2rgb(vec3<f32>(fract(hue), 0.75, 1.0));
}

// Scene SDF
fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let time = u.config.x * u.zoom_params.x;
    let audio = u.config.y;

    // Manta motion
    let flap = sin(pos.x * u.zoom_params.z - time * 3.0) * (pos.x * pos.x) * 0.2;
    pos.y += flap;

    // Core body (flattened sphere)
    let body_d = (length(pos / vec3<f32>(1.0, 0.2, 2.0)) - 1.0) * 0.2;

    // Wings (displaced plane with chrono-plasma ripple)
    let wingNoise = fbm3(pos * 1.5 + vec3<f32>(0.0, 0.0, time * 0.5));
    let wing_d = pos.y + wingNoise * 0.5 * (1.0 + audio);

    // Blend body and wings
    let manta_d = smin(body_d * 0.5, abs(wing_d) - 0.1, 0.5);

    // Material ID: 1.0 for manta, 0.0 for background
    return vec2<f32>(manta_d, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize( e.xyy*map( p + e.xyy ).x +
                      e.yyx*map( p + e.yyx ).x +
                      e.yxy*map( p + e.yxy ).x +
                      e.xxx*map( p + e.xxx ).x );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = (vec2<f32>(id.xy) - 0.5 * resolution) / min(resolution.x, resolution.y);

    let time = u.config.x;
    let audio = u.config.y;
    let bio = u.zoom_params.y;
    let darkMatter = u.zoom_params.w;

    // Read previous frame for subtle temporal blend
    let prev = textureSampleLevel(readTexture, u_sampler, vec2<f32>(id.xy) / resolution, 0.0);
    let prevDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(id.xy) / resolution, 0.0).r;

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0, -5.0);
    var rd = normalize(vec3<f32>(uv, 1.5));

    // Mouse rotation
    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 6.28;
    let new_ro_yz = rot(-mouse.y) * ro.yz;
    ro.y = new_ro_yz.x;
    ro.z = new_ro_yz.y;
    let new_rd_yz = rot(-mouse.y) * rd.yz;
    rd.y = new_rd_yz.x;
    rd.z = new_rd_yz.y;
    let new_ro_xz = rot(-mouse.x) * ro.xz;
    ro.x = new_ro_xz.x;
    ro.z = new_ro_xz.y;
    let new_rd_xz = rot(-mouse.x) * rd.xz;
    rd.x = new_rd_xz.x;
    rd.z = new_rd_xz.y;

    // Light sources
    let keyLight = normalize(vec3<f32>(1.0, 2.0, -1.0));
    let fillLight = normalize(vec3<f32>(-1.5, 0.5, -0.5));
    let rimLightDir = normalize(vec3<f32>(0.0, 1.0, 1.0));
    let keyColor = vec3<f32>(1.3, 0.75, 0.35); // warm auroral sun
    let fillColor = vec3<f32>(0.25, 0.6, 1.4); // cool deep-space fill
    let rimColor = vec3<f32>(1.1, 0.3, 1.6);   // magenta rim

    // Raymarching loop
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var hit = false;
    var hitP = vec3<f32>(0.0);
    var bg_density = 0.0;
    var sss = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);

        // Accumulate dark-matter density along ray
        bg_density += noise(p * 0.5 + vec3<f32>(time * 0.1)) * darkMatter * 0.02;

        if (d.x < 0.001) {
            hit = true;
            hitP = p;
            let n = calcNormal(p);

            let diffKey = max(dot(n, keyLight), 0.0);
            let diffFill = max(dot(n, fillLight), 0.0) * 0.5;
            let rim = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);

            // Subsurface / bio-luminescence
            let thickness = map(p + n * 0.1).x;
            sss = smoothstep(0.0, 0.1, abs(thickness)) * bio;

            let base_col = vec3<f32>(0.08, 0.18, 0.45);
            let glow_col = vec3<f32>(1.0, 0.15, 0.75) * (1.0 + audio * 2.0);

            // Iridescent wing rim
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let iris = iridescence(fresnel, time) * fresnel * 2.2;

            col = base_col * (keyColor * diffKey + fillColor * diffFill)
                + glow_col * sss
                + rimColor * rim * 1.8
                + iris;
            break;
        }
        if (t > 20.0) { break; }
        t += d.x;
    }

    if (!hit) {
        // Deep space / dark matter color with volumetric tint
        col = vec3<f32>(0.02, 0.01, 0.05) + vec3<f32>(0.25, 0.12, 0.5) * bg_density;
        t = 20.0;
    }

    // Volumetric god rays / fog in the void
    var fogAccum = 0.0;
    for (var i = 0; i < 24; i++) {
        let fi = f32(i);
        let fp = ro + rd * (fi * 0.6);
        let fogDen = max(0.0, noise(fp * 0.4 + vec3<f32>(time * 0.08, 0.0, time * 0.05)) - 0.35);
        fogAccum += fogDen * darkMatter * 0.04;
    }
    let fogColor = mix(vec3<f32>(0.1, 0.0, 0.25), vec3<f32>(0.0, 0.5, 0.7), 0.5);
    col += fogColor * fogAccum * 2.0;

    // Audio bloom on hit distance
    col += vec3<f32>(0.2, 0.5, 1.0) * audio * bio * (1.0 / (1.0 + t * t * 0.05));

    // Temporal blend with previous frame
    col = mix(col, prev.rgb, 0.08);

    // HDR clamp preserving hue
    col = hue_preserving_clamp(col, 8.0);

    // ACES tone mapping
    col = aces_tone_map(col);

    // IGN dither
    let dither = (ign_dither(vec2<f32>(id.xy)) - 0.5) / 255.0;
    col = clamp(col + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha based on emission density and hit depth
    let alpha = select(clamp(0.15 + fogAccum + bg_density * 0.5, 0.0, 1.0),
                       clamp(0.85 + sss * 0.15, 0.0, 1.0), hit);

    textureStore(writeTexture, coords, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coords, vec4<f32>(clamp(t * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(fogAccum, bg_density, select(0.0, sss, hit), alpha));
}
