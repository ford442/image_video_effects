// ═══════════════════════════════════════════════════════════════════
//  Cyber Trace — Batch 59
//  Spring brush, capped click blooms, exact C history, ACES composite,
//  semantic alpha, extraBuffer[133..138] at (0,0) only.
//  Ideas: velocity-oriented arc stamp; treble circuit sparks
//  A packing: history RGB (unchanged)
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

fn hue2rgb(p: f32, q: f32, t: f32) -> f32 {
    var tc = t;
    if (tc < 0.0) { tc = tc + 1.0; }
    if (tc > 1.0) { tc = tc - 1.0; }
    if (tc < 1.0 / 6.0) { return p + (q - p) * 6.0 * tc; }
    if (tc < 1.0 / 2.0) { return q; }
    if (tc < 2.0 / 3.0) { return p + (q - p) * (2.0 / 3.0 - tc) * 6.0; }
    return p;
}

fn hslToRgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    if (s == 0.0) {
        return vec3<f32>(l);
    }
    var q: f32;
    if (l < 0.5) {
        q = l * (1.0 + s);
    } else {
        q = l + s - l * s;
    }
    let p = 2.0 * l - q;
    return vec3<f32>(hue2rgb(p, q, h + 1.0 / 3.0), hue2rgb(p, q, h), hue2rgb(p, q, h - 1.0 / 3.0));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / res;
    let decaySpeed = u.zoom_params.x;
    let glowIntensity = u.zoom_params.y;
    let hueShift = u.zoom_params.z;
    let brushSize = u.zoom_params.w * select(1.0, 0.75, u.zoom_config.w > 0.5);
    let time = u.config.x;
    let aspect = res.x / res.y;
    let rawMouse = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mousePos = rawMouse;
    var mouseVel = vec2<f32>(0.0);
    if (hasSpringState && extraBuffer[138] > 0.5) {
        mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        mouseVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
        var springPos = mousePos;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 8.0;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let toPixel = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(toPixel);

    // Idea 1: velocity-oriented arc stamp — trail a capsule behind the sprung
    // cursor along its velocity instead of stamping a plain disc, so fast
    // drags read as a drawn electric arc rather than a dot.
    let velMag = length(mouseVel);
    let arcDir = select(vec2<f32>(1.0, 0.0), mouseVel / max(velMag, 0.0001), velMag > 0.0001);
    let arcLen = clamp(velMag * 0.05, 0.0, brushSize * 2.5);
    let segVec = -arcDir * arcLen;
    let tSeg = clamp(dot(toPixel, segVec) / max(dot(segVec, segVec), 1e-6), 0.0, 1.0);
    let closest = segVec * tSeg;
    let capsuleDist = length(toPixel - closest);
    var brush = smoothstep(brushSize, brushSize * 0.5, capsuleDist) * select(0.5, 1.0, isMouseDown);

    // Idea 2: treble circuit sparks — above a treble threshold, small ticks
    // branch perpendicular off the arc, hashed by a moving grid cell so they
    // flicker like circuit-board traces and decay with the rest of history.
    let sparkPerp = vec2<f32>(-arcDir.y, arcDir.x);
    let sparkCell = floor(uv * 180.0 + time * 2.0);
    let sparkHash = fract(sin(dot(sparkCell, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let sparkActive = step(0.982, sparkHash) * clamp((treble - 0.45) * 3.0, 0.0, 1.0);
    let sparkCenter = closest + sparkPerp * brushSize * (sparkHash - 0.5) * 4.0;
    let sparkDist = length(toPixel - sparkCenter);
    let sparkStamp = smoothstep(brushSize * 0.4, 0.0, sparkDist) * sparkActive * smoothstep(brushSize * 4.0, brushSize * 0.5, dist);
    brush = brush + sparkStamp;

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age < 0.0 || age > 1.5) { continue; }
        let stampDist = length((uv - ripple.xy) * vec2<f32>(aspect, 1.0));
        let stampRadius = brushSize * 1.5;
        brush += smoothstep(stampRadius, stampRadius * 0.5, stampDist) * (1.0 - clamp(age / 1.5, 0.0, 1.0));
    }

    let historyColor = textureLoad(dataTextureC, pixel, 0);
    let colorTick = time * 0.2 * (1.0 + mids * 0.8) + hueShift;
    let drawColor = hslToRgb(fract(colorTick), 1.0, 0.5);
    let newHistory = clamp(historyColor.rgb * decaySpeed + drawColor * brush, vec3<f32>(0.0), vec3<f32>(2.0));

    textureStore(dataTextureA, pixel, vec4<f32>(newHistory, 1.0));

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let band = min(u32(uv.x * 8.0), 7u);
    let bandShimmer = plasmaBuffer[band + 1u].x * 0.3;
    let audioGlow = glowIntensity * (1.0 + bass * 0.5) * (1.0 + bandShimmer) * select(1.0, 1.2, isMouseDown);

    let rawComposite = inputColor + newHistory * audioGlow;
    var finalColor = acesToneMap(rawComposite * (0.92 + mids * 0.08));

    let trailStrength = clamp(luma(newHistory) * audioGlow * 0.5 + brush * 0.4, 0.0, 1.0);
    let alpha = clamp(0.35 + trailStrength * 0.55 + bass * 0.05, 0.0, 0.98);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    textureStore(writeTexture, pixel, vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
