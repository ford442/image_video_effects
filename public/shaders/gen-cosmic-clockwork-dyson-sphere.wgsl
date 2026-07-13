// ═══════════════════════════════════════════════════════════════════════════════
// Cosmic-Clockwork Dyson-Sphere — Algorithmist Upgrade
// Category: generative
// Upgraded with: enhanced KIFS SDFs, domain-warped FBM, Worley/Voronoi noise,
// Beer-Lambert volumetric extinction, Fresnel-Schlick metallic reflections,
// audio-reactive plasma, temporal coherence, mouse Y-flip.
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
    zoom_params: vec4<f32>,  // x=Mechanical Complexity, y=Clock Speed, z=Plasma Intensity, w=Gear Ratio
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const PHI: f32 = 1.618033988749894;

fn applyGenerativePrimaryControls(color: vec4<f32>) -> vec4<f32> {
    let primaryIntensity = mix(0.55, 1.45, clamp(u.zoom_params.x, 0.0, 1.0));
    let speedPulse = 0.92 + 0.16 * (0.5 + 0.5 * sin(u.config.x * mix(0.25, 5.0, clamp(u.zoom_params.y, 0.0, 1.0))));
    let detailContrast = mix(0.75, 1.6, clamp(u.zoom_params.z, 0.0, 1.0));
    let mouseDistance = length(u.zoom_config.yz - vec2<f32>(0.5));
    let mouseInfluence = mix(0.95, 1.15, clamp(u.zoom_params.w * mouseDistance * 2.0, 0.0, 1.0));
    let controlled = pow(max(color.rgb * primaryIntensity * speedPulse * mouseInfluence, vec3<f32>(0.0)), vec3<f32>(1.0 / detailContrast));
    return vec4<f32>(controlled, color.a);
}

// ── Hash / Noise ──
fn hash1(n: f32) -> f32 { return fract(sin(n * 127.1 + 311.7) * 43758.5453123); }
fn hash2(p: vec2<f32>) -> f32 {
    var q = fract(p * vec2<f32>(127.1, 311.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y);
}
fn hash3(p: vec3<f32>) -> f32 {
    var q = fract(p * vec3<f32>(127.1, 311.7, 74.7));
    q += dot(q, q + 19.19);
    return fract(q.x * q.y * q.z);
}

fn vnoise2(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash2(i), hash2(i+vec2<f32>(1,0)), u.x),
               mix(hash2(i+vec2<f32>(0,1)), hash2(i+vec2<f32>(1,1)), u.x), u.y);
}

fn vnoise3(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(hash3(i), hash3(i+vec3<f32>(1,0,0)), u.x),
            mix(hash3(i+vec3<f32>(0,1,0)), hash3(i+vec3<f32>(1,1,0)), u.x), u.y),
        mix(mix(hash3(i+vec3<f32>(0,0,1)), hash3(i+vec3<f32>(1,0,1)), u.x),
            mix(hash3(i+vec3<f32>(0,1,1)), hash3(i+vec3<f32>(1,1,1)), u.x), u.y),
        u.z);
}

// ── Domain-Warped FBM ──
fn fbm_dw2(p: vec2<f32>, t: f32) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * vnoise2(pp);
        let warp = v * 0.3;
        pp = pp * 2.1 + vec2<f32>(1.7 + warp, 9.2 - warp) + vec2<f32>(t * 0.01, -t * 0.007);
        a *= 0.5;
    }
    return v;
}

fn fbm_dw3(p: vec3<f32>, t: f32) -> f32 {
    var v = 0.0; var a = 0.5; var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * vnoise3(pp);
        let warp = v * 0.25;
        pp = pp * 2.1 + vec3<f32>(1.7 + warp, 9.2 - warp, 3.1 + warp * 0.5) + vec3<f32>(t * 0.008, -t * 0.005, t * 0.003);
        a *= 0.5;
    }
    return v;
}

// ── Voronoi / Worley Noise ──
fn voronoi3(p: vec3<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var minDist = 999.0;
    var secondDist = 999.0;
    for (var z: i32 = -1; z <= 1; z++) {
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                let neighbor = vec3<f32>(f32(x), f32(y), f32(z));
                let point = neighbor + vec3<f32>(hash3(i + neighbor), hash3(i + neighbor + 7.31), hash3(i + neighbor + 13.17));
                let diff = neighbor + point - f;
                let d = dot(diff, diff);
                if (d < minDist) {
                    secondDist = minDist;
                    minDist = d;
                } else if (d < secondDist) {
                    secondDist = d;
                }
            }
        }
    }
    return vec2<f32>(sqrt(minDist), sqrt(secondDist));
}

