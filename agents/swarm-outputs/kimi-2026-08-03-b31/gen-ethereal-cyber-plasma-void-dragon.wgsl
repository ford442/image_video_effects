// ----------------------------------------------------------------
// Ethereal Cyber-Plasma Void-Dragon
// Category: generative
// Upgraded 2026-08-03 (batch b31, algorithmist):
//   - CRITICAL FIX: audio was read from u.config.y (rippleCount!) -> now plasmaBuffer[0].xyz
//   - Bounds guard from u.config.zw; mouse y-flip removed (0-1, y=0 top)
//   - Full 3D SDF library; octahedral crystal shards, torus halo around the head, box spine-ribs
//   - 2D geometric layer: Voronoi energy veins + kaleidoscopic fold in the nebula
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

// PRNG
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p = p + dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

// 3D Noise
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    let n = p.x + p.y * 157.0 + 113.0 * p.z;
    return mix(
        mix(mix(fract(sin(n + 0.0) * 43758.5453123),
                fract(sin(n + 1.0) * 43758.5453123), u2.x),
            mix(fract(sin(n + 157.0) * 43758.5453123),
                fract(sin(n + 158.0) * 43758.5453123), u2.x), u2.y),
        mix(mix(fract(sin(n + 113.0) * 43758.5453123),
                fract(sin(n + 114.0) * 43758.5453123), u2.x),
            mix(fract(sin(n + 270.0) * 43758.5453123),
                fract(sin(n + 271.0) * 43758.5453123), u2.x), u2.y), u2.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var cur = p;
    var a = 0.5;
    for (var i = 0; i < 4; i = i + 1) {
        f = f + a * noise(cur);
        cur = cur * 2.0;
        a = a * 0.5;
    }
    return f;
}

// Rotations
fn rotX(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(1., 0., 0., 0., c, -s, 0., s, c);
}
fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0., s, 0., 1., 0., -s, 0., c);
}
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ─── 3D SDF library ───
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
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
// Voronoi edge distance (energy veins), returns vec2(F2-F1, cellHash)
fn voronoiEdge(p: vec2<f32>) -> vec2<f32> {
    let ip = floor(p);
    let fp = fract(p);
    var f1 = 8.0;
    var f2 = 8.0;
    var cid = 0.0;
    for (var j = -1; j <= 1; j = j + 1) {
        for (var i = -1; i <= 1; i = i + 1) {
            let g = vec2<f32>(f32(i), f32(j));
            let o = vec2<f32>(hash12(ip + g), hash12(ip + g + 19.19));
            let r = g + o - fp;
            let d = dot(r, r);
            if (d < f1) { f2 = f1; f1 = d; cid = hash12(ip + g + 7.7); }
            else if (d < f2) { f2 = d; }
        }
    }
    return vec2<f32>(sqrt(f2) - sqrt(f1), cid);
}

// 2D regular-polygon / star SDF (for engraved sigils)
fn sdStar5(p_in: vec2<f32>, r: f32, rf: f32) -> f32 {
    let an = PI / 5.0;
    let en = PI / 5.0 * rf;
    let acs = vec2<f32>(cos(an), sin(an));
    let ecs = vec2<f32>(cos(en), sin(en));
    var p = p_in;
    p.x = abs(p.x);
    var bn = acs * (2.0 * clamp(dot(acs, p), 0.0, 1.0)) - p;
    p = select(p, bn, dot(acs, p) > 0.0);
    bn = ecs * (2.0 * clamp(dot(ecs, p), 0.0, 1.0)) - p;
    p = select(p, bn, dot(ecs, p) > 0.0);
    p = p - vec2<f32>(r, 0.0);
    p = p - vec2<f32>(sin(an), cos(an)) * clamp(dot(p, vec2<f32>(sin(an), cos(an))), 0.0, r);
    return length(p) * sign(p.x);
}

// kaleidoscopic symmetry fold
fn kaleido(p: vec2<f32>, folds: f32) -> vec2<f32> {
    let r = length(p);
    var a = atan2(p.y, p.x);
    let seg = TAU / folds;
    a = fract(a / seg) * seg;
    a = abs(a - seg * 0.5);
    return vec2<f32>(cos(a), sin(a)) * r;
}

