// ═══════════════════════════════════════════════════════════════════
//  Neural Bioluminescence Matrix
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: saltatory action potentials hopping node-of-Ranvier to node along each axon with depolarization spike and refractory undershoot; aequorin-to-GFP energy transfer where calcium flashes (spikes, click calcium waves) emit 469nm blue that lingers as 509nm green fluorescence in the trail
//  A packing: ACES display RGBA in A
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

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=Node Density, y=Pulse Speed, z=Audio Reactivity, w=Bio-Glow Intensity
    ripples: array<vec4<f32>, 50>,
};

// Persistent state (extraBuffer safe zone, pixel (0,0) writes only)
// 133 = bass envelope, 134 = mid envelope, 135 = treble envelope,
// 136 = prev mouse x, 137 = prev mouse y, 138 = clickCount*2 + clickHeld
const RANVIER_NODES: f32 = 4.0;
const AEQUORIN_BLUE: vec3<f32> = vec3<f32>(0.12, 0.45, 1.0);  // ~469 nm
const GFP_GREEN: vec3<f32> = vec3<f32>(0.25, 1.0, 0.45);      // ~509 nm

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- Core SDFs & Noise ---
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let res = exp2(-k * a) + exp2(-k * b);
    return -log2(res) / k;
}

fn hash33(p3_in: vec3<f32>) -> vec3<f32> {
    var p = fract(p3_in * vec3<f32>(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

fn noise(x: vec3<f32>) -> f32 {
    let p = floor(x);
    let f = fract(x);
    let f2 = f * f * (3.0 - 2.0 * f);
    let res = mix(mix(mix(hash33(p + vec3<f32>(0.0,0.0,0.0)).x, hash33(p + vec3<f32>(1.0,0.0,0.0)).x, f2.x),
                      mix(hash33(p + vec3<f32>(0.0,1.0,0.0)).x, hash33(p + vec3<f32>(1.0,1.0,0.0)).x, f2.x), f2.y),
                  mix(mix(hash33(p + vec3<f32>(0.0,0.0,1.0)).x, hash33(p + vec3<f32>(1.0,0.0,1.0)).x, f2.x),
                      mix(hash33(p + vec3<f32>(0.0,1.0,1.0)).x, hash33(p + vec3<f32>(1.0,1.0,1.0)).x, f2.x), f2.y), f2.z);
    return res;
}

fn fbm(p_in: vec3<f32>) -> f32 {
    var f = 0.0;
    var amp = 0.5;
    var pos = p_in;
    for (var i = 0; i < 4; i++) {
        f += amp * noise(pos);
        pos *= 2.0;
        amp *= 0.5;
    }
    return f;
}

fn mod_float(x: f32, y: f32) -> f32 {
    return x - y * floor(x / y);
}

fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn spring_damper(prev: f32, tgt: f32, vel: ptr<function, f32>, k: f32, d: f32) -> f32 {
    let force = (tgt - prev) * k;
    *vel = (*vel + force) * (1.0 - d);
    return prev + *vel;
}

fn nodeSpacing() -> f32 {
    return 4.0 / max(u.zoom_params.x, 0.1); // Node Density
}

fn map(p_in: vec3<f32>, audioPulse: f32, clickPulse: f32) -> f32 {
    var p = p_in;

    // Magnetic mouse repulsion (zoom_config.yz is already normalized uv)
    let mouseX = u.zoom_config.y * 2.0 - 1.0;
    let mouseY = u.zoom_config.z * 2.0 - 1.0;
    let mousePos = vec3<f32>(mouseX * 5.0, mouseY * 5.0, p.z);
    let distToMouse = length(p.xy - mousePos.xy);
    let repulsion = (2.0 + clickPulse * 3.0) * exp(-distToMouse * 1.5);
    p = p + normalize(vec3<f32>(p.xy - mousePos.xy, 0.0001)) * repulsion;

    // Organic displacement using FBM, audio modulated
    p += (vec3<f32>(fbm(p), fbm(p + 10.0), fbm(p + 20.0)) - 0.5) * (1.5 + audioPulse * 0.5);

    let spacing = nodeSpacing();

    var q = p;
    q.x = mod_float(q.x + spacing * 0.5, spacing) - spacing * 0.5;
    q.y = mod_float(q.y + spacing * 0.5, spacing) - spacing * 0.5;
    q.z = mod_float(q.z + spacing * 0.5, spacing) - spacing * 0.5;

    // A few connecting capsules
    let r = 0.15;
    let d1 = sdCapsule(q, vec3<f32>(-spacing*0.5, 0.0, 0.0), vec3<f32>(spacing*0.5, 0.0, 0.0), r);
    let d2 = sdCapsule(q, vec3<f32>(0.0, -spacing*0.5, 0.0), vec3<f32>(0.0, spacing*0.5, 0.0), r);
    let d3 = sdCapsule(q, vec3<f32>(0.0, 0.0, -spacing*0.5), vec3<f32>(0.0, 0.0, spacing*0.5), r);

    var d = smin(d1, d2, 12.0);
    d = smin(d, d3, 12.0);

    return d;
}

fn calcNormal(p: vec3<f32>, audioPulse: f32, clickPulse: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    return normalize(vec3<f32>(
        map(p + e.xyy, audioPulse, clickPulse) - map(p - e.xyy, audioPulse, clickPulse),
        map(p + e.yxy, audioPulse, clickPulse) - map(p - e.yxy, audioPulse, clickPulse),
        map(p + e.yyx, audioPulse, clickPulse) - map(p - e.yyx, audioPulse, clickPulse)
    ));
}

// Saltatory conduction: myelin insulates the internodes, so the action
// potential regenerates only at nodes of Ranvier and hops node to node.
// Returns the membrane response at p: a sharp depolarization flash at the
// node the spike just reached, then a refractory hyperpolarized undershoot.
fn ranvierSpike(p: vec3<f32>, time: f32, pulseSpeed: f32, seed: f32) -> f32 {
    let spacing = nodeSpacing();
    let cell = floor(p / spacing + 0.5);
    let lc = p / spacing - cell;               // -0.5..0.5 within the neuron cell
    let al = abs(lc);
    // Axon direction = dominant local axis (x, y or z capsule)
    var along = lc.x;
    var axis = 0.0;
    if (al.y > al.x && al.y > al.z) { along = lc.y; axis = 1.0; }
    else if (al.z > al.x) { along = lc.z; axis = 2.0; }
    let u01 = along + 0.5;
    let h = hash33(cell * 1.7 + vec3<f32>(axis * 11.0, seed * 23.0, 0.0));
    // Spike front position along the axon (cycles/second from Pulse Speed)
    let front = fract(h.x + time * (0.15 + pulseSpeed * 0.25) * (0.7 + 0.6 * h.y));
    // Nodes of Ranvier: discrete gaps along the myelinated axon
    let nodeIdx = floor(u01 * RANVIER_NODES);
    let nodeU = (nodeIdx + 0.5) / RANVIER_NODES;
    let dn = abs(fract(u01 * RANVIER_NODES) - 0.5) * 2.0;
    let nodeMask = exp(-dn * dn * 10.0);
    // Time since this node fired, in cycle units
    let elapsed = fract(front - nodeU);
    let depol = smoothstep(0.0, 0.015, elapsed) * exp(-elapsed * 30.0);
    let undershoot = exp(-pow((elapsed - 0.12) * 14.0, 2.0)) * 0.35;
    return (depol - undershoot) * nodeMask;
}

// --- Main Render Loop ---
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    let texSize = textureDimensions(writeTexture);
    if (id.x >= texSize.x || id.y >= texSize.y) { return; }

    let fragCoord = vec2<f32>(id.xy);
    var uv = (fragCoord - 0.5 * vec2<f32>(texSize)) / f32(texSize.y);
    let aspect = f32(texSize.x) / f32(texSize.y);

    let time = u.config.x;
    let mouseClick = u.zoom_config.w;
    let mouseUV = u.zoom_config.yz;

    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mid = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let isStatePixel = id.x == 0u && id.y == 0u;

    // Spring-damper audio envelopes
    var velBass = 0.0;
    var velMid = 0.0;
    var velTreble = 0.0;
    var prevBass = 0.0;
    var prevMid = 0.0;
    var prevTreble = 0.0;
    var prevMouseX = mouseUV.x;
    var prevMouseY = mouseUV.y;
    var packedClick = 0.0;
    if (arrayLength(&extraBuffer) > 138u) {
        prevBass = extraBuffer[133];
        prevMid = extraBuffer[134];
        prevTreble = extraBuffer[135];
        prevMouseX = extraBuffer[136];
        prevMouseY = extraBuffer[137];
        packedClick = extraBuffer[138];
    }
    let bassSmooth = spring_damper(prevBass, bass, &velBass, 0.10, 0.08);
    let midSmooth = spring_damper(prevMid, mid, &velMid, 0.12, 0.09);
    let trebleSmooth = spring_damper(prevTreble, treble, &velTreble, 0.14, 0.10);

    // Mouse state persistence
    let clickCount = floor(max(packedClick, 0.0) * 0.5);
    let clickHeld = max(packedClick, 0.0) - clickCount * 2.0;
    let mouseDelta = length(mouseUV - vec2<f32>(prevMouseX, prevMouseY));

    var newClickCount = clickCount;
    var newClickHeld = clickHeld;
    if (mouseClick > 0.5 && clickHeld < 0.5) {
        newClickCount = mod_float(clickCount + 1.0, 100.0); // fract(n*0.13) is 100-periodic
        newClickHeld = 1.0;
    }
    if (mouseClick < 0.5) {
        newClickHeld = 0.0;
    }

    if (isStatePixel) {
        if (arrayLength(&extraBuffer) > 138u) {
            extraBuffer[133] = bassSmooth;
            extraBuffer[134] = midSmooth;
            extraBuffer[135] = trebleSmooth;
            extraBuffer[136] = mouseUV.x;
            extraBuffer[137] = mouseUV.y;
            extraBuffer[138] = newClickCount * 2.0 + newClickHeld;
        }
    }

    let clickPulse = exp(-mouseDelta * 15.0) * mouseClick * 4.0;
    let mutationSeed = fract(newClickCount * 0.13 + time * 0.02);

    let audioPulse = bassSmooth * u.zoom_params.z; // Audio Reactivity

    // Click ripples = calcium waves: Ca2+ spreads from the click point and
    // triggers aequorin flashes wherever the wavefront passes.
    var calcium = 0.0;
    var lens = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age >= 0.0 && age < 3.0) {
            let rpos = vec2<f32>((rp.x - 0.5) * aspect, rp.y - 0.5);
            let dv = uv - rpos;
            let dl = max(length(dv), 1e-4);
            let front = dl - age * 0.45;
            let ring = exp(-front * front * 90.0) * exp(-age * 1.3);
            calcium += ring;
            lens += (dv / dl) * ring * 0.03;
        }
    }
    uv += lens;

    // Camera setup
    var ro = vec3<f32>(0.0, 0.0, time * 2.0);
    var rd = normalize(vec3<f32>(uv, 1.0));

    // Slow camera rotation
    let rd_xy = rot(time * 0.1 + midSmooth * 0.2) * vec2<f32>(rd.x, rd.y);
    rd.x = rd_xy.x;
    rd.y = rd_xy.y;

    let rd_xz = rot(sin(time * 0.05 + trebleSmooth * 0.3) * 0.2) * vec2<f32>(rd.x, rd.z);
    rd.x = rd_xz.x;
    rd.z = rd_xz.y;

    // Raymarching logic
    var t = 0.0;
    var d = 0.0;
    var p = ro;
    var glow = 0.0;
    var spikeGlow = 0.0;

    for (var i = 0; i < 80; i++) {
        p = ro + rd * t;
        d = map(p, audioPulse, clickPulse);

        let pulseWave = sin(dot(p, vec3<f32>(0.5, 0.5, 0.5)) - time * u.zoom_params.y * 3.0 + mutationSeed * 6.28) * 0.5 + 0.5; // Pulse Speed
        let pulseIntensity = pow(pulseWave, 4.0) * (1.0 + audioPulse * 0.5 + clickPulse);

        let proximity = 0.02 / (0.01 + abs(d));
        let ap = ranvierSpike(p, time, u.zoom_params.y, mutationSeed);
        // Refractory undershoot dims the ambient pulse; depolarization flashes
        glow += proximity * max(pulseIntensity * (1.0 + ap * 0.8), 0.0) * u.zoom_params.w; // Bio-Glow Intensity
        spikeGlow += proximity * max(ap, 0.0) * (1.0 + bassSmooth * 0.4) * u.zoom_params.w;

        if (d < 0.01 || t > 50.0) { break; }
        t += d * 0.7;
    }

    var color = vec3<f32>(0.01, 0.01, 0.02); // Deep void background
    let hit = t < 50.0;

    if (hit) {
        let n = calcNormal(p, audioPulse, clickPulse);
        let lightDir = normalize(vec3<f32>(1.0, 1.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let ao = clamp(map(p + n * 0.5, audioPulse, clickPulse) * 2.0, 0.0, 1.0);

        let baseCol = vec3<f32>(0.05, 0.1, 0.15);
        color = baseCol * diff * ao;

        let sss = max(0.0, map(p + rd * 0.5, audioPulse, clickPulse));
        color += vec3<f32>(0.1, 0.3, 0.4) * sss * 0.5;
    }

    let fog = exp(-t * 0.05);
    let glowCol = mix(vec3<f32>(0.0, 0.8, 1.0), vec3<f32>(1.0, 0.0, 0.8), sin(p.z * 0.5 + time + trebleSmooth * 2.0) * 0.5 + 0.5);
    color += glowCol * glow * 0.05 * fog;

    // Aequorin flash: Ca2+-bound photoprotein emits blue at the firing nodes
    // and along calcium wavefronts from clicks.
    let flash = spikeGlow * 0.06 * fog + calcium * (0.4 + treble * 0.3) * (0.3 + u.zoom_params.w * 0.15);
    color += AEQUORIN_BLUE * flash;

    color = mix(color, vec3<f32>(0.01, 0.01, 0.02), 1.0 - exp(-t * 0.02));

    // Chromatic aberration driven by audio + click bursts
    let caStr = (0.01 + trebleSmooth * 0.02 + clickPulse * 0.03) * u.zoom_params.z;
    color = vec3<f32>(color.r + caStr, color.g, color.b - caStr * 0.5);

    // ACES display colour
    var display = aces(max(color, vec3<f32>(0.0)));

    // Temporal feedback from dataTextureC (exact load of previous display RGBA)
    let prevData = textureLoad(dataTextureC, vec2<i32>(id.xy), 0);
    // GFP energy transfer: light lingering in the trail is re-emitted by GFP
    // as green fluorescence, so fresh blue flashes decay into green afterglow.
    let prevLuma = dot(prevData.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let fretTrail = mix(prevData.rgb, GFP_GREEN * prevLuma, 0.08 + midSmooth * 0.04);
    let feedbackMix = 0.2 + bassSmooth * 0.1;
    display = clamp(mix(fretTrail * 0.95, display, feedbackMix), vec3<f32>(0.0), vec3<f32>(1.0));

    // Alpha: neural tissue coverage + emitted bioluminescence density
    let tissue = select(0.0, exp(-t * 0.03), hit);
    let alphaNow = clamp(tissue * 0.6 + min(glow * 0.02, 1.0) * 0.25 + min(flash, 1.0) * 0.3, 0.02, 1.0);
    let alpha = clamp(mix(prevData.a * 0.95, alphaNow, max(feedbackMix, 0.35)), 0.02, 1.0);
    let outColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, id.xy, outColor);

    // Depth from the raymarched hit distance (near = 1)
    let depth = clamp(1.0 - t / 50.0, 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<i32>(id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));

    textureStore(dataTextureA, vec2<i32>(id.xy), outColor);
}
