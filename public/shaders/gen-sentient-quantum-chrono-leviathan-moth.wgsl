// ----------------------------------------------------------------
// Sentient Quantum-Chrono Leviathan-Moth
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Wing Span, y=Plasma Intensity, z=Chrono Distortion, w=Nebular Density
    ripples: array<vec4<f32>, 50>,
};

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
// Helper functions and Math utilities
// ----------------------------------------------------------------
const PI: f32 = 3.14159265359;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + vec3<f32>(33.33));
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14)), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D Voronoi / Cellular noise approximation
fn voronoi(p: vec3<f32>) -> f32 {
    let n = floor(p);
    let f = fract(p);
    var res: f32 = 8.0;
    for(var k = -1; k <= 1; k++) {
        for(var j = -1; j <= 1; j++) {
            for(var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = b - f + hash3(n + b);
                let d = dot(r, r);
                res = min(res, d);
            }
        }
    }
    return sqrt(res);
}

fn fbm(p: vec3<f32>) -> f32 {
    var value: f32 = 0.0;
    var amp: f32 = 0.5;
    var pp = p;
    for(var i = 0; i < 4; i++) {
        value += amp * (voronoi(pp) * 2.0 - 1.0);
        pp *= 2.0;
        amp *= 0.5;
    }
    return value;
}

// ----------------------------------------------------------------
// SDFs
// ----------------------------------------------------------------

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

// Gyroid for nebula
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let pp = p * scale;
    return abs(dot(sin(pp), cos(pp.zxy)) + bias) / scale - thickness;
}

// Moth mapping
fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let time = u.config.x;
    let audio = u.config.y;

    // Mouse rotation (acts as gravitational chronal anomaly)
    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z) * 2.0 - 1.0;
    p.xz = rot(mouse.x * PI) * p.xz;
    p.yz = rot(-mouse.y * PI) * p.yz;

    var dMain = 1e10;
    var matID = 0.0; // 1.0 = Body, 2.0 = Wings

    // Body (Capsule with displacement)
    var pBody = p;
    let bodyRadius = 0.3 + 0.05 * sin(time * 2.0 + pBody.z * 5.0);
    var dBody = sdCapsule(pBody, vec3<f32>(0.0, 0.0, 1.0), vec3<f32>(0.0, 0.0, -1.0), bodyRadius);
    // Fractal displacement
    dBody -= 0.1 * fbm(pBody * 4.0 + time * 0.5);

    // Wings
    var pWings = p;
    pWings.x = abs(pWings.x); // Symmetry

    let wingSpan = u.zoom_params.x;
    let chronoDistortion = u.zoom_params.z;

    // Wing flapping
    let flapSpeed = 4.0 + audio * 10.0;
    let flapAngle = sin(time * flapSpeed) * 0.5 * (1.0 + audio);
    pWings.xy = rot(flapAngle) * pWings.xy;

    // Wing shape (thin flat SDF with Voronoi)
    pWings.x -= wingSpan * 0.5; // Offset from body
    var dWings = sdBox(pWings, vec3<f32>(wingSpan * 0.5, 0.01, wingSpan * 0.6));

    // Wing pattern/crystalline structure
    let wingNoise = voronoi(pWings * 8.0 - vec3<f32>(0.0, 0.0, time * 2.0));
    dWings += 0.02 * wingNoise;
    // Add chrono distortion ripples
    dWings += chronoDistortion * 0.05 * sin(length(pWings.xz) * 20.0 - time * 10.0);

    // Combine
    if (dBody < dWings) {
        dMain = dBody;
        matID = 1.0;
    } else {
        dMain = dWings;
        matID = 2.0;
    }

    // Smooth merge slightly
    dMain = smin(dBody, dWings, 0.2);
    if(dBody - 0.1 < dWings) { matID = 1.0; } else { matID = 2.0; } // approx

    return vec2<f32>(dMain, matID);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.0005;
    return normalize(
        e.xyy * map(p + e.xyy).x +
        e.yyx * map(p + e.yyx).x +
        e.yxy * map(p + e.yxy).x +
        e.xxx * map(p + e.xxx).x
    );
}

// Blackbody color map
fn blackbody(temp: f32) -> vec3<f32> {
    let t = temp * 4000.0;
    var color = vec3<f32>(0.0);
    if (t < 1000.0) {
        color = vec3<f32>(t/1000.0, 0.0, 0.0);
    } else if (t < 2000.0) {
        color = vec3<f32>(1.0, (t-1000.0)/1000.0, 0.0);
    } else {
        color = vec3<f32>(1.0, 1.0, (t-2000.0)/2000.0);
    }
    // Shift color for neon pink/cyan bioluminescence
    return color.zyx + vec3<f32>(0.2, 0.0, 0.5) * temp;
}

