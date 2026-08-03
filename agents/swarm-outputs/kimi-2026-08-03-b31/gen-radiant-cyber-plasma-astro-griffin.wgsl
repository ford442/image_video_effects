// ----------------------------------------------------------------
// Radiant Cyber-Plasma Astro-Griffin  (visualist upgrade b31)
// Category: generative
// Upgrade: material-ID palette split (wings/body/core), per-feather
//          facet variation, tri-tessellated chrono-prism inlay,
//          3-point lighting + Fresnel rim, ACES tonemap, real depth
//          + data outputs, plasmaBuffer[0] audio contract fix.
// ----------------------------------------------------------------
// --- CANONICAL HEADER (bindings 0-12) ---
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY (0-1, y=0 top), w=MouseDown
    zoom_params: vec4<f32>,  // x=Warp Intensity, y=Wing Span, z=Fractal Depth, w=Plasma Glow
    ripples: array<vec4<f32>, 50>,
};

// --- UTILITIES ---
const PI: f32 = 3.14159265359;
const MAX_DIST: f32 = 20.0;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash33(p3: vec3<f32>) -> vec3<f32> {
    var p = fract(p3 * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + vec3<f32>(33.33));
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn hash21(p: vec2<f32>) -> f32 {
    let q = fract(p * vec2<f32>(234.34, 435.345));
    let s = dot(q, q + 34.23);
    return fract(q.x * q.y + s);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Triangular tessellation edge distance (2D): 0 on grid lines.
// Used to carve glowing chrono-prism seams into the griffin's hide.
fn triGridEdge(p: vec2<f32>, scale: f32) -> f32 {
    let q = p * scale;
    let r = vec2<f32>(1.0, 1.7320508); // hex basis (1, sqrt3)
    let a = fract(q / r) * r - r * 0.5;
    let b = fract((q - r * 0.5) / r) * r - r * 0.5;
    let g = select(a, b, dot(b, b) < dot(a, a));
    // distance to the 3 mirror planes of the triangle cell
    let d1 = abs(g.y);
    let d2 = abs(dot(g, vec2<f32>(0.8660254, 0.5)));
    let d3 = abs(dot(g, vec2<f32>(-0.8660254, 0.5)));
    return min(d1, min(d2, d3)) / scale;
}

// --- SDF FUNCTIONS ---

// Wing feathers using domain repetition (returns distance + feather cell id)
fn wingFeathers(p: vec3<f32>, span: f32) -> vec2<f32> {
    var q = p;
    let cellX = floor(q.x * 2.0);
    let cellZ = floor(q.z * 2.0);
    q.x = (fract(q.x * 2.0) - 0.5) / 2.0;
    q.z = (fract(q.z * 2.0) - 0.5) / 2.0;

    let width = 0.1 + span * 0.1;
    let spanLen = 0.5 + span * 0.5;

    let d = abs(q) - vec3<f32>(width, 0.02, spanLen);
    let dist = length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
    return vec2<f32>(dist, hash21(vec2<f32>(cellX, cellZ)));
}

// Griffin core body
fn griffinBody(p: vec3<f32>) -> f32 {
    let bodyScale = vec3<f32>(0.5, 0.4, 0.8);
    let bodyDist = length(p / bodyScale) - 1.0;
    return bodyDist * min(min(bodyScale.x, min(bodyScale.y, bodyScale.z)), 1.0);
}

// Eagle head + beak wedge crowning the body
fn griffinHead(p: vec3<f32>) -> f32 {
    var q = p - vec3<f32>(0.0, 0.45, -0.75);
    let skull = length(q / vec3<f32>(0.28, 0.26, 0.32)) - 1.0;
    // Beak: flattened wedge tapering forward
    var b = q - vec3<f32>(0.0, -0.05, -0.35);
    b.z = max(b.z, -b.z * 0.5);
    let beak = length(max(abs(b) - vec3<f32>(0.08 - b.z * 0.05, 0.06, 0.22), vec3<f32>(0.0))) - 0.02;
    return smin(skull * 0.26, beak, 0.08);
}

// Returns vec2(distance, materialId): 0=void, 1=wings, 2=body, 3=head
fn map(p: vec3<f32>) -> vec3<f32> {
    var p_warp = p;

    // Mouse warp implementation
    let mouse = u.zoom_config.yz;
    let anomaly_pos = vec3<f32>(mouse.x * 2.0, mouse.y * 2.0, 0.0);
    p_warp -= anomaly_pos;

    let warp_intensity = u.zoom_params.x;
    let dist_to_anomaly = length(p_warp);
    let twist_amount = warp_intensity * (1.0 / (dist_to_anomaly + 0.1));

    let tmp_x = p_warp.x * cos(twist_amount) - p_warp.z * sin(twist_amount);
    let tmp_z = p_warp.x * sin(twist_amount) + p_warp.z * cos(twist_amount);
    p_warp.x = tmp_x;
    p_warp.z = tmp_z;

    // Animated flight/flapping
    let t = u.config.x * 2.0;

    // Wings
    var wing_p = p_warp;
    let flap = sin(t) * 0.5;
    wing_p.y -= abs(wing_p.x) * flap;
    wing_p.x = abs(wing_p.x) - 1.0;
    let wing_span = u.zoom_params.y;
    let wing = wingFeathers(wing_p, wing_span);

    // Body + head
    var body_p = p_warp;
    body_p.y += sin(t * 1.5) * 0.2;
    let body_dist = griffinBody(body_p);
    let head_dist = griffinHead(body_p);

    // Noise displacement for "shattered chrono-prism" look
    let fractal_depth = u.zoom_params.z;
    let displacement = sin(p_warp.x * 10.0) * sin(p_warp.y * 10.0) * sin(p_warp.z * 10.0) * 0.05 * fractal_depth;

    var d = smin(wing.x, body_dist, 0.2);
    var matId = select(2.0, 1.0, wing.x < body_dist);
    if (head_dist < d) {
        d = smin(d, head_dist, 0.1);
        matId = select(matId, 3.0, head_dist < d + 0.1);
    }
    d += displacement;

    // Facet id of the dominant feather cell rides in .z
    return vec3<f32>(d, matId, wing.y);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var t = 0.0;
    var res = vec3<f32>(-1.0, 0.0, 0.0);
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);
        if (d.x < 0.001) {
            res = vec3<f32>(t, d.y, d.z);
            break;
        }
        if (t > MAX_DIST) { break; }
        t += d.x;
    }
    return res;
}

