// ----------------------------------------------------------------
// Prismatic Fractal-Dunes
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
    config: vec4<f32>, // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>, // x=Dune Complexity, y=Prism Dispersion, z=Geyser Height, w=Wind Speed
    ripples: array<vec4<f32>, 50>,
};

// --- UTILS ---
fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    var mat = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < octaves; i++) {
        v += a * noise(pp);
        pp = mat * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// Smooth operators (best of both branches)
fn smax(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return max(a, b) + h * h * k * 0.25;
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// --- SCENE MAP ---
fn map(p: vec3<f32>, time: f32, audio: f32, duneComplexity: f32, windSpeed: f32, geyserHeight: f32, mousePos: vec3<f32>) -> vec2<f32> {
    var d = p.y;
    var matId = 0.0; // 0 = sand, 1 = prismatic crystal geyser

    // === DUNES (domain-warped fbm from main + feature style) ===
    let conveyor = vec2<f32>(time * windSpeed * 1.15, time * windSpeed * 0.48);
    let uv_dune = p.xz * 0.5 + conveyor;
    let warpX = fbm(uv_dune, 3);
    let warpY = fbm(uv_dune + vec2<f32>(5.2, 1.3), 3);
    let warped_uv = p.xz * (0.2 * duneComplexity) + vec2<f32>(warpX, warpY) * 2.0;
    let duneOctaves = clamp(i32(2.0 + duneComplexity * 0.4), 2, 6);
    let racingRidge = sin(p.x * 1.3 + p.z * 0.65 - time * windSpeed * 7.0) * 0.18;
    let dune_h = fbm(warped_uv, duneOctaves) * 3.0 + racingRidge;

    d -= dune_h;

    // Audio-reactive lift
    d -= audio * 0.5 * fbm(p.xz * 2.0, 3);

    // Mouse gravity crater (pushes terrain down)
    let mouseDist = length(p.xz - mousePos.xz);
    let crater = smoothstep(3.0, 0.0, mouseDist) * 2.0;
    d += crater * 1.5;

    // === PRISMATIC GEYSERS (KIFS from feature + sparse activation from main) ===
    var q = p;
    let q_xz = p.xz - round(p.xz / 4.0) * 4.0; // domain repetition
    q.x = q_xz.x;
    q.z = q_xz.y;
    let cellId = floor(p.xz / 4.0);
    let launchSeed = hash21(cellId + vec2<f32>(4.7, 9.1));
    let launchPhase = fract(time * (0.32 + windSpeed * 0.12) + launchSeed);
    let ballisticLift = geyserHeight * 4.0 * launchPhase * (1.0 - launchPhase);
    q.y -= dune_h + ballisticLift;

    let is_active = hash21(cellId) > 0.75; // ~25% of cells have geysers

    if (is_active) {
        var bp = q;
        for (var i = 0; i < 4; i++) { // more iterations = sharper prisms
            let bp_xz = abs(bp.xz) - 0.5;
            bp.x = bp_xz.x;
            bp.z = bp_xz.y;
            let rot = rotate2D(time * 0.5 + f32(i) * 0.7);
            let temp_xz = rot * bp.xz;
            bp.x = temp_xz.x;
            bp.z = temp_xz.y;
            bp.y = abs(bp.y) - 0.5;
            bp *= 1.2; // scale for more fractal detail
        }
        let d_kifs = length(bp) - 0.25 * (1.0 + min(audio, 1.5) * geyserHeight);
        let geyserD = smax(length(q.xz) - 0.2, d_kifs, 0.25);

        if (geyserD < d) {
            d = geyserD;
            matId = 1.0;
        }
    }

    // Mouse pull on nearby crystals
    if (mouseDist < 4.0 && matId == 1.0) {
        d = smin(d, length(p - mousePos) - 0.6, 1.2);
    }

    return vec2<f32>(d * 0.5, matId);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, duneComplexity: f32, windSpeed: f32, geyserHeight: f32, mousePos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, audio, duneComplexity, windSpeed, geyserHeight, mousePos).x - map(p - e.xyy, time, audio, duneComplexity, windSpeed, geyserHeight, mousePos).x,
        map(p + e.yxy, time, audio, duneComplexity, windSpeed, geyserHeight, mousePos).x - map(p - e.yxy, time, audio, duneComplexity, windSpeed, geyserHeight, mousePos).x,
        map(p + e.yyx, time, audio, duneComplexity, windSpeed, geyserHeight, mousePos).x - map(p - e.yyx, time, audio, duneComplexity, windSpeed, geyserHeight, mousePos).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord * 2.0 - res) / res.y;
    let time = u.config.x;
    let audioBands = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
    let audio = dot(audioBands, vec3<f32>(0.5, 0.3, 0.2));

    // Parameters from uniform
    let duneComplexity = u.zoom_params.x;
    let dispersion   = u.zoom_params.y;
    let geyserHeight = u.zoom_params.z;
    let windSpeed    = u.zoom_params.w;

    // === CAMERA (dynamic from feature + slight downward tilt from main) ===
    var ro = vec3<f32>(time * windSpeed * 1.9, 4.0 + audioBands.x * 0.7, -8.0 + time * windSpeed * 1.05);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Gentle downward look
    let camRot = rotate2D(0.35);
    let temp_rd_yz = camRot * rd.yz;
    rd.y = temp_rd_yz.x;
    rd.z = temp_rd_yz.y;

    // Mouse position in world space
    let mouseX = (u.zoom_config.y * 2.0 - 1.0) * res.x / res.y;
    let mouseY = u.zoom_config.z * 2.0 - 1.0;
    let mousePos = ro + vec3<f32>(mouseX * 12.0, 0.0, mouseY * 12.0);

    // === RAYMARCH ===
    var t = 0.0;
    var hit = false;
    var matId = 0.0;
    let marchSteps = 64 + i32(clamp(duneComplexity, 1.0, 10.0) * 2.4);
    for (var i = 0; i < 88; i++) {
        if (i >= marchSteps) { break; }
        let p = ro + rd * t;
        let resMap = map(p, time, audio, duneComplexity, windSpeed, geyserHeight, mousePos);
        if (resMap.x < 0.008) {
            hit = true;
            matId = resMap.y;
            break;
        }
        t += max(resMap.x, 0.004);
        if (t > 60.0) { break; }
    }

    var col = vec3<f32>(0.08, 0.04, 0.15) * (1.0 - uv.y * 0.6); // deep desert sky

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p, time, audio, duneComplexity, windSpeed, geyserHeight, mousePos);

        let light1 = normalize(vec3<f32>(1.0, 0.8, -0.6));
        let light2 = normalize(vec3<f32>(-0.7, 0.6, 1.0));

        // Prismatic chromatic dispersion
        let shift = dispersion * 0.12;
        let rDiff = max(0.0, dot(n, normalize(light1 + vec3<f32>(shift, 0.0, 0.0))));
        let gDiff = max(0.0, dot(n, light1));
        let bDiff = max(0.0, dot(n, normalize(light1 - vec3<f32>(shift, 0.0, 0.0))));

        let diff1 = vec3<f32>(rDiff, gDiff, bDiff);
        let diff2 = max(0.0, dot(n, light2)) * vec3<f32>(0.25, 0.35, 0.7);

        if (matId == 0.0) {
            // Sand dunes
            let sand = vec3<f32>(0.85, 0.68, 0.42);
            col = sand * (diff1 * 1.1 + diff2) * 0.9;
        } else {
            // Prismatic crystal geyser
            let base = vec3<f32>(0.15, 0.75, 1.0) * (1.0 + audio * 2.5);
            let fre = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            col = base * (diff1 * 1.6 + diff2) + vec3<f32>(1.0, 0.3, 0.9) * fre * dispersion * 2.0;
        }

        // Volumetric fog
        col = mix(col, vec3<f32>(0.12, 0.06, 0.18), 1.0 - exp(-0.018 * t));
    }

    // Wind-aligned sand streaks use continuous phases and velocity stretching.
    var sandStreaks = 0.0;
    for (var si = 0; si < 7; si++) {
        let fs = f32(si);
        let lane = fract(hash21(vec2<f32>(fs, 4.2)) + time * windSpeed * (0.35 + fs * 0.025));
        let center = vec2<f32>(lane * 2.4 - 1.2, hash21(vec2<f32>(fs, 8.8)) * 1.6 - 0.8);
        let delta = uv - center;
        sandStreaks += exp(-abs(delta.y) * 90.0) * exp(-abs(delta.x + 0.08) * 10.0) * (1.0 - lane);
    }
    col += vec3<f32>(1.0, 0.68, 0.28) * sandStreaks * (0.08 + windSpeed * 0.035);

    // Click-launched dust fronts skim the terrain.
    let screenUV = fragCoord / res;
    let aspectFix = vec2<f32>(res.x / res.y, 1.0);
    var dustFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri++) {
        let ripple = u.ripples[ri];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.5) { continue; }
        let ring = abs(length((screenUV - ripple.xy) * aspectFix) - age * (0.6 + windSpeed * 0.12));
        dustFront += exp(-ring * 48.0) * (1.0 - age / 2.5);
    }
    col += vec3<f32>(0.95, 0.55, 0.3) * dustFront * (0.25 + audioBands.y * 0.2);

    col = clamp(col, vec3<f32>(0.0), vec3<f32>(4.0));
    let windDir = normalize(vec2<f32>(1.0, 0.35));
    let historyUV = clamp(screenUV - windDir * (0.004 + windSpeed * 0.004), vec2<f32>(0.002), vec2<f32>(0.998));
    let previous = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0).rgb;
    let temporal = clamp(max(col, previous * 0.89), vec3<f32>(0.0), vec3<f32>(5.0));
    let depth = select(1.0, clamp(t / 60.0, 0.0, 0.995), hit);
    textureStore(dataTextureA, id.xy, vec4<f32>(temporal, 1.0));
    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(temporal, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
