// ----------------------------------------------------------------
// Prismatic Cyber-Chrono Nebula-Peacock
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    config: vec4<f32>, // x: time, y: audio, z/w: unused
    zoom_params: vec4<f32>, // custom UI slider parameters
    camera_pos: vec3<f32>,
    camera_dir: vec3<f32>,
    zoom_config: vec4<f32>,
    ripples: vec4<f32>,
}

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

// ----------------------------------------------------------------
// HELPER FUNCTIONS
// ----------------------------------------------------------------
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ----------------------------------------------------------------
// SDF & DOMAIN FUNCTIONS
// ----------------------------------------------------------------
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdCylinder(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

struct MapResult {
    d: f32,
    mat: f32,
    glow: f32
}

fn map(pos: vec3<f32>) -> MapResult {
    var p = pos;
    let time = u.config.x;
    let audio = u.config.y;

    // Sliders
    let plumageSpread = u.zoom_params.x;
    let refraction = u.zoom_params.y;
    let nebulaDensity = u.zoom_params.z;
    let audioReact = u.zoom_params.w;

    // 1. Mouse rotation & distortion
    let mouse = (u.mouse / u.resolution) * 2.0 - 1.0;
    let new_xz = rot(mouse.x * 3.1415 + time * 0.2) * p.xz;
    p.x = new_xz.x;
    p.z = new_xz.y;
    let new_yz = rot(mouse.y * 3.1415) * p.yz;
    p.y = new_yz.x;
    p.z = new_yz.y;

    var glow = 0.0;

    // 2. Peacock cyber-body SDF
    // Central core / body
    let bodyRadius = 0.6;
    let bodyHeight = 1.2;
    var dBody = sdCapsule(p, vec3<f32>(0.0, -bodyHeight, 0.0), vec3<f32>(0.0, bodyHeight, 0.0), bodyRadius);

    // Cyber-ribs
    var pBody = p;
    pBody.y = pBody.y - bodyHeight * floor(pBody.y / bodyHeight); // repetition along y

    // 3. Fractal plumage via folding
    var pTail = p;

    // Move tail back
    pTail.z -= 1.5;

    // Gravitational warping from mouse dist to center
    let centerDist = length(u.mouse / u.resolution - vec2<f32>(0.5));
    pTail.y -= sin(pTail.x * 2.0) * plumageSpread * centerDist;
    pTail.z -= cos(pTail.y * 2.0) * plumageSpread * centerDist;

    var scale = 1.0;
    var dFeathers = 100.0;

    for (var i = 0; i < 4; i++) {
        // Polar repeat
        let angle = atan2(pTail.y, pTail.x);
        let radius = length(pTail.xy);

        let segments = 8.0;
        let segmentAngle = 6.28318 / segments;
        // manually calculate modulo for f32
        let angleMod = angle - segmentAngle * floor(angle/segmentAngle);
        let a = angleMod - segmentAngle * 0.5;

        pTail.x = cos(a) * radius;
        pTail.y = sin(a) * radius;

        // Fold
        pTail.x = abs(pTail.x) - 0.5 * scale;
        pTail.z = abs(pTail.z) - 0.1 * scale;

        let new_xy = rot(0.2) * pTail.xy;
        pTail.x = new_xy.x;
        pTail.y = new_xy.y;
        let new_yz2 = rot(0.1 + sin(time * 0.5) * 0.05) * pTail.yz;
        pTail.y = new_yz2.x;
        pTail.z = new_yz2.y;

        scale *= 0.8;

        // Feather stem
        let dStem = sdCapsule(pTail, vec3<f32>(0.0, -2.0, 0.0), vec3<f32>(0.0, 2.0, 0.0), 0.05 * scale);

        // Eye spots
        var pEye = pTail;
        pEye.y -= 1.0 * scale;
        let dEye = sdSphere(pEye, 0.2 * scale);

        // Accumulate glow for eye spots (audio reactive)
        let eyeIntensity = clamp(1.0 - dEye * 2.0, 0.0, 1.0) * audio * audioReact;
        glow += eyeIntensity * 2.0;

        dFeathers = min(dFeathers, min(dStem, dEye));
    }

    dFeathers = dFeathers * 0.6; // Correct for scaling artifacts

    // Combine body and feathers
    var d = smin(dBody, dFeathers, 0.3);

    // Add some noise displacement to the body
    d -= sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0) * 0.05;

    var mat = 1.0; // Cyber glass
    if (dFeathers < dBody) {
        mat = 2.0; // Feathers
    }

    return MapResult(d, mat, glow);
}

