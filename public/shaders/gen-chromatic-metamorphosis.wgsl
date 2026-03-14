// ═══════════════════════════════════════════════════════════════════════════════
//  Chromatic Metamorphosis
//  Category: GENERATIVE | Complexity: VERY_HIGH
//  Shape-shifting blobs that morph between geometric forms (sphere → torus →
//  cube → asymmetric) while color dances independently across surfaces.
//  Beauty in transformation itself.
//  Mathematical approach: Ray marching with SDF morphing via smooth interpolation
//  between primitive SDFs, independent color field via 3D noise mapped to surface
//  normals, iridescent Fresnel coating, temporal morphing with easing functions.
// ═══════════════════════════════════════════════════════════════════════════════

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
    config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=MorphSpeed, y=MouseX, z=MouseY, w=IridescenceStr
    zoom_params: vec4<f32>,  // x=BlobCount, y=Smoothness, z=ColorSpeed, w=Deformation
    ripples: array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Rotation
// ─────────────────────────────────────────────────────────────────────────────
fn rot2(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Hash and noise
// ─────────────────────────────────────────────────────────────────────────────
fn hash31(p: vec3<f32>) -> f32 {
    let h = dot(p, vec3<f32>(127.1, 311.7, 74.7));
    return fract(sin(h) * 43758.5453123);
}

fn noise3D(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash31(i), hash31(i + vec3<f32>(1, 0, 0)), u.x),
            mix(hash31(i + vec3<f32>(0, 1, 0)), hash31(i + vec3<f32>(1, 1, 0)), u.x), u.y),
        mix(mix(hash31(i + vec3<f32>(0, 0, 1)), hash31(i + vec3<f32>(1, 0, 1)), u.x),
            mix(hash31(i + vec3<f32>(0, 1, 1)), hash31(i + vec3<f32>(1, 1, 1)), u.x), u.y),
        u.z
    );
}

fn fbm3(p: vec3<f32>) -> f32 {
    var v = 0.0; var a = 0.5; var freq = 1.0;
    for (var i = 0; i < 4; i++) {
        v += a * noise3D(p * freq);
        a *= 0.5; freq *= 2.0;
    }
    return v;
}

// ─────────────────────────────────────────────────────────────────────────────
//  SDF primitives
// ─────────────────────────────────────────────────────────────────────────────
fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * 0.25;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Smooth easing for morph transitions
// ─────────────────────────────────────────────────────────────────────────────
fn easeInOut(t: f32) -> f32 {
    return t * t * (3.0 - 2.0 * t);
}

