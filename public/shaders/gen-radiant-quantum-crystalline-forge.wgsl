// ═══════════════════════════════════════════════════════════════════
//  Radiant Quantum-Crystalline Forge
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-27, 2026-11-08
//  Ideas: crystallographic twin facets; accretion weld seams; blackbody seam cooling; cleavage-plane glints; hammer-strike heat front with cooling tail; albite twin flash (§12.2E fold-count parity revives the twin facets)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Density, y=Chroma, z=Fog, w=Mouse Influence

const MAX_STEPS: i32 = 80;
const MAX_DIST: f32 = 50.0;
const SURF_DIST: f32 = 0.01;

fn rotate(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

var<private> g_seam: f32 = 1.0;

fn mapSDF(p_in: vec3<f32>) -> vec2<f32> {
    var p = p_in;
    let t = u.config.x * 0.5;
    let audio = plasmaBuffer[0].x; // bass drives fold expansion
    let density = u.zoom_params.x;

    p.x += sin(p.z * 0.2 + t) * 0.5;
    p.y += cos(p.x * 0.2 + t) * 0.5;

    var scale: f32 = 1.0;
    var refl = 0.0;
    var seam = 10.0;
    let iter = 6;
    for(var i = 0; i < iter; i++) {
        // ── Rescue R2 (§12.2E fold count as material): HEAD's `twin = f32(i & 1)` was
        // overwritten every pass and always ended as 1.0, so the twin tint never split.
        // Count the mirror reflections the point goes through; parity = twin domain.
        refl += f32(p.x < 0.0) + f32(p.y < 0.0) + f32(p.z < 0.0);
        let plane = min(abs(p.x), min(abs(p.y), abs(p.z)));
        let edge = min(min(abs(abs(p.x) - abs(p.y)), abs(abs(p.y) - abs(p.z))), abs(abs(p.z) - abs(p.x)));
        seam = min(seam, (plane + edge) / max(scale, 0.001));
        p = abs(p) - vec3<f32>(1.2, 0.8, 1.5) * density * (1.0 + audio * 0.2);
        let rot = rotate(t * 0.2 + f32(i) * 0.5);
        p = vec3<f32>(rot * p.xy, p.z);
        let rot2 = rotate(t * 0.3);
        p = vec3<f32>(p.x, rot2 * p.yz);

        let s = 1.8;
        p *= s;
        scale *= s;
    }

    g_seam = seam;
    let twin = refl - 2.0 * floor(refl * 0.5);
    let d = (length(p) - 1.0) / scale;
    return vec2<f32>(d, twin);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        mapSDF(p + e.xyy).x - mapSDF(p - e.xyy).x,
        mapSDF(p + e.yxy).x - mapSDF(p - e.yxy).x,
        mapSDF(p + e.yyx).x - mapSDF(p - e.yyx).x
    ));
}

// Idea 3 helper: blackbody-ish ramp, 0 = cold dull red, 1 = white-hot.
fn blackbody(heat: f32) -> vec3<f32> {
    let h = clamp(heat, 0.0, 1.0);
    return vec3<f32>(
        smoothstep(0.0, 0.35, h),
        smoothstep(0.25, 0.75, h) * 0.9,
        smoothstep(0.6, 1.0, h) * 0.85
    ) * (0.35 + 1.1 * h);
}

// ── Idea 5 helper: hammer-strike heat front with a cooling tail. Every ~4.5 s a blow lands
// on the camera-facing side of the mass; a spherical heat front spreads from the strike point
// across the surface (arrival-gated by world distance to the strike) and the metal behind it
// cools along the blackbody ramp. Radius of the mass ≈ 3.5·density. The per-blow constants
// are built once per pixel (strikeSetup); strikeHeat is only length + two exp per march step.
struct Strike {
    at: vec3<f32>,
    front: f32,
    w: f32,
    tailW: f32,
    env: f32,
}