// Background rift (volumetric accumulation)
fn getBackgroundRift(rd: vec3<f32>, time: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var p = rd * 5.0;
    for (var i = 1; i <= 4; i++) {
        let fi = f32(i);
        let tmp_x = p.x * cos(time * 0.1) - p.z * sin(time * 0.1);
        let tmp_z = p.x * sin(time * 0.1) + p.z * cos(time * 0.1);
        p.x = tmp_x;
        p.z = tmp_z;
        let noise_val = sin(p.x * fi + time) * cos(p.y * fi) * sin(p.z * fi);
        col += vec3<f32>(0.1, 0.2, 0.5) * max(0.0, noise_val) / fi;
    }
    let bass = plasmaBuffer[0].x;
    col *= (1.0 + bass * 0.5);
    return col;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let pixel = vec2<i32>(id.xy);
    let res = u.config.zw;
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }

    let uv = (vec2<f32>(id.xy) - 0.5 * res) / res.y;
    let time = u.config.x;

    var ro = vec3<f32>(0.0, 0.0, 3.0);
    let rd = normalize(vec3<f32>(uv, -1.0));

    // Audio (contract: plasmaBuffer[0].xyz only)
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let plasma_glow_multiplier = u.zoom_params.w;
    let fractal_depth = u.zoom_params.z;

    let hit = raymarch(ro, rd);
    let t = hit.x;

    var col = vec3<f32>(0.0);
    var depth = 0.0;
    var nrm = vec3<f32>(0.0);
    var matTag = 0.0;

    if (t > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        nrm = n;
        let v = -rd;
        let dot_nv = clamp(dot(n, v), 0.0, 1.0);
        let matId = hit.y;
        matTag = matId;

        // Faceted chrono-prism normal: quantize toward facet centers
        let facetN = normalize(floor(n * 6.0) + 0.5);
        let facetHash = hash33(facetN * 3.7).x;

        // 3-point lighting rig
        let keyL = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let fillL = normalize(vec3<f32>(-0.8, 0.2, 0.5));
        let backL = normalize(vec3<f32>(0.0, -0.5, -1.0));
        let diffKey = clamp(dot(facetN, keyL), 0.0, 1.0);
        let diffFill = clamp(dot(n, fillL), 0.0, 1.0);
        let diffBack = clamp(dot(n, backL), 0.0, 1.0);

        // Material-ID driven palettes
        var baseCol = mix(vec3<f32>(0.1, 0.2, 0.8), vec3<f32>(0.5, 0.1, 0.8), p.y + 0.5);
        baseCol = mix(baseCol, vec3<f32>(0.9, 0.75, 0.3), select(0.0, 1.0, matId == 3.0) * 0.7); // golden head
        baseCol *= 0.8 + facetHash * 0.4; // per-facet albedo variation

        // Plasma gold/magenta wingtips (per-feather cell tint)
        let wingGlow = smoothstep(0.5, 1.5, abs(p.x)) * select(0.0, 1.0, matId == 1.0);
        let glowCol = mix(vec3<f32>(1.0, 0.8, 0.1), vec3<f32>(1.0, 0.2, 0.8), sin(time * 2.0 + hit.z * 6.28) * 0.5 + 0.5);
        baseCol = mix(baseCol, glowCol, wingGlow);

        // Tri-tessellated chrono-prism inlay seams on the body/head
        let seamScale = 6.0 + fractal_depth * 14.0;
        let seamD = triGridEdge(p.xy + p.z * 0.35, seamScale);
        let seam = (1.0 - smoothstep(0.0, 0.06, seamD)) * select(0.0, 1.0, matId >= 2.0);
        let seamCol = mix(vec3<f32>(0.2, 0.9, 1.0), vec3<f32>(1.0, 0.4, 0.9), facetHash);

        // Lighting accumulation
        col += baseCol * diffKey * (0.5 + 0.5 * mids * plasma_glow_multiplier);
        col += baseCol.zyx * diffFill * 0.25;
        col += vec3<f32>(0.3, 0.6, 1.0) * diffBack * 0.2;
        col += seamCol * seam * plasma_glow_multiplier * (0.6 + treble * 0.6);

        // Blinn-Phong specular on prism facets
        let halfDir = normalize(keyL + v);
        let spec = pow(clamp(dot(facetN, halfDir), 0.0, 1.0), 40.0);
        col += vec3<f32>(0.9, 0.95, 1.0) * spec * (0.4 + facetHash * 0.6);

        // Fresnel plasma rim
        let rim = 1.0 - dot_nv;
        col += glowCol * pow(rim, 3.0) * plasma_glow_multiplier;

        // Distance fog into the rift
        col = mix(col, vec3<f32>(0.02, 0.0, 0.05), 1.0 - exp(-0.05 * t * t));

        depth = clamp(1.0 - t / MAX_DIST, 0.0, 1.0);
    } else {
        col = getBackgroundRift(rd, time);
    }

    // ACES filmic tonemap + gamma
    col = acesToneMap(col * 1.2);
    col = pow(col, vec3<f32>(1.0 / 2.2));

    // Semantic alpha: rift background stays translucent, the griffin is solid
    let luma = dot(col, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(luma * 0.7 + select(0.1, 0.55, t > 0.0), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(nrm * 0.5 + 0.5, matTag * 0.25));
}
