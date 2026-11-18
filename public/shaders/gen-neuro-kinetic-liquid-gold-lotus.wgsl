// ═══════════════════════════════════════════════════════════════════
//  Neuro-Kinetic Liquid-Gold Lotus
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14, 2026-11-18
//  Ideas: conductor Fresnel on liquid gold (spectral F0 tint at normal, white at grazing); golden-angle phyllotaxis stamen florets firing in spiral order on the core; capillary rivulets running down petal blades as brighter gold channels; Kelvin-Helmholtz shear rolls modulating plasma runners along torque-driven petal flow; mirror-gold reflection with petal inter-reflection (double-bounce F0^2 + studio env through the conductor Fresnel); anisotropic Kajiya-Kay vein highlight along the petal radial tangent
//  Rescues 2026-11-18: camera aimed at the bloom (was horizontal + upside-down, lotus cropped at the top); petal domain repetition (eight blades, not a blob); plasma overlay no longer extrapolates into negative ACES input
//  A packing: ACES display RGBA in A (rgb = max(ACES(frame), torque-advected C history * decay), a = semantic coverage)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Bloom Radius, y=Plasma Intensity, z=Gold Smoothness, w=Mouse Influence

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

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// 3D Noise for fluid/plasma
fn hash(p: vec3<f32>) -> vec3<f32> {
    var p_temp = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                           dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                           dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return fract(sin(p_temp) * 43758.5453123) * 2.0 - vec3<f32>(1.0);
}

fn noise(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - vec3<f32>(2.0) * f);
    return mix(mix(mix(dot(hash(i + vec3<f32>(0.0,0.0,0.0)), f - vec3<f32>(0.0,0.0,0.0)),
                       dot(hash(i + vec3<f32>(1.0,0.0,0.0)), f - vec3<f32>(1.0,0.0,0.0)), u.x),
                   mix(dot(hash(i + vec3<f32>(0.0,1.0,0.0)), f - vec3<f32>(0.0,1.0,0.0)),
                       dot(hash(i + vec3<f32>(1.0,1.0,0.0)), f - vec3<f32>(1.0,1.0,0.0)), u.x), u.y),
               mix(mix(dot(hash(i + vec3<f32>(0.0,0.0,1.0)), f - vec3<f32>(0.0,0.0,1.0)),
                       dot(hash(i + vec3<f32>(1.0,0.0,1.0)), f - vec3<f32>(1.0,0.0,1.0)), u.x),
                   mix(dot(hash(i + vec3<f32>(0.0,1.0,1.0)), f - vec3<f32>(0.0,1.0,1.0)),
                       dot(hash(i + vec3<f32>(1.0,1.0,1.0)), f - vec3<f32>(1.0,1.0,1.0)), u.x), u.y), u.z);
}

fn fbm(p: vec3<f32>) -> f32 {
    var f = 0.0;
    var w = 0.5;
    var pp = p;
    for(var i=0; i<4; i++) {
        f += w * noise(pp);
        pp *= 2.0;
        w *= 0.5;
    }
    return f;
}

fn opSmoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(d2 - d1)/k, 0.0, 1.0);
    return mix(d2, d1, h) - k*h*(1.0-h);
}

fn sdSphere(p: vec3<f32>, s: f32) -> f32 {
    return length(p) - s;
}

fn sdLotusPetals(p: vec3<f32>, time: f32, bloom: f32, torque: f32) -> f32 {
    // ── Rescue 2: petal domain repetition ──
    // HEAD rotated the UNtwisted p by +a_mod (sector centre landed at 2*a_mod, not 0), used the
    // twisted point only to pick the sector id and never offset the petal radially, so the eight
    // petals collapsed into one blob round the axis. Now: rotate the torque-twisted q by -a_mod
    // (sector centre -> +z), stand each petal off the core as an ellipsoid blade. The HEAD twin
    // lobe (abs(x) - c), bowl lift (0.5 r^2 - bloom/2) and fbm liquid perturbation are kept.
    let num_petals = 8.0;
    let r = length(p.xz);
    let torqueWave = sin(r * 7.0 - time * 11.0) * torque * (0.15 + r * 0.08);
    let q = rotY(torqueWave) * p;
    let angle = atan2(q.x, q.z);

    // Domain repetition
    let a = angle * num_petals / (2.0 * 3.14159265);
    let id = floor(a);
    let a_mod = (id + 0.5) * (2.0 * 3.14159265) / num_petals;
    let c = cos(a_mod);
    let s = sin(a_mod);
    var p_w = vec3<f32>(q.x * c - q.z * s, q.y, q.x * s + q.z * c);

    // Petal shape
    p_w.x = abs(p_w.x) - 0.06;
    p_w.y -= 0.5 * r * r - bloom * 0.5;
    p_w.z -= 0.85;

    let rad = vec3<f32>(0.2, 0.3, 0.55);
    let k0 = length(p_w / rad);
    let k1 = length(p_w / (rad * rad));
    let base = k0 * (k0 - 1.0) / max(k1, 1e-4);

    // Add liquid perturbation
    let n = fbm(p * 2.0 + vec3<f32>(0.0, time * 0.5, 0.0)) * 0.1;

    return base + n;
}

