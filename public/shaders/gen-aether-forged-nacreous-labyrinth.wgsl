// ═══════════════════════════════════════════════════════════════════
//  Aether-Forged Nacreous Labyrinth
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-18
//  Ideas: nacre film thickness read from the gyroid level-set (colour follows the membrane); periodic KIFS polytypes (z-wrapped lattice, per-cell hash into the fold angle); labyrinth breathing (gyroid bias driven by a slow sine + mids);
//         fold count as material (§12.2E: few-mirror facets polished, deep-folded facets frosted); aragonite tablet mosaic (per-tablet film thickness + matte organic seams on the nacre)
//  A packing: ACES display RGBA (0.8 temporal blend with exact dataTextureC history)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: .x = Crystal Sharpness, .y = Flow Speed, .z = Aether Density, .w = Iridescence Shift

const PI: f32 = 3.14159265359;

// Rotation matrix
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Smooth min
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// 3D hash
fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                      dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                      dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(q) * 43758.5453) * 2.0 - 1.0;
}

// Simplex/Gradient Noise (simplified)
fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 0.0)), f - vec3<f32>(0.0, 0.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 0.0)), f - vec3<f32>(1.0, 0.0, 0.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 0.0)), f - vec3<f32>(0.0, 1.0, 0.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 0.0)), f - vec3<f32>(1.0, 1.0, 0.0)), u.x), u.y),
        mix(mix(dot(hash3(i + vec3<f32>(0.0, 0.0, 1.0)), f - vec3<f32>(0.0, 0.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 0.0, 1.0)), f - vec3<f32>(1.0, 0.0, 1.0)), u.x),
            mix(dot(hash3(i + vec3<f32>(0.0, 1.0, 1.0)), f - vec3<f32>(0.0, 1.0, 1.0)),
                dot(hash3(i + vec3<f32>(1.0, 1.0, 1.0)), f - vec3<f32>(1.0, 1.0, 1.0)), u.x), u.y), u.z);
}

// Curl noise
fn curlNoise(p: vec3<f32>) -> vec3<f32> {
    let e = 0.05;
    let dx = vec3<f32>(e, 0.0, 0.0);
    let dy = vec3<f32>(0.0, e, 0.0);
    let dz = vec3<f32>(0.0, 0.0, e);

    let x = noise(p + dy) - noise(p - dy) - (noise(p + dz) - noise(p - dz));
    let y = noise(p + dz) - noise(p - dz) - (noise(p + dx) - noise(p - dx));
    let z = noise(p + dx) - noise(p - dx) - (noise(p + dy) - noise(p - dy));

    return vec3<f32>(x, y, z) / (2.0 * e);
}

