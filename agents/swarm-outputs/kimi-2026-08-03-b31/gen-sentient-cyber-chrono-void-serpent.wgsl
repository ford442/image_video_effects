// ----------------------------------------------------------------
// Sentient Cyber-Chrono Void-Serpent
// Category: generative
// Upgraded 2026-08-03 (batch b31, algorithmist):
//   - Bounds guard from u.config.zw; mouse handled as 0-1 (y=0 top), no flip/re-normalization
//   - Full 3D SDF library; torus chrono-rings + octahedral chrono-glass shards (matID 3/4)
//   - 2D geometric layer: hex-tessellated scale armor + Julia orbit-trap temporal rift backdrop
//   - Adaptive raymarch, real depth, semantic alpha, dataTextureA output
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
  config: vec4<f32>,       // .x = time (seconds), .y = rippleCount (0-50 active ripples), .zw = resolution (width, height)
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv (0–1 canvas: y=0 top), .w = mouse_down (>0.5 = pressed)
  zoom_params: vec4<f32>,  // .xyzw = user params p1…p4 (mapped from UI sliders)
  ripples: array<vec4<f32>, 50>,  // .xy = ripple uv, .z = startTime (seconds), .w = padding (0)
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}

fn hash33(p: vec3<f32>) -> vec3<f32> {
    var p2 = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                       dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                       dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(p2) * 43758.5453123);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    let v0 = vec3<f32>(0.0, 0.0, 0.0); let v1 = vec3<f32>(1.0, 0.0, 0.0);
    let v2 = vec3<f32>(0.0, 1.0, 0.0); let v3 = vec3<f32>(1.0, 1.0, 0.0);
    let v4 = vec3<f32>(0.0, 0.0, 1.0); let v5 = vec3<f32>(1.0, 0.0, 1.0);
    let v6 = vec3<f32>(0.0, 1.0, 1.0); let v7 = vec3<f32>(1.0, 1.0, 1.0);
    let nx00 = mix(dot(hash33(i + v0), f - v0), dot(hash33(i + v1), f - v1), u2.x);
    let nx10 = mix(dot(hash33(i + v2), f - v2), dot(hash33(i + v3), f - v3), u2.x);
    let nx01 = mix(dot(hash33(i + v4), f - v4), dot(hash33(i + v5), f - v5), u2.x);
    let nx11 = mix(dot(hash33(i + v6), f - v6), dot(hash33(i + v7), f - v7), u2.x);
    return mix(mix(nx00, nx10, u2.y), mix(nx01, nx11, u2.y), u2.z);
}

