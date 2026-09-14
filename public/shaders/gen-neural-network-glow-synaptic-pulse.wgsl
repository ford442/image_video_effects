// ═══════════════════════════════════════════════════════════════════
//  Neural Network Glow - Synaptic Pulse
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-14
//  Ideas: quantal vesicle release with diffusing neurotransmitter clouds; action-potential spike with refractory afterhyperpolarization
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
  config: vec4<f32>,       // .x = time, .y = rippleCount, .zw = resolution
  zoom_config: vec4<f32>,  // .x = time, .yz = mouse_uv, .w = mouse_down
  zoom_params: vec4<f32>,  // .x = Pulse Speed, .y = Glow Intensity, .z = Trail Decay, .w = Mouse Influence
  ripples: array<vec4<f32>, 50>,
};

// Persistent state (extraBuffer safe zone, pixel (0,0) writes only):
//   [133] bass envelope, [134..135] smoothed mouse uv, [136] init flag

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var q = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return fract(sin(q) * 43758.5453);
}

fn hash12(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(41.3, 289.1))) * 43758.5453);
}

fn bass_env(prev: f32, bass: f32, attack: f32, release: f32) -> f32 {
    let k = select(release, attack, bass > prev);
    return mix(prev, bass, k);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Membrane-voltage colormap (replaces the plasmaBuffer[idx] "palette" read):
// resting indigo -> depolarized cyan -> spiking white-gold
fn membraneColor(v: f32) -> vec3<f32> {
    let x = clamp(v, 0.0, 2.0);
    let rest = vec3<f32>(0.04, 0.03, 0.12);
    let depol = vec3<f32>(0.1, 0.55, 0.9);
    let spike = vec3<f32>(1.0, 0.92, 0.7);
    return mix(mix(rest, depol, smoothstep(0.0, 0.8, x)), spike, smoothstep(0.8, 2.0, x));
}

// Idea 2: action-potential waveform over a conduction phase in [0,1).
// Sharp depolarization spike near phase 1, then afterhyperpolarization (negative
// undershoot) during the refractory window just after the spike passes.
fn actionPotential(phase: f32, sharp: f32) -> vec2<f32> {
    let spike = smoothstep(0.9 + sharp * 0.04, 1.0, phase);
    let ahp = smoothstep(0.0, 0.03, phase) * (1.0 - smoothstep(0.03, 0.22, phase));
    return vec2<f32>(spike, ahp);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let coords = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    let uv = vec2<f32>(global_id.xy) / res;
    let t = u.config.x;

    let depth = textureLoad(readDepthTexture, coords, 0).r;

    let dimsC = vec2<i32>(textureDimensions(dataTextureC));
    let prev = textureLoad(dataTextureC, clamp(coords, vec2<i32>(0), dimsC - vec2<i32>(1)), 0);
    let prev_trail = prev.a;

    let bass   = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids   = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let pulse_speed = u.zoom_params.x;
    let glow_intensity = u.zoom_params.y;
    let trail_decay = u.zoom_params.z;
    let mouse_gain = u.zoom_params.w / 0.5; // default 0.5 == original gravity strength

    // Relocated state: bass envelope + mouse spring (was misread from dataTextureC color)
    let mouse_target = u.zoom_config.yz;
    var prev_env = bass;
    var mouse_current = mouse_target;
    if (arrayLength(&extraBuffer) > 138u) {
        if (extraBuffer[136] > 0.5) {
            prev_env = extraBuffer[133];
            mouse_current = vec2<f32>(extraBuffer[134], extraBuffer[135]);
        }
    }
    let env = bass_env(prev_env, bass, 0.8, 0.15);
    let mouse_delta = length(mouse_target - mouse_current);
    let spring_k = select(0.12, 0.03, mouse_delta > 0.02);
    let smooth_mouse = mix(mouse_current, mouse_target, spring_k);
    if (global_id.x == 0u && global_id.y == 0u && arrayLength(&extraBuffer) > 138u) {
        extraBuffer[133] = env;
        extraBuffer[134] = smooth_mouse.x;
        extraBuffer[135] = smooth_mouse.y;
        extraBuffer[136] = 1.0;
    }

    let to_mouse = smooth_mouse - uv;
    let dist2 = dot(to_mouse, to_mouse) + 0.005;
    let dlen = length(to_mouse);
    let gravity = select(vec2<f32>(0.0), to_mouse * (0.5 + u.zoom_config.w * 3.0) * mouse_gain / (dlen * dist2) * 0.002, dlen > 0.0001);
    let displaced_uv = uv + gravity;

    let input_luma = dot(textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));

    // Idea 1 constants: release rate follows Pulse Speed, diffusion coefficient follows mids
    let releaseRate = 0.6 + pulse_speed * 0.8;
    let releaseProb = 0.25 + env * 0.55;
    let diffusionD = 0.004 + mids * 0.006;

    let p = displaced_uv * (4.0 + env);
    let i = floor(p);
    let f = fract(p);
    var min_dist = 1.0;
    var transmitter = 0.0;
    for (var y = -1; y <= 1; y = y + 1) {
        for (var x = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let cell = i + neighbor;
            let pt = hash22(cell);
            let dist = length(neighbor + pt - f);
            min_dist = select(min_dist, dist, dist < min_dist);

            // Idea 1: quantal vesicle release at each synaptic bouton (cell node).
            // Each release quantum fires with probability releaseProb; the released
            // transmitter spreads as the 2D diffusion Green's function
            // C ~ exp(-r^2 / (4 D age)) / (4 D age), cleared by reuptake.
            let cellPhase = t * releaseRate + hash12(cell) * 7.0;
            let quantum = floor(cellPhase);
            let age = fract(cellPhase) / releaseRate + 0.02;
            let fires = step(hash12(cell + vec2<f32>(quantum * 1.37, quantum * 0.71)), releaseProb);
            let spread = 4.0 * diffusionD * age * 60.0;
            let site = neighbor + pt - f;
            let r2 = dot(site, site);
            let cloud = exp(-r2 / spread) / (1.0 + spread * 8.0) * exp(-age * 1.5);
            transmitter += fires * cloud;
        }
    }

    let pulse_ring = fract(min_dist * 5.0 - t * pulse_speed * 0.1 + input_luma * 0.3);
    let edge_intensity = smoothstep(0.05, 0.0, min_dist);
    let ap = actionPotential(pulse_ring, treble);
    let wave = ap.x * (1.0 + env * 2.5);
    let ahp = ap.y * smoothstep(0.35, 0.0, min_dist);
    let intensity = max((edge_intensity + wave) * glow_intensity - ahp * 0.35 * glow_intensity, 0.0);

    var col = membraneColor(intensity) * (0.35 + intensity);
    // Refractory undershoot: hyperpolarized membrane cools and darkens
    col = mix(col, col * vec3<f32>(0.35, 0.45, 0.8), clamp(ahp, 0.0, 1.0) * 0.6);

    // Neurotransmitter clouds (glutamate green-gold) around firing boutons
    let nt = clamp(transmitter, 0.0, 1.5);
    col += vec3<f32>(0.55, 1.0, 0.45) * nt * 0.35 * glow_intensity * (1.0 + bass * 0.4);

    // Chromatic synapse separation: excitatory = warm, inhibitory = cool
    let excite = smoothstep(0.3, 0.8, bass);
    let inhibit = smoothstep(0.3, 0.8, treble);
    let warm = vec3<f32>(1.0, 0.6, 0.3) * excite * intensity;
    let cool = vec3<f32>(0.3, 0.6, 1.0) * inhibit * intensity;
    col = col + warm + cool;
    col = col + vec3<f32>(treble * 0.1, mids * 0.05, bass * 0.05);

    // Click ripples: evoked stimulus rings (one extra depolarizing wave per click)
    let rippleCount = min(u32(u.config.y), 50u);
    let aspect = res.x / res.y;
    var evoked = 0.0;
    for (var k = 0u; k < rippleCount; k = k + 1u) {
        let r = u.ripples[k];
        let age = t - r.z;
        if (age >= 0.0 && age < 2.5) {
            let d = length((uv - r.xy) * vec2<f32>(aspect, 1.0));
            let front = age * 0.35;
            evoked += exp(-(d - front) * (d - front) * 400.0) * exp(-age * 1.2);
        }
    }
    col = col + vec3<f32>(1.0, 0.5, 0.2) * evoked * 0.6 * (0.5 + edge_intensity + nt);

    // Mouse held: tetanic stimulation brightens synapses near the cursor
    let heldGlow = u.zoom_config.w * u.zoom_params.w * smoothstep(0.25, 0.0, dlen);
    col = col + vec3<f32>(0.9, 0.8, 1.0) * heldGlow * (edge_intensity + wave) * 0.5;

    // Temporal potentiation: previous trail strengthens with repeated activation
    let potentiation = max(intensity * 0.5 + evoked * 0.3, prev_trail * trail_decay * (1.0 + bass * 0.1));
    col = mix(col, col * 1.3, clamp(potentiation, 0.0, 1.0));

    // Depth-scaled node density: distant nodes appear smaller
    let depthScale = 0.5 + depth * 0.5;
    col = col * depthScale;
    let scaledIntensity = intensity * depthScale;

    // Alpha = synaptic activity: potentiated trail + firing intensity + transmitter density
    let alpha = clamp(potentiation + scaledIntensity * 0.3 + nt * 0.2 + mids * 0.05 + treble * 0.05, 0.0, 1.0);

    let display = acesToneMap(col * 1.1);
    let finalColor = vec4<f32>(display, alpha);

    textureStore(writeTexture, coords, finalColor);
    textureStore(dataTextureA, coords, finalColor);
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
