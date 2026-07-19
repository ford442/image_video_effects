// ═══════════════════════════════════════════════════════════════════════════════
//  Hyper-Refractive Rain-Matrix - Visualist Upgrade
//  Category: generative
//  Features: OkLab color mixing, Blackbody temperature, Cosine palettes,
//            Fresnel rim lighting, HDR tone mapping, raymarched rain drops
//  Upgraded: 2026-06-28
// ═══════════════════════════════════════════════════════════════════════════════
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
    config: vec4<f32>,       // x=Time, y=Audio/ClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
    zoom_params: vec4<f32>,  // x=Intensity, y=Speed, z=Scale, w=MouseInfluence
    ripples: array<vec4<f32>, 50>,
};
fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
  let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
  let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
  let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
  let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
  let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
  let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
  return vec4<f32>(controlled, color.a);
}

// --- Color Science: OkLab ---
fn srgb_to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(2.2));
}
fn linear_to_srgb(c: vec3<f32>) -> vec3<f32> {
    return pow(c, vec3<f32>(1.0 / 2.2));
}
fn linear_to_oklab(c: vec3<f32>) -> vec3<f32> {
    let lms = mat3x3<f32>(
        vec3<f32>(0.8189330101, 0.3618667424, -0.1288597137),
        vec3<f32>(0.0329845436, 0.9293118715, 0.0361456387),
        vec3<f32>(0.0482003018, 0.2643662691, 0.6338517070)
    ) * c;
    let lms_ = sign(lms) * pow(abs(lms), vec3<f32>(1.0/3.0));
    return mat3x3<f32>(
        vec3<f32>(0.2104542553, 1.9779984951, 0.0259040371),
        vec3<f32>(0.7936177850, -2.4285922050, 0.7827717662),
        vec3<f32>(-0.0040720468, 0.4505937099, -0.8086757660)
    ) * lms_;
}
fn oklab_to_linear(c: vec3<f32>) -> vec3<f32> {
    let lms_ = mat3x3<f32>(
        vec3<f32>(1.0, 1.0, 1.0),
        vec3<f32>(0.3963377774, -0.1055613458, -0.0894841775),
        vec3<f32>(0.2158037573, -0.0638541728, -1.2914855480)
    ) * c;
    let lms = lms_ * lms_ * lms_;
    return mat3x3<f32>(
        vec3<f32>(1.2270138510, -0.5577992887, 0.2812561490),
        vec3<f32>(-0.0405801784, 1.1122568696, -0.0716766787),
        vec3<f32>(-0.0763812845, -0.4214819784, 1.5861632204)
    ) * lms;
}
fn oklab_mix(a: vec3<f32>, b: vec3<f32>, t: f32) -> vec3<f32> {
    return oklab_to_linear(mix(linear_to_oklab(a), linear_to_oklab(b), t));
}

