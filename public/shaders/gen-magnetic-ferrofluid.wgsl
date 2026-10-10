// ═══════════════════════════════════════════════════════════════════
//  Magnetic Ferrofluid
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-10-10
//  Ideas: Rosensweig hexagonal spike lattice with critical-field onset and capillary-wavenumber spacing; labyrinthine fingering instability when the field is tipped tangential (mouse held); Rayleigh l=2/l=3 shape-mode ringing kicked by bass; studio softbox + horizon reflections on the mirror body
//  A packing: ACES display RGBA in A
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"
// zoom_params: x=Magnetic Strength (Spikes), y=Fluid Density, z=Oscillation Speed, w=Iridescence Shift

// --- Helper Functions ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Native idea 1: Rosensweig normal-field instability. Above the critical
// field Hc the flat interface breaks into a hexagonal lattice of peaks whose
// spacing is set by the capillary wavenumber kc = sqrt(rho*g/sigma); the
// amplitude grows as a supercritical sqrt(H - Hc) bifurcation. Evaluated
// triplanar over the fluid mass: three plane waves 120 degrees apart.
fn hexLattice2(q: vec2<f32>, k: f32) -> f32 {
    let k1 = vec2<f32>(1.0, 0.0);
    let k2 = vec2<f32>(-0.5, 0.8660254);
    let k3 = vec2<f32>(-0.5, -0.8660254);
    let h = cos(k * dot(q, k1)) + cos(k * dot(q, k2)) + cos(k * dot(q, k3));
    // h in [-1.5, 3]; peaks (3) are the hexagonal spike sites.
    return clamp((h + 1.5) / 4.5, 0.0, 1.0);
}

fn rosensweigLattice(p: vec3<f32>, kc: f32) -> f32 {
    let w = pow(abs(normalize(p + vec3<f32>(1e-5))), vec3<f32>(4.0));
    let ws = w / (w.x + w.y + w.z);
    let h = hexLattice2(p.yz, kc) * ws.x + hexLattice2(p.zx, kc) * ws.y + hexLattice2(p.xy, kc) * ws.z;
    // Sharpen into cusped Rosensweig peaks.
    return pow(h, 3.0);
}

