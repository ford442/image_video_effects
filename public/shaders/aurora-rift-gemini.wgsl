// ===============================================================
// Aurora Rift Gemini – Hyper-Spectral Flux v2
// Enhanced aurora with magnetic field simulation, shimmering
// particle effects, and a dual-palette color system.
// ===============================================================
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,
    zoom_params: vec4<f32>,
    zoom_config: vec4<f32>,
    ripples:     array<vec4<f32>, 50>,
};

// --- (Hash functions, noise, fbm, curlNoise, voronoiCell, quaternionRotate, hsv2rgb - unchanged) ---

fn hash2(p: vec2<f32>) -> f32 {
    var h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash4(p: vec4<f32>) -> f32 {
    let dot4 = dot(p, vec4<f32>(1.0, 57.0, 113.0, 157.0));
    return fract(sin(dot4) * 43758.5453123);
}

fn noise4d(p: vec4<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    var sum = 0.0;
    for (var w: i32 = 0; w <= 1; w = w + 1) {
        for (var z: i32 = 0; z <= 1; z = z + 1) {
            for (var y: i32 = 0; y <= 1; y = y + 1) {
                for (var x: i32 = 0; x <= 1; x = x + 1) {
                    let corner = i + vec4<f32>(f32(x), f32(y), f32(z), f32(w));
                    let wx = select(1.0 - u.x, u.x, x == 1);
                    let wy = select(1.0 - u.y, u.y, y == 1);
                    let wz = select(1.0 - u.z, u.z, z == 1);
                    let ww = select(1.0 - u.w, u.w, w == 1);
                    sum = sum + wx * wy * wz * ww * hash4(corner);
                }
            }
        }
    }
    return sum * 2.0 - 1.0;
}

fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum = sum + amp * (hash2(p * freq + time * 0.1) - 0.5);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.001;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>(n2 - n4, n1 - n3) / (2.0 * eps);
}

fn voronoiCell(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    var best = 1e5;
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let cellPos = i + vec2<f32>(f32(x), f32(y));
            let seed = vec2<f32>(hash2(cellPos), hash2(cellPos + 13.37));
            let point = cellPos + seed - 0.5;
            let d = length(point - p);
            best = min(best, d);
        }
    }
    return best;
}