// Main SDF evaluation: vec2(dist, matID) — 0 void, 1 dragon, 2 crystal, 3 halo
fn map(p: vec3<f32>, time: f32, audio: f32, mouseTarget: vec3<f32>, params: vec4<f32>) -> vec2<f32> {
    let plasma_int = params.x;
    let dragon_speed = params.y;
    let segment_den = params.z;
    let treble = plasmaBuffer[0].z;

    // Base time adjusted by speed
    let t = time * dragon_speed;

    // Dragon path / spine
    var d = 1000.0;
    var matID = 0.0;

    // Mouse attraction point + wandering head
    let dragon_head = mouseTarget + vec3<f32>(sin(t * 0.5), cos(t * 0.3), sin(t * 0.7)) * 2.0;
    var prev_pos = dragon_head;

    // Segment logic (fixed loop bound, skipped by density slider)
    for (var i = 0; i < 20; i = i + 1) {
        if (f32(i) >= segment_den) { continue; }

        let fi = f32(i);
        let t_offset = fi * 0.15;

        // Generate undulation
        let undulation = vec3<f32>(
            sin(t * 2.0 - t_offset) * 1.5,
            cos(t * 1.5 - t_offset) * 1.0,
            sin(t * 1.2 - t_offset) * 1.0
        );

        var cur_pos = prev_pos + vec3<f32>(0.0, 0.0, 1.2) + undulation * (0.2 + fi * 0.02);
        cur_pos = cur_pos + (hash33(vec3<f32>(fi, time * 0.1, 0.0)) - 0.5) * 0.5 * audio;

        let r = 0.8 - fi * 0.03 + sin(fi * 0.5 + t * 3.0) * 0.1;
        let seg_d = sdCapsule(p, prev_pos, cur_pos, max(r, 0.1));

        // Crystalline temporal scales: octahedral displacement + box rib cage per segment
        let scale_disp = (noise(p * 5.0 + time) * 2.0 - 1.0) * 0.05 * (1.0 + audio * 2.0);
        let mid = (prev_pos + cur_pos) * 0.5;
        let ribLocal = rotY(fi * 0.6 + t * 0.5) * (p - mid);
        let rib_d = sdBox(ribLocal, vec3<f32>(max(r, 0.1) + 0.12, 0.04, 0.04)) - 0.02;
        let shardLocal = rotX(fi * 1.3 - t) * (p - mid - vec3<f32>(0.0, max(r, 0.1) + 0.15, 0.0));
        let shard_d = sdOctahedron(shardLocal, 0.09 + treble * 0.06);

        let seg_geo = smin(smin(seg_d, rib_d, 0.1), shard_d, 0.08);
        d = smin(d, seg_geo + scale_disp, 0.8);

        prev_pos = cur_pos;
    }

    matID = 1.0;

    // Torus halo around the dragon's head — bass-pulsed plasma crown
    let haloLocal = rotX(sin(t * 0.8) * 0.6) * rotY(t * 0.9) * (p - dragon_head);
    let halo_d = sdTorus(haloLocal, vec2<f32>(1.3 + audio * 0.5, 0.05 + treble * 0.04));
    if (halo_d < d) { d = halo_d; matID = 3.0; }

    // Void/nebula floating octahedral crystals (replaces plain spheres)
    let grid = floor(p / 10.0);
    let cell_p = fract(p / 10.0) * 10.0 - 5.0;
    if (hash12(grid.xy + grid.z) > 0.7) {
        let crLocal = rotY(time * 0.5 + grid.x) * cell_p;
        let cr_d = sdOctahedron(crLocal, 0.7 + audio * 0.8);
        if (cr_d < d) { d = cr_d; matID = 2.0; }
    }

    return vec2<f32>(d, matID);
}

