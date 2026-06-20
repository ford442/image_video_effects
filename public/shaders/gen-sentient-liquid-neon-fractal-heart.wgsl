// ----------------------------------------------------------------
// Sentient Liquid-Neon Fractal-Heart
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
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn getAudioRipple(p: vec3<f32>) -> f32 {
    var sum = 0.0;
    for(var i=0; i<10; i++) {
        let r = u.ripples[i];
        if (r.w > 0.0) {
            let dist = distance(p.xy, r.xy * 2.0 - 1.0);
            let wave = sin(dist * 20.0 - u.config.x * 5.0) * exp(-dist * 5.0);
            sum += wave * r.z;
        }
    }
    return sum;
}

fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    let time = u.config.x;
    let complexity = u.zoom_params.x; // default 0.5
    let pulseIntensity = u.zoom_params.y; // default 0.8

    // Heartbeat
    let beat = fract(time * 0.5);
    let pulse = exp(-beat * 4.0) * sin(beat * 20.0) * 0.2 * pulseIntensity;
    let audio = getAudioRipple(p);

    // Mouse Interaction
    var mousePos = (vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0);
    let mouseDist = length(p.xy - mousePos);
    let mouseShock = smoothstep(0.5, 0.0, mouseDist) * 0.5 * sin(time * 10.0);

    p = p / (1.0 + pulse + audio + mouseShock);

    // Fractal structure
    var d = length(p) - 1.0; // Central sphere

    var scale = 1.0;
    let iters = i32(1.0 + complexity * 5.0);

    for (var i = 0; i < iters; i++) {
        p = abs(p) - vec3<f32>(0.2, 0.1, 0.3) / scale;
        p.xy = rot(0.5 + time * 0.1) * p.xy;
        p.yz = rot(0.3 + sin(time * 0.2)) * p.yz;
        scale *= 1.5;
        let box = (max(abs(p.x), max(abs(p.y), abs(p.z))) - 0.2) / scale;
        d = smin(d, box, 0.2 / scale);
    }

    // Material ID based on distance from core
    let mat = clamp(length(p_in) * 0.5, 0.0, 1.0);

    return vec2<f32>(d, mat);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    let coords = vec2<i32>(id.xy);

    if (coords.x >= dimensions.x || coords.y >= dimensions.y) {
        return;
    }

    let resolution = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let uv = (vec2<f32>(coords) - 0.5 * resolution) / resolution.y;

    let time = u.config.x;

    var ro = vec3<f32>(0.0, 0.0, 3.5);
    var rd = normalize(vec3<f32>(uv, -1.0));

    // Subtle camera movement
    ro.xy = rot(sin(time * 0.1) * 0.2) * ro.xy;
    rd.xy = rot(sin(time * 0.1) * 0.2) * rd.xy;

    var t = 0.0;
    var col = vec3<f32>(0.0);
    var glow = 0.0;

    let neonSaturation = u.zoom_params.z; // default 0.7
    let fogDensity = u.zoom_params.w; // default 0.4

    // Raymarching
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);

        if (d.x < 0.001) {
            let n = getNormal(p);
            let l = normalize(vec3<f32>(1.0, 1.0, 1.0));
            let diff = max(dot(n, l), 0.0);

            // Subsurface scattering approx
            let sss = smoothstep(0.0, 0.5, map(p + l * 0.1).x);

            // Colors
            let mat = d.y;
            let neonColor = mix(vec3<f32>(1.0, 0.0, 0.5), vec3<f32>(0.0, 1.0, 1.0), sin(mat * 10.0 + time) * 0.5 + 0.5) * neonSaturation;
            let tissueColor = vec3<f32>(0.2, 0.0, 0.3);

            col = mix(neonColor, tissueColor, mat) * (diff * 0.5 + 0.5) + sss * vec3<f32>(0.5, 0.1, 0.2);
            break;
        }

        t += d.x * 0.5; // Step smaller for volumetric feel
        glow += 0.01 / (0.01 + d.x * d.x) * (1.0 - clamp(d.y, 0.0, 1.0));

        if (t > 10.0) { break; }
    }

    // Volumetric glow / bioluminescent fog
    let fog = vec3<f32>(0.0, 0.05, 0.1) * fogDensity * t;
    col += vec3<f32>(1.0, 0.0, 0.5) * glow * 0.05 * neonSaturation;
    col = mix(col, fog, clamp(t / 10.0, 0.0, 1.0));

    // Particles in background
    if (t > 9.0) {
       let p_bg = ro + rd * 5.0;
       let particleNoise = hash3(floor(p_bg * 5.0 + time));
       if(particleNoise.x > 0.99) {
           col += vec3<f32>(0.5, 1.0, 1.0) * (sin(time * 5.0 + particleNoise.y * 10.0) * 0.5 + 0.5);
       }
    }

    // Tone mapping
    col = clamp((col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
}