// Native idea 2: labyrinthine fingering. When the applied field lies in the
// film plane the hexagonal lattice is no longer selected; the thin film breaks
// into meandering, branching stripe domains (magnetic labyrinth) whose width
// is again set by the critical wavelength and whose walls repel each other.
fn labyrinthFingers(p: vec3<f32>, kc: f32, time: f32) -> f32 {
    // Low-frequency domain warp makes stripes meander and branch.
    let warp = vec3<f32>(
        sin(p.y * 1.7 + time * 0.23) + sin(p.z * 2.3 - time * 0.17),
        sin(p.z * 1.9 - time * 0.19) + sin(p.x * 2.1 + time * 0.21),
        sin(p.x * 1.6 + time * 0.13) + sin(p.y * 2.5 - time * 0.27)
    ) * 0.35;
    let q = p + warp;
    // Stripes run perpendicular to the in-plane (tangential) field direction.
    let fieldDir = normalize(vec3<f32>(1.0, 0.35, 0.2));
    let s1 = cos(kc * dot(q, fieldDir));
    let s2 = cos(kc * 0.93 * dot(q, normalize(vec3<f32>(0.2, 1.0, -0.4))) + 1.3);
    let stripes = max(s1, s2 * 0.85);
    return smoothstep(0.1, 0.95, stripes);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

// Native idea 3: Rayleigh shape modes. A free liquid drop rings in
// Legendre modes P_l(cos theta) with omega_l ~ sqrt(l(l-1)(l+2)); the l=2
// (prolate/oblate) and l=3 (pear) modes are kicked by bass and ring down.
fn rayleighModes(pos: vec3<f32>, time: f32, bass: f32) -> f32 {
    let c = pos.y / max(length(pos), 1e-3);
    let p2 = 0.5 * (3.0 * c * c - 1.0);
    let p3 = 0.5 * (5.0 * c * c * c - 3.0 * c);
    let a2 = 0.02 + bass * 0.11;
    let a3 = 0.012 + bass * 0.07;
    return p2 * a2 * sin(time * 2.83 * 1.6) + p3 * a3 * sin(time * 5.48 * 1.6 + 1.3);
}

// Native idea 4: studio softbox environment. Two rectangular boxes (warm key,
// cool strip) and a thin horizon line, defined on the reflection direction, so
// the black mirror surface carries the classic ferrofluid product-photo glints.
fn softboxEnv(refl: vec3<f32>) -> vec3<f32> {
    let az = atan2(refl.z, refl.x);
    let el = asin(clamp(refl.y, -1.0, 1.0));
    let key = smoothstep(0.07, 0.0, max(abs(az - 0.7) - 0.32, abs(el - 0.55) - 0.4));
    let strip = smoothstep(0.05, 0.0, max(abs(az + 2.1) - 0.1, abs(el - 0.1) - 0.7));
    let top = smoothstep(0.08, 0.0, max(abs(refl.x) - 0.35, abs(refl.z - 0.15) - 0.25)) * step(0.7, refl.y);
    let horizon = smoothstep(0.035, 0.0, abs(el + 0.03));
    return vec3<f32>(1.0, 0.93, 0.82) * key * 2.6
         + vec3<f32>(0.75, 0.88, 1.0) * strip * 2.2
         + vec3<f32>(1.0) * top * 1.8
         + vec3<f32>(0.5, 0.65, 0.9) * horizon * 0.5;
}

// --- SDFs ---

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Map Function ---

fn map(p: vec3<f32>) -> vec2<f32> {
    var pos = p;
    let time = u.config.x * u.zoom_params.z; // Speed control
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);

    // Base fluid mass
    let fluidRadius = 1.15 + u.zoom_params.y * 0.65;
    var d = sdSphere(pos, fluidRadius);
    d -= rayleighModes(pos, time, bass);

    // Magnetic spikes displacement
    let spikeDensity = u.zoom_params.y * 5.0 + 3.0;
    let spikeHeight = u.zoom_params.x * (0.38 + bass * 0.18) + 0.04;

    // Use noise to generate spiky perturbations based on direction
    let spikeDisplacement = sin(spikeDensity * pos.x) * sin(spikeDensity * pos.y) * sin(spikeDensity * pos.z) * spikeHeight;

    // Add time-based oscillation to the spikes
    let oscillation = sin(time + length(pos) * 4.0 + bass * 3.0) * 0.5 + 0.5;

    d += spikeDisplacement * oscillation * 0.55;

    // Rosensweig onset: field H from Magnetic Strength, kicked by bass.
    let fieldH = u.zoom_params.x * (1.0 + bass * 0.45);
    let criticalH = 0.22;
    let supercrit = sqrt(max(fieldH - criticalH, 0.0));
    // Capillary wavenumber: denser fluid -> shorter wavelength; slight
    // tightening with field excess as in the nonlinear regime.
    let kc = (5.0 + u.zoom_params.y * 7.0) * (1.0 + supercrit * 0.25);
    let latticeAmp = supercrit * 0.42;
    // Field orientation: normal (hexagonal peaks) -> tangential (labyrinth) while held.
    let tangential = held;
    if (latticeAmp > 0.0) {
        let hexPeaks = rosensweigLattice(pos, kc);
        let fingers = labyrinthFingers(pos, kc * 0.8, time);
        let relief = mix(hexPeaks * latticeAmp, fingers * latticeAmp * 0.35, tangential);
        // Lipschitz-safe scaling: surface relief pulls the surface outward.
        d -= relief * 0.4;
    }

    // Optional: Add smaller orbiting fluid droplets that merge smoothly
    let dropletPos = vec3<f32>(sin(time)*2.0, cos(time*1.3)*1.5, sin(time*0.8)*2.0);
    let d2 = sdSphere(pos - dropletPos, 0.24 + u.zoom_params.y * 0.28);

    d = smin(d, d2, 0.5); // Smoothly blend droplets into the main mass

    return vec2<f32>(d, 1.0); // ID 1.0 for ferrofluid material
}

