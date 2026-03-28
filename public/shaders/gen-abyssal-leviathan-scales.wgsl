// ----------------------------------------------------------------
// Abyssal Leviathan-Scales
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
    zoom_params: vec4<f32>,  // x=Scale Density, y=Plasma Intensity, z=Breathing Speed, w=Core Heat
    ripples: array<vec4<f32>, 50>,
};

// --- UTILITY FUNCTIONS ---
fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453); }
fn rot2D(a: f32) -> mat2x2<f32> { let c = cos(a); let s = sin(a); return mat2x2<f32>(c, -s, s, c); }

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + vec3<f32>(33.33));
    return fract((p3.x + p3.y) * p3.z);
}
fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let u = f*f*(vec3<f32>(3.0)-2.0*f); let n = i.x + i.y*157.0 + 113.0*i.z;
    return mix(mix(mix(hash31(vec3<f32>(n+0.0)), hash31(vec3<f32>(n+1.0)), u.x), mix(hash31(vec3<f32>(n+157.0)), hash31(vec3<f32>(n+158.0)), u.x), u.y), mix(mix(hash31(vec3<f32>(n+113.0)), hash31(vec3<f32>(n+114.0)), u.x), mix(hash31(vec3<f32>(n+270.0)), hash31(vec3<f32>(n+271.0)), u.x), u.y), u.z);
}
fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0; var w = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) { f += w * noise3(pp); pp *= 2.0; w *= 0.5; }
    return f;
}

// --- SDF FUNCTIONS ---
fn sdScale(p: vec3<f32>, size: vec2<f32>) -> f32 {
    // A flat, smooth-edged domed scale.
    let d = vec2<f32>(length(p.xz), p.y);
    return length(max(abs(d) - size, vec2<f32>(0.0))) + min(max(abs(d.x) - size.x, abs(d.y) - size.y), 0.0) - 0.1;
}

var<private> g_time: f32;
var<private> g_audio: f32;
var<private> g_mouse: vec2<f32>;

fn map(pos: vec3<f32>) -> vec2<f32> {
    var p = pos;
    let scaleDensity = max(1.0, u.zoom_params.x);
    let breathingSpeed = u.zoom_params.z;
    let spacing = 10.0 / scaleDensity;

    // Hexagonal grid setup on XZ plane
    let grid = vec2<f32>(1.0, 1.7320508) * spacing;
    let h1 = p.xz % grid - grid * 0.5;
    let h2 = (p.xz + grid * 0.5) % grid - grid * 0.5;
    var cellPos = h1;
    var cellId = floor(p.xz / grid);
    if (length(h1) > length(h2)) {
        cellPos = h2;
        cellId = floor((p.xz + grid * 0.5) / grid) + 0.5;
    }

    var q = p;
    q.x = cellPos.x;
    q.z = cellPos.y;

    // Breathing FBM based on cell ID and time
    let fbmVal = fbm(vec3<f32>(cellId.x, cellId.y, g_time * breathingSpeed * 0.5));
    let localTime = g_time * breathingSpeed + fbmVal * 6.28;

    var lift = sin(localTime) * 0.2 + 0.2;
    var tilt = cos(localTime) * 0.3;

    // Mouse Repulsion
    let mouseWorld = vec2<f32>(g_mouse.x * 10.0, -g_mouse.y * 10.0 + g_time);
    let distToMouse = length(p.xz - mouseWorld);
    let repel = 1.0 - smoothstep(0.0, 5.0, distToMouse);
    lift += repel * 1.5;
    tilt += repel * 1.5;

    // Apply lift and tilt to the scale
    q.y -= lift;
    let rM = rot2D(tilt);
    let tmp = rM * vec2<f32>(q.y, q.z);
    q.y = tmp.x;
    q.z = tmp.y;

    // Evaluate scale SDF
    let size = vec2<f32>(spacing * 0.45, 0.05);
    let dScale = sdScale(q, size);

    // Underlying plasma plane heavily distorted by domain warping
    let plasmaWarp = fbm(p * 0.5 + vec3<f32>(0.0, 0.0, -g_time * 2.0));
    let dPlasma = p.y + 1.0 - plasmaWarp * 0.5;

    if (dScale < dPlasma) {
        return vec2<f32>(dScale * 0.6, 1.0); // Material 1: Scale
    }
    return vec2<f32>(dPlasma * 0.6, 2.0); // Material 2: Plasma
}

// --- RAYMARCHING & LIGHTING ---
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    var uv = (fragCoord * 2.0 - dims) / dims.y;
    g_time = u.config.x;
    g_audio = u.config.y * 0.1; // u.config.y accumulates clicks/beats
    let mX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mY = -(u.zoom_config.z / dims.y) * 2.0 + 1.0;
    g_mouse = vec2<f32>(mX, mY);

    // Setup Camera
    var ro = vec3<f32>(0.0, 5.0, g_time);
    let ta = ro + vec3<f32>(0.0, -1.0, 1.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    var t = 0.0;
    var d = 0.0;
    var m = 0.0;
    var glow = 0.0;
    let maxT = 30.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (m == 2.0) {
            glow += 0.01 / (0.01 + abs(d)); // Accumulate volumetric glow for plasma
        }
        if (d < 0.001 || t > maxT) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    let plasmaIntensity = u.zoom_params.y;
    let coreHeat = u.zoom_params.w;
    let audioPulse = 1.0 + g_audio * 5.0; // Audio reactivity

    if (t < maxT) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        let v = -rd;

        if (m == 1.0) {
            // Material 1: Oily Metallic Scale
            let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
            let h = normalize(l + v);
            let ndotl = max(dot(n, l), 0.0);
            let ndoth = max(dot(n, h), 0.0);
            let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

            // Thin-film interference
            let sheen = cos(fresnel * 10.0 + vec3<f32>(0.0, 2.0, 4.0)) * 0.5 + 0.5;
            let diff = vec3<f32>(0.05, 0.05, 0.06) * ndotl;
            let spec = sheen * pow(ndoth, 32.0) * 0.5;

            col = diff + spec + sheen * fresnel * 0.2;

            // Subsurface scattering proxy from plasma below
            let plasmaProximity = exp(-p.y * 2.0);
            col += vec3<f32>(0.8, 0.2, 0.1) * plasmaProximity * 0.2 * plasmaIntensity * audioPulse;

        } else if (m == 2.0) {
            // Material 2: Quantum Fusion Core (Plasma)
            let heat = fbm(p * 2.0 - vec3<f32>(0.0, 0.0, g_time * 4.0)) * coreHeat;
            col = vec3<f32>(1.0, 0.2, 0.05) * heat * audioPulse * plasmaIntensity;
            col += vec3<f32>(0.1, 0.5, 1.0) * pow(heat, 3.0) * audioPulse * plasmaIntensity;
        }
    }

    // Add volumetric glow
    col += vec3<f32>(1.0, 0.3, 0.1) * glow * 0.05 * plasmaIntensity * audioPulse * coreHeat;

    // Background fade (fog)
    col = mix(col, vec3<f32>(0.01, 0.01, 0.02), 1.0 - exp(-t * 0.05));

    // Tone mapping and gamma correction
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}