// fBM
fn fbm(p: vec3<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec3<f32>(100.0);
    var pos = p;
    for (var i = 0; i < 4; i++) {
        v += a * noise(pos);
        pos = pos * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Cosine palette for iridescence
fn pal(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(2.0 * PI * (c * t + d));
}

// Gyroid
fn sdGyroid(p: vec3<f32>, scale: f32, thickness: f32, bias: f32) -> f32 {
    let p_scaled = p * scale;
    return abs(dot(sin(p_scaled), cos(p_scaled.zxy)) + bias) / scale - thickness;
}

// KIFS fractal lattice. Returns (distance, fold count).
fn sdKIFSFolds(p: vec3<f32>, sharp: f32, polytype: f32) -> vec2<f32> {
    var q = p;
    let s = 1.2;
    var d = 1000.0;
    var folds = 0.0;
    for(var i = 0; i < 4; i++) {
        // ── Idea 4: fold count as material (§12.2E) — every abs() mirror a point
        // passes through is counted; each kaleidoscope facet gets its own count.
        folds += dot(vec3<f32>(1.0), step(q, vec3<f32>(0.0)));
        q = abs(q) - vec3<f32>(0.5, 0.5, 0.5) * sharp;

        let rot1 = rot(PI / 4.0 + 0.1 * f32(i));
        let qxy = rot1 * q.xy;
        q = vec3<f32>(qxy.x, qxy.y, q.z);

        let rot2 = rot(PI / 3.0 + polytype * 0.6); // Idea 2: per-cell polytype bends the fold angle
        let qxz = rot2 * vec2<f32>(q.x, q.z);
        q = vec3<f32>(qxz.x, q.y, qxz.y);

        q *= s;
        d = min(d, length(max(abs(q) - 0.2, vec3<f32>(0.0))) / pow(s, f32(i+1)));
    }
    return vec2<f32>(d, folds);
}


// Idea 2: periodic KIFS polytypes. The lattice used to drift past the camera at
// z = -0.5*t*flow; wrap z with period L and hash each cell into its fold angle.
// min() of the two nearest copies keeps the field continuous across cell faces.
fn kifsHash(c: f32) -> f32 {
    return fract(sin(c * 12.9898 + 4.1414) * 43758.5453) - 0.5;
}

fn sdKIFSPeriodicFolds(p: vec3<f32>, sharp: f32) -> vec2<f32> {
    let L = 4.0;
    let g = p.z / L + 0.5;
    let c0 = floor(g);
    let f = fract(g) - 0.5;
    let sgn = select(-1.0, 1.0, f >= 0.0);
    let c1 = c0 + sgn;
    let d0 = sdKIFSFolds(vec3<f32>(p.x, p.y, f * L), sharp, kifsHash(c0));
    let d1 = sdKIFSFolds(vec3<f32>(p.x, p.y, (f - sgn) * L), sharp, kifsHash(c1));
    return select(d1, d0, d0.x <= d1.x);
}

// Spatial distortion based on mouse
fn applyGravityWell(p: vec3<f32>, ro: vec3<f32>) -> vec3<f32> {
    if (u.zoom_config.w <= 0.5) {
        return p;
    }

    // Map mouse UV to world space approx
    let mouse_uv = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let ndc = (mouse_uv * 2.0 - 1.0) * vec2<f32>(u.config.z / u.config.w, -1.0);

    // Construct ray direction for mouse (simplified)
    let cd = normalize(vec3<f32>(0.0, 0.0, 1.0));
    let cu = normalize(vec3<f32>(0.0, 1.0, 0.0));
    let cr = normalize(cross(cd, cu));
    let m_rd = normalize(ndc.x * cr + ndc.y * cu + 2.0 * cd);

    // Assume mouse intersects a plane at z = 3.0
    let t = (3.0 - ro.z) / m_rd.z;
    let gravity_center = ro + m_rd * t;

    let d = length(p - gravity_center);
    let pull = 1.0 / (1.0 + d * d * 0.5);

    var q = p;
    // Radial contraction
    q = mix(q, gravity_center, pull * 0.5);

    // Twist
    let twist = pull * 2.0;
    let r = rot(twist);
    let qxy = r * (q.xy - gravity_center.xy);
    q = vec3<f32>(qxy.x + gravity_center.xy.x, qxy.y + gravity_center.xy.y, q.z);

    return q;
}

// Lattice space: gravity well + flow drift (shared by map and the shading pass)
fn flowSpace(pos_in: vec3<f32>, ro: vec3<f32>) -> vec3<f32> {
    let flowSpeed = u.zoom_params.y; // Flow Speed
    let flowOffset = vec3<f32>(0.0, 0.0, u.config.x * 0.5 * flowSpeed);
    return applyGravityWell(pos_in, ro) + flowOffset;
}

// Membrane space: lattice space deformed with curl noise
fn orgSpace(p: vec3<f32>) -> vec3<f32> {
    let aetherDen = u.zoom_params.z; // Aether Density
    let curl = curlNoise(p * 0.5 + u.config.x * 0.2);
    return p + curl * 0.2 * aetherDen;
}

// Scene SDF: (distance, material, nacre film, KIFS fold count)
fn map(pos_in: vec3<f32>, ro: vec3<f32>, audio: f32) -> vec4<f32> {
    let p = flowSpace(pos_in, ro);

    let time = u.config.x;
    let sharp = u.zoom_params.x;     // Crystal Sharpness

    let p_org = orgSpace(p);

    // Organic Labyrinth (Gyroid + fBM)
    // Idea 3: labyrinth breathing - the hard-wired bias=0 level-set now swells and
    // shrinks the passages (slow sine) and opens further with mids.
    let mids = plasmaBuffer[0].y;
    let bias = 0.22 * sin(time * 0.35) + mids * 0.2;
    let d_org = sdGyroid(p_org, 2.0, 0.05 + audio * 0.05, bias) + fbm(p_org * 4.0) * 0.05;

    // Rigid KIFS Lattice (Idea 2: periodic polytypes)
    let kifs = sdKIFSPeriodicFolds(p, sharp);
    let d_kifs = kifs.x;

    // Blend
    let d_final = smin(d_org, d_kifs, 0.2);

    // Material ID: 0.0 for organic, 1.0 for crystal
    let mat = smoothstep(0.0, 0.1, d_org - d_kifs);

    // Idea 1: nacre film thickness = signed gyroid level-set (which face of the
    // membrane) + a lower-frequency gyroid harmonic, so colour bands follow the sheet.
    let ps = p_org * 2.0;
    let pl = p_org * 0.8;
    let film = (dot(sin(ps), cos(ps.zxy)) + bias) * 2.0 + dot(sin(pl), cos(pl.zxy)) * 0.5;

    return vec4<f32>(d_final, mat, film, kifs.y);
}

// ── Idea 5 helper: aragonite tablet mosaic. Real nacre is brick-and-mortar —
// polygonal aragonite tablets glued by thin organic seams. 3-D Voronoi in membrane
// space: returns (seam proximity 0..1, per-tablet hash -0.5..0.5).
fn nacreTablets(p: vec3<f32>) -> vec2<f32> {
    let i = floor(p);
    let f = fract(p);
    var f1 = 8.0;
    var f2 = 8.0;
    var id = 0.0;
    for (var z = -1; z <= 1; z++) {
        for (var y = -1; y <= 1; y++) {
            for (var x = -1; x <= 1; x++) {
                let o = vec3<f32>(f32(x), f32(y), f32(z));
                let h = hash3(i + o);
                let r = o + 0.5 + 0.4 * h - f;
                let dd = dot(r, r);
                let closer = dd < f1;
                f2 = select(min(f2, dd), f1, closer);
                id = select(id, h.x, closer);
                f1 = min(f1, dd);
            }
        }
    }
    let gap = sqrt(f2) - sqrt(f1);
    return vec2<f32>(1.0 - smoothstep(0.03, 0.12, gap), id * 0.5);
}

// Normal calculation
fn calcNormal(p: vec3<f32>, ro: vec3<f32>, audio: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let d = map(p, ro, audio).x;
    let n = vec3<f32>(
        map(p + e.xyy, ro, audio).x - d,
        map(p + e.yxy, ro, audio).x - d,
        map(p + e.yyx, ro, audio).x - d
    );
    return normalize(n);
}

// Fake Subsurface Scattering (Soft Shadow / Blur)
fn calcSSS(p: vec3<f32>, ro: vec3<f32>, n: vec3<f32>, l: vec3<f32>, audio: f32) -> f32 {
    var occ = 0.0;
    var sca = 1.0;
    for(var i = 0; i < 5; i++) {
        let hr = 0.01 + 0.12 * f32(i) / 4.0;
        let aopos = n * hr + p;
        let dd = map(aopos, ro, audio).x;
        occ += -(dd - hr) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(dims.x) || coord.y >= i32(dims.y)) { return; }

    let resolution = vec2<f32>(f32(dims.x), f32(dims.y));
    var uv = (vec2<f32>(coord) - 0.5 * resolution) / resolution.y;
    uv.y = -uv.y;

    // Audio extraction
    let bass = plasmaBuffer[0].x;
    let fft_mid = plasmaBuffer[0].y;

    // Ray setup
    let ro = vec3<f32>(0.0, 0.0, -3.0);
    let rd = normalize(vec3<f32>(uv, 2.0));

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var mat_id = 0.0;
    var film = 0.0;
    var folds = 0.0;
    let max_steps = 100;
    let max_dist = 20.0;

    var p = ro;
    var steps = 0;

    for (var i = 0; i < max_steps; i++) {
        steps = i;
        p = ro + rd * t;
        let res = map(p, ro, bass);
        d = res.x;
        mat_id = res.y;
        film = res.z;
        folds = res.w;
        if (d < 0.001 || t > max_dist) { break; }
        t += d;
    }

    var col = vec3<f32>(0.0);
    var depth = 1.0;

    // Real hit flag: step-exhausted rays far from a surface are sky, not hits.
    let hit = d < 0.01 && t < max_dist;

    if (hit) {
        let n = calcNormal(p, ro, bass);
        let v = -rd;
        let l = normalize(vec3<f32>(1.0, 2.0, -2.0));
        let h = normalize(v + l);

        let ndotv = max(dot(n, v), 0.0);
        let ndotl = max(dot(n, l), 0.0);
        let ndoth = max(dot(n, h), 0.0);

        // Material parameters
        let iridescenceShift = u.zoom_params.w;

        // Base Ambient/SSS
        let sss = calcSSS(p, ro, n, l, bass);

        if (mat_id < 0.5) {
            // Organic Nacreous
            // ── Idea 5: aragonite tablet mosaic — each tablet is a slightly different
            // film thickness (shifts its interference colour); the organic seams between
            // them are matte and dark, so the pearl reads as tiled at close range.
            let po = orgSpace(flowSpace(p, ro));
            let tab = nacreTablets(po * 16.0);
            let tabFade = 1.0 - smoothstep(3.0, 8.0, t);
            let iridescence_t = ndotv + iridescenceShift + p.z * 0.1 + film * 0.5 + tab.y * 0.35 * tabFade; // Idea 1
            let iri_col = pal(iridescence_t, vec3<f32>(0.5,0.5,0.5), vec3<f32>(0.5,0.5,0.5), vec3<f32>(1.0,1.0,1.0), vec3<f32>(0.0,0.33,0.67));

            let diffuse = ndotl * iri_col;
            let seam = tab.x * tabFade;
            let specular = pow(ndoth, 16.0) * vec3<f32>(1.0) * (1.0 - seam * 0.8);

            col = (diffuse * 0.8 + specular * 0.5 + iri_col * sss * 0.5) * (1.0 - seam * 0.45);

            // Bioluminescent glow from audio
            col += iri_col * fft_mid * 2.0 * sss;

        } else {
            // Rigid Crystalline
            let metallic_col = vec3<f32>(0.7, 0.8, 0.9);
            // ── Idea 4: fold count as material — facets reached through few mirrors are
            // polished (tight, bright highlight); deeply folded facets are frosted (broad,
            // dimmer highlight, more diffuse). Median count lands near the old exponent (64).
            let fm = clamp((folds - 3.5) / 4.5, 0.0, 1.0); // counts span ~5..8 of 12
            let specExp = mix(128.0, 20.0, fm);
            let diffuse = ndotl * metallic_col * mix(0.1, 0.32, fm);
            let specular = pow(ndoth, specExp) * vec3<f32>(1.0, 1.0, 1.0) * mix(1.3, 0.55, fm);

            // Chromatic aberration at grazing angles
            let fresnel = pow(clamp(1.0 - ndotv, 0.0, 1.0), 5.0);
            let chromExp = specExp * 0.5;
            let r = pow(ndoth, chromExp);
            let g = pow(max(dot(n, normalize(l + vec3<f32>(0.1, 0.0, 0.0))), 0.0), chromExp);
            let b = pow(max(dot(n, normalize(l + vec3<f32>(-0.1, 0.0, 0.0))), 0.0), chromExp);
            let chromatic = vec3<f32>(r, g, b);

            col = diffuse + specular + fresnel * metallic_col + chromatic * 0.5;
        }

        // Fake AO based on steps
        col *= 1.0 - f32(steps) / f32(max_steps);

        // Fog
        col = mix(col, vec3<f32>(0.05, 0.12, 0.25), 1.0 - exp(-0.05 * t * t));
        depth = t / max_dist;
    } else {
        // Aether Background
        let bg_dir = rd;
        let bg_noise = max(fbm(bg_dir * 10.0 + u.config.x * 0.1), 0.0);
        col = vec3<f32>(0.05, 0.12, 0.25) * bg_noise * (1.0 + bass);
    }

    // ACES on display RGB (replaces Reinhard + gamma); clamp so no NaN reaches the history blend
    col = acesToneMap(max(col, vec3<f32>(0.0)) * 1.6);

    let current_frame = vec4<f32>(col, select(0.4, 1.0, hit));

    // Temporal blending (history)
    let history_coord = vec2<i32>(coord);
    let history = clamp(textureLoad(dataTextureC, history_coord, 0), vec4<f32>(0.0), vec4<f32>(1.0));
    let blend_factor = 0.8;
    let final_color = mix(current_frame, history, blend_factor);

    textureStore(writeTexture, coord, final_color);
    textureStore(dataTextureA, coord, final_color);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
