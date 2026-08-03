// ═══════════════════════════════════════════════════════════════════
//  Magnetic Ferrofluid
//  Category: generative
//  Features: raymarched, mouse-driven, audio-reactive
//  Complexity: High
//  Upgraded: 2026-08-03 (Batch 34)
//  upgraded-rgba
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
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
    zoom_params: vec4<f32>,  // x=SpikeHeight, y=Density, z=Speed, w=ColorShift
    ripples: array<vec4<f32>, 50>,
};

// --- Helper Functions ---

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

// Pseudo-random and Noise functions
// ... (hash33, snoise, etc.) ...

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
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
    let bass = plasmaBuffer[0].x;

    // Base fluid mass
    let fluidRadius = 1.15 + u.zoom_params.y * 0.65;
    var d = sdSphere(pos, fluidRadius);

    // Magnetic spikes displacement
    let spikeDensity = u.zoom_params.y * 5.0 + 3.0;
    let spikeHeight = u.zoom_params.x * (0.38 + bass * 0.18) + 0.04;

    // Use noise to generate spiky perturbations based on direction
    let spikeDisplacement = sin(spikeDensity * pos.x) * sin(spikeDensity * pos.y) * sin(spikeDensity * pos.z) * spikeHeight;

    // Add time-based oscillation to the spikes
    let oscillation = sin(time + length(pos) * 4.0 + bass * 3.0) * 0.5 + 0.5;

    d += spikeDisplacement * oscillation;

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
    let bass = plasmaBuffer[0].x;
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
    var mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) { mouse = rawMouse; mouseVelocity = vec2<f32>(0.0); }
    let springDt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
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
        t += max(abs(d) * 0.75, 0.002);
    }

    var col = vec3<f32>(0.05, 0.05, 0.08); // Background color

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

        col = matCol * dif * (1.5 + bass * 0.4) + vec3<f32>(1.0) * spec * (1.5 + plasmaBuffer[0].z) + matCol * fre;

        // Add fake environment reflection (simple gradient mapping)
        let refl = reflect(rd, n);
        let envCol = mix(vec3<f32>(0.1, 0.2, 0.3), vec3<f32>(0.8, 0.9, 1.0), refl.y * 0.5 + 0.5);
        col += envCol * matCol * 0.8;
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
    col += vec3<f32>(0.25, 0.8, 1.25) * magneticPulse * (0.7 + plasmaBuffer[0].y * 0.35);

    // Subtle vignette
    col = col * (1.0 - 0.2 * length(uv));
    let coord = vec2<i32>(id.xy);
    let prev = textureLoad(dataTextureC, coord, 0);
    col = mix(max(col, vec3<f32>(0.0)), prev.rgb * 0.9, clamp(0.025 + plasmaBuffer[0].y * 0.008, 0.0, 0.05));
    col = acesToneMap(col * 1.1);
    let _alpha = clamp(select(0.08, 0.78, hit) + magneticPulse * 0.18, 0.0, 0.96);
    let outColor = vec4<f32>(col, _alpha);
    let _depth = select(0.0, clamp(1.0 - t / 20.0, 0.0, 1.0), hit);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(_depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outColor);
}
