// ═══════════════════════════════════════════════════════════════════
//  Rain Ripples  (RETRY expanded upgrade)
//  Category: liquid-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba,
//            depth-aware, aces-tone-map, fbm-micro-ripples,
//            voronoi-raindrops, caustics, thin-film-interference
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

const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(dot(p, vec2<f32>(127.1, 311.7)));
    return fract(vec2<f32>(n, n * 1.618) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) {
        s += a * valueNoise(p * f);
        f *= 2.0;
        a *= 0.5;
    }
    return s;
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn voronoi(p: vec2<f32>, t: f32) -> vec2<f32> {
    // Returns distance to nearest cell center in x, cell-id hash in y.
    let i = floor(p);
    let f = fract(p);
    var minD = 100.0;
    var cellHash = 0.0;
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let offset = vec2<f32>(f32(x), f32(y));
            let neighbor = i + offset;
            let point = offset + 0.5 + 0.5 * sin(hash22(neighbor) * TAU + t);
            let d = length(point - f);
            if (d < minD) {
                minD = d;
                cellHash = hash21(neighbor);
            }
        }
    }
    return vec2<f32>(minD, cellHash);
}
fn caustics(p: vec2<f32>, t: f32) -> f32 {
    // Caustic-like pattern via overlapping warped sine gradients.
    let c1 = sin(p.x * 18.0 + t + sin(p.y * 12.0));
    let c2 = sin(p.y * 16.0 - t * 0.7 + sin(p.x * 14.0));
    let c3 = sin((p.x + p.y) * 10.0 + t * 0.4);
    return pow(abs(c1 + c2 + c3) * 0.3, 2.0);
}
fn wetMask(p: vec2<f32>, t: f32) -> f32 {
    // SDF mask: wet patches are soft disks animated by FBM.
    let f = fbm(p * 3.0 + t * 0.05, 3);
    return smoothstep(0.35, 0.65, f);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }

    let uv = vec2<f32>(coord) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    let aspect = resolution.x / max(resolution.y, 0.001);
    let speed = mix(0.2, 1.2, p2);
    let waveWidth = mix(0.03, 0.12, 1.0 - p4);
    let scale = mix(0.5, 2.5, p3);

    let hasSpring = arrayLength(&extraBuffer) >= 139u;
    var rainPointer = u.zoom_config.yz; var pointerVelocity = vec2<f32>(0.0);
    if (hasSpring && extraBuffer[138] > 0.5) {
        rainPointer = vec2<f32>(extraBuffer[133], extraBuffer[134]); pointerVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    }
    if (hasSpring && global_id.x == 0u && global_id.y == 0u) {
        var pos = rainPointer; var vel = pointerVelocity; let seeded = extraBuffer[138] > 0.5;
        if (!seeded) { pos = u.zoom_config.yz; vel = vec2<f32>(0.0); }
        let dt = select(0.0, clamp(time - extraBuffer[137], 0.0, 0.05), seeded);
        vel += ((u.zoom_config.yz - pos) * 175.0 - vel * 24.0) * dt; pos += vel * dt;
        extraBuffer[133] = pos.x; extraBuffer[134] = pos.y; extraBuffer[135] = vel.x; extraBuffer[136] = vel.y; extraBuffer[137] = time; extraBuffer[138] = 1.0;
    }

    // Domain-warped FBM micro-ripples.
    let q = vec2<f32>(fbm(uv * scale * 8.0 + time * 0.1, 3),
                      fbm(uv * scale * 8.0 + vec2<f32>(5.2, 1.3) - time * 0.08, 3));
    let micro = vec2<f32>(fbm(uv * scale * 12.0 + 3.0 * q + time * 0.15, 3),
                          fbm(uv * scale * 12.0 + 3.0 * q + vec2<f32>(5.2, 1.3) - time * 0.12, 3)) * 0.004 * p4;

    // Voronoi cellular raindrop impacts.
    let cell = voronoi(uv * mix(4.0, 12.0, p3) + time * 0.05, time * 2.0);
    let drop = sin(cell.x * 40.0 - time * 8.0) * exp(-cell.x * 3.0) * 0.015 * p3;

    let pointerDelta = (uv - rainPointer) * vec2<f32>(aspect, 1.0);
    let pointerDist = length(pointerDelta); let pointerMask = exp(-pointerDist * pointerDist * 75.0);
    let pointerDir = select(vec2<f32>(0.0), pointerDelta / pointerDist, pointerDist > 0.001);
    let held = select(0.14, 1.0, u.zoom_config.w > 0.5);
    var totalDisplacement = pointerDir / vec2<f32>(aspect, 1.0) * pointerMask * held * (0.004 + p1 * 0.018)
        + pointerVelocity * pointerMask * select(0.001, 0.006, u.zoom_config.w > 0.5);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let startTime = ripple.z;
        let elapsed = time - startTime;
        let rippleMask = f32(startTime > 0.0 && elapsed >= 0.0 && elapsed <= 2.0);
        let uvC = vec2<f32>(uv.x * aspect, uv.y);
        let posC = vec2<f32>(ripple.x * aspect, ripple.y);
        let diff = uvC - posC;
        let dist = max(length(diff), 0.0001);
        let radius = speed * elapsed;
        let distFromWave = dist - radius;
        let waveMask = smoothstep(waveWidth, 0.0, abs(distFromWave));
        let profile = cos(distFromWave / max(waveWidth, 0.001) * TAU);
        let decay = max(0.0, 1.0 - elapsed * 0.5);
        let distDecay = max(0.0, 1.0 - dist * 2.0);
        let amplitude = profile * decay * distDecay * 0.03 * (1.0 + bass * 0.4) * waveMask * rippleMask;
        totalDisplacement -= (diff / dist) * amplitude;
    }
    totalDisplacement += micro;

    // Add raindrop displacement along ripple gradient.
    let dropGrad = vec2<f32>(cos(cell.y * TAU), sin(cell.y * TAU));
    totalDisplacement += dropGrad * drop;

    let displacedUV = clamp(uv + totalDisplacement, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, displacedUV, 0.0);

    let dispMag = length(totalDisplacement);
    let highlight = smoothstep(0.0005, 0.002, dispMag);
    let spec = vec3<f32>(0.12, 0.14, 0.18) * highlight * (1.0 + treble);
    color = vec4<f32>(color.rgb + spec, color.a);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let fog = exp(-depth * 2.0 * (1.0 - p1));
    color = vec4<f32>(color.rgb * fog, color.a);

    // Caustic refraction overlay on wet areas.
    let wet = wetMask(uv, time);
    let caus = caustics(uv * mix(2.0, 6.0, p3) + totalDisplacement * 50.0, time);
    let causColor = vec3<f32>(0.9, 0.95, 1.0) * caus * wet * p4;
    color = vec4<f32>(color.rgb + causColor * 0.15, color.a);

    // Chromatic aberration.
    let caDir = normalize(totalDisplacement + vec2<f32>(0.0001)) * dispMag * 0.5;
    let r = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV + caDir, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(displacedUV - caDir * 0.6, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color = vec4<f32>(mix(color.rgb, vec3<f32>(r, color.g, b), p4 * 0.5), color.a);

    // Thin-film rainbow interference on high curvature.
    let curvature = fbm(uv * 20.0 + totalDisplacement * 100.0, 2);
    let film = vec3<f32>(sin(curvature * TAU + 0.0), sin(curvature * TAU + 2.09), sin(curvature * TAU + 4.18));
    color = vec4<f32>(mix(color.rgb, color.rgb * (0.7 + 0.3 * film), wet * p3 * 0.25), color.a);

    let historyCoord = clamp(vec2<i32>(floor((uv - totalDisplacement * 0.35) * resolution)), vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1));
    let history = textureLoad(dataTextureC, historyCoord, 0);
    let persistence = clamp((0.08 + p4 * 0.22) * history.a, 0.0, 0.3);
    let hdr = mix(color.rgb * (1.0 + mids * 0.15), history.rgb * 0.975, persistence);
    let alpha = clamp(max(color.a, history.a * persistence) + dispMag * 18.0 + wet * 0.12 + bass * 0.06, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(acesToneMap(hdr), alpha));
    textureStore(dataTextureA, coord, vec4<f32>(min(hdr, vec3<f32>(8.0)), alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
