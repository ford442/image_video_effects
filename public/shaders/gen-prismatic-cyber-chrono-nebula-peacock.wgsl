// ----------------------------------------------------------------
// Prismatic Cyber-Chrono Nebula-Peacock
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
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    config: vec4<f32>, // x: time, y: audio, z/w: unused
    zoom_params: vec4<f32>, // custom UI slider parameters
    camera_pos: vec3<f32>,
    camera_dir: vec3<f32>,
    zoom_config: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
};

// ----------------------------------------------------------------
// HELPER FUNCTIONS
// ----------------------------------------------------------------
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
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

// Mandelbox-style fold for fractal plumage
fn sphereFold(p: ptr<function, vec3<f32>>, min_r: f32, max_r: f32) {
    let r2 = dot(*p, *p);
    if (r2 < min_r) {
        let temp = (max_r / min_r);
        *p = *p * temp;
    } else if (r2 < max_r) {
        let temp = (max_r / r2);
        *p = *p * temp;
    }
}

fn boxFold(p: ptr<function, vec3<f32>>, fold: vec3<f32>) {
    *p = clamp(*p, -fold, fold) * 2.0 - *p;
}

fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let time = u.config.x;
    let audio = u.config.y * u.zoom_params.w;

    // Mouse rotation
    let m = u.mouse.xy;
    if (m.x > 0.0) {
        let angleX = (m.x - 0.5) * 6.28;
        let rx = rot(angleX) * vec2<f32>(p.x, p.z);
        p.x = rx.x;
        p.z = rx.y;
        let angleY = (m.y - 0.5) * 3.14;
        let ry = rot(angleY) * vec2<f32>(p.y, p.z);
        p.y = ry.x;
        p.z = ry.y;
    } else {
        let rxt = rot(time * 0.2) * vec2<f32>(p.x, p.z);
        p.x = rxt.x;
        p.z = rxt.y;
    }

    // Chrono-Distortion Ripples from Mouse interaction
    let mouseDist = length(u.mouse.xy - vec2<f32>(0.5)) * 2.0;
    let rippleWarp = sin(length(p) * 5.0 - time * 3.0) * mouseDist * 0.1 * u.zoom_params.x;
    p.y = p.y + rippleWarp;

    // Core Peacock Body
    var dBody = sdCylinder(p, vec2<f32>(0.5, 1.2));
    dBody = max(dBody, -sdSphere(p - vec3<f32>(0.0, 0.5, 0.0), 0.7)); // Subtraction for glass structure

    // Fractal Plumage (Feathers)
    var pF = p;
    let plumageSpread = u.zoom_params.x;
    pF.z = pF.z - 0.5; // Offset backward

    var scale: f32 = 1.0;
    for(var i = 0; i < 5; i++) {
        boxFold(&pF, vec3<f32>(1.5 + sin(time * 0.1 + f32(i)) * 0.2 * plumageSpread));
        sphereFold(&pF, 0.5, 1.0);
        pF = pF * 2.0 + vec3<f32>(0.1, -1.0, 0.5);
        scale = scale * 2.0;
        let rfxy = rot(0.2 * sin(time * 0.5) * plumageSpread) * vec2<f32>(pF.x, pF.y);
        pF.x = rfxy.x;
        pF.y = rfxy.y;
        let rfxz = rot(0.1 * plumageSpread) * vec2<f32>(pF.x, pF.z);
        pF.x = rfxz.x;
        pF.z = rfxz.y;
    }

    var dPlumage = sdCylinder(pF, vec2<f32>(0.1, 2.0)) / scale;

    // Audio-Reactive Eye-Spots
    let pE = pF - vec3<f32>(0.0, 1.8, 0.0);
    let dEye = sdSphere(pE, 0.4 + audio * 0.3) / scale;

    // Material logic
    var d = dBody;
    var mat = 1.0; // Glass body

    if (dPlumage < d) {
        d = dPlumage;
        mat = 2.0; // Feathers
    }

    if (dEye < d) {
        d = dEye;
        mat = 3.0; // Glowing Eyes
    }

    // Add some organic noise to the plumage
    if (mat == 2.0) {
        d = d - sin(pF.x*5.0)*sin(pF.y*5.0)*sin(pF.z*5.0) * 0.05 / scale;
    }

    return vec2<f32>(d, mat);
}