// ── Rotation Matrices ──
fn rotX(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(1.0, 0.0, 0.0, 0.0, c, -s, 0.0, s, c);
}
fn rotY(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}
fn rotZ(angle: f32) -> mat3x3<f32> {
    let s = sin(angle); let c = cos(angle);
    return mat3x3<f32>(c, -s, 0.0, s, c, 0.0, 0.0, 0.0, 1.0);
}

// ── SDF Primitives ──
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}
fn sdCylinder(p: vec3<f32>, h: f32, r: f32) -> f32 {
    let d = vec2<f32>(length(p.xz), p.y);
    return length(max(d - vec2<f32>(r, h), vec2<f32>(0.0))) + min(max(d.x - r, d.y - h), 0.0);
}
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    let q = vec2<f32>(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

// ── Fresnel-Schlick ──
fn fresnelSchlick(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> {
    return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0);
}

// ── Beer-Lambert ──
fn beerLambert(density: f32, absorption: f32) -> f32 {
    return exp(-density * absorption);
}

// ── Scene Map with Enhanced KIFS + Gear Details ──
fn map(pos: vec3<f32>, complex: f32, gearRatio: f32, t: f32) -> f32 {
    var p = pos;
    var d = 1000.0;

    // Core Singularity with Voronoi perturbation
    let voro = voronoi3(p * 2.0 + t * 0.1);
    let dCore = length(p) - 0.5 * (1.0 + voro.x * 0.15);

    // KIFS Folds with temporal variation
    let kifsTime = t * 0.1;
    for (var i = 0; i < 5; i++) {
        p = abs(p);
        let offset = gearRatio * 1.5 + 0.1 * sin(kifsTime + f32(i) * 1.7);
        p = p - vec3<f32>(offset, gearRatio * 0.5, offset);
        p = p * rotY(complex * 2.0 + kifsTime * 0.2);
        p = p * rotZ(complex * 1.5 + kifsTime * 0.15);
        p = p * rotX(complex * 0.5 + sin(kifsTime * 0.3) * 0.1);
    }

    // Main box structure with noise detail
    let noiseDetail = fbm_dw3(p * 3.0, t) * 0.05;
    let box = sdBox(p, vec3<f32>(0.2 + noiseDetail, 1.0 + noiseDetail, 0.2 + noiseDetail));

    // Gear rings (toroidal)
    let gearRing1 = sdTorus(p * rotY(t * 0.2), vec2<f32>(1.2 + gearRatio, 0.08));
    let gearRing2 = sdTorus(p * rotZ(t * 0.15), vec2<f32>(0.8 + gearRatio * 0.5, 0.06));
    let gearRing3 = sdTorus(p * rotX(t * 0.1), vec2<f32>(0.5 + gearRatio * 0.3, 0.04));

    // Cylindrical struts
    let strut = sdCylinder(p * rotZ(PI * 0.25), 0.5, 0.03);

    // Combine all structures
    d = min(d, box);
    d = min(d, gearRing1);
    d = min(d, gearRing2);
    d = min(d, gearRing3);
    d = min(d, strut);

    // Remove geometry too close to singularity (event horizon mask)
    d = max(d, -dCore + 0.05);

    return d;
}

// ── Normal calculation with higher precision ──
fn calcNormal(p: vec3<f32>, complex: f32, gearRatio: f32, t: f32) -> vec3<f32> {
    let e = vec2<f32>(0.0005, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, complex, gearRatio, t) - map(p - e.xyy, complex, gearRatio, t),
        map(p + e.yxy, complex, gearRatio, t) - map(p - e.yxy, complex, gearRatio, t),
        map(p + e.yyx, complex, gearRatio, t) - map(p - e.yyx, complex, gearRatio, t)
    ));
}

// ── Ambient Occlusion ──
fn calcAO(p: vec3<f32>, n: vec3<f32>, complex: f32, gearRatio: f32, t: f32) -> f32 {
    var ao = 0.0;
    for (var i = 1; i <= 4; i++) {
        let d = f32(i) * 0.05;
        ao += (d - map(p + n * d, complex, gearRatio, t)) / d;
    }
    return clamp(1.0 - ao * 0.25, 0.0, 1.0);
}