// ─────────────────────────────────────────────────────────────────────────────
//  HSV to RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(h6 % 2.0 - 1.0));
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
//  Scene SDF: morphing shapes
// ─────────────────────────────────────────────────────────────────────────────
fn map(p_in: vec3<f32>, time: f32, morphSpeed: f32, blobCount: f32, smoothK: f32, deform: f32) -> vec2<f32> {
    var d = 1e5;

    // Morph phase: cycles through 4 shapes
    let cycle = time * morphSpeed;
    let phase = cycle % 4.0;
    let t = easeInOut(fract(cycle));
    let shapeIdx = i32(floor(phase));

    let numBlobs = i32(blobCount * 3.0 + 2.0); // 2-5 blobs

    for (var i = 0; i < 5; i++) {
        if (i >= numBlobs) { break; }
        let fi = f32(i);

        // Each blob orbits independently
        let orbitAngle = time * (0.5 + fi * 0.2) + fi * 1.256;
        let orbitRadius = 0.8 + fi * 0.3;
        var blobPos = vec3<f32>(
            orbitRadius * cos(orbitAngle),
            sin(time * 0.7 + fi * 2.0) * 0.5,
            orbitRadius * sin(orbitAngle * 0.8 + fi)
        );

        let localP = p_in - blobPos;

        // Organic deformation
        let deformNoise = fbm3(localP * 2.0 + time * 0.3 + fi * 10.0) * deform;

        // Morph between shapes
        var shape: f32;
        let nextShape = (shapeIdx + 1) % 4;

        var s1: f32; var s2: f32;
        if (shapeIdx == 0) { s1 = sdSphere(localP, 0.5); }
        else if (shapeIdx == 1) { s1 = sdTorus(localP, vec2<f32>(0.4, 0.15)); }
        else if (shapeIdx == 2) { s1 = sdBox(localP, vec3<f32>(0.35)); }
        else { s1 = sdOctahedron(localP, 0.6); }

        if (nextShape == 0) { s2 = sdSphere(localP, 0.5); }
        else if (nextShape == 1) { s2 = sdTorus(localP, vec2<f32>(0.4, 0.15)); }
        else if (nextShape == 2) { s2 = sdBox(localP, vec3<f32>(0.35)); }
        else { s2 = sdOctahedron(localP, 0.6); }

        shape = mix(s1, s2, t) + deformNoise * 0.2;
        d = smin(d, shape, smoothK);
    }

    return vec2<f32>(d, 0.0);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Normal calculation
// ─────────────────────────────────────────────────────────────────────────────
fn calcNormal(p: vec3<f32>, time: f32, ms: f32, bc: f32, sk: f32, df: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, time, ms, bc, sk, df).x - map(p - e.xyy, time, ms, bc, sk, df).x,
        map(p + e.yxy, time, ms, bc, sk, df).x - map(p - e.yxy, time, ms, bc, sk, df).x,
        map(p + e.yyx, time, ms, bc, sk, df).x - map(p - e.yyx, time, ms, bc, sk, df).x
    ));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let fragCoord = vec2<f32>(id.xy);
    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) { return; }

    let uv = (fragCoord * 2.0 - dims) / dims.y;
    let time = u.config.x;

    // Parameters
    let morphSpeed = u.zoom_config.x * 0.5 + 0.1;
    let iridescence = u.zoom_config.w * 1.5 + 0.2;
    let blobCount = u.zoom_params.x;
    let smoothK = u.zoom_params.y * 0.8 + 0.2;
    let colorSpeed = u.zoom_params.z * 2.0 + 0.3;
    let deform = u.zoom_params.w * 1.5;

    // Camera
    let mouseX = (u.zoom_config.y / dims.x) * 2.0 - 1.0;
    let mouseY = (u.zoom_config.z / dims.y) * 2.0 - 1.0;
    var ro = vec3<f32>(0.0, 0.0, 5.0);
    ro.yz = rot2(mouseY * 1.0) * ro.yz;
    ro.xz = rot2(mouseX * 3.14 + time * 0.15) * ro.xz;

    let ta = vec3<f32>(0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = cross(uu, ww);
    let rd = normalize(uv.x * uu + uv.y * vv + 2.0 * ww);

    // Raymarch
    var t = 0.0;
    var hit = false;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p, time, morphSpeed, blobCount, smoothK, deform).x;
        if (d < 0.001) { hit = true; break; }
        if (t > 25.0) { break; }
        t += d * 0.7;
    }

    // Background: gradient with subtle stars
    var col = mix(vec3<f32>(0.02, 0.03, 0.08), vec3<f32>(0.08, 0.04, 0.12), uv.y * 0.5 + 0.5);
    let stars = pow(hash31(rd * 400.0), 25.0);
    col += vec3<f32>(stars * 0.5);

    if (hit) {
        let p = ro + rd * t;
        let n = calcNormal(p, time, morphSpeed, blobCount, smoothK, deform);
        let v = normalize(ro - p);

        // Independent color field: 3D noise mapped to surface
        let colorNoise = fbm3(p * 1.5 + time * colorSpeed * 0.3);
        let colorNoise2 = fbm3(p * 3.0 - time * colorSpeed * 0.2 + 50.0);
        let baseHue = fract(colorNoise * 2.0 + time * colorSpeed * 0.05);
        let baseSat = 0.6 + 0.4 * colorNoise2;
        let baseCol = hsv2rgb(baseHue, baseSat, 0.9);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 1.5, 0.8));
        let diff = max(dot(n, lightDir), 0.0);
        let hal = normalize(lightDir + v);
        let spec = pow(max(dot(n, hal), 0.0), 32.0);
        let fresnel = pow(1.0 - max(dot(n, v), 0.0), 5.0);

        // Iridescent Fresnel: color shifts with viewing angle
        let iridHue = fract(fresnel * 2.0 + dot(n, vec3<f32>(1.0, 0.0, 0.0)) * 0.5 + time * 0.1);
        let iridCol = hsv2rgb(iridHue, 0.9, 1.0);

        col = baseCol * (diff * 0.7 + 0.3);
        col += vec3<f32>(1.0) * spec * 0.5;
        col += iridCol * fresnel * iridescence;

        // AO approximation
        let ao = 0.5 + 0.5 * map(p + n * 0.1, time, morphSpeed, blobCount, smoothK, deform).x / 0.1;
        col *= clamp(ao, 0.3, 1.0);

        // Distance fog
        col = mix(col, vec3<f32>(0.02, 0.03, 0.08), 1.0 - exp(-0.06 * t));
    }

    // Vignette
    col *= 1.0 - 0.3 * length(uv);

    // Tone map + gamma
    col = col / (col + vec3<f32>(1.0));
    col = pow(col, vec3<f32>(0.4545));

    textureStore(writeTexture, vec2<i32>(id.xy), vec4<f32>(col, 1.0));
}
