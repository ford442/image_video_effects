// ----------------------------------------------------------------
// Prismatic Cyber-Chrono Nebula-Peacock
// Category: generative
// ----------------------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Plumage, y=Refraction, z=Nebula, w=AudioReact
    ripples: array<vec4<f32>, 50>,
};

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

// ----------------------------------------------------------------
// CONSTANTS & HELPERS
// ----------------------------------------------------------------
const PI: f32 = 3.14159265359;
const MAX_STEPS: i32 = 100;
const MAX_DIST: f32 = 20.0;
const SURF_DIST: f32 = 0.001;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 3D Noise for Nebula
fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp2(-k * a) + exp2(-k * b);
    return -log2(res) / k;
}

// ----------------------------------------------------------------
// SDFs
// ----------------------------------------------------------------
fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdCylinder(p: vec3<f32>, h: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - h;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

// ----------------------------------------------------------------
// MAPPING & DOMAIN WARPING
// ----------------------------------------------------------------

// Returns vec3: x=distance, y=material_id, z=glow_intensity
fn map(pos: vec3<f32>) -> vec3<f32> {
    var p = pos;
    let time = u.config.x;
    let audio = u.config.y * u.zoom_params.w;

    let plumageSpread = u.zoom_params.x;

    // Mouse Interaction (Gravitational Singularity)
    // Convert mouse to world space roughly
    let mx = (u.zoom_config.y * 2.0 - 1.0) * (u.config.z / u.config.w);
    let my = (u.zoom_config.z * 2.0 - 1.0);

    let mouseDist = length(p.xy - vec2<f32>(mx, my));
    let gravity = exp(-mouseDist * 2.0) * 0.5;

    p.x += sin(time * 0.5 + p.y) * gravity;
    p.y += cos(time * 0.5 + p.x) * gravity;

    // --- Core Body (Quantum Glass) ---
    var bodyP = p;
    bodyP.y += sin(time * 0.3) * 0.1; // Gentle bobbing
    // Slightly rotate body
    var temp_xz = rot(time * 0.1) * bodyP.xz;
    bodyP.x = temp_xz.x;
    bodyP.z = temp_xz.y;

    var dBody = sdCylinder(bodyP, vec2<f32>(0.2, 0.8));
    var temp_yz = rot(0.2) * bodyP.yz;
    bodyP.y = temp_yz.x;
    bodyP.z = temp_yz.y;
    dBody = smin(dBody, sdSphere(bodyP - vec3<f32>(0.0, 0.9, 0.3), 0.25), 8.0); // Head

    // --- Fractal Plumage (Feathers) ---
    var tailP = p;
    tailP.y -= 0.5; // Offset to attach to body

    // Rotate tail based on spread
    var temp_yz2 = rot(-0.5 - plumageSpread * 0.5) * tailP.yz;
    tailP.y = temp_yz2.x;
    tailP.z = temp_yz2.y;

    // Polar domain repetition for the feathers
    let angle = atan2(tailP.x, tailP.y);
    let r = length(tailP.xy);

    let featherCount = 12.0 + plumageSpread * 8.0;
    let sector = (2.0 * PI) / featherCount;
    let aID = floor(angle / sector + 0.5);
    let aMod = (fract(angle / sector + 0.5) - 0.5) * sector;

    tailP.x = r * sin(aMod);
    tailP.y = r * cos(aMod);

    // Fractal fold
    var foldP = tailP;
    var glow = 0.0;
    for (var i = 0; i < 4; i++) {
        foldP.x = abs(foldP.x) - 0.1 * (1.0 + plumageSpread);
        foldP.z = abs(foldP.z) - 0.05;

        var temp_xy = rot(0.2 + sin(time * 0.2 + f32(i)) * 0.1) * foldP.xy;
        foldP.x = temp_xy.x;
        foldP.y = temp_xy.y;

        // Add tiny 'eye-spots' inside the fractal
        if (i == 3) {
            let eyeDist = sdSphere(foldP - vec3<f32>(0.0, 0.5, 0.0), 0.05 + audio * 0.05);
            glow += 0.01 / (eyeDist * eyeDist + 0.001) * audio;
        }
    }

    let dTail = sdBox(foldP, vec3<f32>(0.05, 1.5, 0.02));

    var d = min(dBody, dTail);
    var mat = 0.0; // 0 for body, 1 for feathers
    if (dTail < dBody) {
        mat = 1.0;
    }

    return vec3<f32>(d, mat, glow);
}

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// ----------------------------------------------------------------
// NEBULA / VOLUMETRICS
// ----------------------------------------------------------------
fn nebulaFBM(p: vec3<f32>) -> f32 {
    var q = p;
    var f = 0.0;
    var a = 0.5;
    for (var i = 0; i < 4; i++) {
        let h = hash33(floor(q));
        let fr = fract(q);
        let sm = fr * fr * (3.0 - 2.0 * fr);
        // extremely crude noise approximation
        let val = mix(
            mix(mix(h.x, hash33(floor(q) + vec3<f32>(1.,0.,0.)).x, sm.x),
                mix(hash33(floor(q) + vec3<f32>(0.,1.,0.)).x, hash33(floor(q) + vec3<f32>(1.,1.,0.)).x, sm.x), sm.y),
            mix(mix(hash33(floor(q) + vec3<f32>(0.,0.,1.)).x, hash33(floor(q) + vec3<f32>(1.,0.,1.)).x, sm.x),
                mix(hash33(floor(q) + vec3<f32>(0.,1.,1.)).x, hash33(floor(q) + vec3<f32>(1.,1.,1.)).x, sm.x), sm.y), sm.z);

        f += a * val;
        q = q * 2.0;
        a *= 0.5;
    }
    return f;
}

// ----------------------------------------------------------------
// MAIN COMPUTE
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = textureDimensions(writeTexture);
    if (id.x >= dimensions.x || id.y >= dimensions.y) {
        return;
    }

    let res = vec2<f32>(f32(dimensions.x), f32(dimensions.y));
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    var uv = (fragCoord * 2.0 - res) / res.y;

    let time = u.config.x;
    let audio = u.config.y;

    // Parameters
    let ior = u.zoom_params.y;
    let nebDensity = u.zoom_params.z;

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -4.0);
    let rd = normalize(vec3<f32>(uv, 1.5));

    // Raymarch
    var t = 0.0;
    var dInfo = vec3<f32>(0.0);
    var hit = false;
    var totalGlow = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t;
        dInfo = map(p);
        totalGlow += dInfo.z;
        if (dInfo.x < SURF_DIST) {
            hit = true;
            break;
        }
        if (t > MAX_DIST) {
            break;
        }
        t += dInfo.x;
    }

    var col = vec3<f32>(0.0);

    // Volumetric Nebula Background (simplified)
    var nebAcc = 0.0;
    for(var i=0; i<5; i++) {
        let np = ro + rd * (t + f32(i) * 0.5);
        nebAcc += nebulaFBM(np + time * 0.1) * nebDensity;
    }
    col += vec3<f32>(0.1, 0.3, 0.6) * (nebAcc / 5.0) * (1.0 + audio * 0.5);

    if (hit) {
        let p = ro + rd * t;
        let n = getNormal(p);
        let v = -rd;

        let lightPos = vec3<f32>(2.0, 4.0, -3.0);
        let l = normalize(lightPos - p);

        let diff = max(dot(n, l), 0.0);
        let r = reflect(-l, n);
        let spec = pow(max(dot(v, r), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

        if (dInfo.y < 0.5) {
            // Body: Quantum Glass
            let glassCol = vec3<f32>(0.8, 0.9, 1.0);

            // Fake refraction / chromatic aberration based on IOR param
            let refractDirR = refract(rd, n, 1.0 / ior);
            let refractDirG = refract(rd, n, 1.0 / (ior + 0.02));
            let refractDirB = refract(rd, n, 1.0 / (ior + 0.04));

            // Simple fake environment lookup
            let bgR = nebulaFBM(p + refractDirR * 2.0);
            let bgG = nebulaFBM(p + refractDirG * 2.0);
            let bgB = nebulaFBM(p + refractDirB * 2.0);

            let refrCol = vec3<f32>(bgR, bgG, bgB) * 2.0;

            col = mix(refrCol, glassCol, fresnel) + spec;
            col *= vec3<f32>(0.5, 0.8, 1.0); // Tint
        } else {
            // Feathers: Iridescent Metallic
            let iridMix = fract(length(p) * 2.0 - time);
            let baseCol = mix(vec3<f32>(0.0, 0.8, 0.8), vec3<f32>(0.8, 0.0, 0.8), iridMix); // Teal to Magenta

            col = baseCol * diff + spec * vec3<f32>(1.0, 0.8, 0.4) + fresnel * baseCol;
        }
    }

    // Add eye-spot glow
    col += vec3<f32>(1.0, 0.8, 0.2) * totalGlow * 0.05;

    // Tone mapping (ACES)
    col = (col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14);

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
