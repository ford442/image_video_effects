// ═══════════════════════════════════════════════════════════════════
//  Holographic Plasma-Geode
//  Category: generative
//  Features: audio-reactive, mouse-driven, click-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-06
//  Ideas: crystal Cauchy facet dispersion & TIR; dielectric plasma arc filaments; agate mineral growth banding
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

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
    zoom_params: vec4<f32>,  // x=Plasma Intensity, y=Crystal Density, z=Holographic Hue, w=Core Rotation Speed
    ripples: array<vec4<f32>, 50>,
};

fn hash(p: vec3<f32>) -> f32 {
    return fract(sin(dot(p, vec3<f32>(12.9898, 78.233, 45.164))) * 43758.5453);
}

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn map(p_in: vec3<f32>, time: f32, audio: f32) -> vec2<f32> {
    var p = p_in;

    // Domain repetition for infinite geode
    let rep_xy = fract(vec2<f32>(p.x, p.y) / 4.0 + vec2<f32>(0.5)) * 4.0 - vec2<f32>(2.0);
    p = vec3<f32>(rep_xy.x, rep_xy.y, p.z);

    // Rocky exterior: repeated box and sphere SDF with noise displacement
    let b = vec3<f32>(1.5, 1.5, 1.5);
    var q = abs(p) - b;
    let box = length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
    let sphere = length(p) - 1.8;

    let noise = sin(p.x * 10.0) * sin(p.y * 10.0) * sin(p.z * 10.0) * 0.1;
    var rocky = max(box, sphere) + noise;

    // Smooth subtraction to expose the cavity
    let cavity = length(p) - 1.2;
    let h = clamp(0.5 - 0.5 * (rocky + cavity) / 0.2, 0.0, 1.0);
    rocky = mix(rocky, -cavity, h) + 0.2 * h * (1.0 - h);

    // Crystals inside the cavity (KIFS fractal)
    var cp = p;
    let crystalDensity = u.zoom_params.y;
    for (var i = 0; i < 4; i++) {
        cp = abs(cp) - vec3<f32>(0.5 * crystalDensity);

        let rot_xy = rotate2D(0.5 + time * 0.1) * vec2<f32>(cp.x, cp.y);
        cp = vec3<f32>(rot_xy.x, rot_xy.y, cp.z);

        let rot_yz = rotate2D(0.3 - time * 0.05) * vec2<f32>(cp.y, cp.z);
        cp = vec3<f32>(cp.x, rot_yz.x, rot_yz.y);
    }
    let crystal_d = length(cp) - 0.05;

    // Crystals only exist inside the cavity
    let crystals = max(crystal_d, length(p) - 1.2);

    // Return min dist and material ID (0.0 for rocky, 1.0 for crystals)
    if (crystals < rocky) {
        return vec2<f32>(crystals, 1.0);
    }
    return vec2<f32>(rocky, 0.0);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e.x, e.y, e.y), time, audio).x - map(p - vec3<f32>(e.x, e.y, e.y), time, audio).x,
        map(p + vec3<f32>(e.y, e.x, e.y), time, audio).x - map(p - vec3<f32>(e.y, e.x, e.y), time, audio).x,
        map(p + vec3<f32>(e.y, e.y, e.x), time, audio).x - map(p - vec3<f32>(e.y, e.y, e.x), time, audio).x
    ));
}