// ----------------------------------------------------------------
// Main Compute
// ----------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(id.xy) / dim;
    let ndc = uv * 2.0 - 1.0;
    let aspect = dim.x / dim.y;

    let time = u.config.x;
    let audio = u.config.y;

    // Camera
    var ro = vec3<f32>(0.0, 1.0, -4.0);
    var rd = normalize(vec3<f32>(ndc.x * aspect, ndc.y, 1.5));

    // Background / Nebula
    var col = vec3<f32>(0.0);
    let nebDensity = u.zoom_params.w;

    // Raymarching Moth
    var t = 0.0;
    var d = 0.0;
    var matID = 0.0;
    var hit = false;

    var p = ro;

    for(var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let res = map(p);
        d = res.x;
        matID = res.y;

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d;
    }

    var glow = 0.0; // Plasma dust glow

    // Shading
    if (hit) {
        let n = calcNormal(p);
        let v = -rd;

        if (matID == 1.0) {
            // Body: Metallic and reflective
            let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
            let h = normalize(l + v);
            let diff = max(dot(n, l), 0.0);
            let spec = pow(max(dot(n, h), 0.0), 32.0);
            let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

            col = vec3<f32>(0.1, 0.15, 0.2) * diff + spec * 0.5 + fresnel * vec3<f32>(0.2, 0.4, 0.5);
            col += 0.1 * fbm(p * 10.0) * vec3<f32>(0.0, 1.0, 0.5); // Bioluminescent dots
        } else {
            // Wings: Crystalline and refractive
            let l = normalize(vec3<f32>(0.0, -1.0, 0.0));
            let diff = max(dot(n, l), 0.0);
            let fresnel = pow(1.0 - max(dot(n, v), 0.0), 3.0);

            // Faux refraction
            let refrRd = refract(rd, n, 0.8);
            // Sample nebula background slightly shifted
            let bgShift = sdGyroid(p + refrRd * 0.5, 2.0, 0.05, time) * 0.1;

            let baseColor = vec3<f32>(0.2, 0.6, 1.0);
            col = mix(baseColor, vec3<f32>(1.0, 0.5, 0.8), audio);
            col *= (0.2 + diff * 0.3) + fresnel * 0.5;

            // Glowing lines
            let wingGlow = smoothstep(0.4, 0.5, voronoi(p * 15.0));
            col += wingGlow * vec3<f32>(0.5, 1.0, 1.0) * u.zoom_params.y;

            // Shedding dust (approximated along trailing axis)
            glow += 0.5 * u.zoom_params.y * smoothstep(0.0, 1.0, p.z);
        }
    }

    // Volumetric Nebula and Plasma Trails
    var vT = 0.0;
    var vCol = vec3<f32>(0.0);
    for(var i = 0; i < 50; i++) {
        let vp = ro + rd * vT;
        let g = sdGyroid(vp, 1.5, 0.03, time * 0.2);

        var density = smoothstep(0.1, 0.0, g) * nebDensity * 0.05;
        // Add color based on depth and audio
        let vColor = mix(vec3<f32>(0.0, 0.1, 0.2), vec3<f32>(0.4, 0.0, 0.3), fract(vT * 0.1 + audio * 0.5));

        vCol += density * vColor;

        // Quantum Dust / Plasma trail behind the moth
        let trailMask = smoothstep(2.0, 0.0, length(vp.xy)) * smoothstep(-1.0, 5.0, vp.z);
        let dustNoise = fbm(vp * 5.0 - vec3<f32>(0.0, 0.0, time * 5.0));
        var dustDens = smoothstep(0.6, 1.0, dustNoise) * trailMask;

        // Mouse click/drag interaction increases dust
        let clickVal = u.config.y; // Simplified
        dustDens *= 1.0 + clickVal * 2.0;

        let dustColor = blackbody(dustNoise * 2.0 * u.zoom_params.y);
        vCol += dustDens * dustColor * 0.2;

        vT += 0.2 + hash3(vp).x * 0.1; // Dithered stepping
        if (vT > 20.0) { break; }
    }

    if (!hit) {
        col = vCol;
    } else {
        col = mix(col, vCol, 1.0 - exp(-t * 0.05)); // Fog blend
    }

    col += glow * vec3<f32>(0.1, 0.5, 1.0);

    // Post-processing
    col = acesToneMap(col);

    textureStore(writeTexture, id.xy, vec4<f32>(col, 1.0));
}