fn strikeSetup(time: f32, density: f32) -> Strike {
    let massR = 3.5 * density + 0.2;
    let sid = floor(time * 0.22);
    let ph = fract(time * 0.22);
    let h1 = fract(sin(sid * 12.9898 + 1.3) * 43758.5453);
    let h2 = fract(sin(sid * 78.233 + 4.1) * 43758.5453);
    var st: Strike;
    st.at = vec3<f32>((h1 - 0.5) * 1.3 * massR, (h2 - 0.5) * 1.3 * massR, -0.8 * massR);
    st.front = ph * 2.2 * massR;
    st.w = 0.10 * massR + 0.08;
    st.tailW = 0.16 * massR + 0.05;
    st.env = 1.0 - smoothstep(0.8, 1.0, ph);   // fade out before the next blow: no pop
    return st;
}

fn strikeHeat(pw: vec3<f32>, st: Strike) -> f32 {
    let r = length(pw - st.at);
    let dx = (r - st.front) / st.w;
    let shell = exp(-dx * dx);
    let tail = step(r, st.front) * exp(-max(st.front - r, 0.0) / st.tailW);
    return (shell + 0.3 * tail) * st.env;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(global_id.x) >= res.x || f32(global_id.y) >= res.y) { return; }

    var uv = (vec2<f32>(global_id.xy) - vec2<f32>(0.5) * res) / res.y;

    // Audio reactivity: mids feed volumetric fog, treble adds spec sparkle
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Mouse Interaction: Gravity well distortion (normalized UV)
    var m = (u.zoom_config.yz - vec2<f32>(0.5)) * vec2<f32>(res.x / max(res.y, 1.0), 1.0);
    let mDist = length(uv - m);
    if (mDist < 0.5) {
        let force = (0.5 - mDist) * 2.0 * u.zoom_params.w;
        uv += normalize(uv - m + vec2<f32>(1e-4)) * force * 0.1 * sin(u.config.x * 2.0);
    }

    // ── Rescue R1: HEAD flew `-8 + 2*time` forever — inside the solid at t≈3.5–4.7 and
    // permanently past it (blank) from t≈5. The dolly now breathes between HEAD's start
    // frame (z = -8 at t = 0) and a stand-off that scales with the density slider (the
    // crystal mass grows with density), so the camera never enters the solid.
    let dMin = max(7.0 * u.zoom_params.x, 0.8);
    let dolly = 0.5 + 0.5 * cos(u.config.x * 0.5);
    let ro = vec3<f32>(0.0, 0.0, -mix(dMin, 8.0, dolly));
    let rd = normalize(vec3<f32>(uv, 1.0));

    var dO = 0.0;
    var hit = false;
    var glow = 0.0;
    var seamGlow = vec3<f32>(0.0);
    var p = ro;

    let chroma = u.zoom_params.y;
    let fogInt = u.zoom_params.z;
    let strikeBlow = strikeSetup(u.config.x, u.zoom_params.x);

    for(var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let dS = mapSDF(p);

        // Volumetric Fog accumulation
        glow += 0.01 * fogInt / (1.0 + dS.x * dS.x * 100.0) * (1.0 + mids * 0.8);
        // Idea 3: seam fog glows by blackbody heat that cools with distance
        // from the forge front (the camera).
        let seamE = exp(-g_seam * 14.0);
        // ── Idea 5: the strike front lights the seam fog as it passes
        let strike = strikeHeat(p, strikeBlow);
        glow += 0.004 * fogInt * seamE * (1.0 + 1.0 * strike);
        seamGlow += blackbody(exp(-dO * 0.07) + 0.3 * strike) * 0.006 * fogInt * seamE * (1.0 + 1.0 * strike);

        if(dS.x < SURF_DIST) {
            hit = true;
            break;
        }
        if(dO > MAX_DIST) { break; }
        dO += dS.x * 0.8;
    }

    var col = vec3<f32>(0.0);
    var surfFresnel = 0.0;

    if(hit) {
        let n = calcNormal(p);
        let hitMap = mapSDF(p);
        let l = normalize(vec3<f32>(1.0, 2.0, -3.0));
        let view = normalize(ro - p);
        let h = normalize(l + view);

        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(n, h), 0.0), 32.0) * (1.0 + treble * 1.5);
        let fresnel = pow(1.0 - max(dot(n, view), 0.0), 4.0);
        surfFresnel = fresnel;

        // Iridescent chromatic dispersion based on normals and time
        let baseCol = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(u.config.x) + p.xyz * 0.5 + vec3<f32>(0.0, 2.0, 4.0));
        let twinA = vec3<f32>(0.55, 0.85, 1.0);
        let twinB = vec3<f32>(1.0, 0.55, 0.35);
        let twinTint = mix(twinA, twinB, hitMap.y);
        col = mix(baseCol, twinTint, 0.45 * chroma) * diff + spec * vec3<f32>(1.0) + fresnel * twinTint * chroma;
        // ── Idea 5: weld seams flare at the hammer-strike front and cool behind it
        let strikeHit = strikeHeat(p, strikeBlow);
        let weld = exp(-g_seam * 18.0) * (1.0 + 0.7 * strikeHit);
        let weldPal = mix(vec3<f32>(1.0, 0.95, 0.75), vec3<f32>(0.55, 0.2, 1.0), fract(u.config.x * 0.15 + g_seam * 4.0));
        let weldHeat = blackbody(exp(-dO * 0.07) * (0.85 + treble * 0.3) + 0.3 * strikeHit);
        col += mix(weldPal, weldHeat * 1.3, 0.55) * weld * (0.8 + treble);

        // ── Idea 6: albite twin flash. Twin lamellae of a real crystal flash alternately
        // as it turns: tilt the half-vector ±δ about the facet's dominant axis by the twin
        // parity (R2), so the two twin domains catch the key light at different instants.
        let an = abs(n);
        let axX = f32(an.x >= max(an.y, an.z));
        let axY = (1.0 - axX) * f32(an.y >= an.z);
        let domAxis = vec3<f32>(axX, axY, 1.0 - axX - axY);
        let twinTilt = cross(n, domAxis) * (hitMap.y * 2.0 - 1.0) * 0.24;
        let hTwin = normalize(h + twinTilt);
        let twinFlash = pow(max(dot(n, hTwin), 0.0), 64.0) * (0.6 + treble * 1.2);
        col += twinTint * twinFlash * 0.9;

        // Idea 4: cleavage-plane glints — facets lying on the axis-aligned fold
        // planes flash a razor specular when they catch the light.
        let axisAlign = max(abs(n.x), max(abs(n.y), abs(n.z)));
        let cleave = pow(axisAlign, 24.0) * pow(max(dot(n, h), 0.0), 160.0);
        col += vec3<f32>(0.9, 0.97, 1.0) * cleave * (2.5 + treble * 4.0);
    }

    // Add fog
    let fogCol = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(u.config.x * 0.2) + vec3<f32>(0.0, 1.0, 2.0));
    col += vec3<f32>(glow) * fogCol + seamGlow;

    // Background fade
    let bgFade = smoothstep(0.0, MAX_DIST, dO);
    col = mix(col, vec3<f32>(0.05, 0.0, 0.1), bgFade);

    // Alpha: crystal surface coverage + volumetric fog density, never flat 1.0
    let alpha = clamp(select(0.0, 0.4, hit) + surfFresnel * 0.4 + clamp(glow, 0.0, 1.0) * 0.4, 0.0, 1.0);
    let out = vec4<f32>(acesToneMap(col * 1.1), alpha);
    let depth = select(0.0, clamp(1.0 - dO / MAX_DIST, 0.0, 1.0), hit);
    let coord = vec2<i32>(global_id.xy);
    textureStore(writeTexture, coord, out);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, out);
}
