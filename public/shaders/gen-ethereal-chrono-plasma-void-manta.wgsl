// ═══════════════════════════════════════════════════════════════════
//  Ethereal Chrono-Plasma Void-Manta
//  Category: generative
//  Features: mouse-driven, audio-reactive, click-reactive, upgraded-rgba
//  Upgraded: 2026-10-10
//  Ideas: manta banking (wings roll/yaw toward the pointer through a smooth
//         cubic, stateless, plus a slow glide sway); bass-pumped wing flap
//         amplitude via plasmaBuffer, bounded by a span falloff; treble
//         chrono-plasma veins pulsing along the wing span at ripple freq.
//         2nd pass: manta planform (diamond wings + cephalic fins + whip tail
//         cut from the wing slab); wingtip vortex wakes (counter-rotating
//         spiral filaments shed from the tips, phased by the flap); ventral
//         counter-shading with breathing gill-slit rows on the underside
//  A packing: ACES display RGBA (hue-preserving clamp before tonemap;
//             alpha = manta/sss or fog coverage; matches exact C read)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

// Custom Parameters Mapping:
// zoom_params.x = Manta Speed
// zoom_params.y = Bio-Luminescence Intensity
// zoom_params.z = Wing Ripple Frequency
// zoom_params.w = Dark Matter Density

const PI: f32 = 3.14159265359;
const SPAN: f32 = 2.7;     // wingtip half-span (planform)
const TIP_Z: f32 = 0.3;    // z of the wingtips (head is toward -z)

var<private> g_audio: f32 = 0.0;
var<private> g_bank: vec2<f32> = vec2<f32>(0.0);

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash(p: vec3<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x * 0.1031, p.y * 0.1030, p.z * 0.0973));
    p3 = p3 + vec3<f32>(dot(p3, p3.yxz + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f_new = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let f_final = f_new;
    return mix(mix(mix(hash(p + vec3<f32>(0.0, 0.0, 0.0)),
                        hash(p + vec3<f32>(1.0, 0.0, 0.0)), f_final.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 0.0)),
                        hash(p + vec3<f32>(1.0, 1.0, 0.0)), f_final.x), f_final.y),
               mix(mix(hash(p + vec3<f32>(0.0, 0.0, 1.0)),
                        hash(p + vec3<f32>(1.0, 0.0, 1.0)), f_final.x),
                   mix(hash(p + vec3<f32>(0.0, 1.0, 1.0)),
                        hash(p + vec3<f32>(1.0, 1.0, 1.0)), f_final.x), f_final.y), f_final.z);
}

fn fbm3(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(pp);
        pp = pp * 2.0 + vec3<f32>(f32(i) * 12.34);
        a *= 0.5;
    }
    return v;
}

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
    return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let v = max(c.r, max(c.g, c.b));
    let minc = min(c.r, min(c.g, c.b));
    let s = select(0.0, (v - minc) / v, v > 0.0);
    let delta = v - minc;
    var h = 0.0;
    if (delta > 0.0) {
        if (v == c.r) { h = (c.g - c.b) / delta; }
        else if (v == c.g) { h = 2.0 + (c.b - c.r) / delta; }
        else { h = 4.0 + (c.r - c.g) / delta; }
    }
    h = fract(h / 6.0 + 1.0);
    return vec3<f32>(h, s, v);
}

fn hue_preserving_clamp(c: vec3<f32>, max_val: f32) -> vec3<f32> {
    let hsv = rgb2hsv(c);
    return hsv2rgb(vec3<f32>(hsv.x, hsv.y, min(hsv.z, max_val)));
}

