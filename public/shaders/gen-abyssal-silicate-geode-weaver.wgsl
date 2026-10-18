// ═══════════════════════════════════════════════════════════════════
//  Abyssal Silicate Geode-Weaver
//  Category: generative
//  Features: audio-reactive, mouse-driven, click-reactive, temporal, depth-aware, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27
//  Ideas: agate banding from Voronoi F1 rings; dew-bead knots strung on the threads; thread thickness feeds thin-film phase
//  A packing: HDR history RGB (max(col, prev*0.9)) + semantic alpha; ACES on writeTexture only
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

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn voronoi(x: vec3<f32>) -> vec2<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec2<f32>(8.0);

    for(var k = -1; k <= 1; k = k + 1) {
        for(var j = -1; j <= 1; j = j + 1) {
            for(var i = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + g);
                let d = g + o - f;
                let d2 = dot(d, d);
                if(d2 < m.x) {
                    m = vec2<f32>(m.x, d2);
                    m.x = d2;
                } else if(d2 < m.y) {
                    m.y = d2;
                }
            }
        }
    }
    return m;
}

// IDEA 1 helper: same F1/F2 search as voronoi(), plus a hash of the nearest cell.
fn voronoiCell(x: vec3<f32>) -> vec3<f32> {
    let n = floor(x);
    let f = fract(x);
    var m = vec2<f32>(8.0);
    var cellId = 0.0;
    for(var k = -1; k <= 1; k = k + 1) {
        for(var j = -1; j <= 1; j = j + 1) {
            for(var i = -1; i <= 1; i = i + 1) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash33(n + g);
                let d = g + o - f;
                let d2 = dot(d, d);
                if(d2 < m.x) {
                    m = vec2<f32>(d2, m.x);
                    cellId = o.x;
                } else if(d2 < m.y) {
                    m.y = d2;
                }
            }
        }
    }
    return vec3<f32>(m.x, m.y, cellId);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn gyroid(p: vec3<f32>) -> f32 {
    return dot(sin(p), cos(p.yzx));
}

fn gyroidGrad(p: vec3<f32>) -> vec3<f32> {
    let s = sin(p);
    let c = cos(p);
    return vec3<f32>(
        c.x * c.y - s.z * s.x,
        c.y * c.z - s.x * s.y,
        c.z * c.x - s.y * s.z
    );
}

// Warped / rotating domain in which the gyroid threads are static. Shared by
// map() and the IDEA 2 bead lattice so pearls ride the threads.
fn threadDomain(p: vec3<f32>, time: f32, mouse_pos: vec3<f32>) -> vec3<f32> {
    let threadDensity = u.zoom_params.x;

    // Silicate Threads (domain-warped gyroid)
    var thread_p = p * threadDensity;

    // Gentle gravity well towards mouse
    let to_mouse = mouse_pos - p;
    let dist_to_mouse = length(to_mouse);
    let gravity_pull = 1.0 / (1.0 + dist_to_mouse * dist_to_mouse);
    thread_p = thread_p + normalize(to_mouse + 0.001) * gravity_pull * 0.5;

    // Fast gyroid filaments stream through a rotating domain. Motion is
    // analytic in time, so it remains smooth across refresh rates.
    let domainRot = rot2D(time * 1.35);
    let rotatedXZ = domainRot * thread_p.xz;
    thread_p.x = rotatedXZ.x;
    thread_p.z = rotatedXZ.y;
    thread_p = thread_p + vec3<f32>(sin(time * 2.2), cos(time * 1.7), -time * 3.2) * 0.55;
    return thread_p;
}

fn map(p: vec3<f32>, time: f32, mouse_pos: vec3<f32>) -> vec2<f32> {
    let threadDensity = u.zoom_params.x; // mapped: (1.0, 0.1, 3.0) default 1.0
    let geodeScale = u.zoom_params.y;    // mapped: (2.5, 0.5, 5.0) default 2.5

    // Outer Geode Cavity
    let v = voronoi(p * geodeScale);
    let crystalDist = (v.y - v.x) * 0.5 - 0.1;
    let sphereDist = length(p) - 2.5;
    let geodeDist = max(sphereDist, -crystalDist);

    let thread_p = threadDomain(p, time, mouse_pos);
    let threadDist = (abs(gyroid(thread_p)) - 0.05) / threadDensity;

    // Combine and identify material (1 = geode, 2 = threads)
    let k = 0.2;
    let dist = smin(geodeDist, threadDist, k);

    var mat = 1.0;
    if (threadDist < geodeDist) {
        mat = 2.0;
    }

    return vec2<f32>(dist, mat);
}

fn calcNormal(p: vec3<f32>, time: f32, mouse_pos: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, mouse_pos).x - map(p - e.xyy, time, mouse_pos).x,
        map(p + e.yxy, time, mouse_pos).x - map(p - e.yxy, time, mouse_pos).x,
        map(p + e.yyx, time, mouse_pos).x - map(p - e.yyx, time, mouse_pos).x
    ));
}

