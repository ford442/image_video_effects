// ----------------------------------------------------------------
// Stellar Web-Loom
// Category: generative
// Features: cosmic-thread-raymarch, volumetric-glow, starfield,
//           warp-speed-streaks, hdr-feedback-trails, audio-transient-burst,
//           audio-color-temperature, aces-tone-map, semantic-alpha,
//           generated-depth, fast-motion
//  Upgraded: 2026-10-19
//  Ideas: plucked standing-wave strings pinned at lattice nodes;
//         warp/weft hues + over/under weave thickness; gyro ring per node;
//         shuttle pick racing along every weft thread with a cooling laid pick;
//         stellar-class knots (§12.2E orbit trap of node distance → blackbody)
//  A packing: A.rgb = HDR trail colour (clamped), A.a = march depth; writeTexture alpha = 0.85 void + 0.15 thread intensity
// ----------------------------------------------------------------
#include "_prelude.wgsl"

const HDR_CLAMP: f32 = 6.0; // feedback history energy ceiling (stability at speed)

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
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn luma(rgb: vec3<f32>) -> f32 {
    return dot(rgb, vec3<f32>(0.2126, 0.7152, 0.0722));
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
var<private> g_shuttle: f32;      // Idea 4: shuttle bead + laid-pick glow on the weft row at this step
var<private> g_node: f32;         // Idea 5: node-sphere distance at this step (orbit-trap source)
var<private> g_nodeCell: vec3<f32>;

// Idea 5: blackbody colour for a stellar surface temperature in kelvin
// (Helland fit, guarded so the unselected branches never see a negative base).
fn blackbody(kelvin: f32) -> vec3<f32> {
    let tt = kelvin / 100.0;
    let hot = tt > 66.0;
    let r = select(1.0, clamp(1.292936 * pow(max(tt - 60.0, 1.0), -0.1332047), 0.0, 1.0), hot);
    let g = select(clamp(0.3900816 * log(tt) - 0.6318414, 0.0, 1.0),
                   clamp(1.1298909 * pow(max(tt - 60.0, 1.0), -0.0755148), 0.0, 1.0), hot);
    let b = select(clamp(0.5432068 * log(max(tt - 10.0, 1.0)) - 1.1962541, 0.0, 1.0), 1.0, hot);
    return vec3<f32>(r, g, b);
}

// Idea 5: each knot hashes a surface temperature, skewed toward cool K/M stars
// with rare hot O/B ones.
fn starColour(cell: vec3<f32>) -> vec3<f32> {
    let h = hash31(cell + vec3<f32>(3.3, 8.1, 1.7));
    let bb = blackbody(mix(2800.0, 26000.0, h * h * h));
    // Stretch the pastel blackbody chroma so classes read against the glow, then
    // normalise to a fixed luminance so a hot star is bluer, not brighter.
    let lw = vec3<f32>(0.2126, 0.7152, 0.0722);
    let sat = max(mix(vec3<f32>(dot(bb, lw)), bb, 2.6), vec3<f32>(0.0));
    return sat / max(dot(sat, lw), 1e-3);
}

// IDEA 1: plucked string. s = signed axis coordinate inside the cell (node at 0),
// seg = hashed id of the node-to-node segment (same id from both neighbouring
// cells), returns transverse displacement. Mode 1 is pinned at both nodes
// (|s| keeps it continuous across the cell face), mode 2 decays faster.
fn pluck(s: f32, sp: f32, seg: vec3<f32>, salt: f32) -> vec2<f32> {
    let h = hash31(seg + vec3<f32>(salt, salt * 1.7, salt * 2.3));
    let ring = exp(-3.0 * fract(g_time * 0.3 + h)); // re-plucked every ~3 s
    let amp = min(0.05 + 0.16 * ring + 0.2 * g_audio, 0.3);
    let e1 = sin(3.14159265 * abs(s) / sp);
    let e2 = sin(6.2831853 * s / sp);
    let a = g_time * 4.0 + h * 6.2831853;
    let b = g_time * 8.0 + h * 17.0;
    return amp * (e1 * vec2<f32>(cos(a), sin(a)) + 0.4 * ring * e2 * vec2<f32>(cos(b), sin(b)));
}

fn map(pos: vec3<f32>) -> vec2<f32> {
    let density = max(0.1, u.zoom_params.x);
    let weaveSpeed = u.zoom_params.y;
    // Click deepens the singularity. The idle pointer parks at the canvas centre, i.e.
    // on the flight axis, so HEAD's 1.5-rad idle pull swirled the whole lattice into an
    // unreadable vortex; idle is now a gentle 0.6, held reaches 3.0 (HEAD: 3.0).
    let singularityPull = 0.6 + u.zoom_config.w * 2.4;

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

    // Weave turbulence — time-warp eased for fast surges that never strobe
    let fbm_time = (g_time + 0.35 * sin(g_time * 0.43)) * weaveSpeed * 0.9 + g_audio;
    let warp = vec3<f32>(
        fbm(q + vec3<f32>(fbm_time, 0.0, 0.0)),
        fbm(q + vec3<f32>(0.0, fbm_time, 0.0)),
        fbm(q + vec3<f32>(0.0, 0.0, fbm_time))
    ) * 2.0 - vec3<f32>(1.0);

    let warped_q = q + warp * 0.5;

    let nodeDist = sdSphere(q, 0.3);
    g_node = nodeDist;
    g_nodeCell = cell;

    // IDEA 1: per-axis plucked displacement of the thread centre-line.
    let sp = domainSpacing;
    let segZ = cell + vec3<f32>(0.0, 0.0, select(0.0, -1.0, q.z < 0.0));
    let segX = cell + vec3<f32>(select(0.0, -1.0, q.x < 0.0), 0.0, 0.0);
    let segY = cell + vec3<f32>(0.0, select(0.0, -1.0, q.y < 0.0), 0.0);
    let dZ = pluck(q.z, sp, segZ, 3.1);
    let dX = pluck(q.x, sp, segX, 11.3);
    let dY = pluck(q.y, sp, segY, 23.7);

    // IDEA 2: plain-weave parity. Radius swells where a thread passes over its
    // crossing neighbours and thins where it passes under; cos(2*pi*s/sp) is
    // continuous across cell faces because parity flips with the cell.
    let par = cell.x + cell.y + cell.z;
    let pf = select(-1.0, 1.0, fract(par * 0.5) < 0.25);
    let swZ = pf * cos(6.2831853 * q.z / sp);
    let swX = -pf * cos(6.2831853 * q.x / sp);
    let swY = pf * cos(6.2831853 * q.y / sp);

    // IDEA 4: shuttle pick. Each weft row (x-family thread, fixed cell.y/z) carries
    // one shuttle per 3 lattice spans, thrown in +x at a hashed phase. ph = 0 at the
    // shuttle; small ph is the pick it has just laid behind it, which cools off.
    // The shuttle is a spindle: it also swells the weft thread it rides.
    let rowH = hash31(vec3<f32>(7.7, cell.y, cell.z));
    let shuttleRate = 0.12 + 0.18 * weaveSpeed;
    let ph = fract(rowH + g_time * shuttleRate - p.x / (3.0 * sp));
    let along = 3.0 * sp;
    let bead = exp(-min(ph, 1.0 - ph) * along * 5.0);
    let laid = exp(-ph * along * 0.9) * (1.0 - bead);
    g_shuttle = bead * 3.0 + laid * 0.6;

    // Cylinder axes: cylDistX runs along z, cylDistY along x, cylDistZ along y.
    let cylDistX = sdCylinder((warped_q + vec3<f32>(dZ.x, dZ.y, 0.0)).yzx, vec2<f32>(0.05 * (1.0 + 0.6 * swZ), sp));
    let cylDistY = sdCylinder((warped_q + vec3<f32>(0.0, dX.x, dX.y)).zxy, vec2<f32>(0.05 * (1.0 + 0.6 * swX) + 0.09 * bead, sp));
    let cylDistZ = sdCylinder((warped_q + vec3<f32>(dY.x, 0.0, dY.y)).xyz, vec2<f32>(0.05 * (1.0 + 0.6 * swY), sp));

    let threadDist = min(cylDistX, min(cylDistY, cylDistZ));


    // IDEA 3: gyro ring — tilted torus precessing about each node.
    let hN = hash31(cell + vec3<f32>(5.5, 1.3, 9.1));
    var rp = q;
    let ryz = rot(hN * 3.14159265) * vec2<f32>(rp.y, rp.z);
    rp = vec3<f32>(rp.x, ryz.x, ryz.y);
    let rxz = rot(g_time * (0.8 + hN) + hN * 6.2831853) * vec2<f32>(rp.x, rp.z);
    rp = vec3<f32>(rxz.x, rp.y, rxz.y);
    let ringDist = length(vec2<f32>(length(vec2<f32>(rp.x, rp.z)) - 0.36, rp.y)) - 0.022;

    let d = min(ringDist, min(nodeDist, threadDist));
    // mat_id: 0 node, 1/2/3 thread family (z/x/y, +0.5 when passing under), 4 ring
    var mat_id = 0.0;
    if (ringDist < nodeDist && ringDist < threadDist) {
        mat_id = 4.0;
    } else if (threadDist < nodeDist) {
        if (cylDistX <= cylDistY && cylDistX <= cylDistZ) {
            mat_id = 1.0 + select(0.0, 0.5, swZ < 0.0);
        } else if (cylDistY <= cylDistZ) {
            mat_id = 2.0 + select(0.0, 0.5, swX < 0.0);
        } else {
            mat_id = 3.0 + select(0.0, 0.5, swY < 0.0);
        }
    }

    return vec2<f32>(d * 0.6, mat_id);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let dims = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(dims.x) || pixel.y >= i32(dims.y)) { return; }

    let fragCoord = vec2<f32>(pixel);
    var uv = (fragCoord * 2.0 - dims) / dims.y;
    uv.y = -uv.y; // row 0 is the top of the canvas

    g_time = u.config.x;

    // Audio (plasmaBuffer only)
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    g_audio = bass * 0.5;

    // Audio transient burst — stateless per-pixel (was extraBuffer[133/134], which is
    // zeroed every upload and raced across threads). Fires on loud bass hits, 0..1.
    // It is a level, not a transient, so sustained bass held it at 2.0 and (with the
    // exposure term) whited out the frame; now it fires only above 0.45 and caps at 1.
    let burst = clamp((bass - 0.45) * 3.0, 0.0, 1.0);

    // Mouse: zoom_config.yz is 0–1 canvas uv with y=0 at the top; flip to y-up like uv.
    g_mouse = vec2<f32>(u.zoom_config.y * 2.0 - 1.0, 1.0 - u.zoom_config.z * 2.0);

    let weaveSpeed = u.zoom_params.y;

    // Audio-reactive color temperature: mids swing the loom cool→warm
    let tempMix = clamp(mids * 0.45, 0.0, 1.0);
    let coolTint = vec3<f32>(0.35, 0.7, 1.0);
    let warmTint = vec3<f32>(1.0, 0.55, 0.25);
    let tempTint = mix(coolTint, warmTint, tempMix);
    let threadTint = mix(vec3<f32>(1.0), tempTint, 0.5); // keep the three thread hues distinct

    // Starfield — smooth sinusoidal twinkle (no per-frame hash strobing)
    var starCol = vec3<f32>(0.0);
    let star_uv = uv + g_mouse * 0.1;
    for (var i = 1; i <= 3; i++) {
        let fi = f32(i);
        let cellId = floor(star_uv * 100.0 / fi);
        let s = hash31(vec3<f32>(cellId, fi));
        if (s > 0.98) {
            let twinkle = 0.65 + 0.35 * sin(g_time * (1.5 + fi) + s * 40.0);
            starCol += vec3<f32>(s) * (1.0 - fi * 0.2) * twinkle * (1.0 + treble * 0.6);
        }
    }

    // Camera — warp-flight: forward speed rides the Weave Speed slider so the
    // whole loom rushes past; lateral sway keeps the organic drift.
    let flightSpeed = 1.2 + weaveSpeed * 1.6;
    var ro = vec3<f32>(0.0, 0.0, -5.0 + g_time * flightSpeed);
    ro.x += sin(g_time * 0.35) * 1.0;
    ro.y += cos(g_time * 0.42) * 1.0;

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
    var nodeTrap = 1e3;
    var trapCell = vec3<f32>(0.0);

    for (var i = 0; i < 80; i++) {
        let p = ro + rd * t;
        let res = map(p);
        d = res.x;

        let curGlow = 0.05 / (0.01 + abs(d));
        glow += curGlow;

        let mat_id = res.y;
        // IDEA 5: orbit trap over the march — closest knot the ray grazed.
        if (g_node < nodeTrap) { nodeTrap = g_node; trapCell = g_nodeCell; }
        if (mat_id == 0.0) {
            // IDEA 5: the knot's glow takes its star's spectral colour (HEAD: flat blue).
            let knotHue = mix(vec3<f32>(0.1, 0.3, 0.8) * tempTint, starColour(g_nodeCell) * 0.22, 0.75);
            colorAccum += knotHue * curGlow * plasmaGlow * 0.02 * (1.0 + bass + burst);
        } else if (mat_id >= 4.0) {
            // IDEA 3: gyro ring, pale cyan-white
            colorAccum += vec3<f32>(0.6, 0.85, 1.0) * tempTint * curGlow * plasmaGlow * 0.02 * (1.0 + bass + burst);
        } else {
            // IDEA 2: warp/weft hue by axis family; under-passing segments dimmer
            let fam = i32(floor(mat_id));
            var hue = vec3<f32>(0.5, 0.2, 0.9);   // z: violet (original thread colour)
            if (fam == 2) { hue = vec3<f32>(0.9, 0.5, 0.12); }  // x: amber
            if (fam == 3) { hue = vec3<f32>(0.1, 0.7, 0.5); }   // y: teal
            let shade = select(1.0, 0.55, fract(mat_id) > 0.25);
            colorAccum += hue * threadTint * shade * curGlow * plasmaGlow * 0.015 * (1.0 + bass * 1.5 + burst * 1.5);
            // IDEA 4: the shuttle and its freshly laid pick ride the amber weft only.
            if (fam == 2) {
                colorAccum += vec3<f32>(1.0, 0.82, 0.45) * g_shuttle * curGlow * plasmaGlow * 0.02 * (1.0 + bass);
            }
        }

        if (d < 0.001 || t > maxT) { break; }
        t += d;
    }

    colorAccum += vec3<f32>(1.0, 0.4, 0.2) * g_audio * glow * 0.005 * (1.0 + burst);

    // IDEA 5: stellar-class knots. Each knot hashes a surface temperature, skewed
    // toward cool K/M stars with rare hot O/B ones, and shines through the trap.
    // The trap's minimum gives the corona of the knot the ray grazed most closely.
    let knot = exp(-max(nodeTrap, 0.0) * 14.0);
    colorAccum += starColour(trapCell) * knot * plasmaGlow * 0.05 * (1.0 + bass * 0.6 + burst * 0.5);

    var col = colorAccum + starCol * exp(-t * 0.1);

    // ── Warp speed streaks: radial speed-lines along flight direction ──
    // Stretched along the radial (motion) direction, rushing inward — smooth
    // noise only, temporally coherent at any speed.
    let r = max(length(uv), 0.001);
    let ang = atan2(uv.y, uv.x);
    let streakPhase = 1.6 / (r + 0.15) - g_time * (2.5 + weaveSpeed * 3.5);
    let streakN = noise3(vec3<f32>(ang * 9.0, streakPhase, g_time * 0.35));
    let streaks = smoothstep(0.60, 0.95, streakN) * exp(-r * 0.9);
    col += tempTint * streaks * (0.35 + bass * 0.4 + burst * 1.2);

    // ── HDR velocity feedback trails (dataTextureC → dataTextureA) ────
    // The warp flight smears luminous threads into light-trails. History is
    // clamped to HDR_CLAMP so speed can never blow up the feedback loop.
    let prev = textureLoad(dataTextureC, pixel, 0);
    let trailDecay = 0.82 + clamp(weaveSpeed, 0.0, 3.0) * 0.04; // faster weave → longer streaks
    let history = min(prev.rgb * trailDecay, vec3<f32>(HDR_CLAMP));
    // Trails only where history is brighter than the new frame: col + prev was a
    // 1/(1-decay) ≈ 7x feedback gain that pinned every pixel at HDR_CLAMP (white page).
    var hdr = col + 0.35 * max(history - col, vec3<f32>(0.0));
    hdr = min(hdr, vec3<f32>(HDR_CLAMP));

    // Real generated depth (raymarch travel distance, normalized)
    let depthOut = clamp(t / maxT, 0.0, 1.0);
    textureStore(dataTextureA, pixel, vec4<f32>(hdr, depthOut));

    // ── ACES tone map (linear HDR workflow, exposure rides audio) ─────
    let exposure = 1.05 + plasmaGlow * 0.06 + mids * 0.2 + burst * 0.25;
    let outCol = acesToneMap(hdr * exposure);

    // Semantic alpha: an opaque void (0.85) that threads push to 1, shaped by
    // the Thread Opacity slider. A bare intensity alpha left the void ~0 and
    // the page showed through as a wash.
    let intensity = luma(outCol);
    let threadOpacityExp = max(u.zoom_params.w, 0.25);
    let alpha = 0.85 + 0.15 * pow(clamp(intensity * 1.8, 0.0, 1.0), threadOpacityExp);

    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(writeTexture, pixel, vec4<f32>(outCol, alpha));
}
