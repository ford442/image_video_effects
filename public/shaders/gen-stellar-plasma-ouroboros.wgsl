// ----------------------------------------------------------------
// Stellar Plasma-Ouroboros
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
    zoom_params: vec4<f32>,  // x=Scale Density, y=Plasma Intensity, z=Anomaly Gravity, w=Time Warp
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                dot(hash3(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var bp = p;
    var amp = 0.5;
    for(var i=0; i<4; i++) {
        f += amp * noise(bp);
        bp *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn sdHexPrism(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let k = vec3<f32>(-0.8660254, 0.5, 0.57735);
    var p_abs = abs(p);
    p_abs.x -= 2.0 * min(dot(k.xy, p_abs.xy), 0.0) * k.x;
    p_abs.y -= 2.0 * min(dot(k.xy, p_abs.xy), 0.0) * k.y;
    let d1 = length(p_abs.xy - vec2<f32>(clamp(p_abs.x, -k.z * h.x, k.z * h.x), h.x)) * sign(p_abs.y - h.x);
    let d2 = p_abs.z - h.y;
    return min(max(d1, d2), 0.0) + length(max(vec2<f32>(d1, d2), vec2<f32>(0.0)));
}

fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    return length(p.xz) - c.x;
}

fn pModPolar(p: vec2<f32>, repetitions: f32) -> vec2<f32> {
    let angle = 6.2831853 / repetitions;
    let a = atan2(p.y, p.x) + angle / 2.0;
    let r = length(p);
    let c = floor(a / angle);
    let a_mod = (a % angle + angle) % angle - angle / 2.0;
    return vec2<f32>(cos(a_mod) * r, sin(a_mod) * r);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;

    let scaleDensity = u.zoom_params.x;
    let plasmaIntensity = u.zoom_params.y;
    let anomalyGravity = u.zoom_params.z;
    let timeWarp = u.zoom_params.w;

    let time = u.config.x * timeWarp * 0.2;
    let audioReactivity = u.config.y;

    var ro = vec3<f32>(0.0, 0.0, -10.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = -(u.zoom_config.z * 2.0 - 1.0);
    let mousePos = vec3<f32>(mouseX * 8.0, mouseY * 8.0, 0.0);

    let mouseDist = distance(ro + rd * 10.0, mousePos);
    if (mouseDist > 0.1) {
        rd = normalize(rd + (mousePos - (ro + rd * 10.0)) * (anomalyGravity * 0.1 / mouseDist));
    }

    var col = vec3<f32>(0.0);
    var t = 0.0;
    var d = 0.0;
    var glow = vec3<f32>(0.0);
    var hitPlasma = false;

    for (var i = 0; i < 100; i++) {
        var p = ro + rd * t;

        let pathDistort = vec3<f32>(sin(p.z * 0.2 + time) * 3.0, cos(p.z * 0.2 + time * 0.8) * 3.0, 0.0);
        p -= pathDistort;

        let rot1 = rotate2D(p.z * 0.1 + time * 0.5);
        let temp_p_xy = rot1 * p.xy;
        p.x = temp_p_xy.x;
        p.y = temp_p_xy.y;

        let cylD = sdCylinder(p, vec2<f32>(2.0, 0.0));

        var q = p;
        q.z = fract(q.z * (scaleDensity / 10.0)) - 0.5;
        let polar_xy = pModPolar(q.xy, scaleDensity);
        q.x = polar_xy.x;
        q.y = polar_xy.y;

        q.x -= 2.0;

        let hexD = sdHexPrism(q, vec2<f32>(0.5, 0.1));

        d = max(cylD, -hexD);

        let innerPlasma = sdCylinder(p, vec2<f32>(1.8, 0.0));

        if (d < 0.01) {
            let n_fbm = fbm(p * 2.0 + vec3<f32>(0.0, 0.0, time * 2.0));
            col = vec3<f32>(0.1, 0.2, 0.3) + vec3<f32>(0.5, 0.7, 1.0) * n_fbm;
            let refl = reflect(rd, normalize(p));
            col += textureSampleLevel(readTexture, u_sampler, refl.xy, 0.0).rgb * 0.5;
            break;
        }

        if (innerPlasma < 0.1) {
            hitPlasma = true;
            let n_plasma = fbm(p * 5.0 - vec3<f32>(0.0, 0.0, time * 5.0 + audioReactivity * 10.0));
            glow += vec3<f32>(1.0, 0.4, 0.1) * (0.05 * plasmaIntensity) / (abs(innerPlasma - n_plasma) + 0.05);
        }

        t += d * 0.5;
        if (t > 50.0) { break; }
    }

    if (!hitPlasma && d >= 0.01) {
        let stars = pow(fbm(rd * 100.0), 10.0);
        col = vec3<f32>(stars);
    }

    col += glow;
    col = clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}