// ----------------------------------------------------------------
// SHADING & RAYMARCHING
// ----------------------------------------------------------------
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy).d +
        e.yyx * map(p + e.yyx).d +
        e.yxy * map(p + e.yxy).d +
        e.xxx * map(p + e.xxx).d
    );
}

// Simple 3D hash for noise
fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Value noise
fn noise(x: vec3<f32>) -> f32 {
    let i = floor(x);
    let f = fract(x);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);

    return mix(mix(mix(hash33(i + vec3<f32>(0.0,0.0,0.0)).x,
                       hash33(i + vec3<f32>(1.0,0.0,0.0)).x, u.x),
                   mix(hash33(i + vec3<f32>(0.0,1.0,0.0)).x,
                       hash33(i + vec3<f32>(1.0,1.0,0.0)).x, u.x), u.y),
               mix(mix(hash33(i + vec3<f32>(0.0,0.0,1.0)).x,
                       hash33(i + vec3<f32>(1.0,0.0,1.0)).x, u.x),
                   mix(hash33(i + vec3<f32>(0.0,1.0,1.0)).x,
                       hash33(i + vec3<f32>(1.0,1.0,1.0)).x, u.x), u.y), u.z);
}

fn fbm(x_in: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var x = x_in;
    for (var i = 0; i < 4; i++) {
        v += a * noise(x);
        x = x * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}


@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv = (fragCoord * 2.0 - u.resolution.xy) / u.resolution.y;

    let time = u.config.x;
    let audio = u.config.y;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -8.0); // Adjust camera to see the full entity
    let rd = normalize(vec3<f32>(uv, 1.5));

    // Raymarching
    var t = 0.0;
    var tMax = 20.0;
    var res: MapResult;
    var totalGlow = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        res = map(p);

        if (res.d < 0.001 || t > tMax) { break; }
        t += res.d;
        totalGlow += res.glow * 0.01;
    }

    var col = vec3<f32>(0.0);

    // Background / Nebula
    if (t > tMax) {
        // Volumetric nebula
        let nebulaDensityParam = u.zoom_params.z;
        let rd_noise = rd + vec3<f32>(time * 0.1);
        let density = fbm(rd_noise * 3.0) * nebulaDensityParam;
        col = mix(vec3<f32>(0.01, 0.02, 0.05), vec3<f32>(0.1, 0.5, 0.8), density);

        // Add some stars
        if (hash33(rd * 1000.0).x > 0.99) {
            col += vec3<f32>(1.0);
        }
    } else {
        // Object Shading
        let p = ro + rd * t;
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let viewDir = normalize(ro - p);
        let fresnel = pow(1.0 - max(dot(n, viewDir), 0.0), 4.0);

        if (res.mat == 1.0) {
            // Cyber glass body
            let refraction = u.zoom_params.y;
            let glassCol = vec3<f32>(0.2, 0.8, 1.0); // Teal
            col = glassCol * diff * 0.5 + glassCol * fresnel * refraction;

            // Fake internal reflection/chromatic abberation
            let refDirR = refract(-viewDir, n, 1.0/1.1);
            let refDirG = refract(-viewDir, n, 1.0/1.2);
            let refDirB = refract(-viewDir, n, 1.0/1.3);

            // Sample background slightly
            col += vec3<f32>(
                fbm(refDirR * 5.0 + time),
                fbm(refDirG * 5.0 + time),
                fbm(refDirB * 5.0 + time)
            ) * 0.2;

        } else {
            // Feathers (Liquid-Aurora Luminescence)
            // Use polar coords for iridescent map
            let r = length(p.xy);
            let a = atan2(p.y, p.x);
            let iridescent = vec3<f32>(
                sin(r * 5.0 + time) * 0.5 + 0.5,
                sin(a * 3.0 - time) * 0.5 + 0.5,
                sin(p.z * 2.0 + time) * 0.5 + 0.5
            );

            let featherBase = mix(vec3<f32>(0.8, 0.2, 0.8), vec3<f32>(1.0, 0.8, 0.2), iridescent.x);
            col = featherBase * diff * 0.8 + featherBase * fresnel * 0.5;
        }
    }

    // Add accumulated glow (bloom)
    let glowColor = mix(vec3<f32>(1.0, 0.2, 0.5), vec3<f32>(0.2, 1.0, 0.8), sin(time)*0.5+0.5);
    col += totalGlow * glowColor * u.zoom_params.w; // Audio reactivity multiplier

    // Tone mapping (ACES approx)
    col = (col*(2.51*col+0.03))/(col*(2.43*col+0.59)+0.14);

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
