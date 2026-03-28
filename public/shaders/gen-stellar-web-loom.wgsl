// ----------------------------------------------------------------
// Stellar Web-Loom
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Thread Density, y=Weave Speed, z=Plasma Glow, w=Singularity Pull
    ripples: array<vec4<f32>, 50>,
};

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn rot2D(a: f32) -> mat2x2<f32> {
    return rot(a);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let n = i.x + i.y * 157.0 + 113.0 * i.z;
    return mix(
        mix(mix(hash31(vec3<f32>(n + 0.0)), hash31(vec3<f32>(n + 1.0)), u.x),
            mix(hash31(vec3<f32>(n + 157.0)), hash31(vec3<f32>(n + 158.0)), u.x), u.y),
        mix(mix(hash31(vec3<f32>(n + 113.0)), hash31(vec3<f32>(n + 114.0)), u.x),
            mix(hash31(vec3<f32>(n + 270.0)), hash31(vec3<f32>(n + 271.0)), u.x), u.y), u.z
    );
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pp = p;
    for (var i = 0; i < 4; i++) {
        f += w * noise3(pp);
        pp *= 2.0;
        w *= 0.5;
    }
    return f;
}

fn sdCylinder(p: vec3<f32>, c: vec2<f32>) -> f32 {
    let d = abs(vec2<f32>(length(p.xz), p.y)) - c;
    return min(max(d.x, d.y), 0.0) + length(max(d, vec2<f32>(0.0)));
}

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

var<private> g_time: f32;
var<private> g_mouse: vec2<f32>;
var<private> g_audio: f32;

fn map(pos: vec3<f32>) -> vec2<f32> {
    let density = max(0.1, u.zoom_params.x);
    let weaveSpeed = u.zoom_params.y;
    let singularityPull = u.zoom_params.w;

    var p = pos;

    let mouseDist = length(p.xy - g_mouse * 5.0);
    if (mouseDist < 5.0) {
        let pull = singularityPull * (1.0 - smoothstep(0.0, 5.0, mouseDist));
        let theta = pull * 2.0;
        let temp_p_xy = rot2D(theta) * p.xy;
        p.x = temp_p_xy.x;
        p.y = temp_p_xy.y;

        p.x -= g_mouse.x * pull * 2.0;
        p.y -= g_mouse.y * pull * 2.0;
        p.z -= pull * 2.0;
    }

    let domainSpacing = 4.0 / density;

    var cell = floor((p + vec3<f32>(domainSpacing * 0.5)) / domainSpacing);
    var q = p;
    q.x = p.x - cell.x * domainSpacing;
    q.y = p.y - cell.y * domainSpacing;
    q.z = p.z - cell.z * domainSpacing;

    let fbm_time = g_time * weaveSpeed * 0.5 + g_audio;
    let warp = vec3<f32>(
        fbm(q + vec3<f32>(fbm_time, 0.0, 0.0)),
        fbm(q + vec3<f32>(0.0, fbm_time, 0.0)),
        fbm(q + vec3<f32>(0.0, 0.0, fbm_time))
    ) * 2.0 - vec3<f32>(1.0);

    let warped_q = q + warp * 0.5;

    let nodeDist = sdSphere(q, 0.3);

    let cylDistX = sdCylinder(warped_q.yzx, vec2<f32>(0.05, domainSpacing));
    let cylDistY = sdCylinder(warped_q.zxy, vec2<f32>(0.05, domainSpacing));
    let cylDistZ = sdCylinder(warped_q.xyz, vec2<f32>(0.05, domainSpacing));

    let threadDist = min(cylDistX, min(cylDistY, cylDistZ));

    let d = min(nodeDist, threadDist);
    var mat_id = 0.0;
    if (threadDist < nodeDist) { mat_id = 1.0; }

    return vec2<f32>(d * 0.6, mat_id);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    var uv = (fragCoord * 2.0 - dims) / dims.y;

    g_time = u.config.x;
    g_audio = u.config.y * 0.1;

    let mX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mY = -(u.zoom_config.z / dims.y) * 2.0 + 1.0;
    g_mouse = vec2<f32>(mX, mY);

    var starCol = vec3<f32>(0.0);
    let star_uv = uv + g_mouse * 0.1;
    for (var i = 1; i <= 3; i++) {
        let fi = f32(i);
        let s = hash31(vec3<f32>(floor(star_uv * 100.0 / fi), fi));
        if (s > 0.98) { starCol += vec3<f32>(s) * (1.0 - fi * 0.2); }
    }

    var ro = vec3<f32>(0.0, 0.0, -5.0 + g_time * 0.5);
    ro.x += sin(g_time * 0.2) * 1.0;
    ro.y += cos(g_time * 0.25) * 1.0;

    let ta = ro + vec3<f32>(0.0, 0.0, 1.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    var t = 0.0;
    var d = 0.0;
    var maxT = 20.0;
    var glow = 0.0;
    var colorAccum = vec3<f32>(0.0);
    let plasmaGlow = u.zoom_params.z;

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;

        let curGlow = 0.05 / (0.01 + abs(d));
        glow += curGlow;

        let mat_id = res.y;
        if (mat_id == 0.0) {
            colorAccum += vec3<f32>(0.1, 0.3, 0.8) * curGlow * plasmaGlow * 0.02;
        } else {
            colorAccum += vec3<f32>(0.5, 0.2, 0.9) * curGlow * plasmaGlow * 0.015;
        }

        if (d < 0.001 || t > maxT) { break; }
        t += d;
    }

    colorAccum += vec3<f32>(1.0, 0.4, 0.2) * g_audio * glow * 0.005;

    var col = colorAccum + starCol * exp(-t * 0.1);

    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