fn aces_tone_map(x: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(2.51);
    let b = vec3<f32>(0.03);
    let c = vec3<f32>(2.43);
    let d = vec3<f32>(0.59);
    let e = vec3<f32>(0.14);
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn ign_dither(uv: vec2<f32>) -> f32 {
    let p = floor(uv);
    return fract(52.9829189 * fract(0.06711056 * p.x + 0.00583715 * p.y));
}

fn iridescence(cosTheta: f32, time: f32) -> vec3<f32> {
    let t = 1.0 - cosTheta;
    let hue = 0.55 + 0.25 * sin(t * 6.0 + time * 0.7) + 0.15 * cos(t * 9.0 - time * 0.4);
    return hsv2rgb(vec3<f32>(fract(hue), 0.75, 1.0));
}

// World -> manta frame: bank roll (xy) then yaw (xz). Pure rotation, so it
// also maps directions and normals.
fn toManta(v: vec3<f32>) -> vec3<f32> {
    var pos = v;
    let rolled = rot(g_bank.x) * pos.xy;
    pos.x = rolled.x; pos.y = rolled.y;
    let yawed = rot(g_bank.y) * pos.xz;
    pos.x = yawed.x; pos.z = yawed.y;
    return pos;
}

// Span envelope of the flap: grows ~x^2 near the body, saturates at the tips
// (HEAD used raw x^2, unbounded across an infinite sheet).
fn flapEnv(x: f32) -> f32 {
    let x2 = x * x;
    return x2 / (1.0 + 0.15 * x2);
}

fn ndot2(a: vec2<f32>, b: vec2<f32>) -> f32 { return a.x * b.x - a.y * b.y; }

fn sdRhombus(p_in: vec2<f32>, b: vec2<f32>) -> f32 {
    let p = abs(p_in);
    let h = clamp(ndot2(b - 2.0 * p, b) / dot(b, b), -1.0, 1.0);
    let d = length(p - 0.5 * b * vec2<f32>(1.0 - h, 1.0 + h));
    return d * sign(p.x * b.y + p.y * b.x - b.x * b.y);
}

fn sdSeg2(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

fn sdCapsule3(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// Idea: manta planform — 2D outline in the wing plane (pos.xz): swept
// diamond wings (head toward -z), plus two cephalic fins flanking the head.
fn planform(q: vec2<f32>) -> f32 {
    let zc = q.y - TIP_Z;
    let b = vec2<f32>(SPAN, select(1.8, 2.0, zc < 0.0));
    let wings = sdRhombus(vec2<f32>(q.x, zc), b) - 0.04;
    let fins = sdSeg2(vec2<f32>(abs(q.x), q.y), vec2<f32>(0.42, -1.35), vec2<f32>(0.55, -2.25)) - 0.12;
    return smin(wings, fins, 0.15);
}

// Scene SDF
fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = toManta(p);
    let time = u.config.x * u.zoom_params.x;
    let audio = g_audio;
    let freq = u.zoom_params.z;

    // Manta motion: bass-pumped flap, span-bounded
    let ampK = 0.2 + audio * 0.15;
    let flap = sin(pos.x * freq - time * 3.0) * flapEnv(pos.x) * ampK;
    pos.y += flap;

    // Core body (flattened sphere) + whip tail
    let body_d = (length(pos / vec3<f32>(1.0, 0.2, 2.0)) - 1.0) * 0.2;
    let tail = sdCapsule3(pos, vec3<f32>(0.0, -0.05, 1.9), vec3<f32>(0.0, -0.12, 4.0), 0.035);
    let bodyAll = min(body_d * 0.5, tail);

    // Wings (displaced plane with chrono-plasma ripple), thinning to the tips
    let wingNoise = fbm3(pos * 1.5 + vec3<f32>(0.0, 0.0, time * 0.5));
    let wing_d = pos.y + wingNoise * 0.5 * (1.0 + audio);
    let thick = 0.1 * (1.0 - 0.55 * smoothstep(0.3, SPAN, abs(pos.x)));
    // Lipschitz guard for the flap + noise displacement
    let gFlap = flapEnv(SPAN) * ampK * freq;
    let lip = 0.85 / (1.0 + 0.5 * gFlap);
    let slab = (abs(wing_d) - thick) * lip;
    // Planform cut: the wing is a finite manta outline, not an infinite sheet
    let wing = max(slab, planform(pos.xz));

    // Blend body and wings
    let manta_d = smin(bodyAll, wing, 0.5);

    // Material ID: 1.0 for manta, 0.0 for background
    return vec2<f32>(manta_d, 1.0);
}

// Idea: wingtip vortex wakes. Each tip sheds a counter-rotating spiral
// filament that streams aft (+z). Its centreline replays the tip's flap at
// the retarded time (shed earlier = further back), so the wake traces the
// stroke. Evaluated analytically at the ray's closest approach to each wake
// axis (in the manta frame), occluded by the hit distance.
fn wingtipWakes(ro_m: vec3<f32>, rd_m: vec3<f32>, tHit: f32, mantaTime: f32) -> vec3<f32> {
    let freq = u.zoom_params.z;
    let ampK = 0.2 + g_audio * 0.15;
    var acc = vec3<f32>(0.0);
    let denom = 1.0 - rd_m.z * rd_m.z;
    if (denom < 1e-4) { return acc; }
    for (var side = 0; side < 2; side++) {
        let sgn = select(-1.0, 1.0, side == 1);
        let xs = sgn * SPAN * 0.98;
        let L0 = vec3<f32>(xs, -0.25, 0.0);
        let w0 = ro_m - L0;
        let dd = dot(rd_m, w0);
        let t = (rd_m.z * w0.z - dd) / denom;
        let s = (w0.z - rd_m.z * dd) / denom;
        let ds = s - TIP_Z;
        if (t <= 0.0 || t > tHit || ds < -0.2 || ds > 7.0) { continue; }
        let P = ro_m + rd_m * t;
        let tau = mantaTime - ds / 2.2;
        let yc = -0.25 - sin(xs * freq - tau * 3.0) * flapEnv(xs) * ampK * exp(-ds * 0.15) - ds * 0.05;
        let xc = xs + sgn * ds * 0.06;
        let off = vec2<f32>(P.x - xc, P.y - yc);
        let r = length(off);
        let w = 0.05 + ds * 0.025;
        let ang = atan2(off.y, off.x) * sgn;
        let spiral = 0.5 + 0.5 * cos(2.0 * ang - log(r + 0.02) * 4.0 + ds * 3.0 - mantaTime * 4.0);
        let core = exp(-r * r / (w * w));
        let halo = exp(-r * r / (9.0 * w * w)) * 0.25;
        let along = exp(-max(ds, 0.0) * 0.35) * smoothstep(-0.2, 0.25, ds);
        let g = (core * (0.4 + 0.6 * spiral) + halo * spiral) * along;
        acc += mix(vec3<f32>(0.3, 0.9, 1.4), vec3<f32>(1.0, 0.15, 0.75), spiral) * g;
    }
    return acc;
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(1.0, -1.0) * 0.5773 * 0.0005;
    return normalize( e.xyy*map( p + e.xyy ).x +
                      e.yyx*map( p + e.yyx ).x +
                      e.yxy*map( p + e.yxy ).x +
                      e.xxx*map( p + e.xxx ).x );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coords = vec2<i32>(id.xy);
    if (coords.x >= i32(dims.x) || coords.y >= i32(dims.y)) { return; }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = (vec2<f32>(id.xy) - 0.5 * resolution) / min(resolution.x, resolution.y);
    let uv01 = (vec2<f32>(id.xy) + 0.5) / resolution;

    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audio = bass * 0.55 + mids * 0.3 + treble * 0.15;
    let bio = u.zoom_params.y;
    let darkMatter = u.zoom_params.w;
    g_audio = audio;

    // Stateless banking: HEAD's spring lived in extraBuffer[133..137], which
    // the engine re-uploads every frame, so it never moved. The pointer bank
    // goes through a smooth cubic, plus a slow glide sway.
    let rawMouse = u.zoom_config.yz - vec2<f32>(0.5);
    let mx = clamp(rawMouse.x * 2.0, -1.0, 1.0);
    let shaped = mx * (1.5 - 0.5 * mx * mx);
    let mantaTime = time * u.zoom_params.x;
    let sway = sin(mantaTime * 0.5) * 0.08;
    g_bank = vec2<f32>(clamp(-shaped * 0.55 + sway, -0.9, 0.9),
                       clamp(shaped * 0.4, -1.2, 1.2));

    // Exact previous-frame display history.
    let prev = textureLoad(dataTextureC, coords, 0);

    var shock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 3.2) {
            let front = abs(length((uv01 - ripple.xy) * vec2<f32>(resolution.x / resolution.y, 1.0)) - age * (0.16 + u.zoom_params.x * 0.04));
            shock += (1.0 - smoothstep(0.0, 0.026, front)) * (1.0 - age / 3.2);
        }
    }
    shock = min(shock, 2.0);

    // Camera setup
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    var ro = vec3<f32>(0.0, 2.0, -5.0 + held * 0.8);
    // Aim at the manta (origin) with +y up on screen (pixel rows grow down).
    // HEAD looked level along +z over an infinite sheet, upside down; with a
    // finite planform that framing would leave the manta out of shot.
    let camFw = normalize(vec3<f32>(0.0, -0.25, -0.6) - ro); // head + cephalic fins in frame
    let camRi = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), camFw));
    let camUp = cross(camFw, camRi);
    var rd = normalize(uv.x * camRi - uv.y * camUp + 1.5 * camFw);

    // Mouse rotation
    let mouse = (u.zoom_config.yz - vec2<f32>(0.5)) * 6.28;
    let new_ro_yz = rot(-mouse.y) * ro.yz;
    ro.y = new_ro_yz.x;
    ro.z = new_ro_yz.y;
    let new_rd_yz = rot(-mouse.y) * rd.yz;
    rd.y = new_rd_yz.x;
    rd.z = new_rd_yz.y;
    let new_ro_xz = rot(-mouse.x) * ro.xz;
    ro.x = new_ro_xz.x;
    ro.z = new_ro_xz.y;
    let new_rd_xz = rot(-mouse.x) * rd.xz;
    rd.x = new_rd_xz.x;
    rd.z = new_rd_xz.y;

    // Light sources
    let keyLight = normalize(vec3<f32>(1.0, 2.0, -1.0));
    let fillLight = normalize(vec3<f32>(-1.5, 0.5, -0.5));
    let rimLightDir = normalize(vec3<f32>(0.0, 1.0, 1.0));
    let keyColor = vec3<f32>(1.3, 0.75, 0.35); // warm auroral sun
    let fillColor = vec3<f32>(0.25, 0.6, 1.4); // cool deep-space fill
    let rimColor = vec3<f32>(1.1, 0.3, 1.6);   // magenta rim

    // Raymarching loop
    var t = 0.0;
    var col = vec3<f32>(0.0);
    var hit = false;
    var hitP = vec3<f32>(0.0);
    var bg_density = 0.0;
    var sss = 0.0;

    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let d = map(p);

        // Accumulate dark-matter density along ray (per distance travelled,
        // so the finite manta's longer steps keep HEAD's density)
        bg_density += noise(p * 0.5 + vec3<f32>(time * 0.1)) * darkMatter * 0.02 * clamp(d.x / 0.6, 0.05, 1.0);

        if (d.x < 0.001) {
            hit = true;
            hitP = p;
            let n = calcNormal(p);

            let diffKey = max(dot(n, keyLight), 0.0);
            let diffFill = max(dot(n, fillLight), 0.0) * 0.5;
            let rim = pow(1.0 - max(dot(n, -rd), 0.0), 4.0);

            // Subsurface / bio-luminescence: sample INSIDE (p - n*k), so thin
            // wing membrane transmits and the thick body does not (HEAD
            // sampled outward, which measured nothing).
            let inside = map(p - n * 0.2).x;
            sss = exp(-max(-inside, 0.0) * 25.0) * bio;

            // Idea: ventral counter-shading — pale belly, dark back (manta frame)
            let pm = toManta(p);
            let nm = toManta(n);
            let ventral = 1.0 - smoothstep(-0.4, 0.1, nm.y);
            let base_col = mix(vec3<f32>(0.08, 0.18, 0.45), vec3<f32>(0.62, 0.66, 0.78) * 0.55, ventral);
            let glow_col = vec3<f32>(1.0, 0.15, 0.75) * (1.0 + audio * 2.0);

            // Iridescent wing rim
            let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
            let iris = iridescence(fresnel, time) * fresnel * 2.2;

            // Treble chrono-plasma veins along the wing span
            let veinPhase = p.x * u.zoom_params.z * 3.0 + fbm3(p * 2.0) * 4.0 - time * (2.0 + u.zoom_params.x);
            let vein = pow(1.0 - abs(sin(veinPhase)), 12.0) * (0.3 + treble * 2.5) * bio;
            col = vec3<f32>(0.3, 0.9, 1.4) * vein
                + base_col * (keyColor * diffKey + fillColor * diffFill)
                + glow_col * sss
                + rimColor * rim * 1.8
                + iris
                + vec3<f32>(0.62, 0.66, 0.78) * 0.06 * ventral;

            // Idea: gill-slit rows — five paired slits on the ventral head,
            // dark cuts with a breathing bioluminescent glow inside.
            let gz = (pm.z + 0.95) / 0.17;
            let gk = floor(gz);
            let gValid = select(0.0, 1.0, gk >= 0.0 && gk <= 4.0);
            let gxc = 0.42 + gk * 0.03;
            let inX = 1.0 - smoothstep(0.1, 0.14, abs(abs(pm.x) - gxc));
            let slitLine = 1.0 - smoothstep(0.06, 0.16, abs(fract(gz) - 0.5));
            let slit = slitLine * inX * gValid * ventral;
            let breath = 0.5 + 0.5 * sin(time * 2.0 + gk * 0.6);
            col = col * (1.0 - slit * 0.6) + vec3<f32>(0.3, 0.9, 1.4) * slit * (0.25 + mids * 0.8) * bio * breath;
            break;
        }
        if (t > 20.0) { break; }
        t += d.x;
    }

    if (!hit) {
        // Deep space / dark matter color with volumetric tint
        col = vec3<f32>(0.02, 0.01, 0.05) + vec3<f32>(0.25, 0.12, 0.5) * bg_density;
        t = 20.0;
    }

    // Volumetric god rays / fog in the void
    var fogAccum = 0.0;
    for (var i = 0; i < 24; i++) {
        let fi = f32(i);
        let fp = ro + rd * (fi * 0.6);
        let fogDen = max(0.0, noise(fp * 0.4 + vec3<f32>(time * 0.08, 0.0, time * 0.05)) - 0.35);
        fogAccum += fogDen * darkMatter * 0.04;
    }
    let fogColor = mix(vec3<f32>(0.1, 0.0, 0.25), vec3<f32>(0.0, 0.5, 0.7), 0.5);
    col += fogColor * fogAccum * 2.0;

    // Wingtip vortex wakes, in the same void as the fog
    let wakes = wingtipWakes(toManta(ro), toManta(rd), t, mantaTime);
    col += wakes * bio * (0.35 + bass * 0.8);

    // Audio bloom on hit distance
    col += vec3<f32>(0.2, 0.5, 1.0) * audio * bio * (1.0 / (1.0 + t * t * 0.05));
    col += vec3<f32>(0.95, 0.16 + mids * 0.35, 1.0) * shock * (0.45 + treble * 0.8);

    // HDR clamp preserving hue, then ACES on display RGB
    let display = aces_tone_map(hue_preserving_clamp(max(col, vec3<f32>(0.0)), 8.0));

    // Temporal blend in display space with exact previous-frame history
    col = mix(prev.rgb * 0.94, display, 0.3 + bass * 0.03);

    // IGN dither
    let dither = (ign_dither(vec2<f32>(id.xy)) - 0.5) / 255.0;
    col = clamp(col + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha based on emission density and hit depth
    let alpha = select(clamp(0.15 + fogAccum + bg_density * 0.5, 0.0, 1.0),
                       clamp(0.85 + sss * 0.15, 0.0, 1.0), hit);

    textureStore(writeTexture, coords, vec4<f32>(col, alpha));
    // Depth: near = 1, void = 0
    textureStore(writeDepthTexture, coords, vec4<f32>(1.0 - clamp(t * 0.05, 0.0, 1.0), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(col, alpha));
}