// ─── 3D SDF library ───
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}
fn sdOctahedron(p_in: vec3<f32>, s: f32) -> f32 {
    let p = abs(p_in);
    return (p.x + p.y + p.z - s) * 0.57735027;
}
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// ─── 2D geometric library ───
fn mod2(a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    return a - b * floor(a / b);
}
fn hexDist(p: vec2<f32>) -> f32 {
    let q = abs(p);
    return max(dot(q, normalize(vec2<f32>(1.0, 1.7320508))), q.x);
}
fn hexCell(p: vec2<f32>) -> vec4<f32> { // vec4(local_xy, cell_id_xy) of nearest hex cell
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let a = mod2(p, r) - h;
    let b = mod2(p - h, r) - h;
    let gv = select(b, a, dot(a, a) < dot(b, b));
    return vec4<f32>(gv, p - gv);
}
// Julia set ring orbit-trap (temporal rift signature)
fn juliaTrap(p: vec2<f32>, c: vec2<f32>) -> f32 {
    var z = p;
    var trap = 1e10;
    for (var i = 0; i < 8; i = i + 1) {
        z = vec2<f32>(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        trap = min(trap, abs(length(z) - 1.0)); // ring trap
        if (dot(z, z) > 16.0) { break; }
    }
    return trap;
}

// vec2(dist, matID) — 1 serpent, 2 void rift, 3 chrono-rings, 4 glass shards
fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let t = u.config.x * u.zoom_params.x * 0.5;

    // Mouse pull — mouse_uv is 0-1, y=0 top; world is y-up
    let mUv = u.zoom_config.yz;
    let mouse_pos = vec3<f32>((mUv.x - 0.5) * 6.0, (0.5 - mUv.y) * 6.0, 0.0);
    let dist_to_mouse = length(p - mouse_pos);
    let pull = 1.0 - smoothstep(0.0, 2.0, dist_to_mouse);
    p = mix(p, mouse_pos, pull * 0.5);

    let bass = plasmaBuffer[0].x * u.zoom_params.y;
    let treble = plasmaBuffer[0].z;

    // Serpent spine undulation
    var q = p;
    let serpent_freq = 0.5;
    let serpent_amp = 1.5;
    q.x = q.x + sin(q.z * serpent_freq + t) * serpent_amp;
    q.y = q.y + cos(q.z * serpent_freq * 0.8 + t * 1.2) * serpent_amp;

    // Repeating scale segments, twisted along z
    let scale_size = 0.5;
    var scale_p = q;
    scale_p.z = (fract(scale_p.z / scale_size + 0.5) - 0.5) * scale_size;
    let scale_rot = rot(q.z * 2.0);
    scale_p = vec3<f32>(scale_rot[0].x * scale_p.x + scale_rot[1].x * scale_p.y,
                        scale_rot[0].y * scale_p.x + scale_rot[1].y * scale_p.y, scale_p.z);

    let fracture = u.zoom_params.w;
    let disp = noise3D(q * 5.0 + t) * 0.1 * fracture;

    let serpent_thickness = 0.4 + bass * 0.3;
    let core_dist = length(q.xy) - serpent_thickness + disp;
    // Chrono-glass scale shard: octahedron instead of sphere, fracture expands it
    let shardLocal = rotY(q.z * 3.0 + t) * scale_p;
    let scale_dist = sdOctahedron(shardLocal, 0.3 + disp * 2.0);

    let serpent_dist = smin(core_dist, scale_dist, 0.2);

    // Torus chrono-rings clamped around the spine (matID 3)
    let ringRep = 2.0;
    var ring_p = q;
    ring_p.z = (fract(ring_p.z / ringRep + 0.5) - 0.5) * ringRep;
    let ring_rot = rot(q.z * 1.5 - t * 0.8);
    let ring_xy = ring_rot * ring_p.xy;
    let ring_dist = sdTorus(vec3<f32>(ring_xy.x, ring_p.z, ring_xy.y),
                            vec2<f32>(serpent_thickness + 0.25 + bass * 0.2, 0.03 + treble * 0.03));

    // Free-floating chrono-glass shards in the rift (matID 4)
    let glassGrid = floor(p / 3.0);
    var glass_dist = 1e5;
    if (hash21(glassGrid.xy + glassGrid.z * 7.7) > 0.5) {
        let cell_p = fract(p / 3.0) * 3.0 - 1.5;
        let glassLocal = rotY(t + glassGrid.z) * cell_p;
        glass_dist = sdOctahedron(glassLocal, 0.25 + treble * 0.2 + fracture * 0.02);
    }

    // Decaying temporal void floor
    var void_p = p;
    void_p.z = void_p.z + t * 2.0;
    let void_noise = noise3D(void_p * 2.0) * 0.5 + noise3D(void_p * 4.0) * 0.25;
    let void_dist = -void_p.y + void_noise * u.zoom_params.z * 2.0;

    var res = vec2<f32>(serpent_dist, 1.0);
    if (ring_dist < res.x) { res = vec2<f32>(ring_dist, 3.0); }
    if (glass_dist < res.x) { res = vec2<f32>(glass_dist, 4.0); }
    if (void_dist < res.x) { res = vec2<f32>(void_dist, 2.0); }
    return res;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e.x, e.y, e.y)).x - map(p - vec3<f32>(e.x, e.y, e.y)).x,
        map(p + vec3<f32>(e.y, e.x, e.y)).x - map(p - vec3<f32>(e.y, e.x, e.y)).x,
        map(p + vec3<f32>(e.y, e.y, e.x)).x - map(p - vec3<f32>(e.y, e.y, e.x)).x
    ));
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(TAU * (c * t + d));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    // bounds guard — mandatory
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(pixel) - 0.5 * res) / res.y;

    let t = u.config.x;
    let bass = plasmaBuffer[0].x * u.zoom_params.y;

    var ro = vec3<f32>(0.0, 0.0, -4.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Camera orbit from mouse (0-1, y=0 top -> centered, y-up world)
    let mC = (u.zoom_config.yz - vec2<f32>(0.5)) * 2.0;
    let cam_rot_y = rot(mC.x * PI);
    let cam_rot_x = rot(mC.y * PI * 0.5);
    ro = vec3<f32>(cam_rot_y[0].x * ro.x + cam_rot_y[1].x * ro.z, ro.y, cam_rot_y[0].y * ro.x + cam_rot_y[1].y * ro.z);
    rd = vec3<f32>(cam_rot_y[0].x * rd.x + cam_rot_y[1].x * rd.z, rd.y, cam_rot_y[0].y * rd.x + cam_rot_y[1].y * rd.z);
    ro = vec3<f32>(ro.x, cam_rot_x[0].x * ro.y + cam_rot_x[1].x * ro.z, cam_rot_x[0].y * ro.y + cam_rot_x[1].y * ro.z);
    rd = vec3<f32>(rd.x, cam_rot_x[0].x * rd.y + cam_rot_x[1].x * rd.z, cam_rot_x[0].y * rd.y + cam_rot_x[1].y * rd.z);

    // Raymarching — adaptive step count with fracture depth
    var dO = 0.0;
    var p = vec3<f32>(0.0);
    var hit_id = 0.0;
    var glow = 0.0;
    var hit = false;

    let maxSteps = 80 + min(i32(u.zoom_params.w * 5.0), 40);
    let maxDist = 20.0;

    for (var i = 0; i < maxSteps; i = i + 1) {
        p = ro + rd * dO;
        let dS = map(p);
        if (dS.x < 0.001) { hit_id = dS.y; hit = true; break; }
        if (dO > maxDist) { break; }
        dO += dS.x;
        if (dS.y == 1.0 || dS.y == 3.0) {
            glow += 0.01 / (0.01 + abs(dS.x)) * (0.5 + bass * 0.5);
        }
    }

    var col = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, l), 0.0);
        let amb = 0.1;
        let spec = pow(max(dot(reflect(rd, n), l), 0.0), 32.0);
        let fres = pow(clamp(1.0 - dot(n, -rd), 0.0, 1.0), 3.0);
        if (hit_id == 1.0) {
            let base_col = vec3<f32>(0.05, 0.05, 0.08);
            let spine_col = palette(p.z * 0.1 - t * u.zoom_params.x,
                                    vec3<f32>(0.5, 0.5, 0.5), vec3<f32>(0.5, 0.5, 0.5),
                                    vec3<f32>(1.0, 1.0, 1.0), vec3<f32>(0.0, 0.33, 0.67));
            col = base_col * (diff + amb) + spec;
            col += spine_col * glow * u.zoom_params.y;
            // Hex-tessellated scale armor etching (2D geometric layer)
            let armorUV = vec2<f32>(atan2(p.y, p.x) * 1.5, p.z * 1.2);
            let hc = hexCell(armorUV * 4.0);
            let hexEdge = smoothstep(0.4, 0.48, hexDist(hc.xy));
            let hexPulse = 0.5 + 0.5 * sin(t * 4.0 + dot(hc.zw, vec2<f32>(2.1, 1.3)));
            col += spine_col * hexEdge * hexPulse * (0.3 + bass * 0.4);
        } else if (hit_id == 2.0) {
            col = vec3<f32>(0.1, 0.02, 0.2) * (diff + amb);
        } else if (hit_id == 3.0) {
            // Chrono-rings — spectral time-band emission
            let band = 0.5 + 0.5 * sin(p.z * 8.0 - t * 6.0);
            let ring_col = mix(vec3<f32>(0.1, 0.9, 1.0), vec3<f32>(1.0, 0.4, 0.9), band);
            col = ring_col * (diff * 0.4 + 0.8) * (1.0 + bass) + fres * ring_col;

        } else {
            // Chrono-glass shards — refractive prism fresnel
            let prism = 0.5 + 0.5 * cos(t + p.z * 3.0 + vec3<f32>(0.0, 2.1, 4.2));
            col = prism * (diff * 0.5 + 0.3) + prism * fres * 1.5 + spec * 0.5;
        }
    } else {
        // Julia orbit-trap temporal rift backdrop (2D geometric layer)
        let jc = vec2<f32>(-0.74 + 0.05 * sin(t * 0.3), 0.18 + 0.04 * cos(t * 0.23));
        let trap = juliaTrap(uv * 1.6, jc);
        let trapGlow = (1.0 - smoothstep(0.0, 0.25, trap)) * (0.4 + bass * 0.6);
        let rift_col = palette(trap * 2.0 + t * 0.1,
                               vec3<f32>(0.2, 0.1, 0.3),
                               vec3<f32>(0.3, 0.2, 0.3),
                               vec3<f32>(1.0, 1.0, 1.0),
                               vec3<f32>(0.0, 0.33, 0.67));
        col += rift_col * trapGlow * u.zoom_params.z;
    }

    let fog = 1.0 - exp(-0.05 * dO);
    col = mix(col, vec3<f32>(0.02, 0.0, 0.05) + vec3<f32>(0.1, 0.05, 0.2) * glow * 0.2 * u.zoom_params.z, fog);

    // ACES-ish tone map
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    col = clamp((col * (a * col + vec3<f32>(b))) / (col * (c * col + vec3<f32>(d)) + vec3<f32>(e)), vec3<f32>(0.0), vec3<f32>(1.0));

    // Real depth: normalized ray distance on hit
    let depth = select(0.0, clamp(1.0 - dO / maxDist, 0.0, 1.0), hit);

    // Semantic alpha from luma
    let luma = dot(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + 0.2, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
