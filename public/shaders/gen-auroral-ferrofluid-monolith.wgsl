// ═══════════════════════════════════════════════════════════════════
//  Auroral Ferrofluid-Monolith
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-23
//  Upgraded: 2026-09-27
//  Ideas: aurora sheath hugging the spike SDF; co-wound field aurora pinched toward the mouse pole; aurora-tinted spike-tip corona
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
// ---------------------------------------------------

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=ClickCount (NOT audio), z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
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

// Magnetic twist: the monolith's field frame (shared by the spikes and, via Idea 2, the aurora)
fn fieldFrame(p_in: vec3<f32>) -> vec3<f32> {
    var p = p_in;
    let twist = u.zoom_params.z;
    let rot_xz = rot(p.y * twist * 0.5 + u.config.x * 0.2) * p.xz;
    p.x = rot_xz.x;
    p.z = rot_xz.y;
    return p;
}

// Mouse as external rotating magnetic field, orbiting the pillar axis.
// Fix: HEAD added zoom_config.w * 8.0 to the angle, which teleported the pole 8 rad on press/release.
fn magPole() -> vec3<f32> {
    let mx = (u.zoom_config.y - 0.5) * 12.0;
    let my = (u.zoom_config.z - 0.5) * 12.0;
    let mouseAngle = u.config.x * 1.2;
    let mousePole = vec3<f32>(mx, my, 0.0);
    return vec3<f32>(mousePole.x * cos(mouseAngle) - mousePole.z * sin(mouseAngle), mousePole.y, mousePole.x * sin(mouseAngle) + mousePole.z * cos(mouseAngle));
}