fn palette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557) + vec3<f32>(u.zoom_params.z);
    return a + b * cos(6.28318 * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(textureDimensions(writeTexture));
    if (f32(id.x) >= dims.x || f32(id.y) >= dims.y) { return; }
    let coord = vec2<i32>(id.xy);
    let uv = (vec2<f32>(id.xy) * 2.0 - dims) / min(dims.x, dims.y);
    let res = u.config.zw;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let audio = bass;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = u.zoom_config.z * 2.0 - 1.0;
    let mouseDown = u.zoom_config.w > 0.5;

    // Raymarching setup
    var ro = vec3<f32>(0.0, 0.0, -3.0);

    // Mouse interaction (gravitational anomaly warping space)
    var rd = normalize(vec3<f32>(uv, 1.0));
    let m = vec2<f32>(mouseX, mouseY);

    // Domain distortion around center based on mouse
    let distToMouse = length(uv - m);
    let warpFactor = exp(-distToMouse * 2.0) * select(0.18, 0.58, mouseDown);

    // Finite click shocks alternately compress the shell and flare the core.
    let rippleCount = min(u32(u.config.y), 50u);
    var shellShock = 0.0;
    var coreShock = 0.0;
    var shockVector = vec2<f32>(0.0);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age < 0.0 || age > 3.5) { continue; }
        let center = (ripple.xy - 0.5) * vec2<f32>(res.x / max(res.y, 1.0), 1.0) * 2.0;
        let delta = uv - center;
        let d = length(delta);
        let radius = age * (0.32 + u.zoom_params.w * 0.38);
        let front = exp(-pow((d - radius) * 18.0, 2.0)) * exp(-age * 0.82);
        shellShock += front;
        coreShock += exp(-d * d * 3.5) * exp(-age * 1.3);
        shockVector += delta / max(d, 1e-4) * front;
    }

    let safeMouseDir = (uv - m) / max(distToMouse, 1e-4);
    let warp_xy = vec2<f32>(rd.x, rd.y) + safeMouseDir * warpFactor + shockVector * 0.045;
    rd = normalize(vec3<f32>(warp_xy.x, warp_xy.y, rd.z));

    var col = vec3<f32>(0.0);

    var t = 0.0;
    var matId = 0.0;
    var p = vec3<f32>(0.0);
    for (var i = 0; i < 100; i++) {
        p = ro + rd * t;
        let res_map = map(p, time, audio);
        let d = res_map.x;
        matId = res_map.y;

        if (d < 0.001) {
            let n = calcNormal(p, time, audio);

            if (matId > 0.5) {
                // ─── Native Idea 1: Crystal Cauchy Facet Dispersion & TIR ───
                let viewAngle = max(dot(n, -rd), 0.0);
                let cauchySpread = 0.06 + treble * 0.12;
                let colR = palette(viewAngle * (1.0 + cauchySpread) + u.zoom_params.z);
                let colG = palette(viewAngle + u.zoom_params.z);
                let colB = palette(viewAngle * (1.0 - cauchySpread) + u.zoom_params.z);
                let dispersedHolo = vec3<f32>(colR.r, colG.g, colB.b);

                // Internal total internal reflection glint
                let tirFresnel = pow(1.0 - viewAngle, 4.0);
                let tirGlint = vec3<f32>(1.0, 0.95, 0.85) * tirFresnel * 1.8;

                // Subsurface scattering approximation
                let sss = smoothstep(0.0, 1.0, map(p + rd * 0.1, time, audio).x);
                col = (dispersedHolo * (0.5 + 0.5 * sss) + tirGlint) * (1.0 + shellShock * 0.7 + mids * 0.15);
            } else {
                // ─── Native Idea 3: Agate Mineral Growth Banding ───
                let rimDist = length(p);
                let mineralNoise = sin(p.x * 12.0) * sin(p.y * 12.0);
                let bandFreq = rimDist * 26.0 + mineralNoise * 4.0;
                let agateBands = sin(bandFreq);
                let baseRock = mix(vec3<f32>(0.04, 0.04, 0.07), vec3<f32>(0.15, 0.11, 0.18), smoothstep(-0.3, 0.3, agateBands));
                // Chalcedony quartz hairline ring
                let fineLine = smoothstep(0.75, 0.95, sin(bandFreq * 2.5)) * 0.18;
                let rockyColor = baseRock + vec3<f32>(fineLine * 0.9, fineLine * 0.7, fineLine * 0.5);

                let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
                let diff = max(dot(n, l), 0.0);
                let spec = pow(max(dot(reflect(-l, n), -rd), 0.0), 16.0);
                col = rockyColor * (diff + 0.2) + vec3<f32>(spec * 0.1);
            }
            break;
        }
        if (t > 20.0) {
            break;
        }
        t += d;
    }

    // ─── Volumetric Plasma Core & Native Idea 2: Dielectric Discharge Arcs ───
    var plasma = vec3<f32>(0.0);
    let coreRotationSpeed = u.zoom_params.w;
    let plasmaIntensity = u.zoom_params.x;
    for(var i=0; i<15; i++) {
        let pt = ro + rd * (t * f32(i) / 15.0);

        // Repeated space for plasma
        let rpt_xy = fract(vec2<f32>(pt.x, pt.y) / 4.0 + vec2<f32>(0.5)) * 4.0 - vec2<f32>(2.0);
        let rpt = vec3<f32>(rpt_xy.x, rpt_xy.y, fract(pt.z / 4.0 + 0.5) * 4.0 - 2.0);
        let dist = length(rpt);

        if (dist < 1.0) {
            var vortexP = rpt;
            // Vortex rotation accelerated by mouse
            let angle = dist * 2.0 - time * coreRotationSpeed * (1.0 + warpFactor * 5.0);

            let rot_xz = rotate2D(angle) * vec2<f32>(vortexP.x, vortexP.z);
            vortexP = vec3<f32>(rot_xz.x, vortexP.y, rot_xz.y);

            // Volumetric FBM noise for swirling plasma core
            let noiseVal = hash(vortexP * 5.0 + vec3<f32>(time + audio * 0.5, time + audio * 0.5, time + audio * 0.5));
            // Bright neon magenta, cyan, and gold emission
            let emission = mix(
                vec3<f32>(1.0, 0.0, 1.0), // Magenta
                mix(vec3<f32>(0.0, 1.0, 1.0), vec3<f32>(1.0, 0.8, 0.0), noiseVal), // Cyan/Gold
                sin(time + dist * 5.0) * 0.5 + 0.5
            ) * vec3<f32>(noiseVal * plasmaIntensity * (1.0 - dist) * (1.0 + audio + coreShock * 1.8));

            // Idea 2: Dielectric discharge filament arcs branching between crystals
            let arcField = sin(vortexP.x * 12.0 + time * 6.0) * cos(vortexP.y * 12.0 - time * 5.0) * sin(vortexP.z * 12.0);
            let arcLine = smoothstep(0.06, 0.01, abs(arcField)) * step(0.18, dist) * (1.0 - dist);
            let arcEmission = vec3<f32>(0.75, 0.9, 1.0) * arcLine * (1.4 + bass * 1.8) * plasmaIntensity;

            plasma += (emission + arcEmission) * 0.15;
        }
    }
    col += plasma;

    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let semantic_alpha = clamp(luma * 1.1 + length(plasma) * 0.25 + shellShock * 0.3, 0.05, 0.98);
    let outDepth = 1.0 - clamp(t / 20.0, 0.0, 1.0);
    let currentDisplay = acesToneMap(col * (1.0 + treble * 0.08));
    let prevDisplay = textureLoad(dataTextureC, coord, 0);
    let display = mix(prevDisplay.rgb * 0.95, currentDisplay, 0.24 + audio * 0.04);
    let alpha = max(semantic_alpha, prevDisplay.a * 0.92);
    let outColor = vec4<f32>(display, alpha);

    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