// ── Plasma color with spectral shift ──
fn getPlasmaColor(intensity: f32, t: f32) -> vec3<f32> {
    let c = clamp(intensity, 0.0, 1.0);
    let shift = sin(t * 0.5) * 0.1;
    return mix(
        vec3<f32>(0.1 + shift, 0.0, 0.8 - shift),
        vec3<f32>(1.0, 0.9 + shift, 0.2),
        c
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let coords = vec2<i32>(global_id.xy);
    let res = vec2<i32>(i32(u.config.z), i32(u.config.w));
    if (coords.x >= res.x || coords.y >= res.y) { return; }

    let uv = (vec2<f32>(coords) - vec2<f32>(res) * 0.5) / f32(res.y);

    // Uniforms mapping
    let complex = u.zoom_params.x;  // Mechanical Complexity
    let clockSpd = u.zoom_params.y; // Clock Speed
    let plasmaInt = u.zoom_params.z; // Plasma Intensity
    let gearRatio = u.zoom_params.w; // Gear Ratio

    let time = u.config.x * clockSpd;
    let audio = plasmaBuffer[0].x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Snapping Rotation (stepped time + audio kick)
    let steppedTime = floor(time) + smoothstep(0.8, 1.0, fract(time)) * 1.0;
    let rotAngle = steppedTime * 0.5 + audio * 2.0 + bass * 0.5;

    // Mouse Interaction with Y-flip (screen-top = +Y/up)
    let mousePos = (u.zoom_config.yz * 2.0 - vec2<f32>(1.0, 1.0)) * 3.14;
    let mouseYFlipped = vec2<f32>(mousePos.x, -mousePos.y); // Y-flip for 3D

    // Camera Setup
    var ro = vec3<f32>(0.0, 0.0, 5.0);
    ro = ro * rotX(-mouseYFlipped.y) * rotY(mouseYFlipped.x + rotAngle * 0.1);

    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.0 * ww);

    // Raymarching with volumetric integration
    var t = 0.0;
    var p = ro;
    var coreDist = 1000.0;
    var hit = false;
    var volAccum = 0.0;

    for (var i = 0; i < 120; i++) {
        p = ro + rd * t;
        let d = map(p, complex, gearRatio, time);

        // Track closest distance to core singularity
        let voro = voronoi3(p * 2.0 + time * 0.1);
        let dCore = length(p) - 0.5 * (1.0 + voro.x * 0.15);
        coreDist = min(coreDist, dCore);

        // Volumetric accumulation for plasma glow
        if (dCore < 1.0 && dCore > 0.0) {
            volAccum += exp(-dCore * 3.0) * 0.02 * plasmaInt * (1.0 + audio);
        }

        if (d < 0.001) {
            hit = true;
            break;
        }
        if (t > 30.0) { break; }
        t += max(d, 0.001);
    }

    var color = vec3<f32>(0.0);

    if (hit) {
        let n = calcNormal(p, complex, gearRatio, time);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let refl = reflect(rd, n);
        let spec = pow(max(dot(refl, lightDir), 0.0), 64.0);

        // Metallic Brass with Fresnel
        let baseColor = vec3<f32>(0.8, 0.6, 0.2);
        let f0 = vec3<f32>(0.56, 0.57, 0.58); // Brass F0
        let cosTheta = max(dot(-rd, n), 0.0);
        let fresnel = fresnelSchlick(cosTheta, f0);

        color = baseColor * diff + fresnel * spec * 2.0;

        // Ambient Occlusion with enhanced detail
        let ao = calcAO(p, n, complex, gearRatio, time);
        color = color * ao;

        // Surface detail from Voronoi
        let voro = voronoi3(p * 5.0 + time * 0.05);
        let surfaceDetail = smoothstep(0.05, 0.0, voro.x) * 0.15;
        color += vec3<f32>(0.9, 0.7, 0.3) * surfaceDetail * ao;

        // Domain-warped noise for weathering
        let weather = fbm_dw3(p * 8.0, time);
        color = mix(color, color * 0.7, weather * 0.3);
    }

    // Volumetric Glow (Plasma Core) with Beer-Lambert
    if (coreDist < 1.5) {
        let glowStrength = clamp(1.0 - coreDist / 1.5, 0.0, 1.0) * plasmaInt * (1.0 + audio);
        let plasmaCol = getPlasmaColor(glowStrength, time);
        // Beer-Lambert extinction for volumetric falloff
        let extinction = beerLambert(coreDist * 2.0, 1.5 + bass * 0.5);
        color += plasmaCol * glowStrength * 2.0 * extinction + volAccum * plasmaCol;
    }

    // Audio-reactive bloom on hit surfaces
    if (hit && bass > 0.3) {
        let bloom = bass * 0.2 * exp(-t * 0.1);
        color += vec3<f32>(1.0, 0.8, 0.3) * bloom;
    }

    // Gamma correction
    color = pow(color, vec3<f32>(1.0 / 2.2));

    let _luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let _alpha = clamp(_luma * 0.7 + 0.2 + volAccum * 0.5, 0.0, 1.0);

    textureStore(writeTexture, coords, applyGenerativePrimaryControls(vec4<f32>(color, _alpha)));
    let _depth_uv = clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0));
    let _depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, _depth_uv, 0.0).r;
    textureStore(writeDepthTexture, coords, vec4<f32>(_depth, 0.0, 0.0, 0.0));
    // Write to dataTextureA for temporal feedback
    textureStore(dataTextureA, coords, vec4<f32>(color, _alpha));
}
