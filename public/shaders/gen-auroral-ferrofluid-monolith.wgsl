// ----------------------------------------------------------------
// Auroral Ferrofluid-Monolith
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Spike Length, y=Aurora Intensity, z=Magnetic Twist, w=Fluid Metallic
    ripples: array<vec4<f32>, 50>,
};

// Utils
fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// Simple value noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash33(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash33(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash33(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(dot(hash33(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash33(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash33(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash33(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var q = p;
    var a = 0.5;
    for(var i=0; i<4; i++) {
        f += a * noise(q);
        q *= 2.01;
        a *= 0.5;
    }
    return f;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

// Map function for the monolith
fn map(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;

    // Magnetic twist
    let twist = u.zoom_params.z;
    p.xz = rot(p.y * twist * 0.5 + u.config.x * 0.2) * p.xz;

    // Mouse magnetic pole distortion
    let mx = (u.zoom_config.y - 0.5) * 10.0;
    let my = -(u.zoom_config.z - 0.5) * 10.0;
    let mousePole = vec3<f32>(mx, my, 0.0);
    let dPole = length(p - mousePole);
    let poleDistort = exp(-dPole * 0.5) * 0.5;

    // Monolith base shape
    let size = vec3<f32>(1.0 - p.y*0.05, 4.0, 1.0 - p.y*0.05);
    var d1 = sdBox(p, size);

    // Ferrofluid spikes
    let audio = u.config.y;
    let spikeLength = u.zoom_params.x * (1.0 + audio * 2.0) + poleDistort;

    var sp = p * 4.0;
    let n = abs(noise(sp + vec3<f32>(0.0, -u.config.x * 2.0, 0.0)));
    let spikes = pow(1.0 - n, 8.0) * spikeLength;

    d1 -= spikes;

    // Ensure smoothing
    return vec2<f32>(d1, 1.0); // 1.0 = material ID
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.005, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Aurora density function
fn mapAurora(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    let dBox = sdBox(p, vec3<f32>(1.5, 4.5, 1.5));
    if (dBox > 2.0) { return 0.0; } // Optimization

    p.xz = rot(p.y * 0.5 - u.config.x * 0.5) * p.xz;

    let f1 = fbm(p * 1.5 + vec3<f32>(0.0, u.config.x, 0.0));
    let f2 = fbm(p * 3.0 - vec3<f32>(u.config.x, 0.0, u.config.x));

    let density = smoothstep(0.4, 0.8, f1 * f2);
    let falloff = smoothstep(2.0, 0.0, dBox);

    return density * falloff * u.zoom_params.y;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord - 0.5 * res) / res.y;

    // Camera
    let ro = vec3<f32>(0.0, 0.0, 8.0);
    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let cw = normalize(ta - ro);
    let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0)));
    let cv = normalize(cross(cu, cw));
    let rd = normalize(uv.x * cu + uv.y * cv + 1.2 * cw);

    // Raymarch monolith
    var t = 0.0;
    var tMax = 20.0;
    var hit = false;
    var m = 0.0;

    for(var i=0; i<100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if(d.x < 0.002) {
            hit = true;
            m = d.y;
            break;
        }
        if(t > tMax) { break; }
        t += d.x * 0.5; // slow down for spikes
    }

    var col = vec3<f32>(0.0);

    // Monolith shading
    if(hit) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        // Lighting
        let l1 = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let l2 = normalize(vec3<f32>(-1.0, -0.5, 0.5));

        let dif1 = max(dot(n, l1), 0.0);
        let dif2 = max(dot(n, l2), 0.0);

        let h1 = normalize(l1 + v);
        let spe1 = pow(max(dot(n, h1), 0.0), 32.0);

        let f0 = 0.04;
        let fresnel = f0 + (1.0 - f0) * pow(1.0 - max(dot(n, v), 0.0), 5.0);

        let baseCol = vec3<f32>(0.05, 0.05, 0.08); // Dark chrome
        let metal = u.zoom_params.w;

        col = baseCol * (dif1 + dif2 * 0.5);
        col += vec3<f32>(1.0) * spe1 * metal;
        col = mix(col, vec3<f32>(0.5, 0.8, 1.0), fresnel * metal);

        // Audio reactive chromatic dispersion on tips (based on normal variation)
        let audio = u.config.y;
        if (audio > 0.1) {
            let tipGlow = smoothstep(0.7, 1.0, n.y) * audio;
            col += vec3<f32>(0.8, 0.2, 1.0) * tipGlow;
        }
    } else {
        t = tMax; // for volumetric pass limit
    }

    // Volumetric Aurora Pass
    var aurCol = vec3<f32>(0.0);
    var tVol = 0.0;
    let stepSize = 0.1;

    // Offset start for dither
    tVol += hash33(vec3<f32>(uv, u.config.x)).x * stepSize;

    for(var i=0; i<60; i++) {
        if(tVol >= t) { break; } // stop at geometry

        let p = ro + rd * tVol;
        let den = mapAurora(p);

        if(den > 0.01) {
            // Color gradient based on height and density
            let c1 = vec3<f32>(0.0, 1.0, 0.5); // Cyan/Green
            let c2 = vec3<f32>(1.0, 0.0, 0.8); // Magenta

            let c = mix(c1, c2, sin(p.y + u.config.x) * 0.5 + 0.5);
            aurCol += c * den * stepSize * 2.0;
        }

        tVol += stepSize;
    }

    col += aurCol;

    // Background glow
    let bgGlow = max(0.0, 1.0 - length(uv)) * 0.1;
    col += vec3<f32>(0.1, 0.1, 0.2) * bgGlow;

    // Tone mapping
    col = col / (1.0 + col);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
