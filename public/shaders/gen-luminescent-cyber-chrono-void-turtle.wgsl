// ----------------------------------------------------------------
// Luminescent Cyber-Chrono Void-Turtle
// Category: generative
// ----------------------------------------------------------------
// --- COPY PASTE THIS HEADER ---
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Shell Complexity, y=Plasma Intensity, z=Chrono-Distortion, w=Swim Speed
    ripples: array<vec4<f32>, 50>,
};

// Math & Noise Functions
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// 3D Voronoi for the shell plates
fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let p = floor(x);
    let f = fract(x);

    var res = vec2<f32>(8.0, 8.0);

    for (var k = -1; k <= 1; k++) {
        for (var j = -1; j <= 1; j++) {
            for (var i = -1; i <= 1; i++) {
                let b = vec3<f32>(f32(i), f32(j), f32(k));
                let r = vec3<f32>(b) - f + hash33(p + b);
                let d = dot(r, r);

                if (d < res.x) {
                    res.y = res.x;
                    res.x = d;
                } else if (d < res.y) {
                    res.y = d;
                }
            }
        }
    }

    return vec2<f32>(sqrt(res.x), sqrt(res.y));
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdEllipsoid(p: vec3<f32>, r: vec3<f32>) -> f32 {
    let k0 = length(p / r);
    let k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

// Global Variables
var<private> glow: f32 = 0.0;
var<private> gTime: f32 = 0.0;
var<private> audioVal: f32 = 0.0;

fn map(p_in: vec3<f32>) -> f32 {
    var p = p_in;

    // Mouse Gravity Well (Chrono-distortion)
    let mouseNorm = u.zoom_config.yz / u.config.zw;
    // Map from [0,1] to [-2, 2] roughly for screen space mouse mapping
    let mousePos = vec3<f32>((mouseNorm.x * 2.0 - 1.0) * 4.0, (1.0 - mouseNorm.y * 2.0) * 4.0, 0.0);

    let distToMouse = length(p - mousePos);
    let distortionStrength = u.zoom_params.z;
    if (distortionStrength > 0.0) {
        let warp = distortionStrength / (distToMouse + 0.1);
        p = p + normalize(p - mousePos) * warp;
    }

    // Turtle Base Shape (Ellipsoid body)
    let bodyRot = rot(sin(gTime * u.zoom_params.w) * 0.2);
    var pBody = p;
    pBody.yz = bodyRot * pBody.yz;
    pBody.xz = bodyRot * pBody.xz;

    let baseShell = sdEllipsoid(pBody, vec3<f32>(2.0, 1.0, 2.5));

    // Shell Complexity (Voronoi Plates)
    let complexity = u.zoom_params.x * 5.0 + 2.0;
    let v = voronoi(pBody * complexity + gTime * 0.1);

    // Plate edge thickness
    let edge = v.y - v.x;

    // Extrude plates out slightly
    var shell = baseShell - v.x * 0.2;

    // Create gaps between plates
    let gapWidth = 0.1;
    let inGap = smoothstep(gapWidth, 0.0, edge);

    // Hollow out gaps slightly
    shell = shell + inGap * 0.15;

    // Plasma Glow in gaps
    let plasmaIntensity = u.zoom_params.y;
    // Base glow
    var localGlow = inGap * plasmaIntensity * (1.0 + audioVal * 2.0);

    // Ripple effect in glow
    for(var i = 0u; i < 5u; i++) { // Only check first 5 for performance
        let ripple = u.ripples[i];
        if (ripple.w > 0.0) {
            let rDist = length(p.xy - ripple.xy);
            let rWave = sin((rDist - ripple.z * 10.0) * 5.0) * 0.5 + 0.5;
            let rEnvelope = smoothstep(0.5, 0.0, abs(rDist - ripple.z * 10.0));
            localGlow += rWave * rEnvelope * ripple.w * inGap * plasmaIntensity * 5.0;
        }
    }

    // Accumulate glow (attenuated by distance to surface)
    glow += localGlow * 0.02 / (abs(shell) + 0.01);

    // Add simple head and fins
    var pHead = pBody;
    pHead.z -= 3.0;
    pHead.y -= 0.2;
    let head = sdEllipsoid(pHead, vec3<f32>(0.5, 0.4, 0.8));

    var pFinL = pBody;
    pFinL.x -= 2.2;
    pFinL.z -= 1.5;
    pFinL.xy = rot(-0.5) * pFinL.xy;
    let finL = sdEllipsoid(pFinL, vec3<f32>(1.2, 0.1, 0.8));

    var pFinR = pBody;
    pFinR.x += 2.2;
    pFinR.z -= 1.5;
    pFinR.xy = rot(0.5) * pFinR.xy;
    let finR = sdEllipsoid(pFinR, vec3<f32>(1.2, 0.1, 0.8));

    var turtle = smin(shell, head, 0.5);
    turtle = smin(turtle, finL, 0.3);
    turtle = smin(turtle, finR, 0.3);

    return turtle;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let h = 0.001;
    let k = vec2<f32>(1.0, -1.0);
    return normalize(
        k.xyy * map(p + k.xyy * h) +
        k.yyx * map(p + k.yyx * h) +
        k.yxy * map(p + k.yxy * h) +
        k.xxx * map(p + k.xxx * h)
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var p2 = p;
    for (var i = 0; i < 4; i++) {
        v += a * hash33(p2).x;
        p2 = p2 * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<f32>(u.config.zw);
    let pixelCoords = vec2<f32>(f32(global_id.x), f32(global_id.y));

    if (pixelCoords.x >= dims.x || pixelCoords.y >= dims.y) {
        return;
    }

    let uv = (pixelCoords - 0.5 * dims) / dims.y;

    gTime = u.config.x;
    audioVal = u.config.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 2.0, -8.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slow rotation of camera
    let camRot = rot(sin(gTime * 0.1) * 0.2);
    ro.xz = camRot * ro.xz;
    rd.xz = camRot * rd.xz;
    ro.yz = rot(0.2) * ro.yz;
    rd.yz = rot(0.2) * rd.yz;

    var t = 0.0;
    var d = 0.0;
    var p = ro;
    var hit = false;
    glow = 0.0;

    // Raymarching
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        d = map(p);

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d * 0.7; // Step size reduction for safety with distortions
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let viewDir = normalize(ro - p);
        let refl = reflect(-l, n);
        let spec = pow(max(dot(viewDir, refl), 0.0), 32.0);

        // Dark Obsidian base color
        let baseColor = vec3<f32>(0.05, 0.06, 0.07);

        col = baseColor * (diff * 0.8 + 0.2) + spec * 0.5;

        // Add fake subsurface scattering / ambient based on glow
        col += vec3<f32>(0.1, 0.8, 1.0) * glow * 0.5;
    } else {
        // Nebula background
        let bgStars = pow(fbm(rd * 50.0), 10.0) * 2.0;
        let bgClouds = fbm(rd * 3.0 + vec3<f32>(0.0, 0.0, gTime * 0.05));
        col = vec3<f32>(0.02, 0.05, 0.1) * bgClouds + vec3<f32>(bgStars);
    }

    // Add volumetric plasma glow
    let glowColor = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.2, 0.8), sin(gTime)*0.5+0.5);
    col += glow * glowColor;

    // Add ripple visual directly to background if no hit (for extra effect)
    if (!hit) {
         for(var i = 0u; i < 5u; i++) {
            let ripple = u.ripples[i];
            if (ripple.w > 0.0) {
                 let rDist = length(uv - ripple.xy / dims * 2.0 + 1.0); // Rough approximation
                 let rWave = sin((rDist - ripple.z) * 20.0) * 0.5 + 0.5;
                 let rEnvelope = smoothstep(0.1, 0.0, abs(rDist - ripple.z));
                 col += glowColor * rWave * rEnvelope * ripple.w * 0.2;
            }
        }
    }

    // Tone mapping
    col = col / (1.0 + col);
    // Gamma correction
    col = pow(col, vec3<f32>(1.0 / 2.2));

    textureStore(writeTexture, vec2<i32>(pixelCoords), vec4<f32>(col, 1.0));
}
