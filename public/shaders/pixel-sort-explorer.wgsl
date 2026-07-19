// ═══════════════════════════════════════════════════════════════════
//  Pixel Sort Explorer
//  Category: image
//  Features: pixel-sort, interactive-mouse, audio-reactive,
//            interval-sort, streak-ramps, scan-sweep, upgraded-rgba
//  Upgraded by: kimi-swarm 2026-07-19
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

// ── Canonical hash / noise (3-octave fbm drives the line wobble) ──
fn hash21(p: vec2<f32>) -> f32 {
    let h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var sum = 0.0; var amp = 0.5; var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        sum += amp * valueNoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return sum;
}

// Rec.601 luma — kept identical to the original threshold weights
fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w > 0.5;
    let time = u.config.x;
    let aspect = resolution.x / max(resolution.y, 0.001);

    // Params (normalized before use — original slider semantics preserved)
    let sortThreshold = clamp(u.zoom_params.x, 0.0, 1.0);
    let radius = clamp(u.zoom_params.y, 0.0, 1.0);
    let direction = clamp(u.zoom_params.z, 0.0, 1.0);
    let smoothness = clamp(u.zoom_params.w, 0.0, 1.0);

    // Audio (clamped to the documented ~0–2 range)
    let bass = clamp(plasmaBuffer[0].x, 0.0, 2.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 2.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 2.0);

    // Mids ease the threshold down so more pixels join sort intervals on the beat
    let thresh = clamp(sortThreshold - mids * 0.08, 0.0, 1.0);

    // Spotlight mask: aspect-corrected, breathes with bass, expands while clicked
    let dVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(dVec);
    let downBoost = select(0.0, 1.0, mouseDown);
    let rEff = radius * (1.0 + bass * 0.12 + downBoost * 0.10);
    let mask = 1.0 - smoothstep(rEff, rEff + 0.1, dist);

    // Sort axis: V/H switch exactly as the "Direction (V/H)" slider labels it
    var dirVec = vec2<f32>(0.0, 1.0);
    if (direction > 0.5) { dirVec = vec2<f32>(1.0, 0.0); }
    let perpVec = vec2<f32>(-dirVec.y, dirVec.x);

    var color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let origAlpha = color.a;
    let myLum = luma(color.rgb);

    // ── Interval-segmented pixel sort ─────────────────────────────
    // Walk both ways along the sort axis; a sample whose luma drops below
    // the threshold closes the interval (classic Asendorf-style segments).
    // The brightest in-interval color becomes this pixel's streak color.
    var streak = color.rgb;
    var streakT = 0.0;   // 0 = interval head (bright end), 1 = tail
    var sorted = 0.0;    // 1 when a brighter upstream pixel claims this one

    if (mask > 0.01) {
        let stride = mix(0.001, 0.05, smoothness);
        // Organic wobble of the sampling line so streaks feel hand-drawn
        let wobble = (fbm(uv * 7.0 + vec2<f32>(time * 0.13, -time * 0.09), 3) - 0.5)
                   * (0.010 + smoothness * 0.012);

        var bestVal = -1.0;
        var bestColor = color.rgb;
        var backSteps = 0.0;

        // Backward walk: find the interval start and its brightest color
        for (var i = 1; i <= 12; i++) {
            let fi = f32(i);
            let sUV = uv - dirVec * (fi * stride) + perpVec * (wobble * fi * 0.12);
            if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) { break; }
            let sColor = textureSampleLevel(readTexture, u_sampler, sUV, 0.0).rgb;
            let sLum = luma(sColor);
            if (sLum < thresh) { break; }
            backSteps = fi;
            if (sLum > bestVal) { bestVal = sLum; bestColor = sColor; }
        }

        // Forward walk: measure interval extent (only inside bright runs)
        var fwdSteps = 0.0;
        if (myLum >= thresh) {
            for (var i = 1; i <= 12; i++) {
                let fi = f32(i);
                let sUV = uv + dirVec * (fi * stride) + perpVec * (wobble * fi * 0.12);
                if (sUV.x < 0.0 || sUV.x > 1.0 || sUV.y < 0.0 || sUV.y > 1.0) { break; }
                let sColor = textureSampleLevel(readTexture, u_sampler, sUV, 0.0).rgb;
                if (luma(sColor) < thresh) { break; }
                fwdSteps = fi;
            }
        }

        let intervalLen = backSteps + fwdSteps + 1.0;
        streakT = clamp(backSteps / max(intervalLen, 1.0), 0.0, 1.0);

        if (bestVal > myLum && bestVal > thresh) {
            // Head-bright → tail-dark ramp along the sorted interval
            let ramp = mix(1.10, 0.88, streakT);
            // Luma-preserving saturation punch on the streak color
            let bl = luma(bestColor);
            var sc = clamp(mix(vec3<f32>(bl), bestColor, 1.18), vec3<f32>(0.0), vec3<f32>(1.0));
            sc = clamp(sc * ramp, vec3<f32>(0.0), vec3<f32>(1.0));
            // Treble shimmer concentrated at the streak head
            let headGlow = pow(1.0 - streakT, 3.0) * treble * 0.18;
            sc = clamp(sc + vec3<f32>(headGlow), vec3<f32>(0.0), vec3<f32>(1.0));
            streak = sc;
            sorted = 1.0;
        }
    }

    // Composite the sorted streak (clicking locks the sort in harder)
    let sortMix = clamp(mask * sorted * (0.85 + downBoost * 0.15), 0.0, 1.0);
    var rgb = mix(color.rgb, streak, sortMix);

    // ── Scan sweep: a read-out band traveling along the sort axis ──
    if (mask > 0.01) {
        let axisCoord = dot(dVec, dirVec) / max(rEff, 0.001);
        let scanPos = fract(time * 0.22) * 2.4 - 1.2;
        let ds = axisCoord - scanPos;
        let band = exp(-60.0 * ds * ds) * mask;
        rgb = clamp(rgb + vec3<f32>(0.06, 0.09, 0.13) * band * (0.6 + bass * 0.4),
                    vec3<f32>(0.0), vec3<f32>(1.0));
    }

    // Cool lens rim tracing the spotlight edge
    let rim = smoothstep(rEff - 0.015, rEff + 0.01, dist) * mask;
    rgb = clamp(rgb + vec3<f32>(0.10, 0.16, 0.22) * rim * (0.5 + bass * 0.5),
                vec3<f32>(0.0), vec3<f32>(1.0));

    // Desaturated, dimmed surround keeps the spotlight as the hero
    // (same 0.1 outside dimming as the original, now with gentle desat)
    let gray = luma(rgb);
    let surround = mix(vec3<f32>(gray), rgb, 0.35) * 0.1;
    rgb = mix(surround, rgb, mask);

    // Fine animated grain inside the lens for texture
    let grainSeed = vec2<f32>(global_id.xy)
                  + vec2<f32>(fract(time * 0.7) * 91.7, fract(time * 1.3) * 57.3);
    let grain = (hash21(grainSeed) - 0.5) * 0.028 * mask;
    rgb = clamp(rgb + vec3<f32>(grain), vec3<f32>(0.0), vec3<f32>(1.0));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(rgb, origAlpha));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