// ----------------------------------------------------------------
// SHADING & RAYMARCHING
// ----------------------------------------------------------------
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.001;
    return normalize(
        e.xyy * map(p + e.xyy).x +
        e.yyx * map(p + e.yyx).x +
        e.yxy * map(p + e.yxy).x +
        e.xxx * map(p + e.xxx).x
    );
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    let uv = (fragCoord * 2.0 - vec2<f32>(f32(dimensions.x), f32(dimensions.y))) / f32(dimensions.y);

    let time = u.config.x;
    let audio = u.config.y * u.zoom_params.w;

    // Set default zoom params if they are 0
    var plumageSpread = u.zoom_params.x;
    if (plumageSpread == 0.0) { plumageSpread = 0.5; }
    var glassIOR = u.zoom_params.y;
    if (glassIOR == 0.0) { glassIOR = 1.2; }
    var nebulaDensity = u.zoom_params.z;
    if (nebulaDensity == 0.0) { nebulaDensity = 0.8; }

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -4.0); // Simple camera, can use u.camera_pos if integrated
    let rd = normalize(vec3<f32>(uv, 1.5));

    var t = 0.0;
    var d = 0.0;
    var mat = 0.0;
    var glow = 0.0;
    var nebula = 0.0;

    // Raymarching loop
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        mat = res.y;

        // Volumetric nebula accumulation
        nebula = nebula + (0.01 * nebulaDensity) / (1.0 + abs(d));

        // Eye glow accumulation
        if (mat == 3.0) {
            glow = glow + (0.05 * (1.0 + audio)) / (0.01 + abs(d));
        }

        if (d < 0.001 || t > 20.0) { break; }
        t = t + d * 0.7; // Step slightly conservatively due to folding
    }

    var col = vec3<f32>(0.0);

    if (t < 20.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let v = -rd;
        let h = normalize(l + v);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(n, h), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

        if (mat == 1.0) {
            // Quantum Glass Body
            let baseColor = vec3<f32>(0.1, 0.8, 0.9);
            col = baseColor * (diff * 0.2 + 0.1) + spec + fresnel * vec3<f32>(0.5, 0.9, 1.0);

            // Fake internal reflection/dispersion
            let refrDir = refract(rd, n, 1.0 / glassIOR);
            let internalCol = palette(length(p) + time * 0.1,
                                      vec3<f32>(0.5, 0.5, 0.5),
                                      vec3<f32>(0.5, 0.5, 0.5),
                                      vec3<f32>(1.0, 1.0, 1.0),
                                      vec3<f32>(0.0, 0.33, 0.67));
            col = col + internalCol * 0.3 * (1.0 - fresnel);

        } else if (mat == 2.0) {
            // Iridescent Feathers
            let pColor = palette(length(p) * 2.0 - time * 0.5,
                                vec3<f32>(0.5, 0.5, 0.8),
                                vec3<f32>(0.5, 0.5, 0.4),
                                vec3<f32>(1.0, 1.0, 1.0),
                                vec3<f32>(0.1, 0.5, 0.9)); // Teal, Magenta, Gold
            col = pColor * (diff * 0.8 + 0.2) + spec * 0.5;
            col = mix(col, vec3<f32>(0.0, 1.0, 0.5), fresnel * 0.5);

        } else if (mat == 3.0) {
            // Glowing Eyes (Core)
            col = vec3<f32>(1.0, 1.0, 1.0); // Solid white core
        }
    }

    // Add volumetric effects
    let eyeGlowColor = vec3<f32>(0.1, 0.9, 0.7) * glow * (0.5 + audio * 1.5);
    let nebulaColor = palette(uv.x + uv.y + time * 0.1,
                              vec3<f32>(0.1, 0.05, 0.2),
                              vec3<f32>(0.3, 0.1, 0.4),
                              vec3<f32>(1.0, 1.0, 1.0),
                              vec3<f32>(0.0, 0.2, 0.4)) * nebula;

    col = col + eyeGlowColor + nebulaColor * (1.0 - exp(-t * 0.05));

    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    let finalColor = vec4<f32>(col, 1.0);
    textureStore(writeTexture, vec2<i32>(id.xy), finalColor);
}