fn quaternionRotate(col: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    let s = sin(angle * 0.5);
    let c = cos(angle * 0.5);
    let q = vec4<f32>(normalize(axis) * s, c);
    let t = 2.0 * cross(q.xyz, col);
    return col + q.w * t + cross(q.xyz, t);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Spectral power distribution
// ─────────────────────────────────────────────────────────────────────────────
fn spectralPower(col: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeCol = max(col, vec3<f32>(0.001));
    let high = pow(safeCol, vec3<f32>(2.2));
    let low = sqrt(safeCol);
    let band = sin(safeCol * 3.145679);
    return mix(low, high, pattern) + band * pattern * 0.15;
}

// ✨ GEMINI UPGRADE: Magnetic field simulation
fn magneticField(p: vec2<f32>, time: f32) -> vec2<f32> {
    let p1 = vec2<f32>(sin(time * 0.5), cos(time * 0.5)) * 0.5 + 0.5;
    let p2 = vec2<f32>(sin(time * 0.7), cos(time * 0.4)) * 0.5 + 0.5;
    let v1 = p - p1;
    let v2 = p - p2;
    let f1 = v1 / pow(length(v1), 2.0);
    let f2 = v2 / pow(length(v2), 2.0);
    return (f1 - f2) * 0.01;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let time = u.config.x;

    let scale = u.zoom_params.x * 3.5 + 0.5;
    let flowSpeed = u.zoom_params.y * 2.8 + 0.2;
    let diffusionRate = u.zoom_params.z * 0.8 + 0.1;
    let fbmOctaves = i32(u.zoom_params.w * 5.0 + 2.0);
    let rotSpeed = u.zoom_config.x * 1.9 + 0.1;
    let depthParallax = u.zoom_config.y * 0.8;
    let emitThresh = u.zoom_config.z * 0.25 + 0.05;
    let chromaSpread = u.zoom_config.w * 0.5;

    let srcCol = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;

    // ✨ GEMINI UPGRADE: Integrate magnetic field
    let magField = magneticField(uv, time);
    let curl = curlNoise(uv * scale + depth * depthParallax + magField, time * flowSpeed);

    var totalWarp = vec2<f32>(0.0);
    // (Multi-layer parallax - slightly modified)
    for (var layer: i32 = 0; layer < 4; layer = layer + 1) { // 4 layers
        let layerDepth = f32(layer) / 3.0;
        let layerWeight = 1.0 / (1.0 + abs(depth - layerDepth) * 15.0);
        let advected = curlNoise(uv * scale + curl * 0.4, time * flowSpeed * (1.0 + f32(layer) * 0.5));
        let offset = advected * depthParallax * layerWeight;
        totalWarp += offset * layerWeight;
    }
    
    let cellDist = voronoiCell(uv * scale * 2.0 + totalWarp);
    let fbmVal = fbm(uv * scale * 4.0 + curl, time, fbmOctaves);
    let foamPattern = smoothstep(0.0, 0.1, cellDist) * 0.7 + smoothstep(0.2, 0.4, fbmVal) * 0.3;

    let hyper = noise4d(vec4<f32>(uv * scale * 1.5, time * 0.4, depth * 2.0, sin(time)));
    let hyperMod = (hyper + 1.0) * 0.5;
    
    let waveA = sin(length(uv - 0.5) * 28.0 - time * 3.2);
    let waveB = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 22.0 + time * 2.7);
    let waveC = sin(dot(uv - 0.5, vec2<f32>(1.1, 0.9)) * 30.0 - time * 4.1);
    let interference = (waveA * waveB * waveC + 1.0) * 0.5;

    let pattern = (foamPattern * 0.4 + hyperMod * 0.3 + interference * 0.3) * (1.0 + (1.0 - depth) * 1.8);

    let axis = normalize(srcCol + vec3<f32>(0.12, 0.07, 0.04));
    let angle = time * rotSpeed + pattern * 3.5;
    let quatCol = quaternionRotate(srcCol, angle, axis);

    let disp = pattern * chromaSpread / dims.x * 28.0;
    let rUV = clamp(uv + totalWarp * disp + curl * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + totalWarp * disp * 0.9 + curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + totalWarp * disp * 1.1 - curl * 0.018, vec2<f32>(0.0), vec2<f32>(1.0));
    let dispersed = vec3<f32>(
        textureSampleLevel(videoTex, videoSampler, rUV, 0.0).r,
        textureSampleLevel(videoTex, videoSampler, gUV, 0.0).g,
        textureSampleLevel(videoTex, videoSampler, bUV, 0.0).b
    );

    let border = smoothstep(emitThresh, 1.0, smoothstep(0.08, 0.12, cellDist) * pattern * length(curl));
    
    // ✨ GEMINI UPGRADE: Dual palette plasma
    let plasma1 = hsv2rgb(fract(time * 0.07 + pattern + hyper), 0.9, 1.0);
    let plasma2 = hsv2rgb(fract(time * 0.05 + pattern * 0.5 + hyper * 2.0), 0.8, 1.0);
    let plasma = mix(plasma1, plasma2, 0.5);
    
    let emissive = mix(dispersed, plasma, border * 0.6);

    let historyUV = clamp(uv + totalWarp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let history = textureSampleLevel(historyTex, videoSampler, historyUV, 0.0).rgb;
    let flowDir = normalize(totalWarp + curl + 0.001);
    let anisotropy = 1.0 - abs(dot(flowDir, normalize(uv - 0.5 + 0.001))) * 0.3;
    let diffused = mix(emissive, history, diffusionRate * anisotropy);

    // ✨ GEMINI UPGRADE: Shimmer effect
    let shimmer_noise = hash2(uv + time * 0.1);
    var shimmer = 0.0;
    if (shimmer_noise > 0.995) {
        shimmer = shimmer_noise * 100.0;
    }
    
    let spectral = spectralPower(diffused, pattern);
    let finalCol = mix(srcCol, spectral, 1.0) + shimmer;

    textureStore(outTex, vec2<i32>(gid.xy), vec4<f32>(finalCol, 1.0));
    textureStore(historyBuf, vec2<i32>(gid.xy), vec4<f32>(diffused, 1.0));
    textureStore(outDepth, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
