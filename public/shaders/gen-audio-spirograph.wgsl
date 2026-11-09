// ═══════════════════════════════════════════════════════════════════
//  Audio Spirograph
//  Category: generative
//  Features: audio-reactive, procedural, epitrochoid curves
//  Complexity: Medium
//  Upgraded: 2026-09-27, 2026-11-08
//  Ideas: additive gear glow (all curves); rolling-center hubs; stator ghost; cusp flash; rolling gear + pen arm (the mechanism); no-slip gear teeth locked to the arm; ink pooling by pen speed
//  A packing: history RGB + coverage; texels (0,0) = sprung lens (pos.xy, vel.xy) and (1,0) = (fract(lastTime), -, -, 0.7371 sentinel) are STATE, not pixels (top-left corner; only their trail read is zeroed, invisible)
//  2026-11-08 rescue: the sprung mouse lens lived in extraBuffer[133..138], which the host zeroes every
//    frame, so the lens followed the raw pointer; it now persists in two A texels.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const SENT: f32 = 0.7371;

// Hash function
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rot(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Epitrochoid calculation (spirograph curve)
fn epitrochoid(t: f32, R: f32, r: f32, d: f32) -> vec2<f32> {
    let k = R / r;
    let x = (R + r) * cos(t) - d * cos((k + 1.0) * t);
    let y = (R + r) * sin(t) - d * sin((k + 1.0) * t);
    return vec2<f32>(x, y);
}

// Hypotrochoid calculation (inner spirograph)
fn hypotrochoid(t: f32, R: f32, r: f32, d: f32) -> vec2<f32> {
    let k = R / r;
    let x = (R - r) * cos(t) + d * cos((k - 1.0) * t);
    let y = (R - r) * sin(t) - d * sin((k - 1.0) * t);
    return vec2<f32>(x, y);
}

// Distance to line segment
fn distToSegment(uv: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = uv - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.000001), 0.0, 1.0);
    return length(pa - ba * h);
}