fn map(p: vec3<f32>, time: f32, audio_val: f32, bloom: f32, torque: f32) -> f32 {
    let core = sdSphere(p, 0.5 + audio_val * 0.3) + fbm(p * 3.0 - vec3<f32>(0.0, time, 0.0)) * 0.2;
    let petals = sdLotusPetals(p, time, bloom, torque);
    return opSmoothUnion(core, petals, 0.4);
}

// Native idea 1: Fresnel for a conductor. Gold's complex IOR gives a strongly
// tinted normal-incidence reflectance (F0) that desaturates toward white at grazing.
fn goldConductorFresnel(cosTheta: f32) -> vec3<f32> {
    let f0 = vec3<f32>(1.0, 0.71, 0.29);
    let m = pow(1.0 - clamp(cosTheta, 0.0, 1.0), 5.0);
    return f0 + (vec3<f32>(1.0) - f0) * m;
}

// Native idea 2: golden-angle (137.5 deg) Vogel phyllotaxis florets over the core,
// seen from above. Returns (floret proximity, floret index 0..1).
fn phyllotaxisFlorets(p: vec3<f32>) -> vec2<f32> {
    let golden = 2.39996323;
    let spread = 0.075;
    let r = length(p.xz);
    let kEst = (r / spread) * (r / spread);
    let k0 = i32(floor(kEst));
    var best = 1e5;
    var bestK = 0.0;
    for (var o = -21; o <= 21; o++) {
        let k = f32(max(k0 + o, 0));
        let rk = spread * sqrt(k);
        let ak = k * golden;
        let c = vec2<f32>(cos(ak), sin(ak)) * rk;
        let dd = length(p.xz - c);
        if (dd < best) { best = dd; bestK = k; }
    }
    let prox = exp(-best * best * 900.0);
    return vec2<f32>(prox, bestK / 60.0);
}

// Idea 1 helper: a tiny studio for the gold to mirror — dark warm floor, warm horizon glow, a cool
// dim fill (echoes the scene background) and a key softbox along the existing light direction.
// `sharp` = gold smoothness: rough gold smears the softbox into a wide sheen.
fn goldStudioEnv(r: vec3<f32>, sharp: f32) -> vec3<f32> {
    let key = normalize(vec3<f32>(1.0, 2.0, -1.0));
    let kd = max(dot(r, key), 0.0);
    let softbox = smoothstep(mix(0.45, 0.86, sharp), mix(0.92, 0.97, sharp), kd) * 2.4;
    let upv = clamp(r.y, -1.0, 1.0);
    let skyCol = mix(vec3<f32>(0.07, 0.06, 0.05), vec3<f32>(0.03, 0.05, 0.11), smoothstep(0.0, 0.8, upv));
    let floorCol = vec3<f32>(0.05, 0.035, 0.02);
    let horizon = exp(-abs(upv) * 5.0) * 0.55;
    return mix(floorCol, skyCol, smoothstep(-0.12, 0.12, upv)) + vec3<f32>(1.0, 0.78, 0.5) * (horizon + softbox);
}