// Map function for the monolith. .x = SDF, .y = spike crest factor 0..1 (Idea 3)
fn map(p_in: vec3<f32>) -> vec2<f32> {
    // Magnetic twist
    let p = fieldFrame(p_in);

    // Mouse pole (held = stronger distortion, as HEAD)
    let rotatedPole = magPole();
    let dPole = length(p - rotatedPole);
    let poleDistort = exp(-dPole * 0.45) * (0.6 + u.zoom_config.w * 0.8);

    // Monolith base shape
    let size = vec3<f32>(1.0 - p.y*0.05, 4.0, 1.0 - p.y*0.05);
    var d1 = sdBox(p, size);

    // Audio state
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Ferrofluid spikes — strong bass forms readable magnetic glyphs, treble collapses them into chaos
    let glyphForm = smoothstep(0.4, 0.85, bass) * (1.0 - treble * 0.8);
    let chaos = treble * 1.8 + mids * 0.3;
    // Fix: treble could drive this negative (spikes inverted into pits)
    let spikeLength = max(u.zoom_params.x * (0.7 + bass * 2.2 * glyphForm) + poleDistort - chaos * 0.4, 0.0);

    let sp = p * 4.0;
    let n = abs(noise(sp + vec3<f32>(0.0, -u.config.x * 2.0, 0.0)));
    // Fix: clamp the pow base (negative base is NaN in WGSL)
    let crest = pow(max(1.0 - n, 0.0), 8.0);
    let spikes = crest * spikeLength;

    d1 -= spikes;

    // Idea 3: hand the crest factor to the shading pass (HEAD returned a constant material ID)
    return vec2<f32>(d1, crest);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.005, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

// Aurora colour: HEAD's green→magenta height gradient (shared by the volume and the Idea 3 corona)
fn auroraTint(p: vec3<f32>) -> vec3<f32> {
    let c1 = vec3<f32>(0.0, 1.0, 0.5); // Cyan/Green
    let c2 = vec3<f32>(1.0, 0.0, 0.8); // Magenta
    return mix(c1, c2, sin(p.y + u.config.x) * 0.5 + 0.5);
}

// Aurora density function
fn mapAurora(p_in: vec3<f32>) -> f32 {
    let dBox = sdBox(p_in, vec3<f32>(1.5, 4.5, 1.5));
    if (dBox > 2.0) { return 0.0; } // Optimization

    // Idea 2: co-wound field aurora — enter the monolith's own field frame (Magnetic Twist winding + spin),
    // then pinch the domain toward the orbiting mouse pole the spikes also feel.
    var p = fieldFrame(p_in);
    let pole = magPole();
    let dPole = length(p - pole);
    p = p + (pole - p) * (exp(-dPole * 0.5) * 0.35);
    let poleGlow = 1.0 + (0.8 + u.zoom_config.w * 0.6) * exp(-dPole * 0.6);

    // HEAD rotation, verbatim
    let p_xz = rot(p.y * 0.5 - u.config.x * 0.5) * p.xz;
    p.x = p_xz.x;
    p.z = p_xz.y;

    // Fix: HEAD fbm spans only ~±0.15, so f1*f2 never reached the 0.4 threshold and the aurora was
    // identically zero. Remap each octave-sum to 0..1 so HEAD's smoothstep(0.4, 0.8) can fire.
    let f1 = clamp(0.5 + 4.0 * fbm(p * 1.5 + vec3<f32>(0.0, u.config.x, 0.0)), 0.0, 1.0);
    let f2 = clamp(0.5 + 4.0 * fbm(p * 3.0 - vec3<f32>(u.config.x, 0.0, u.config.x)), 0.0, 1.0);

    let density = smoothstep(0.4, 0.8, f1 * f2);
    let falloff = smoothstep(2.0, 0.0, dBox);

    // Idea 1: aurora sheath — the curtain clings to the spiked surface (x2 at the SDF, ~x0.5 one unit out)
    let dMono = map(p_in).x;
    let sheath = 0.3 + 1.7 * exp(-max(dMono, 0.0) * 2.2);

    return density * falloff * sheath * poleGlow * u.zoom_params.y;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord - 0.5 * res) / res.y;
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

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
    var crest = 0.0;

    for(var i=0; i<100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if(d.x < 0.002) {
            hit = true;
            crest = d.y;
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

        // Idea 3: spike-tip corona — crests discharge in the local aurora colour, brighter at grazing angles.
        // Replaces HEAD's tip glow, which read u.config.y (click count) as audio and grew with every click.
        let tip = smoothstep(0.9, 0.99, crest);
        let rim = 1.0 - max(dot(n, v), 0.0);
        let corona = tip * (0.35 + 0.65 * rim) * (0.9 + treble * 1.5) * u.zoom_params.y;
        col += auroraTint(p) * corona;
    } else {
        t = tMax; // for volumetric pass limit
    }

    // Volumetric Aurora Pass
    var aurCol = vec3<f32>(0.0);
    // Fix: HEAD marched t = 0..6 in 0.1 steps, but the aurora region starts at t = 4.5..5.9 and the pillar
    // surface sits at t = 6.1..9.1, so only the outer falloff shell was ever sampled. March the aurora
    // bounding box (half-extents 3.5/6.5/3.5 contain sdBox(1.5,4.5,1.5) < 2) from entry to min(exit, hit).
    let auroraHalf = vec3<f32>(3.5, 6.5, 3.5);
    let invRd = 1.0 / select(rd, vec3<f32>(1e-6), abs(rd) < vec3<f32>(1e-6));
    let tb0 = (-auroraHalf - ro) * invRd;
    let tb1 = (auroraHalf - ro) * invRd;
    let tNear = max(max(min(tb0.x, tb1.x), min(tb0.y, tb1.y)), min(tb0.z, tb1.z));
    let tFar = min(min(max(tb0.x, tb1.x), max(tb0.y, tb1.y)), max(tb0.z, tb1.z));
    let volStart = max(tNear, 0.0);
    let volEnd = min(tFar, t);
    let volSteps = 56;
    let stepSize = max(volEnd - volStart, 0.0) / f32(volSteps);

    // Offset start for dither
    var tVol = volStart + hash33(vec3<f32>(uv, u.config.x)).x * stepSize;
    var aurDepth = 0.0;

    for(var i=0; i<volSteps; i++) {
        if(tVol >= volEnd) { break; } // stop at geometry / box exit

        let p = ro + rd * tVol;
        let den = mapAurora(p);

        if(den > 0.01) {
            // Color gradient based on height and density
            aurCol += auroraTint(p) * den * stepSize * 2.0;
            aurDepth += den * stepSize * 2.0;
        }

        tVol += stepSize;
    }

    col += aurCol;

    // Background glow
    let bgGlow = max(0.0, 1.0 - length(uv)) * 0.1;
    col += vec3<f32>(0.1, 0.1, 0.2) * bgGlow;

    // Bass forms glyphs → stronger metallic readable structure
    // Treble collapses → softer, more chaotic auroral breakup
    let glyphStrength = smoothstep(0.35, 0.8, bass) * (1.0 - treble * 0.7);
    col = mix(col, col * 1.15 + vec3<f32>(0.2, 0.4, 0.9) * 0.3, glyphStrength * 0.4);

    // Tone mapping: ACES replaces HEAD's Reinhard; HEAD's display gamma kept so the dark chrome is not crushed
    col = acesToneMap(max(col, vec3<f32>(0.0)));
    col = pow(col, vec3<f32>(1.0 / 2.2));

    // Semantic alpha: pillar coverage, else aurora optical depth, else the faint background glow
    let coverage = select(0.0, 1.0, hit);
    let aurOpacity = 1.0 - exp(-aurDepth * 1.5);
    let alpha = clamp(max(coverage, max(aurOpacity, bgGlow * 4.0)), 0.0, 1.0);

    // Depth: near = 1, miss = 0
    let depth = select(0.0, clamp(1.0 - t / tMax, 0.0, 1.0), hit);

    let coord = vec2<i32>(id.xy);
    textureStore(writeTexture, coord, vec4<f32>(col, alpha));
    textureStore(dataTextureA, coord, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