// HSL to RGB
fn hsl2rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(fract(h * 6.0) * 2.0 - 1.0));
    let m = l - c * 0.5;
    
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    
    if (h < 1.0/6.0) { r = c; g = x; }
    else if (h < 2.0/6.0) { r = x; g = c; }
    else if (h < 3.0/6.0) { g = c; b = x; }
    else if (h < 4.0/6.0) { g = x; b = c; }
    else if (h < 5.0/6.0) { r = x; b = c; }
    else { r = c; b = x; }
    
    return vec3<f32>(r + m, g + m, b + m);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    if (global_id.x >= dims.x || global_id.y >= dims.y) { return; }
    let resolution = vec2<f32>(dims);
    var uv = (vec2<f32>(global_id.xy) + vec2<f32>(0.5) - resolution * 0.5) / min(resolution.x, resolution.y);
    let t = u.config.x * 2.5;
    
    // Parameters - safe randomization
    let baseFreq = mix(0.5, 3.0, u.zoom_params.x);
    let audioReactivity = u.zoom_params.y; // 0 to 1
    let trailLength = mix(0.3, 0.95, u.zoom_params.z);
    let lineThickness = mix(0.001, 0.01, u.zoom_params.w);
    
    let audio = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioMod = 1.0 + audio * audioReactivity * 2.0;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    // Sprung lens state lives in two A texels (see header); the sentinel guards the first frame / inherited C.
    let st0 = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);
    let st1 = textureLoad(dataTextureC, vec2<i32>(1, 0), 0);
    let stateOk = abs(st1.w - SENT) < 0.001;
    let rawT = u.config.x;
    var mouseUv = select(rawMouse, st0.xy, stateOk);
    var mouseVelocity = select(vec2<f32>(0.0), st0.zw, stateOk);
    let springDt = select(0.016, clamp(fract(rawT - st1.x), 0.001, 0.05), stateOk);
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouseUv) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouseUv += mouseVelocity * springDt;
    let mouse = (mouseUv - vec2<f32>(0.5)) * vec2<f32>(resolution.x / resolution.y, 1.0);
    let mouseDelta = uv - mouse;
    let mouseLens = exp(-dot(mouseDelta, mouseDelta) * 18.0) * mix(0.04, 0.18, select(0.0, 1.0, u.zoom_config.w > 0.5));
    uv -= mouseDelta * mouseLens;
    
    // Background accumulation for trails
    var prevCol = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    prevCol = select(prevCol, vec3<f32>(0.0), (global_id.y == 0u) && (global_id.x < 2u));   // state texels carry no trail
    
    // Multiple harmonics - musical ratios
    let ratios = array<f32, 5>(1.0, 3.0/2.0, 4.0/3.0, 5.0/4.0, 5.0/3.0);
    let harmonics = array<f32, 5>(1.0, 2.0, 3.0, 4.0, 5.0);
    
    var minDist = 1000.0;
    var curveColor = vec3<f32>(0.0);
    var totalIntensity = 0.0;
    var hubGlow = 0.0;
    var stator = 0.0;
    var cuspFlash = 0.0;
    var mech = vec3<f32>(0.0);
    
    // Generate multiple spirograph curves
    for (var i: i32 = 0; i < 5; i++) {
        let ratio = ratios[i];
        let harmonic = harmonics[i];
        
        let R = 0.3 * (1.0 + f32(i) * 0.1);
        let r = R / (ratio * harmonic * baseFreq);
        let d = r * 0.8 * audioMod;
        
        let speed = 0.5 + f32(i) * 0.1;
        let time = t * speed;
        let sweep = 6.28318 * mix(0.2, 1.0, trailLength);
        let gearRot = rot(t * 0.08 + f32(i) * 0.16);
        let penNow = gearRot * epitrochoid(time, R, r, d);
        var prevPos = penNow;
        var prevTan = vec2<f32>(0.0);
        var dist = 1000.0;
        var segmentFade = 1.0;
        var nearLen = 1.0;
        var lenSum = 0.0;
        for (var j: i32 = 1; j <= 12; j = j + 1) {
            let jf = f32(j) / 12.0;
            let pos = gearRot * epitrochoid(time - sweep * jf, R, r, d);
            let segDist = distToSegment(uv, prevPos, pos);
            let segLen = length(pos - prevPos);
            lenSum += segLen;
            if (segDist < dist) { dist = segDist; segmentFade = 1.0 - jf * 0.65; nearLen = segLen; }
            let tan = pos - prevPos;
            let prevLen = length(prevTan);
            let rev = dot(tan, prevTan) / max(length(tan) * prevLen, 1e-6);
            let flip = smoothstep(0.2, -0.45, rev) * step(1e-4, prevLen);
            cuspFlash = max(cuspFlash, exp(-dot(uv - prevPos, uv - prevPos) / max(lineThickness * lineThickness * 10.0, 1e-8)) * flip);
            prevTan = tan;
            prevPos = pos;
        }
        // ── Idea 7: ink pooling by pen speed ────────────────────────────
        // Equal-time samples: segment length = pen speed. Ink pools where the pen
        // is slow (cusps, turning arcs) and goes thin on fast sweeps.
        let pool = clamp((lenSum / 12.0) / max(nearLen, 1e-5), 0.6, 2.2);
        // ── Idea 6: no-slip gear teeth on the fixed ring ────────────────
        // Teeth counts are in the ratio of the radii (N_stator = N_gear * R / r).
        let minRes = min(resolution.x, resolution.y);
        // teeth capped at ~4 px pitch so they never alias into a dither at low working sizes
        let nGear = clamp(round(6.28318 * r / 0.016), 6.0, max(6.0, min(48.0, floor(6.28318 * r * minRes / 4.0))));
        let nStator = clamp(round(nGear * R / r), 6.0, max(6.0, min(360.0, floor(6.28318 * R * minRes / 4.0))));
        let statorAng = atan2(uv.y, uv.x) - (t * 0.08 + f32(i) * 0.16);
        let statorTeeth = 0.72 + 0.28 * cos(nStator * statorAng);
        // Idea 3 — stator ghost of the fixed circle
        stator += exp(-abs(length(uv) - R) * 78.0) * 0.42 * statorTeeth;
        
        let hue = fract(f32(i) * 0.2 + t * 0.14 + treble * 0.2);
        let sat = 0.7 + audio * 0.3;
        let light = 0.5 + audio * 0.3;
        let col = hsl2rgb(hue, sat, light);
        
        let intensity = 1.0 / (1.0 + f32(i) * 0.5) * segmentFade;
        // Idea 1 — additive gears
        let add = exp(-dist * dist / max(lineThickness * lineThickness * 36.0, 1e-8)) * intensity * pool;
        curveColor += col * add;
        totalIntensity += add;
        minDist = min(minDist, dist);
        // Idea 2 — rolling-center hub
        let hub = rot(t * 0.08 + f32(i) * 0.16) * vec2<f32>((R + r) * cos(time), (R + r) * sin(time));
        hubGlow += exp(-dot(uv - hub, uv - hub) / 0.0009) * 0.45;
        // ── Idea 5: rolling gear + pen arm ──────────────────────────────
        // The mechanism that draws the curve: the rolling gear (radius r about
        // the hub) with its teeth, and the arm from the hub to the pen (length
        // d, breathing with the audio). Teeth are phase-locked to the arm, so
        // they rotate with the gear.
        let toHub = uv - hub;
        let ringD = abs(length(toHub) - r);
        let armAng = atan2(penNow.y - hub.y, penNow.x - hub.x);
        let gearTeeth = 0.55 + 0.45 * cos(nGear * (atan2(toHub.y, toHub.x) - armAng) + 3.14159);
        let ringLine = smoothstep(lineThickness * 2.2, 0.0, ringD) * gearTeeth;
        let armLine = smoothstep(lineThickness * 1.6, 0.0, distToSegment(uv, hub, penNow));
        let penDot = exp(-dot(uv - penNow, uv - penNow) / max(lineThickness * lineThickness * 14.0, 1e-8));
        mech += col * (ringLine * 0.95 + armLine * 1.0 + penDot * 1.0) * (1.0 / (1.0 + f32(i) * 0.2));
    }
    
    // Add secondary harmonics (hypotrochoids)
    for (var i: i32 = 0; i < 3; i++) {
        let ratio = ratios[i + 2];
        let R = 0.25 * audioMod;
        let r = R / ratio;
        let d = r * 0.6;
        
        let time = -t * (0.3 + f32(i) * 0.1);
        let sweep = 6.28318 * mix(0.2, 0.9, trailLength);
        let gearRot = rot(-t * 0.06);
        var prevPos = gearRot * hypotrochoid(time, R, r, d);
        var prevTan = vec2<f32>(0.0);
        var dist = 1000.0;
        var segmentFade = 1.0;
        var nearLen = 1.0;
        var lenSum = 0.0;
        for (var j: i32 = 1; j <= 10; j = j + 1) {
            let jf = f32(j) / 10.0;
            let pos = gearRot * hypotrochoid(time - sweep * jf, R, r, d);
            let segDist = distToSegment(uv, prevPos, pos);
            let segLen = length(pos - prevPos);
            lenSum += segLen;
            if (segDist < dist) { dist = segDist; segmentFade = 1.0 - jf * 0.6; nearLen = segLen; }
            let tan = pos - prevPos;
            let prevLen = length(prevTan);
            let rev = dot(tan, prevTan) / max(length(tan) * prevLen, 1e-6);
            let flip = smoothstep(0.2, -0.45, rev) * step(1e-4, prevLen);
            cuspFlash = max(cuspFlash, exp(-dot(uv - prevPos, uv - prevPos) / max(lineThickness * lineThickness * 10.0, 1e-8)) * flip);
            prevTan = tan;
            prevPos = pos;
        }
        stator += exp(-abs(length(uv) - R) * 78.0) * 0.28;
        let hue = fract(0.5 + f32(i) * 0.15 - t * 0.03);
        let col = hsl2rgb(hue, 0.8, 0.6);
        // Idea 7 (pen-speed ink pooling) on the hypotrochoids too
        let pool = clamp((lenSum / 10.0) / max(nearLen, 1e-5), 0.6, 2.2);
        let add = exp(-dist * dist / max(lineThickness * lineThickness * 36.0, 1e-8)) * 0.7 * segmentFade * pool;
        curveColor += col * add;
        totalIntensity += add;
        minDist = min(minDist, dist);
    }
    
    // Create glow effect
    let glow = smoothstep(lineThickness * 5.0, lineThickness, minDist);
    let core = smoothstep(lineThickness * 2.0, 0.0, minDist);
    
    // Final color
    var col = curveColor * glow * (1.0 + mids * 0.35) + vec3<f32>(1.0) * core * (0.45 + treble * 0.35);
    col += vec3<f32>(1.0, 0.92, 0.75) * clamp(hubGlow, 0.0, 1.2);
    col += vec3<f32>(0.55, 0.78, 1.0) * clamp(stator, 0.0, 0.85);
    col += vec3<f32>(1.0, 0.96, 0.72) * clamp(cuspFlash, 0.0, 1.4) * 0.75;
    col += clamp(mech, vec3<f32>(0.0), vec3<f32>(1.1));

    let uv01 = (vec2<f32>(global_id.xy) + vec2<f32>(0.5)) / resolution;
    var clickChime = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = t - ripple.z;
        if (age >= 0.0 && age < 1.7) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(resolution.x / resolution.y, 1.0);
            let shell = exp(-abs(length(delta) - age * 0.27) * 74.0) * exp(-age * 1.8);
            clickChime = max(clickChime, shell);
        }
    }
    col += vec3<f32>(1.05, 0.18, 0.95) * clickChime * (0.65 + treble * 0.3);
    let geoRing = abs(fract(length(uv) * 12.0 - t * 1.4) - 0.5);
    col += hsl2rgb(fract(t * 0.2 + mids), 0.95, 0.55) * (1.0 - smoothstep(0.0, 0.07, geoRing)) * 0.22;
    
    // Add trail accumulation
    col = col + clamp(prevCol, vec3<f32>(0.0), vec3<f32>(1.2)) * trailLength * 0.78;
    
    // Vignette
    let vignette = clamp(1.0 - length(uv) * 0.8, 0.0, 1.0);
    col = col * vignette;
    
    let coord = vec2<i32>(global_id.xy);
    let history = clamp(max(col, vec3<f32>(0.0)) * 0.94, vec3<f32>(0.0), vec3<f32>(1.25));
    let coverage = clamp(glow * totalIntensity + core * 0.55 + clickChime * 0.2, 0.0, 1.0);
    var aOut = vec4<f32>(history, coverage);
    if (global_id.y == 0u && global_id.x == 0u) { aOut = vec4<f32>(mouseUv, mouseVelocity); }
    if (global_id.y == 0u && global_id.x == 1u) { aOut = vec4<f32>(fract(rawT), 0.0, 0.0, SENT); }
    textureStore(dataTextureA, coord, aOut);
    let display = acesToneMap(history * 1.08);
    let alpha = clamp(coverage, 0.0, 0.96);
    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(coverage, 0.0, 0.0, 0.0));
}
