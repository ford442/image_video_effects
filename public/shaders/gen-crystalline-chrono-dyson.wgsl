// ═══════════════════════════════════════════════════════════════════
//  Crystalline Chrono-Dyson — Algorithmist Upgrade
//  Category: generative
//  Features: raymarched, audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Very High
//  Upgraded: 2026-09-27
//  Ideas: statite swarm (Swarm Count = number of golden-phased octahedron statites on the satellite orbit, core-lit sails); power-grid packets (emissive packets run quasar -> spoke -> torus conduit as one harvest circuit, packet speed = Flux Speed); louvred panels (each shell plate tilts open on its own phase and throws core light outward)
//  A packing: clamped HDR linear RGB (pre-ACES) + semantic alpha; C read back exactly as HDR for chromatic feedback
// ═══════════════════════════════════════════════════════════════════
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
    zoom_params: vec4<f32>,  // x=Panel Density, y=Quasar Glow, z=Flux Speed, w=Swarm Count
    ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const PHI: f32 = 1.618033988749895;

fn fmod(x: f32, y: f32) -> f32 { return x - y * floor(x / y); }
fn rot2D(a: f32) -> mat2x2<f32> { let s = sin(a); let c = cos(a); return mat2x2<f32>(c, -s, s, c); }

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = fract(p * vec3<f32>(0.1031, 0.1030, 0.0973));
    q += dot(q, q.yxz + 33.33);
    return fract((q.xxy + q.yxx) * q.zyx);
}

fn hash1(p: vec3<f32>) -> f32 { return fract(sin(dot(p, vec3<f32>(127.1, 311.7, 74.7))) * 43758.5453); }

fn vnoise(p: vec3<f32>) -> f32 {
    let i = floor(p); let f = fract(p); let s = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash1(i), hash1(i + vec3<f32>(1.0, 0.0, 0.0)), s.x),
                   mix(hash1(i + vec3<f32>(0.0, 1.0, 0.0)), hash1(i + vec3<f32>(1.0, 1.0, 0.0)), s.x), s.y),
               mix(mix(hash1(i + vec3<f32>(0.0, 0.0, 1.0)), hash1(i + vec3<f32>(1.0, 0.0, 1.0)), s.x),
                   mix(hash1(i + vec3<f32>(0.0, 1.0, 1.0)), hash1(i + vec3<f32>(1.0, 1.0, 1.0)), s.x), s.y), s.z);
}

fn fbm(p: vec3<f32>, oct: i32) -> f32 {
    var v = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < 6; i++) { if (i >= oct) { break; } v += a * vnoise(p * f); f *= 2.0; a *= 0.5; }
    return v;
}

fn worley(p: vec3<f32>, density: f32) -> vec2<f32> {
    let n = floor(p * density); let f = fract(p * density);
    var md = 100.0; var md2 = 100.0;
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            for (var k: i32 = -1; k <= 1; k++) {
                let g = vec3<f32>(f32(i), f32(j), f32(k));
                let o = hash3(n + g);
                let r = g + o - f;
                let d = dot(r, r);
                if (d < md) { md2 = md; md = d; }
                else if (d < md2) { md2 = d; }
            }
        }
    }
    return vec2<f32>(sqrt(md), sqrt(md2) - sqrt(md));
}

fn domainWarp(p: vec3<f32>, t: f32) -> vec3<f32> {
    return p + vec3<f32>(fbm(p + vec3<f32>(0.0, 0.0, t), 3), fbm(p + vec3<f32>(5.2, 1.3, t), 3), fbm(p + vec3<f32>(1.7, 9.2, t), 3)) * 0.4;
}

fn fresnel(cosTheta: f32, f0: vec3<f32>) -> vec3<f32> { return f0 + (vec3<f32>(1.0) - f0) * pow(1.0 - cosTheta, 5.0); }
fn smin(a: f32, b: f32, k: f32) -> f32 { let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }

fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 { let d = abs(p) - b; return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, vec3<f32>(0.0))); }

fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 { let q = abs(p); return (q.x + q.y + q.z - s) * 0.57735027; }
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn spectralGlow(angle: f32, intensity: f32) -> vec3<f32> {
    return vec3<f32>(
        0.5 + 0.5 * cos(angle * 6.28 + 0.0),
        0.5 + 0.5 * cos(angle * 6.28 + 2.094),
        0.5 + 0.5 * cos(angle * 6.28 + 4.189)
    ) * intensity;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn volumetricFog(p: vec3<f32>, ro: vec3<f32>, t: f32, audio: f32) -> vec3<f32> {
    let fogDensity = 0.03 + audio * 0.02;
    let fogAmount = 1.0 - exp(-fogDensity * t);
    let fogColor = vec3<f32>(0.05, 0.02, 0.1) * (1.0 + audio * 0.5);
    return fogColor * fogAmount;
}

// Shared Dyson clock + frame (HEAD rotation, now shared by map and shading).
// NOTE: t = time * Flux Speed (HEAD): dragging the slider scrubs the clock. No persistent accumulator is possible
// (extraBuffer[133..] is re-uploaded every frame), so this phase jump on slider moves is kept and documented.
fn dysonClock() -> f32 { return u.config.x * u.zoom_params.z; }
fn dysonFrame(p: vec3<f32>, t: f32) -> vec3<f32> {
    var q = p;
    let rx = rot2D(t * 0.1) * q.xz; q.x = rx.x; q.z = rx.y;
    return q;
}

// Idea 3: louvred panels — every fract panel cell owns a phase and rate and tilts open about its cell X axis.
// open = 0 is the HEAD plate exactly; most cells sit closed most of the time.
fn louvreOpen(cell: vec3<f32>, t: f32) -> f32 {
    let ph = hash1(cell + vec3<f32>(17.0, 3.0, 5.0));
    return smoothstep(0.35, 0.9, sin(t * (0.35 + 0.4 * ph) + ph * TAU));
}

// Idea 1: statite swarm — Swarm Count statites share the HEAD satellite orbit by polar repetition.
// Cell 0 IS the HEAD satellite (radius 2.5, PHI bob, full size); the others spread by golden-ratio phase in height and
// radius, sized to their arc spacing. Only the nearest cell and its same-side neighbour are evaluated (2 SDFs, no N-loop).
// Returns (distance, statite index).
fn statiteSd(q: vec3<f32>, t: f32, treble: f32) -> vec2<f32> {
    let n = clamp(round(u.zoom_params.w), 1.0, 100.0);
    let sector = TAU / n;
    let orbitAngle = t * 0.4;
    let rel = atan2(q.z, q.x) - orbitAngle;
    let kf = floor(rel / sector + 0.5);
    let kn = kf + select(-1.0, 1.0, rel - kf * sector > 0.0);
    let capSize = min(0.15 + treble * 0.05, 0.3 * 2.5 * sector);
    var best = vec2<f32>(1e5, 0.0);
    for (var j = 0; j < 2; j++) {
        let k = select(kf, kn, j == 1);
        let km = k - n * floor(k / n);
        let a = orbitAngle + km * sector;
        let rad = 2.5 + 0.3 * (fract(km * PHI + 0.5) - 0.5);
        let pos = vec3<f32>(cos(a) * rad, sin(orbitAngle * PHI + km * TAU / PHI) * 0.5, sin(a) * rad);
        let size = select(capSize, 0.15 + treble * 0.05, km < 0.5);
        var lp = q - pos;
        let spin = rot2D(t * 0.7 + km * 2.4) * lp.xz; lp.x = spin.x; lp.z = spin.y;
        let d = sdOctahedron(lp, size);
        if (d < best.x) { best = vec2<f32>(d, km); }
    }
    return best;
}

// Idea 2 geometry (+ FIX): 8 real radial spokes from the quasar surface to the conduit ring, built in a rotated sector
// frame (HEAD folded the angle but never rotated q, and fed q.y into both capsule ends: unbounded sheets, not spokes).
// Returns (spoke distance, conduit distance, circuit path length s from the quasar, spoke index 0..7).
fn gridGeom(q: vec3<f32>, t: f32, mids: f32, bass: f32) -> vec4<f32> {
    let sec = TAU / 8.0;
    let ang = atan2(q.z, q.x) + t * 0.2;
    let k = floor(ang / sec + 0.5);
    let la = ang - k * sec;
    let r = length(q.xz);
    let qs = vec3<f32>(r * cos(la), q.y, r * sin(la));
    let ringR = 1.8 + sin(t * 2.0) * 0.2;                       // HEAD conduit radius
    let a = vec3<f32>(0.5, 0.0, 0.0); let b = vec3<f32>(ringR, 0.0, 0.0);
    let pa = qs - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);         // sdCapsule's h, kept for the packets
    let dSpoke = length(pa - ba * h) - (0.03 + mids * 0.02);     // HEAD spoke radius
    let dCond = sdTorus(q, vec2<f32>(ringR, 0.02 + bass * 0.03)); // HEAD conduit
    let spokeLen = ringR - 0.5;
    let s = select(h * spokeLen, spokeLen + abs(la) * ringR, dCond < dSpoke);
    return vec4<f32>(dSpoke, dCond, s, k - 8.0 * floor(k / 8.0));
}