fn getNormal(p: vec3<f32>, time: f32, audio_val: f32, bloom: f32, torque: f32) -> vec3<f32> {
    let e = vec2<f32>(0.01, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, audio_val, bloom, torque) - map(p - e.xyy, time, audio_val, bloom, torque),
        map(p + e.yxy, time, audio_val, bloom, torque) - map(p - e.yxy, time, audio_val, bloom, torque),
        map(p + e.yyx, time, audio_val, bloom, torque) - map(p - e.yyx, time, audio_val, bloom, torque)
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let res = vec2<f32>(textureDimensions(writeTexture));
    let fragCoord = vec2<f32>(f32(id.x), f32(id.y));
    if (fragCoord.x >= res.x || fragCoord.y >= res.y) { return; }

    let uv = (fragCoord - 0.5 * res) / res.y;
    let time = u.config.x;
    let audioBands = clamp(vec3<f32>(plasmaBuffer[0].x, plasmaBuffer[0].y, plasmaBuffer[0].z), vec3<f32>(0.0), vec3<f32>(1.0));

    let bloom_radius = u.zoom_params.x;
    let plasma_int = u.zoom_params.y;
    let gold_smooth = u.zoom_params.z;
    let mouseInfluence = u.zoom_params.w;
    let audio_val = audioBands.x * plasma_int;
    let mouseDown = u.zoom_config.w > 0.5;

    // Persistent cursor spring: [133..134] position, [135..136] velocity,
    // [137] held-gravity envelope, [138] initialization flag.
    // Rescue 4: a negative "pointer inactive" sentinel would rotate the camera by ~3 rad.
    let pointerRaw = select(u.zoom_config.yz, vec2<f32>(0.5), u.zoom_config.y < 0.0);
    var springPos = pointerRaw;
    var springVel = vec2<f32>(0.0);
    var heldGravity = select(0.0, 1.0, mouseDown);
    if (arrayLength(&extraBuffer) > 138u) {
        if (extraBuffer[138] > 0.5) {
            springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
            springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
            heldGravity = extraBuffer[137];
        }
    }
    let springOmega = mix(7.0, 15.0, mouseInfluence);
    let springAccel = springOmega * springOmega * (pointerRaw - springPos) - 2.0 * springOmega * springVel;
    let nextSpringVel = springVel + springAccel * 0.016;
    let nextSpringPos = springPos + nextSpringVel * 0.016;
    let nextHeldGravity = mix(heldGravity, select(0.0, 1.0, mouseDown), 0.14);
    if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = nextSpringPos.x;
        extraBuffer[134] = nextSpringPos.y;
        extraBuffer[135] = nextSpringVel.x;
        extraBuffer[136] = nextSpringVel.y;
        extraBuffer[137] = nextHeldGravity;
        extraBuffer[138] = 1.0;
    }

    let pressKick = 0.35 * mouseInfluence * nextHeldGravity;
    let torque = 0.25 + audioBands.y * 0.35 + pressKick;

    // Mouse Interaction: Bending ray direction
    let mx = (nextSpringPos.x - 0.5) * 2.0;
    let my = (nextSpringPos.y - 0.5) * 2.0;

    // Click wells pull in proportion to each ripple's recorded strength;
    // holding the pointer deepens the sprung well without creating new state.
    let screenAspect = res.x / max(res.y, 1.0);
    let pointerWell = (nextSpringPos - 0.5) * vec2<f32>(screenAspect, 1.0);
    var gravityAim = pointerWell;
    var gravityWeight = 0.25 + nextHeldGravity * mouseInfluence * 1.4;
    let gravityRippleCount = min(u32(u.config.y), 50u);
    for (var gi = 0u; gi < gravityRippleCount; gi++) {
        let ripple = u.ripples[gi];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.0) { continue; }
        // ripple.w is engine padding (always 0), so every live click pulls at full strength.
        let rippleStrength = exp(-age * 1.6);
        let rippleWell = (ripple.xy - 0.5) * vec2<f32>(screenAspect, 1.0);
        gravityAim = (gravityAim * gravityWeight + rippleWell * rippleStrength) / max(gravityWeight + rippleStrength, 0.001);
        gravityWeight += rippleStrength;
    }

    // ── Rescue 1: camera aimed at the bloom ──
    // HEAD looked horizontally along +z (the lotus sat 22 deg below the axis) and used uv.y (screen
    // down) as world-up, so the lotus was upside-down and cropped in the top 30 % of the frame.
    let ro = vec3<f32>(0.0, 2.0, -5.0);
    let camFwd = normalize(vec3<f32>(0.0, -0.05, 0.0) - ro);
    let camRight = vec3<f32>(1.0, 0.0, 0.0);
    let camUp = cross(camFwd, camRight);
    var rd = normalize(camFwd + camRight * uv.x - camUp * uv.y);
    // World-up is screen-up now, so the pointer/click wells (screen-down-positive) flip y.
    let wellWorld = vec2<f32>(gravityAim.x, -gravityAim.y);

    // Apply mouse rotation
    rd = rotX(my * 1.5 * mouseInfluence) * rd;
    rd = rotY(-mx * 1.5 * mouseInfluence) * rd;
    var ro_rot = rotX(my * 1.5 * mouseInfluence) * ro;
    ro_rot = rotY(-mx * 1.5 * mouseInfluence) * ro_rot;

    // Raymarching
    var t = 0.0;
    var p = ro_rot;
    var d = 0.0;
    var hit = false;

    for(var i=0; i<80; i++) {
        p = ro_rot + rd * t;
        // Gravity well distortion near center
        let toWell = wellWorld - p.xy;
        let bend = exp(-dot(toWell, toWell) * 0.55) * (0.08 + min(gravityWeight, 2.5) * 0.11);
        p += vec3<f32>(toWell * bend, 0.0);

        d = map(p, time, audio_val, bloom_radius, torque);
        if(d < 0.001) { hit = true; break; }
        if(t > 20.0) { break; }
        t += max(d * 0.8, 0.001);
    }

    var col = vec3<f32>(0.02, 0.02, 0.05); // Background

    if (hit) {
        let n = getNormal(p, time, audio_val, bloom_radius, torque);
        let l = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let v = normalize(ro_rot - p);
        let h = normalize(l + v);

        // Base liquid-gold color
        let base_gold = vec3<f32>(1.0, 0.7, 0.2);

        // Lighting
        let diff = max(dot(n, l), 0.0);
        let spec = pow(max(dot(n, h), 0.0), mix(8.0, 96.0, gold_smooth));
        let fresnel = goldConductorFresnel(max(dot(n, v), 0.0));
        let rim = pow(1.0 - max(dot(n, v), 0.0), 3.0);

        // Plasma veins logic using fbm
        let vein_noise = fbm(p * 5.0 + vec3<f32>(time * 4.0));
        let runner = pow(max(0.0, sin(atan2(p.z, p.x) * 8.0 + length(p.xz) * 12.0 - time * 22.0)), 10.0);
        // IDEA 4: shear-roll packets ride the torque field and modulate runners.
        let shearRoll = pow(0.5 + 0.5 * sin(p.y * 20.0 - atan2(p.z, p.x) * 7.0 - time * (8.0 + audioBands.y * 5.0)), 4.0);
        let plasma_factor = clamp((smoothstep(0.4, 0.6, vein_noise) * (0.2 + audio_val) + runner * (0.15 + audioBands.z) + shearRoll * (0.12 + audioBands.y * 0.1)) * plasma_int, 0.0, 2.5);
        let plasma_col = vec3<f32>(0.0, 1.0, 1.0) * plasma_factor; // Cyan plasma
        let plasma_col2 = vec3<f32>(1.0, 0.0, 1.0) * plasma_factor; // Magenta plasma
        let mixed_plasma = mix(plasma_col, plasma_col2, sin(time)*0.5+0.5);

        // Combine lighting and material
        // Metals have no diffuse-white highlight: specular and rim are Fresnel-tinted.
        col = base_gold * (diff * 0.5 + 0.2) + fresnel * spec * (1.0 + audioBands.z * 0.3) + fresnel * rim * 0.5 * (0.6 + gold_smooth * 0.5);

        // ── Idea 1: mirror-gold reflection with petal inter-reflection (native: conductor = what it mirrors) ──
        // Short reflected march through the same map(): a strike on another petal returns that gold
        // twice-bounced (F0^2: deeper, more saturated orange); an escape reads the little studio env.
        // Both ride the existing spectral Fresnel; gold smoothness sharpens the mirror.
        let rdir = reflect(-v, n);
        var tr = 0.04;
        var rhit = false;
        for (var k = 0; k < 8; k++) {
            let dr = map(p + rdir * tr, time, audio_val, bloom_radius, torque);
            if (dr < 0.004) { rhit = true; break; }
            tr += max(dr, 0.03);
            if (tr > 3.0) { break; }
        }
        let f0g = vec3<f32>(1.0, 0.71, 0.29);
        let bounceLit = 0.45 + 0.4 * (1.0 - clamp(tr / 1.4, 0.0, 1.0)) + 0.15 * clamp(rdir.y * 0.5 + 0.5, 0.0, 1.0);
        let mirror = select(goldStudioEnv(rdir, gold_smooth), f0g * f0g * bounceLit, rhit);
        col += fresnel * mirror * mix(0.25, 0.6, gold_smooth);

        // ── Idea 2: anisotropic Kajiya-Kay vein highlight along the petal radial tangent (tactic 7) ──
        // The rivulets already run radially; liquid gold drawn down a blade stretches its highlight
        // across that flow. Tangent = radial direction projected onto the tangent plane.
        let radialDir = vec3<f32>(p.x, 0.0, p.z) / max(length(p.xz), 1e-3);
        let tanV = radialDir - n * dot(radialDir, n);
        let tanN = tanV / max(length(tanV), 1e-3);
        let th = dot(tanN, h);
        let aniso = pow(sqrt(max(1.0 - th * th, 0.0)), mix(24.0, 140.0, gold_smooth));
        col += fresnel * aniso * sqrt(diff) * (0.15 + gold_smooth * 0.2);
        // IDEA 3: capillary rivulets on petal blades.
        let rivulet = pow(0.5 + 0.5 * sin(atan2(p.z, p.x) * 20.0 + p.y * 26.0 + time * (4.0 + audioBands.y * 3.0)), 5.0) * smoothstep(0.35, 1.4, length(p.xz));
        col += vec3<f32>(0.95, 0.68, 0.22) * rivulet * (0.18 + gold_smooth * 0.12);

        // Stamen florets on the upper core, firing one after another in spiral (k) order.
        let florets = phyllotaxisFlorets(p);
        let coreMask = smoothstep(1.0, 0.55, length(p)) * smoothstep(-0.2, 0.25, p.y);
        let firing = pow(0.5 + 0.5 * cos((florets.y * 6.28318 - time * (1.5 + audioBands.x * 0.5)) * 3.0), 6.0);
        let anther = florets.x * coreMask * (0.35 + firing * (0.8 + audioBands.z * 0.5)) * (0.5 + plasma_int);
        col += vec3<f32>(1.0, 0.85, 0.45) * anther * 1.4;

        // Overlay plasma
        // ── Rescue 3: HEAD mixed with weight plasma_factor <= 2.5, extrapolating to negative channels
        // (ACES maps negatives to bright, so cyan plasma flared red). Weight clamped to 1. ──
        col = mix(col, mixed_plasma * 2.0, clamp(plasma_factor, 0.0, 1.0));
    }

    // Atmospheric perspective (fog)
    col = mix(col, vec3<f32>(0.02, 0.02, 0.05), 1.0 - exp(-0.02 * t * t));

    // Click-launched blossom shocks race from the pointer through the petals.
    let screenUV = fragCoord / res;
    let aspectFix = vec2<f32>(res.x / res.y, 1.0);
    var blossomShock = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r = 0u; r < rippleCount; r++) {
        let ripple = u.ripples[r];
        let age = time - ripple.z;
        if (age < 0.0 || age > 2.0) { continue; }
        let radius = length((screenUV - ripple.xy) * aspectFix);
        blossomShock += exp(-abs(radius - age * 0.72) * 60.0) * (1.0 - age * 0.5);
    }
    col += vec3<f32>(1.0, 0.42, 0.12) * blossomShock * (0.4 + plasma_int * 0.25);

    // Torque-advect and display bounded gold/plasma history.
    let centered = screenUV - 0.5;
    let historyCentered = rotZ(-0.018 * (1.0 + torque)) * vec3<f32>(centered, 0.0);
    let historyUV = clamp(historyCentered.xy + 0.5, vec2<f32>(0.002), vec2<f32>(0.998));
    let historySize = vec2<i32>(textureDimensions(dataTextureC));
    let historyCoord = clamp(vec2<i32>(floor(historyUV * vec2<f32>(historySize))), vec2<i32>(0), historySize - vec2<i32>(1));
    let previous = textureLoad(dataTextureC, historyCoord, 0).rgb;
    // History in C is already ACES display RGB, so trails decay in display space.
    let temporal = clamp(max(acesToneMap(max(col, vec3<f32>(0.0))), previous * (0.86 + gold_smooth * 0.08)), vec3<f32>(0.0), vec3<f32>(1.0));
    let depth = select(1.0, clamp(t / 20.0, 0.0, 0.995), hit);
    let temporalLuma = dot(temporal, vec3<f32>(0.2126, 0.7152, 0.0722));
    let semanticAlpha = clamp(select(0.08 + smoothstep(0.02, 0.4, temporalLuma) * 0.35, 0.72 + blossomShock * 0.2, hit), 0.0, 1.0);
    let finalColor = vec4<f32>(temporal, semanticAlpha);
    textureStore(writeTexture, vec2<i32>(i32(id.x), i32(id.y)), finalColor);
    textureStore(dataTextureA, id.xy, finalColor);
    textureStore(writeDepthTexture, id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