// --- Lighting & Rendering ---

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy).x - map(p - e.xyy).x,
        map(p + e.yxy).x - map(p - e.yxy).x,
        map(p + e.yyx).x - map(p - e.yyx).x
    ));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let dims = vec2<f32>(u.config.z, u.config.w);
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);
    let held = clamp(u.zoom_config.w, 0.0, 1.0);
    let fragCoord = vec2<f32>(id.xy);

    if (fragCoord.x >= dims.x || fragCoord.y >= dims.y) {
        return;
    }

    var uv = (fragCoord * 2.0 - dims) / dims.y;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, 5.0);
    // Normalized top-down pointer drives a sprung camera orbit.
    let time = u.config.x;
    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mouse = rawMouse;
    var mouseVelocity = vec2<f32>(0.0);
    var springDt = 0.016;
    if (arrayLength(&extraBuffer) > 138u) {
        if (extraBuffer[137] > 0.5) {
            mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
            mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
            springDt = clamp(time - extraBuffer[138], 0.001, 0.05);
        }
    }
    let springOmega = 8.0;
    mouseVelocity += ((rawMouse - mouse) * springOmega * springOmega - mouseVelocity * 2.0 * springOmega) * springDt;
    mouse += mouseVelocity * springDt;
    if (id.x == 0u && id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = mouse.x; extraBuffer[134] = mouse.y;
        extraBuffer[135] = mouseVelocity.x; extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0; extraBuffer[138] = time;
    }
    let mouseX = mouse.x * 2.0 - 1.0;
    let mouseY = mouse.y * 2.0 - 1.0;

    let temp_ro_yz = rot(mouseY * 1.5) * ro.yz;
    ro.y = temp_ro_yz.x;
    ro.z = temp_ro_yz.y;

    let temp_ro_xz = rot(mouseX * 3.14 + u.config.x * 0.2) * ro.xz;
    ro.x = temp_ro_xz.x;
    ro.z = temp_ro_xz.y;


    let ta = vec3<f32>(0.0, 0.0, 0.0);
    let ww = normalize(ta - ro);
    let uu = normalize(cross(ww, vec3<f32>(0.0, 1.0, 0.0)));
    let vv = normalize(cross(uu, ww));
    let rd = normalize(uv.x * uu + uv.y * vv + 1.5 * ww);

    // Raymarching
    var t = 0.0;
    var d = 0.0;
    var m = -1.0;
    var hit = false;
    for (var i = 0; i < 100; i++) {
        var p = ro + rd * t;
        let res = map(p);
        d = res.x;
        m = res.y;
        if (d < 0.001) { hit = true; break; }
        if (t > 20.0) { break; }
        t += max(abs(d) * 0.62, 0.002);
    }

    var col = vec3<f32>(0.05, 0.05, 0.08); // Background color
    var peakGlow = 0.0;

    if (hit) {
        var p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting setup
        let lig = normalize(vec3<f32>(1.0, 1.0, 1.0));
        let hal = normalize(lig - rd);

        let dif = clamp(dot(n, lig), 0.0, 1.0);
        let spec = pow(clamp(dot(n, hal), 0.0, 1.0), 64.0);
        let fre = pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 5.0);

        // Base dark metal color
        var matCol = vec3<f32>(0.1, 0.1, 0.15);

        // Iridescence based on viewing angle and color shift parameter
        let iriPhase = dot(n, rd) * 3.14 + u.zoom_params.w * 5.0;
        let iriCol = vec3<f32>(0.5) + vec3<f32>(0.5) * cos(vec3<f32>(iriPhase) + vec3<f32>(0.0, 2.0, 4.0));

        matCol = mix(matCol, iriCol, vec3<f32>(fre * 0.5));

        col = matCol * dif * (1.5 + bass * 0.4) + vec3<f32>(1.0) * spec * (1.5 + treble) + matCol * fre;

        // Rosensweig peak tips / labyrinth domain walls catch field-aligned light.
        let fieldH = u.zoom_params.x * (1.0 + bass * 0.45);
        let supercrit = sqrt(max(fieldH - 0.22, 0.0));
        if (supercrit > 0.0) {
            let kc = (5.0 + u.zoom_params.y * 7.0) * (1.0 + supercrit * 0.25);
            let tipMask = pow(rosensweigLattice(p, kc), 2.0);
            let fingers = labyrinthFingers(p, kc * 0.8, time * u.zoom_params.z);
            let wallMask = 1.0 - abs(fingers * 2.0 - 1.0);
            peakGlow = mix(tipMask, wallMask * 0.6, held) * supercrit;
            let tipCol = mix(vec3<f32>(0.55, 0.75, 1.1), vec3<f32>(1.0, 0.45, 0.9), held);
            col += tipCol * peakGlow * (0.35 + treble * 0.3) * (0.4 + spec * 2.0 + fre);
        }

        // Add fake environment reflection (simple gradient mapping)
        let refl = reflect(rd, n);
        let envCol = mix(vec3<f32>(0.1, 0.2, 0.3), vec3<f32>(0.8, 0.9, 1.0), refl.y * 0.5 + 0.5);
        col += envCol * matCol * 0.8;
        // Idea 4: softbox glints on the mirror body, Fresnel-weighted
        col += softboxEnv(refl) * (0.3 + 0.7 * fre) * 0.55 * (1.0 + treble * 0.25);
    }

    let uv01 = (fragCoord + vec2<f32>(0.5)) / dims;
    var magneticPulse = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age >= 0.0 && age < 1.7) {
            let delta = (uv01 - ripple.xy) * vec2<f32>(dims.x / dims.y, 1.0);
            let shell = exp(-abs(length(delta) - age * 0.25) * 74.0) * exp(-age * 1.8);
            magneticPulse = max(magneticPulse, shell);
        }
    }
    col += vec3<f32>(0.25, 0.8, 1.25) * magneticPulse * (0.7 + mids * 0.35);

    // Subtle vignette
    col = col * (1.0 - 0.2 * length(uv));
    let coord = vec2<i32>(id.xy);
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(max(col, vec3<f32>(0.0)), prev.rgb * 0.9, clamp(0.025 + mids * 0.008, 0.0, 0.05));
    col = acesToneMap(col * 1.1);
    // Alpha = fluid coverage + field-concentrated peak/wall density + click shell.
    let _alpha = clamp(select(0.08, 0.72, hit) + peakGlow * 0.2 + magneticPulse * 0.18, 0.0, 0.98);
    let outColor = vec4<f32>(col, _alpha);
    let _depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