fn getPalette(t: f32) -> vec3<f32> {
    let a = vec3<f32>(0.5, 0.5, 0.5);
    let b = vec3<f32>(0.5, 0.5, 0.5);
    let c = vec3<f32>(1.0, 1.0, 1.0);
    let d = vec3<f32>(0.263, 0.416, 0.557);
    return a + b * cos(TAU * (c * t + d));
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dim = textureDimensions(writeTexture);
    if (id.x >= dim.x || id.y >= dim.y) {
        return;
    }

    let time = u.config.x;
    let resolution = vec2<f32>(f32(dim.x), f32(dim.y));
    var uv = (vec2<f32>(f32(id.x), f32(id.y)) - 0.5 * resolution) / resolution.y;

    // Mouse coords mapping
    let mouse_uv = u.zoom_config.yz; // 0-1 canvas: y=0 top
    var mouse_clip = (mouse_uv - 0.5) * vec2<f32>(resolution.x/resolution.y, 1.0) * 2.0;
    let mouse_pos = vec3<f32>(mouse_clip.x, mouse_clip.y, 0.0) * 2.0;

    let iridescence = u.zoom_params.z; // mapped: (0.8, 0.0, 1.0) default 0.8
    let acousticGlow = u.zoom_params.w;  // mapped: (1.5, 0.0, 5.0) default 1.5

    let audioBands = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(2.0));
    let audio = dot(audioBands, vec3<f32>(0.5, 0.3, 0.2));

    // Camera setup
    var ro = vec3<f32>(sin(time * 1.1) * 0.35, cos(time * 0.9) * 0.25, 5.0);
    var rd = normalize(vec3<f32>(uv, -1.0));

    let flightTime = time * (0.65 + 0.15 * acousticGlow + audioBands.x * 0.12);
    let cam_rot = rot2D(flightTime);

    // Rotate camera and ray
    let tmp_ro = cam_rot * ro.xz;
    ro = vec3<f32>(tmp_ro.x, ro.y, tmp_ro.y);
    let tmp_rd = cam_rot * rd.xz;
    rd = vec3<f32>(tmp_rd.x, rd.y, tmp_rd.y);

    var t = 0.0;
    var d = 0.0;
    var mat = 0.0;
    var p = vec3<f32>(0.0);
    var depth = 0.0;

    // Raymarching loop
    for(var i = 0; i < 88; i = i + 1) {
        p = ro + rd * t;
        let res = map(p, time, mouse_pos);
        d = res.x;
        mat = res.y;

        if (abs(d) < 0.001 || t > 20.0) {
            break;
        }

        t = t + max(abs(d) * 0.75, 0.001);
        depth = depth + 1.0;
    }

    var col = vec3<f32>(0.01, 0.02, 0.05); // Background
    var alphaCover = 0.2; // void haze floor; surfaces raise it

    if (t < 20.0) {
        let n = calcNormal(p, time, mouse_pos);
        let view_dir = -rd;
        let fresnel = pow(1.0 - max(dot(n, view_dir), 0.0), 3.0);

        if (mat == 1.0) {
            // Geode facets
            let baseCol = vec3<f32>(0.05, 0.1, 0.2);
            let edgeGlow = vec3<f32>(0.1, 0.5, 0.8) * fresnel * 2.0;
            // Depth subsurface scattering
            let sss = smoothstep(0.0, 50.0, depth) * vec3<f32>(0.8, 0.2, 0.5);

            // Audio pulse
            let shardPulse = pow(max(0.0, sin(length(p) * 18.0 - time * 14.0 + atan2(p.y, p.x) * 3.0)), 8.0);
            let pulse = ((sin(time * 5.0 - p.y * 2.0) * 0.5 + 0.5) * audio + shardPulse * (0.25 + audioBands.z)) * acousticGlow;

            col = baseCol + edgeGlow + sss + pulse * vec3<f32>(0.2, 0.6, 1.0);

            // IDEA 1: agate / chalcedony banding. Rings are contours of the
            // Voronoi nearest-seed distance F1 (F2-F1 is pinned by the SDF),
            // phase-offset per cell, colour-zoned blue at the seed -> rose at the rim.
            let vc = voronoiCell(p * u.zoom_params.y);
            let seedR = sqrt(max(vc.x, 0.0));
            let bandPhase = seedR * 11.0 + vc.z * TAU;
            let bandRing = smoothstep(0.35, 0.85, 0.5 + 0.5 * sin(bandPhase));
            let zoneCol = mix(vec3<f32>(0.05, 0.16, 0.36), vec3<f32>(0.62, 0.20, 0.36), smoothstep(0.1, 0.75, seedR));
            col = mix(col, col * 0.55 + zoneCol * 0.9, bandRing * 0.75);
            alphaCover = 0.55 + 0.25 * bandRing;
        } else {
            // Silicate threads
            let runner = sin(p.z * 9.0 - time * 18.0 + gyroid(p * 2.0));
            // IDEA 2: dew-bead knots on a jittered lattice in the thread's own
            // (rotating, warped) domain, so pearls ride the threads.
            let tp = threadDomain(p, time, mouse_pos);
            let bq = tp * 1.6;
            let bcell = hash33(floor(bq));
            let bf = fract(bq) - 0.5 - (bcell - 0.5) * 0.3;
            let bRad = 0.17 + 0.12 * bcell.x;
            let bDist = length(bf);
            let bead = 1.0 - smoothstep(bRad * 0.55, bRad, bDist);

            // IDEA 3: physical sheet thickness (0.1 / |grad gyroid|) plus bead swell
            // feeds the thin-film phase.
            let thickness = 0.1 / max(length(gyroidGrad(tp)), 0.25) + bead * 0.12;

            let iridescenceCol = getPalette(fresnel + time * 0.2 + p.z * 0.1 + runner * 0.12 + thickness * 2.2);
            let baseCol = vec3<f32>(0.8, 0.9, 1.0);

            col = mix(baseCol, iridescenceCol, iridescence);
            col = col + fresnel * 0.5;

            // Pearl dome normal (bead-space offset rotated back into world), then specular.
            var bw = bf;
            let unrot = rot2D(-time * 1.35) * bw.xz;
            bw = vec3<f32>(unrot.x, bw.y, unrot.y);
            let dome = (bw - n * dot(bw, n)) / max(bRad, 0.05);
            let nb = normalize(n + dome * 0.9 * bead);
            let lightDir = normalize(vec3<f32>(0.4, 0.7, 0.6));
            let halfV = normalize(lightDir + view_dir);
            let spec = pow(max(dot(nb, halfV), 0.0), 48.0);
            let pearlCol = vec3<f32>(0.85, 0.93, 1.0) * (0.3 + 1.6 * spec) + iridescenceCol * 0.25 * iridescence;
            col = mix(col, pearlCol, bead * 0.8);
            alphaCover = 0.8 + 0.2 * bead;
        }

        // Fog
        col = mix(col, vec3<f32>(0.01, 0.02, 0.05), 1.0 - exp(-0.02 * t * t));
    }

    // Click waves refract across the cavity wall and launch shard-bright fronts.
    let screenUV = vec2<f32>(id.xy) / resolution;
    let aspectFix = vec2<f32>(resolution.x / resolution.y, 1.0);
    var clickWave = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r = 0u; r < rippleCount; r++) {
        let ripple = u.ripples[r];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.4) { continue; }
        let ring = abs(length((screenUV - ripple.xy) * aspectFix) - age * 0.62);
        clickWave += exp(-ring * 65.0) * (1.0 - age / 2.4);
    }
    col += getPalette(time * 0.15 + clickWave) * clickWave * (0.4 + iridescence);

    // Apply contrast, then advect bounded display history through the rotating cavity.
    col = smoothstep(vec3<f32>(0.0), vec3<f32>(1.2), col);
    let centered = screenUV - 0.5;
    let tangent = vec2<f32>(-centered.y, centered.x);
    let historyUV = clamp(screenUV - tangent * 0.014 - normalize(centered + vec2<f32>(0.0001)) * 0.003, vec2<f32>(0.002), vec2<f32>(0.998));
    // Exact bilinear history read (rgba32float is not filterable): 4 clamped textureLoads.
    let cDim = textureDimensions(dataTextureC);
    let cMax = vec2<i32>(i32(cDim.x) - 1, i32(cDim.y) - 1);
    let hp = historyUV * vec2<f32>(f32(cDim.x), f32(cDim.y)) - vec2<f32>(0.5);
    let hi = vec2<i32>(floor(hp));
    let hf = fract(hp);
    let c00 = textureLoad(dataTextureC, clamp(hi, vec2<i32>(0), cMax), 0).rgb;
    let c10 = textureLoad(dataTextureC, clamp(hi + vec2<i32>(1, 0), vec2<i32>(0), cMax), 0).rgb;
    let c01 = textureLoad(dataTextureC, clamp(hi + vec2<i32>(0, 1), vec2<i32>(0), cMax), 0).rgb;
    let c11 = textureLoad(dataTextureC, clamp(hi + vec2<i32>(1, 1), vec2<i32>(0), cMax), 0).rgb;
    let previous = mix(mix(c00, c10, hf.x), mix(c01, c11, hf.x), hf.y);
    let temporal = clamp(max(col, previous * 0.9), vec3<f32>(0.0), vec3<f32>(5.0));
    let generatedDepth = select(1.0, clamp(t / 20.0, 0.0, 0.995), t < 20.0);
    // Semantic alpha: surface coverage (geode / thread / pearl) plus click emission.
    let alpha = clamp(alphaCover + clickWave * 0.5, 0.0, 1.0);
    // A keeps the HDR history; ACES applies to the display copy only.
    let display = acesToneMap(temporal);
    textureStore(dataTextureA, id.xy, vec4<f32>(temporal, alpha));
    textureStore(writeTexture, id.xy, vec4<f32>(display, alpha));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(generatedDepth, 0.0, 0.0, 0.0));
}