fn calcNormal(p: vec3<f32>, time: f32, audio: f32, mouseTarget: vec3<f32>, params: vec4<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audio, mouseTarget, params).x - map(p - e.xyy, time, audio, mouseTarget, params).x,
        map(p + e.yxy, time, audio, mouseTarget, params).x - map(p - e.yxy, time, audio, mouseTarget, params).x,
        map(p + e.yyx, time, audio, mouseTarget, params).x - map(p - e.yyx, time, audio, mouseTarget, params).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    // bounds guard — mandatory
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(pixel) - 0.5 * res) / res.y;

    let time = u.config.x;
    let audio = plasmaBuffer[0].x; // bass 20-200 Hz
    let mids = plasmaBuffer[0].y;

    // Sliders: x Plasma Intensity, y Undulation Speed, z Segment Density, w Nebula Density
    let params = u.zoom_params;

    // mouse_uv is 0-1, y=0 TOP — map to world with y-up, no flip
    let mUv = u.zoom_config.yz;
    let mouseTarget = vec3<f32>((mUv.x - 0.5) * 20.0, (0.5 - mUv.y) * 20.0, -5.0);

    // Dragon head anchor (matches map()) for halo-space sigil shading
    let tHead = time * params.y;
    let headPos = mouseTarget + vec3<f32>(sin(tHead * 0.5), cos(tHead * 0.3), sin(tHead * 0.7)) * 2.0;

    // Camera
    let ro = vec3<f32>(0.0, 0.0, -15.0);
    var rd = normalize(vec3<f32>(uv, 1.0));
    let cam_rot = rot(time * 0.1);
    rd = vec3<f32>(cam_rot * rd.xy, rd.z);

    // Raymarching — adaptive step count with plasma intensity
    var p = ro;
    var total_dist = 0.0;
    var matID = 0.0;
    var glow = 0.0;
    var hit = false;

    let maxSteps = 80 + min(i32(params.x * 15.0), 40);
    let maxDist = 50.0;

    for (var i = 0; i < maxSteps; i = i + 1) {
        let resMap = map(p, time, audio, mouseTarget, params);
        let d = resMap.x;
        matID = resMap.y;

        if (d < 0.01) { hit = true; break; }
        if (total_dist > maxDist) { break; }

        // Accumulate glow near the surface
        if (matID == 1.0) { // Dragon body glow
            glow = glow + 0.05 / (1.0 + d * d * 10.0) * params.x;
        } else if (matID == 2.0) { // Crystal glow
            glow = glow + 0.1 / (1.0 + d * d * 5.0) * audio;
        } else if (matID == 3.0) { // Halo glow
            glow = glow + 0.08 / (1.0 + d * d * 20.0) * (0.5 + audio * 2.0);
        }

        p = p + rd * d;
        total_dist = total_dist + d;
    }

    // Background Nebula: kaleidoscopically-folded volumetric FBM + Voronoi energy veins
    let kDir = vec3<f32>(kaleido(rd.xy, 6.0 + floor(mids * 4.0)), rd.z);
    let neb = fbm(normalize(kDir) * 3.0 + time * 0.2 + mouseTarget * 0.05) * params.w;
    let veins = voronoiEdge(uv * 6.0 + vec2<f32>(time * 0.05, -time * 0.03));
    let veinGlow = (1.0 - smoothstep(0.0, 0.08, veins.x)) * (0.4 + audio) * params.w;
    let neb_col = mix(vec3<f32>(0.05, 0.0, 0.1), vec3<f32>(0.2, 0.4, 0.6), neb);
    var col = neb_col * (1.0 + audio) + vec3<f32>(0.3, 0.1, 0.6) * veinGlow;

    if (hit) {
        let n = calcNormal(p, time, audio, mouseTarget, params);
        let l = normalize(vec3<f32>(1.0, 1.0, -1.0));

        let diff = max(dot(n, l), 0.0);
        let r_vec = reflect(rd, n);
        let spec = pow(max(dot(r_vec, l), 0.0), 32.0);

        // Fresnel / Iridescence
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let irid_col = 0.5 + 0.5 * cos(time + p.y * 2.0 + vec3<f32>(0.0, 2.0, 4.0));

        if (matID == 1.0) { // Dragon
            let base_col = vec3<f32>(0.1, 0.15, 0.2);
            col = base_col * diff + spec * irid_col + fresnel * irid_col * 2.0;
            // Voronoi circuit veins etched into the armor (2D geometric layer)
            let veinBody = voronoiEdge(p.xy * 4.0 + p.z);
            let etch = (1.0 - smoothstep(0.0, 0.06, veinBody.x)) * (0.5 + audio);
            col += vec3<f32>(0.0, 0.9, 1.0) * etch * params.x * 0.5;
            let inner_glow = vec3<f32>(0.0, 0.8, 1.0) * glow * (1.0 + audio * 1.5);
            col = col + inner_glow;

        } else if (matID == 2.0) { // Octahedral crystal
            col = vec3<f32>(0.8, 0.2, 1.0) * diff + spec + fresnel * vec3<f32>(1.0, 0.5, 0.8);
            col = col + vec3<f32>(1.0, 0.0, 0.5) * glow;
        } else if (matID == 3.0) { // Plasma halo
            let halo_col = mix(vec3<f32>(0.2, 0.6, 1.0), vec3<f32>(1.0, 0.4, 0.9), 0.5 + 0.5 * sin(time));
            col = halo_col * (diff * 0.3 + 0.9) * (1.0 + audio * 2.0) + fresnel * halo_col;
            // Engraved star sigils rotating on the halo plane (2D geometric layer)
            let sigilUV = vec2<f32>(atan2(p.y - headPos.y, p.x - headPos.x), length(p.xy - headPos.xy));
            let star_d = sdStar5(vec2<f32>(fract(sigilUV.x * 2.5) - 0.5, sigilUV.y - 1.3) * 6.0, 0.6, 0.5);
            col += halo_col * (1.0 - smoothstep(0.0, 0.1, abs(star_d))) * (0.5 + audio);
        }
    }

    // Add volumetric nebula fog
    col = mix(col, neb_col, smoothstep(10.0, 50.0, total_dist));

    // Tone mapping + vignette
    col = col / (1.0 + col);
    let vig = 1.0 - length(uv) * 0.8;
    col = col * vig;

    // Real depth: normalized ray distance on hit
    let depth = select(0.0, clamp(1.0 - total_dist / maxDist, 0.0, 1.0), hit);

    // Semantic alpha from luma
    let luma = dot(clamp(col, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + 0.2, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(col, alpha));
}
