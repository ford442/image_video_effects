// ----------------------------------------------------------------
// Sentient Aether-Plasma Nebula-Moth
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

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let s = sin(angle);
    let c = cos(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p2 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p2 += dot(p2, p2.yxz + 33.33);
    return fract((p2.xxy + p2.yxx) * p2.zyx);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);

    let n000 = dot(hash33(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0));
    let n100 = dot(hash33(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0));
    let n010 = dot(hash33(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0));
    let n110 = dot(hash33(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0));
    let n001 = dot(hash33(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0));
    let n101 = dot(hash33(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0));
    let n011 = dot(hash33(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0));
    let n111 = dot(hash33(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0));

    return mix(
        mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
        mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y),
        u.z
    ) * 0.5 + 0.5;
}

fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    var current_p = p;
    for (var i = 0; i < 4; i++) {
        value += amplitude * noise3D(current_p);
        current_p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

fn sdCappedCone(p: vec3<f32>, h: f32, r1: f32, r2: f32) -> f32 {
    let q = vec2<f32>(length(p.xz), p.y);
    let k1 = vec2<f32>(r2, h);
    let k2 = vec2<f32>(r2 - r1, 2.0 * h);
    let ca = vec2<f32>(q.x - min(q.x, select(r2, r1, q.y < 0.0)), abs(q.y) - h);
    let cb = q - k1 + k2 * clamp(dot(k1 - q, k2) / dot(k2, k2), 0.0, 1.0);
    let s = select(1.0, -1.0, cb.x < 0.0 && ca.y < 0.0);
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

fn sdMoth(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Thorax
    let thorax = sdEllipsoid(p, vec3<f32>(0.5, 0.5, 1.2));

    // Abdomen
    let p_abdomen = p - vec3<f32>(0.0, -0.2, -1.2);
    let abdomen = sdEllipsoid(p_abdomen, vec3<f32>(0.4, 0.4, 1.5));

    // Head
    let p_head = p - vec3<f32>(0.0, 0.2, 1.4);
    let head = sdEllipsoid(p_head, vec3<f32>(0.35, 0.35, 0.4));

    var body = smin(thorax, abdomen, 0.4);
    body = smin(body, head, 0.3);

    // Wings
    let flutterFreq = u.zoom_params.x; // default 1.0
    let time = u.config.x;
    let wingFlutter = sin(time * flutterFreq * 10.0 + p.z * 2.0) * 0.3;

    // Symmetrical wings
    var p_wings = p;
    p_wings.x = abs(p_wings.x);

    // Domain warp for wings
    let warp = fbm(p_wings * 2.0 + vec3<f32>(time * 0.5)) * u.zoom_params.w;
    p_wings.y += wingFlutter + warp;
    p_wings.x -= 0.6;
    p_wings.z += 0.2;

    let wing_rot = rotate2D(0.3);
    let xy_rot = wing_rot * vec2<f32>(p_wings.x, p_wings.y);
    p_wings.x = xy_rot.x;
    p_wings.y = xy_rot.y;

    let wings = sdEllipsoid(p_wings, vec3<f32>(2.5, 0.05, 1.8));

    return min(body, wings);
}

fn map(p: vec3<f32>) -> vec2<f32> {
    // x = distance, y = material id
    let moth_dist = sdMoth(p);

    return vec2<f32>(moth_dist, 1.0);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Particle storm via raymarching accumulation
fn renderStorm(ro: vec3<f32>, rd: vec3<f32>, tmax: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var t = 0.0;
    let stormIntensity = u.zoom_params.y; // default 0.5

    for (var i = 0; i < 30; i++) {
        let p = ro + rd * t;
        let noiseVal = noise3D(p * 2.0 - vec3<f32>(u.config.x * 0.5));
        if (noiseVal > 0.7) {
            col += vec3<f32>(0.2, 0.5, 0.8) * stormIntensity * (noiseVal - 0.7) * 3.0 / (1.0 + t * t * 0.1);
        }
        t += 0.5;
        if (t > tmax) { break; }
    }
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * res) / res.y;

    // Mouse interaction for camera
    let mouse = u.zoom_config.yz * 2.0 - vec2<f32>(1.0);

    var ro = vec3<f32>(mouse.x * 3.0, mouse.y * 3.0 + 2.0, -6.0);
    let cam_target = vec3<f32>(0.0, 0.0, 0.0);

    let cz = normalize(cam_target - ro);
    let cx = normalize(cross(cz, vec3<f32>(0.0, 1.0, 0.0)));
    let cy = normalize(cross(cx, cz));
    let rd = normalize(cx * uv.x + cy * uv.y + cz * 1.5);

    var t = 0.0;
    var m = -1.0;
    let max_dist = 20.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if (res.x < 0.001) {
            m = res.y;
            break;
        }
        t += res.x;
        if (t > max_dist) { break; }
    }

    var color = vec3<f32>(0.0);
    let bgCol = renderStorm(ro, rd, max_dist);
    color += bgCol;

    let bass = plasmaBuffer[0].x * 0.1; // Audio reactivity

    if (m > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));

        let diff = max(dot(n, l), 0.0);
        let amb = 0.1;

        // Base color shifting palette
        var objCol = vec3<f32>(0.1, 0.8, 0.4); // Auroral green

        // Wing plasma glow
        let plasmaGlow = u.zoom_params.z; // default 0.8
        let wingDist = sdEllipsoid(p, vec3<f32>(3.0, 0.1, 2.0)); // Approximate wing area
        if (wingDist < 0.5) {
            let fbmVal = fbm(p * 5.0 - vec3<f32>(u.config.x));
            objCol = mix(objCol, vec3<f32>(0.1, 0.9, 0.9), fbmVal) * plasmaGlow; // Bioluminescent cyan

            // Shattered chrono-glass reflections
            let spec = pow(max(dot(reflect(rd, n), l), 0.0), 16.0);
            objCol += spec * vec3<f32>(0.8, 0.2, 0.9); // Quantum purple
        }

        // Thorax sub-bass pulsation
        let thoraxDist = sdEllipsoid(p, vec3<f32>(0.6, 0.6, 1.3));
        if (thoraxDist < 0.2) {
             objCol += vec3<f32>(1.0, 0.2, 0.5) * bass * 5.0; // Pulsates with sub-bass
        }

        color = objCol * (diff + amb);

        // Fake subsurface scattering / bloom
        let sss = smoothstep(0.0, 0.5, fbm(p * 10.0 + vec3<f32>(u.config.x)));
        color += sss * vec3<f32>(0.0, 0.5, 0.2) * 0.3;
    }

    // Fog
    color = mix(color, vec3<f32>(0.02, 0.01, 0.05), 1.0 - exp(-0.02 * t * t));

    // ACES Tonemapping
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    color = clamp((color * (a * color + vec3<f32>(b))) / (color * (c * color + vec3<f32>(d)) + vec3<f32>(e)), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