// --- Blackbody Color Temperature ---
fn blackbody(t: f32) -> vec3<f32> {
    var col = vec3<f32>(1.0);
    col.y = 0.3900815787690196 * log(t) - 0.6318414437886275;
    col.z = 0.5432067891101961 * log(t) - 1.1964741063266880;
    return clamp(col, vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Cosine Palette (Inigo Quilez) ---
fn cosinePalette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

// --- HDR Tone Mapping ---
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51); let b = vec3<f32>(0.03);
    let c = vec3<f32>(2.43); let d = vec3<f32>(0.59);
    let e = vec3<f32>(0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rotate2D(angle: f32) -> mat2x2<f32> {
    let c = cos(angle); let s = sin(angle);
    return mat2x2<f32>(vec2<f32>(c, -s), vec2<f32>(s, c));
}
fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p3 = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 += vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn sdSphere(p: vec3<f32>, s: f32) -> f32 { return length(p) - s; }
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn map(pos_in: vec3<f32>) -> vec2<f32> {
    var p = pos_in;
    let rainDensity = u.zoom_params.x;
    let dropSpeed = u.zoom_params.y;
    let fluidViscosity = u.zoom_params.z;
    let audioReactive = plasmaBuffer[0].x;
    let t = u.config.x * dropSpeed * (1.0 + audioReactive * 0.5);
    p.y -= t * 5.0;
    // Mouse Y-flip: screen-top = +Y/up
    let mousePos = vec2<f32>((u.zoom_config.y - 0.5) * 20.0, (u.zoom_config.z - 0.5) * 20.0);
    let dMouse = length(p.xz - mousePos);
    if (dMouse < 5.0) {
        let repelForce = (5.0 - dMouse) * 0.5;
        let dir = normalize(p.xz - mousePos);
        p.x += dir.x * repelForce;
        p.z += dir.y * repelForce;
    }
    let cellSpacing = 4.0 / rainDensity;
    let cell = floor(p / cellSpacing);
    var q = p - cell * cellSpacing - cellSpacing * 0.5;
    let h = hash33(cell);
    q.y += (h.y - 0.5) * cellSpacing;
    let stretch = 1.0 + dropSpeed + audioReactive;
    let d1 = sdCapsule(q, vec3<f32>(0.0, stretch, 0.0), vec3<f32>(0.0, -stretch, 0.0), 0.2 + h.x * 0.3);
    var d2 = 1e10;
    for(var i=-1; i<=1; i++) {
        for(var j=-1; j<=1; j++) {
            if (i==0 && j==0) { continue; }
            let ncell = cell + vec3<f32>(f32(i), 0.0, f32(j));
            let nh = hash33(ncell);
            var nq = p - ncell * cellSpacing - cellSpacing * 0.5;
            nq.y += (nh.y - 0.5) * cellSpacing;
            let nd = sdCapsule(nq, vec3<f32>(0.0, stretch, 0.0), vec3<f32>(0.0, -stretch, 0.0), 0.2 + nh.x * 0.3);
            d2 = smin(d2, nd, fluidViscosity * 1.5 + 0.1);
        }
    }
    let dFinal = smin(d1, d2, fluidViscosity * 1.5 + 0.1);
    return vec2<f32>(dFinal, h.x);
}
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize(e.xyy * map(p + e.xyy).x + e.yyx * map(p + e.yyx).x + e.yxy * map(p + e.yxy).x + e.xxx * map(p + e.xxx).x);
}
fn render(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    var t = 0.0;
    var m = -1.0;
    for(var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if (res.x < 0.001) { m = res.y; break; }
        if (t > 50.0) { break; }
        t += res.x * 0.8;
    }
    let stormIntensity = u.zoom_params.w;
    // Cosine palette for sky + OkLab mixing with blackbody
    let skyCp = cosinePalette(rd.y * 0.5 + 0.5, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(0.6, 0.8, 1.0), vec3<f32>(0.1, 0.3, 0.6));
    let skyBb = blackbody(mix(3000.0, 7000.0, rd.y * 0.5 + 0.5 + sin(u.config.x * 0.2) * 0.2));
    let bgCol = oklab_mix(skyCp, skyBb, 0.4) * stormIntensity;
    col = bgCol;
    if (m > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);
        // Pseudo-refraction with cosine palette
        let refDir = refract(rd, n, 0.8);
        let hRef = hash33(refDir * 10.0 + u.config.x);
        let refCp = cosinePalette(hRef.x, vec3<f32>(0.5), vec3<f32>(0.5), vec3<f32>(0.8, 1.0, 1.0), vec3<f32>(0.2, 0.5, 0.8));
        let refBb = blackbody(mix(5000.0, 12000.0, hRef.x));
        let refCol = oklab_mix(refCp, refBb, 0.5) * stormIntensity;
        // Lighting
        let lig = normalize(vec3<f32>(0.5, 0.8, 0.3));
        let hal = normalize(lig - rd);
        let dif = clamp(dot(n, lig), 0.0, 1.0);
        let spe = pow(clamp(dot(n, hal), 0.0, 1.0), 32.0);
        // Fresnel rim lighting with OkLab mixing
        let fresnel = pow(1.0 + dot(rd, n), 4.0);
        let rimWarm = blackbody(4000.0);
        let rimCool = blackbody(9000.0);
        let rimColor = oklab_mix(rimWarm, rimCool, m + sin(u.config.x * 0.3) * 0.3);
        col = mix(refCol, vec3<f32>(1.0), spe + dif * 0.2);
        col += rimColor * fresnel * 0.5;
        // Caustics approximation on surface
        let caustics = sin(p.x * 20.0 + u.config.x * 2.0) * cos(p.z * 20.0 + u.config.x * 1.5) * 0.5 + 0.5;
        col += refCol * caustics * 0.15 * fresnel;
        // Fog with OkLab mixing
        col = mix(col, bgCol, 1.0 - exp(-0.02 * t * t));
    }
    return col;
}
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dimensions = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= dimensions.x || fragCoord.y >= dimensions.y) { return; }
    let uv = (fragCoord - 0.5 * dimensions) / dimensions.y;
    var ro = vec3<f32>(0.0, 5.0, 10.0);
    var rd = normalize(vec3<f32>(uv, -1.0));
    let rotY = rotate2D(u.config.x * 0.1);
    let roXZ = rotY * vec2<f32>(ro.x, ro.z); ro.x = roXZ.x; ro.z = roXZ.y;
    let rdXZ = rotY * vec2<f32>(rd.x, rd.z); rd.x = rdXZ.x; rd.z = rdXZ.y;
    let col = render(ro, rd);
    // HDR tone mapping
    let hdrCol = acesToneMap(col * 1.2);
    let _luma = dot(hdrCol, vec3<f32>(0.299, 0.587, 0.114));
    let _alpha = clamp(_luma * 0.7 + 0.2, 0.0, 1.0);
    let finalCol2 = vec4<f32>(hdrCol, _alpha);
    textureStore(writeTexture, vec2<i32>(id.xy), applyGenerativePrimaryControls(finalCol2));
    let _depth_uv = clamp(vec2<f32>(id.xy) / vec2<f32>(u.config.z, u.config.w), vec2<f32>(0.0), vec2<f32>(1.0));
    let _depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, _depth_uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(_depth, 0.0, 0.0, 0.0));
}
