// ═══════════════════════════════════════════════════════════════════
//  Chroma Kinetic Blackbody
//  Category: advanced-hybrid
//  Features: chroma-kinetic, blackbody-thermal, physical-color, mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-15, 2026-11-15
//  Ideas: λ-scaled RGB split; C luma-delta kinetic boost; Wien split; white-hot core
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
//  Mouse-driven kinetic RGB split combined with physically-correct
//  blackbody thermal coloring. Luminance drives temperature; velocity
//  drives chromatic separation. Hotspots bloom with Stefan-Boltzmann
//  radiance and chromatic aberration.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

fn blackbodyColor(temperatureK: f32) -> vec3<f32> {
    let t = clamp(temperatureK / 1000.0, 0.5, 30.0);
    var r: f32;
    var g: f32;
    var b: f32;
    if (t <= 6.5) {
        r = 1.0;
        g = clamp(0.39 * log(max(t, 0.05)) - 0.63, 0.0, 1.0);
        b = clamp(0.54 * log(max(t - 1.0, 0.05)) - 1.0, 0.0, 1.0);
    } else {
        r = clamp(1.29 * pow(t - 0.6, -0.133), 0.0, 1.0);
        g = clamp(1.29 * pow(t - 0.6, -0.076), 0.0, 1.0);
        b = 1.0;
    }
    let radiance = pow(t / 6.5, 4.0);
    return vec3<f32>(r, g, b) * radiance;
}

fn loadC(coord: vec2<i32>, max_coord: vec2<i32>) -> vec4<f32> {
    let c = clamp(coord, vec2<i32>(0), max_coord);
    return textureLoad(dataTextureC, c, 0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    if (f32(gid.x) >= res.x || f32(gid.y) >= res.y) { return; }

    let coord = vec2<i32>(gid.xy);
    let max_coord = vec2<i32>(res) - vec2<i32>(1);
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let aspect = res.x / max(res.y, 1.0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let strength = u.zoom_params.x * 0.1;
    let radius = u.zoom_params.y;
    let luma_inf = u.zoom_params.z;
    let rotation = u.zoom_params.w * 6.28318;

    var mousePos = u.zoom_config.yz;
    let diff = uv - mousePos;
    let diffAspect = diff * vec2<f32>(aspect, 1.0);
    let dist = length(diffAspect);

    var dir = vec2<f32>(0.0);
    if (dist > 0.001) { dir = normalize(diffAspect); }

    let c = cos(rotation);
    let s = sin(rotation);
    let rotDir = vec2<f32>(dir.x * c - dir.y * s, dir.x * s + dir.y * c);
    let uvOffsetDir = vec2<f32>(rotDir.x / aspect, rotDir.y);

    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let luma = dot(baseColor.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let falloff = smoothstep(radius, 0.0, dist);
    let modFactor = max(0.0, 1.0 + (luma - 0.5) * luma_inf * 2.0);

    // Idea 2 — split boost from previous-frame luma delta
    let prev = loadC(coord, max_coord);
    let prevLuma = dot(prev.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let kineticBoost = 1.0 + abs(luma - prevLuma) * (2.8 + treble * 0.8);

    let mag = strength * falloff * modFactor * kineticBoost * (1.0 + bass * 0.15);

    var temperature = mix(1200.0, 9000.0, luma);
    let mouseDown = u.zoom_config.w > 0.5;
    if (mouseDown) {
        let mouseDist = length(uv - mousePos);
        let mouseHeat = exp(-mouseDist * mouseDist * 400.0);
        temperature += mouseHeat * 4500.0;
    }
    temperature = clamp(temperature, 800.0, 15000.0);

    // ── Idea 1: Wien split ─────────────────────────────────────────
    // The 1.00 / 0.18 / 0.68 offsets stay the baseline. Hotter temperature
    // stretches the blue fringe and shortens the red one.
    let tempNorm = clamp((temperature - 1200.0) / 7800.0, 0.0, 1.0);
    let uvR = clamp(uv - uvOffsetDir * mag * mix(1.22, 0.78, tempNorm), vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv - uvOffsetDir * mag * 0.18, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + uvOffsetDir * mag * 0.68 * mix(0.72, 1.38, tempNorm), vec2<f32>(0.0), vec2<f32>(1.0));

    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;
    var color = vec3<f32>(r, g, b);

    let thermalIntensity = 0.8 + luma * 1.4 + mids * 0.25;
    let thermalColor = blackbodyColor(temperature) * thermalIntensity;
    var blend = mix(color, thermalColor, 0.6);

    // ── Idea 2: white-hot core ─────────────────────────────────────
    // Core chroma collapses toward its own luma. Warmth stays in the
    // shoulder of the same falloff, not in a second light.
    let hot = clamp((temperature - 4200.0) / 5500.0, 0.0, 1.0);
    let core = hot * hot * falloff;
    let blendL = dot(max(blend, vec3<f32>(0.0)), vec3<f32>(0.299, 0.587, 0.114));
    blend = mix(blend, vec3<f32>(blendL), core * 0.72);
    blend += vec3<f32>(1.0, 0.42, 0.12) * hot * (1.0 - hot) * falloff * 0.35;

    let display = toneMapACES(max(blend, vec3<f32>(0.0)));
    let splitAmt = clamp(length(uvOffsetDir * mag) * 14.0, 0.0, 1.0);
    let alpha = clamp(0.48 + splitAmt * 0.35 + luma * 0.2 + select(0.0, 0.08, mouseDown), 0.0, 1.0);

    textureStore(writeTexture, gid.xy, vec4<f32>(display, alpha));
    textureStore(dataTextureA, gid.xy, vec4<f32>(display, alpha));

    let depth = textureLoad(readDepthTexture, coord, 0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
