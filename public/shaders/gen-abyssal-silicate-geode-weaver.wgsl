// ----------------------------------------------------------------
// Abyssal Silicate Geode-Weaver
// Category: generative
// ----------------------------------------------------------------
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

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

fn gyroid(p: vec3<f32>) -> f32 {
    return dot(sin(p), cos(p.yzx));
}

fn map(p: vec3<f32>, time: f32, mouse_pos: vec3<f32>) -> vec2<f32> {
    let threadDensity = u.zoom_params.x; // mapped: (1.0, 0.1, 3.0) default 1.0
    let geodeScale = u.zoom_params.y;    // mapped: (2.5, 0.5, 5.0) default 2.5

    // Outer Geode Cavity
    let v = voronoi(p * geodeScale);
    let crystalDist = (v.y - v.x) * 0.5 - 0.1;
    let sphereDist = length(p) - 2.5;
    let geodeDist = max(sphereDist, -crystalDist);

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

    var threadDist = (abs(gyroid(thread_p)) - 0.05) / threadDensity;

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
        } else {
            // Silicate threads
            let runner = sin(p.z * 9.0 - time * 18.0 + gyroid(p * 2.0));
            let iridescenceCol = getPalette(fresnel + time * 0.2 + p.z * 0.1 + runner * 0.12);
            let baseCol = vec3<f32>(0.8, 0.9, 1.0);

            col = mix(baseCol, iridescenceCol, iridescence);
            col = col + fresnel * 0.5;
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
    let previous = textureSampleLevel(dataTextureC, u_sampler, historyUV, 0.0).rgb;
    let temporal = clamp(max(col, previous * 0.9), vec3<f32>(0.0), vec3<f32>(5.0));
    let generatedDepth = select(1.0, clamp(t / 20.0, 0.0, 0.995), t < 20.0);
    textureStore(dataTextureA, id.xy, vec4<f32>(temporal, 1.0));
    textureStore(writeTexture, id.xy, vec4<f32>(temporal, 1.0));
    textureStore(writeDepthTexture, id.xy, vec4<f32>(generatedDepth, 0.0, 0.0, 0.0));
}