// Idea 2: power-grid packets — comet pulses with a hard leading edge run outward along the circuit
// (quasar -> spoke -> both ways round the conduit) at a Flux-Speed rate; each spoke fires on its own golden phase;
// energy drains as it spreads round the ring.
fn gridPacket(s: f32, k: f32, t: f32) -> f32 {
    let ph = fract(s / 0.45 - t * 0.9 + k * 0.618);
    let pk = smoothstep(0.35, 0.9, ph) * (1.0 - smoothstep(0.9, 1.0, ph));
    return pk * pk * exp(-max(s - 1.3, 0.0) * 0.9);
}

fn map(p: vec3<f32>) -> f32 {
    let audio = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
    let t = dysonClock(); let density = u.zoom_params.x;
    // Rotate entire Dyson sphere
    let q = dysonFrame(p, t);
    // KIFS crystal fractal inside panel space
    var kq = q; var scale = 1.0;
    for (var i = 0; i < 4; i++) {
        kq = abs(kq) - vec3<f32>(0.3, 0.3, 0.3);
        let xy = rot2D(0.5 + treble * 0.2) * vec2<f32>(kq.x, kq.y); kq.x = xy.x; kq.y = xy.y;
        let yz = rot2D(0.3 + mids * 0.1) * vec2<f32>(kq.y, kq.z); kq.y = yz.x; kq.z = yz.y;
        scale *= 1.2; kq *= 1.2;
    }
    let kifs = sdBox(kq, vec3<f32>(0.1, 0.1, 0.01)) / scale;
    // Domain repetition for crystal panels
    var panel_q = fract(q * density) - 0.5;
    // Idea 3: louvre tilt of this cell's plate about its X axis
    let lz = rot2D(louvreOpen(floor(q * density), t) * 1.2) * panel_q.yz; panel_q.y = lz.x; panel_q.z = lz.y;
    let w = worley(q * 0.5 + t * 0.05, density * 2.0);
    // FIX: panel_q is in cell units, so divide by density (HEAD over-reported the plate distance by x density)
    let crystal = (sdBox(panel_q, vec3<f32>(0.15 + w.x * 0.05, 0.15 + w.y * 0.05, 0.01)) - 0.01) / max(density, 1.0);
    // Dyson shell
    let shell = abs(length(q) - 2.0) - 0.1;
    let panels = max(shell, crystal);
    // Central quasar with FBM turbulence
    let qwarp = domainWarp(q * 0.5, t * 0.3);
    let quasar = sdSphere(q, 0.5 + sin(t * 5.0 + q.x * 10.0) * 0.05 * audio) + fbm(qwarp, 3) * 0.1;
    // Plasma conduit + radial capsule spokes (the power grid)
    let grid = gridGeom(q, t, mids, audio);
    let conduit = grid.y;
    let capsule = grid.x;
    // Octahedron crystal satellites orbiting — now the statite swarm
    let satellite = statiteSd(q, t, treble).x;
    let h = 0.5; let blend = clamp(0.5 + 0.5 * (panels - quasar) / h, 0.0, 1.0);
    var d = mix(panels, quasar, blend) - h * blend * (1.0 - blend);
    d = smin(d, kifs, 0.15);
    d = smin(d, conduit, 0.08);
    d = smin(d, satellite, 0.1);
    d = smin(d, capsule, 0.06);
    return d;
}

fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 { let q = vec2<f32>(length(p.xz) - t.x, p.y); return length(q) - t.y; }

