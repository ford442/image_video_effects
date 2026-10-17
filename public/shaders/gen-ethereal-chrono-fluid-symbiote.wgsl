// ═══════════════════════════════════════════════════════════════════
//  Ethereal Chrono-Fluid Symbiote
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: meniscus film on the fluid-crystal seam; chrono smear from previous frame;
//         peristaltic vein bands in the fluid mantle; crystal twinning shear planes
//  A packing: ACES display RGBA; C is the previous display frame
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Density, y=Fluid Viscosity, z=Chrono Warp, w=Symbiote Glow

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;
const PI: f32 = 3.14159265359;

fn rot2D(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// 4D noise approximation (value noise based)
fn hash41(p: vec4<f32>) -> f32 {
    var p3 = fract(p.xyz * 0.1031 + p.w * 0.0313);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise4D(p: vec4<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);

    return mix(
        mix(
            mix(hash41(i + vec4<f32>(0.0,0.0,0.0,0.0)), hash41(i + vec4<f32>(1.0,0.0,0.0,0.0)), u.x),
            mix(hash41(i + vec4<f32>(0.0,1.0,0.0,0.0)), hash41(i + vec4<f32>(1.0,1.0,0.0,0.0)), u.x),
            u.y),
        mix(
            mix(hash41(i + vec4<f32>(0.0,0.0,1.0,0.0)), hash41(i + vec4<f32>(1.0,0.0,1.0,0.0)), u.x),
            mix(hash41(i + vec4<f32>(0.0,1.0,1.0,0.0)), hash41(i + vec4<f32>(1.0,1.0,1.0,0.0)), u.x),
            u.y),
        u.z
    );
}

fn fbm4D(p: vec4<f32>) -> f32 {
    var val = 0.0;
    var amp = 0.5;
    var pos = p;
    for (var i = 0; i < 4; i++) {
        val += amp * noise4D(pos);
        pos *= 2.0;
        amp *= 0.5;
    }
    return val;
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

struct MapResult {
    dist: f32,
    matId: f32, // 0.0 = fluid, 1.0 = crystal
    glow: f32,
    seam: f32,
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

var<private> global_glow: f32 = 0.0;

fn map(p: vec3<f32>, time: f32, audioBass: f32, audioHigh: f32, mousePos: vec2<f32>) -> MapResult {
    var res: MapResult;

    // Parameters
    let density = u.zoom_params.x;
    let viscosity = u.zoom_params.y;
    let chronoWarp = u.zoom_params.z;
    let symbioteGlow = u.zoom_params.w;

    var pos = p;

    // Mouse Interaction: Symbiotic Gravity Well
    if (u.zoom_config.w > 0.0) {
        // Convert mouse UV to world space approx
        var mPos = vec3<f32>((mousePos - 0.5) * 5.0, 0.0);
        let distToMouse = length(pos.xy - mPos.xy);
        let pull = 1.0 / (1.0 + distToMouse * distToMouse);
        let warpStrength = sin(time * 5.0 - distToMouse * 3.0) * 0.5 + 0.5;
        pos -= normalize(vec3<f32>(pos.xy - mPos.xy, pos.z)) * pull * warpStrength * 2.0;
    }

    // Domain warping / Fluid
    let t = time * chronoWarp * (0.5 + audioBass * 0.5);
    let warpX = fbm4D(vec4<f32>(pos.xyz * viscosity, t));
    let warpY = fbm4D(vec4<f32>(pos.yzx * viscosity + 10.0, t * 1.1));
    let warpZ = fbm4D(vec4<f32>(pos.zxy * viscosity + 20.0, t * 0.9));

    var fluidPos = pos + vec3<f32>(warpX, warpY, warpZ) * 2.0 * density * (1.0 + audioBass);

    // Fluid SDF
    let fluidBase = length(fluidPos) - 1.5;
    let fluidDetail = fbm4D(vec4<f32>(fluidPos * 2.0, t)) * 0.5;
    let dFluid = fluidBase + fluidDetail;

    // Crystalline structure
    var q = pos;
    let qxy = q.xy * rot2D(t * 0.2);
    q = vec3<f32>(qxy, q.z);
    let qxz = q.xz * rot2D(t * 0.3);
    q = vec3<f32>(qxz.x, q.y, qxz.y);
    q = fract(q * 0.5) * 2.0 - 1.0; // domain repetition

    let crystalBase = length(max(abs(q) - vec3<f32>(0.2, 0.2, 1.0), vec3<f32>(0.0))) - 0.05;

    // Idea 1 — meniscus: the symbiotic film where fluid and crystal distances meet.
    let meniscus = exp(-abs(dFluid - crystalBase) * 16.0) * symbioteGlow;
    res.seam = meniscus;

    // Combine
    res.dist = smin(dFluid, crystalBase, 0.5);

    // Materials
    if (dFluid < crystalBase) {
        res.matId = 0.0; // Fluid
        res.glow = exp(-abs(dFluid) * 2.0) * symbioteGlow * (1.0 + audioHigh * 2.0);
    } else {
        res.matId = 1.0; // Crystal
        res.glow = exp(-abs(crystalBase) * 5.0) * symbioteGlow * (1.0 + audioBass * 3.0);
    }

    global_glow += res.glow * 0.02 + meniscus * 0.015;

    return res;
}

fn getNormal(p: vec3<f32>, time: f32, audioBass: f32, audioHigh: f32, mousePos: vec2<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    let d = map(p, time, audioBass, audioHigh, mousePos).dist;
    let n = vec3<f32>(
        d - map(p - e.xyy, time, audioBass, audioHigh, mousePos).dist,
        d - map(p - e.yxy, time, audioBass, audioHigh, mousePos).dist,
        d - map(p - e.yyx, time, audioBass, audioHigh, mousePos).dist
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(global_id.xy) / res;

    if (global_id.x >= u32(res.x) || global_id.y >= u32(res.y)) {
        return;
    }

    // Audio Reactivity
    let bass = plasmaBuffer[0].x;
    let high = plasmaBuffer[0].z;

    let time = u.config.x;
    let mouseUV = u.zoom_config.yz;

    // Camera
    var ro = vec3<f32>(0.0, 0.0, -5.0);
    var rd = normalize(vec3<f32>(uv * 2.0 - 1.0, 1.0));
    rd = vec3<f32>(rd.xy * (res.x / res.y), rd.z);

    // Mouse interaction rotation (slight camera shift)
    if (u.zoom_config.w > 0.0) {
    ro = vec3<f32>(ro.xy + (mouseUV - 0.5) * 2.0, ro.z);
    let rdxy = rd.xy * rot2D((mouseUV.x - 0.5) * PI * 0.2);
    rd = vec3<f32>(rdxy, rd.z);
    }

    // Raymarching
    var t_dist = 0.0;
    var maxIter = 0;
    var finalMatId = 0.0;

    global_glow = 0.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        let p = ro + rd * t_dist;
        let mapRes = map(p, time, bass, high, mouseUV);
        if (abs(mapRes.dist) < SURF_DIST) {
            finalMatId = mapRes.matId;
            maxIter = i;
            break;
        }
        if (t_dist > MAX_DIST) {
            break;
        }
        t_dist += mapRes.dist;
        maxIter = i;
    }

    var col = vec3<f32>(0.05, 0.02, 0.1); // Background
    var depthOut = 1.0;

    if (t_dist < MAX_DIST) {
        let p = ro + rd * t_dist;
        let n = getNormal(p, time, bass, high, mouseUV);
        let l = normalize(vec3<f32>(1.0, 2.0, -3.0));
        let dif = max(dot(n, l), 0.0);

        // Materials
        if (finalMatId < 0.5) { // Fluid
            let sss = max(0.0, map(p + l * 0.5, time, bass, high, mouseUV).dist) * 2.0; // Subsurface scattering approx
            var fluidCol = vec3<f32>(0.0, 0.5, 0.8) + vec3<f32>(0.2, 0.8, 0.4) * sss;
            col = fluidCol * dif;

            // Fresnel
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            col += vec3<f32>(0.5, 0.8, 1.0) * fresnel;
            let seam = map(p, time, bass, high, mouseUV).seam;
            col += vec3<f32>(0.65, 1.0, 0.78) * seam;
            let veinBands = pow(max(0.0, sin((p.z + p.x) * 7.0 - time * 3.4)), 4.0) * (0.3 + bass * 0.7);
            col += vec3<f32>(0.2, 0.95, 0.72) * veinBands * 0.25;

        } else { // Crystal
            let refl = reflect(rd, n);
            let spec = pow(max(dot(refl, l), 0.0), 32.0);
            var crystalCol = vec3<f32>(0.7, 0.2, 0.9);
            col = crystalCol * dif + vec3<f32>(1.0) * spec;
            let seam = map(p, time, bass, high, mouseUV).seam;
            col += vec3<f32>(0.75, 0.95, 1.0) * seam * 0.65;
            let twinningPlanes = exp(-abs(sin((p.x - p.y) * 14.0 + time * 1.2)) * 6.0);
            col += vec3<f32>(0.95, 0.72, 1.0) * twinningPlanes * (0.1 + high * 0.35);
        }

        depthOut = t_dist / MAX_DIST;
    }

    // Bloom / Ethereal Glow
    col += vec3<f32>(0.1, 0.9, 0.4) * global_glow * 2.0;

    // Idea 2 — chrono smear: Chrono Warp leans this frame on the previous display.
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0);
    let chronoWarp = u.zoom_params.z;
    let smear = clamp(chronoWarp / 5.0, 0.0, 1.0) * 0.5;
    let fluidWeight = select(0.12, 0.8, t_dist < MAX_DIST && finalMatId < 0.5);
    col = mix(col, prev.rgb, smear * fluidWeight);

    col = acesToneMap(col * 1.2);
    let hit = t_dist < MAX_DIST;
    let alpha = clamp(select(0.05, 0.74, hit) + global_glow * 0.2 + smear * 0.08, 0.0, 1.0);
    let outColor = vec4<f32>(col, alpha);
    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);
}