fn getNormal(p: vec3<f32>) -> vec3<f32> {
    let d = map(p); let e = vec2<f32>(0.001, 0.0);
    return normalize(d - vec3<f32>(map(p - e.xyy), map(p - e.yxy), map(p - e.yyx)));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let coords = vec2<i32>(id.xy); let res = vec2<f32>(u.config.z, u.config.w);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) { return; }
    let uv01 = vec2<f32>(coords) / res;
    // FIX: flip Y so screen-top = world +Y (HEAD rendered the sphere upside-down despite the comment below)
    let uv = vec2<f32>(f32(coords.x) - 0.5 * res.x, 0.5 * res.y - f32(coords.y)) / res.y;
    let bass = plasmaBuffer[0].x; let mids = plasmaBuffer[0].y; let treble = plasmaBuffer[0].z;
    var ro = vec3<f32>(0.0, 0.0, -5.0); var rd = normalize(vec3<f32>(uv, 1.0));
    // Mouse orbital camera (Y-flip: screen-top = +Y/up)
    let mx = (u.zoom_config.y - 0.5) * 6.28; let my = clamp((u.zoom_config.z - 0.5) * 3.14, -1.45, 1.45); // FIX: pitch clamp, no pole NaN
    let ro_xz = rot2D(mx) * vec2<f32>(ro.x, ro.z); ro.x = ro_xz.x; ro.z = ro_xz.y;
    let ro_yz = rot2D(my) * vec2<f32>(ro.y, ro.z); ro.y = ro_yz.x; ro.z = ro_yz.y;
    let cw = normalize(-ro); let cu = normalize(cross(cw, vec3<f32>(0.0, 1.0, 0.0))); let cv = cross(cu, cw);
    rd = normalize(uv.x * cu + uv.y * cv + 1.0 * cw);
    // Gravity well warp
    let warp = 1.0 - smoothstep(0.0, 0.5, length(uv));
    rd = normalize(rd + vec3<f32>(warp * 0.1 * sin(u.config.x), warp * 0.1 * cos(u.config.x), 0.0));
    let tD = dysonClock();
    var t = 0.0; var hit = false; var gridGlow = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t; let d = map(p);
        // Idea 2: packet halo — line integral of packet light around spokes/conduit, occluded at the hit
        let gg = gridGeom(dysonFrame(p, tD), tD, mids, bass);
        gridGlow += gridPacket(gg.z, gg.w, tD) * exp(-max(min(gg.x, gg.y), 0.0) * 30.0) * clamp(d, 0.0, 0.25);
        if (d < 0.001) { hit = true; break; }
        if (t > 20.0) { break; }
        t += d * 0.9; // FIX: relaxed step (noise-displaced core, repeated louvres/statites are not exact SDFs)
    }
    var col = vec3<f32>(0.0);
    if (hit) {
        let p = ro + rd * t; let n = getNormal(p); let v = -rd;
        let quasar_glow = u.zoom_params.y; let audio_pulse = 1.0 + bass * 0.5;
        let dist_to_center = length(p);
        let gradient = mix(vec3<f32>(0.2, 0.0, 0.5), vec3<f32>(1.0, 0.8, 0.2), 1.0 - smoothstep(0.0, 2.0, dist_to_center));
        let f0 = vec3<f32>(0.04, 0.02, 0.01); let fres = fresnel(max(dot(n, v), 0.0), f0);
        col = gradient * quasar_glow * audio_pulse / (t * 0.5 + 0.1);
        col += fres * (0.5 + mids * 0.5);
        // Crystal subsurface scattering via Beer-Lambert
        let thickness = clamp(2.0 - dist_to_center, 0.0, 2.0);
        let transmittance = exp(-thickness * 0.8);
        col += vec3<f32>(0.1, 0.3, 0.6) * transmittance * (1.0 + treble);
        // Spectral glow from quasar core
        let viewAngle = max(dot(n, v), 0.0);
        col += spectralGlow(viewAngle * 3.0 + dist_to_center * 2.0, quasar_glow * 0.3 * audio_pulse);
        let q = dysonFrame(p, tD);
        let coreDir = -p / max(dist_to_center, 1e-4); // toward the quasar (origin in both frames)
        let coreFacing = max(dot(n, coreDir), 0.0);
        // Idea 1: statite sails — Swarm Count now counts real statites; HEAD's fake drones (depth stripes
        // sin(t * swarm)) are retired into them. Core-facing sail faces catch quasar light; golden-phased shimmer.
        let st = statiteSd(q, tD, treble);
        let onStatite = 1.0 - smoothstep(0.004, 0.03, st.x);
        let shimmer = 0.6 + 0.4 * sin(u.config.x * 1.7 + st.y * TAU / PHI);
        col += vec3<f32>(0.1, 0.8, 1.0) * onStatite * (0.3 + 1.1 * coreFacing * (0.4 + 0.4 * quasar_glow)) * shimmer;
        // Idea 2: packets light the spoke / conduit surface they are crossing
        let g = gridGeom(q, tD, mids, bass);
        let onGrid = 1.0 - smoothstep(0.004, 0.03, min(g.x, g.y));
        col += vec3<f32>(1.0, 0.72, 0.3) * onGrid * gridPacket(g.z, g.w, tD) * (1.2 + 1.2 * quasar_glow);
        // Idea 3: open louvres turn their tilted faces to the core and throw its light outward
        let onShell = 1.0 - smoothstep(0.1, 0.16, abs(dist_to_center - 2.0));
        let louvre = louvreOpen(floor(q * u.zoom_params.x), tD);
        col += vec3<f32>(1.0, 0.8, 0.45) * onShell * louvre * (0.25 + abs(dot(n, coreDir))) * quasar_glow * 0.45;
    } else {
        // FIX: HEAD hash3(rd).x was per-pixel static crawling with the camera — sparse fixed stars instead
        let sc = hash3(floor(rd * 260.0) + 11.0);
        col = vec3<f32>(0.012, 0.012, 0.025) + vec3<f32>(0.55, 0.6, 0.8) * step(0.995, sc.x) * (0.4 + 0.6 * sc.y);
    }
    // Idea 2: packet halo along the view ray
    col += vec3<f32>(1.0, 0.72, 0.3) * gridGlow * (2.0 + 2.0 * u.zoom_params.y);
    // Volumetric fog integration
    col += volumetricFog(ro + rd * t, ro, t, bass);
    // Temporal feedback with integer chromatic dispersion. C must never be filtered.
    let maxCoord = vec2<i32>(max(i32(res.x) - 1, 0), max(i32(res.y) - 1, 0));
    let prev = textureLoad(dataTextureC, coords, 0);
    col = mix(col, prev.rgb * 0.9, 0.03 + bass * 0.01);
    let cStr = 0.003 + bass * 0.005; let cDir = normalize(uv01 - vec2<f32>(0.5) + 0.001);
    let dispersionPx = cDir * cStr * res;
    let prevR = textureLoad(dataTextureC, clamp(coords + vec2<i32>(dispersionPx * (1.0 + mids)), vec2<i32>(0), maxCoord), 0).r;
    let prevG = textureLoad(dataTextureC, clamp(coords + vec2<i32>(dispersionPx * (0.5 + treble)), vec2<i32>(0), maxCoord), 0).g;
    let prevB = textureLoad(dataTextureC, clamp(coords - vec2<i32>(dispersionPx * (0.8 + bass * 0.5)), vec2<i32>(0), maxCoord), 0).b;
    col.r = mix(col.r, prevR * 0.9, 0.02 + treble * 0.01);
    col.g = mix(col.g, prevG * 0.9, 0.02 + bass * 0.01);
    col.b = mix(col.b, prevB * 0.9, 0.02 + mids * 0.01);
    var clickEnergy = 0.0;
    let rippleCount = min(u32(max(u.config.y, 0.0)), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let ripple = u.ripples[i];
        let age = u.config.x - ripple.z;
        if (age > 0.0 && age < 3.0) {
            let radius = age * 0.18;
            clickEnergy += exp(-abs(distance(uv01, ripple.xy) - radius) * 90.0) * exp(-age * 1.5);
        }
    }
    col += spectralGlow(length(uv) + u.config.x * 0.08, clickEnergy * (0.25 + treble * 0.45));
    let hdrColor = clamp(col, vec3<f32>(0.0), vec3<f32>(8.0));
    let mappedColor = acesToneMap(hdrColor);
    let lum = dot(mappedColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(select(0.08, 0.3 + lum * 0.65, hit) + clickEnergy * 0.08 + min(gridGlow, 1.0) * 0.2, 0.02, 1.0);
    textureStore(writeTexture, coords, vec4<f32>(mappedColor, alpha));
    let depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(hdrColor, alpha));
}
