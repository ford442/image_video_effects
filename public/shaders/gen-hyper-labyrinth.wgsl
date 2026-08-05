// ═══════════════════════════════════════════════════════════════
// Hyper Labyrinth - 4D Maze Visualization
// Category: generative
// Features: 4D geometry, raymarching, neon aesthetics
// Upgrade (Batch 36 / Visualist): 3-point lighting with dynamic
// key temperature, volumetric proximity glow, HDR neon veins +
// ACES grade, emissive persistence in dataTextureA, audio-
// reactive veins / rim / shimmer, near-is-one depth.
// ═══════════════════════════════════════════════════════════════

// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame (A)
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data

// ---------------------------------------------------
struct Uniforms {
    config: vec4<f32>, // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>, // x=ZoomTime, y=MouseX, z=MouseY (0-1, y=0 top), w=MouseDown
    zoom_params: vec4<f32>, // x=Param1 (scale), y=Param2 (morph speed), z=Param3 (glow), w=Param4 (thickness)
    ripples: array<vec4<f32>, 50>,
};

// ── Color science helpers ───────────────────────────────────────
// ACES filmic approximation (HDR in, display-ready out)
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Dynamic key-light temperature: ember amber <-> hot arc-white,
// drifting slowly and pushed warm by bass energy.
fn keyTemperature(t: f32, bass: f32) -> vec3<f32> {
    let k = 0.5 + 0.5 * sin(t * 0.23 + bass * 1.7);
    return mix(vec3<f32>(1.30, 0.82, 0.55), vec3<f32>(1.05, 1.08, 1.15), k);
}

// 4D Rotation in XW plane
fn rotate4D(p: vec4<f32>, angle: f32) -> vec4<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec4<f32>(
        p.x * c - p.w * s,
        p.y,
        p.z,
        p.x * s + p.w * c
    );
}

// Map function (SDF) - merged best of both
fn map(pos3: vec3<f32>) -> vec2<f32> {
    // Transform 3D pos to 4D (small w for "thickness")
    var p4 = vec4<f32>(pos3, 1.0);

    // 4D rotation driven by time/params
    let speed = mix(0.1, 2.0, u.zoom_params.y); // morph speed
    let time = u.config.x * speed;
    p4 = rotate4D(p4, time);

    // Extra YZ rotation for nice 3D orbiting feel (from main)
    let rotYZ = u.config.x * 0.1;
    let cy = cos(rotYZ);
    let sy = sin(rotYZ);
    let tempY = p4.y * cy - p4.z * sy;
    let tempZ = p4.y * sy + p4.z * cy;
    p4.y = tempY;
    p4.z = tempZ;

    // Gyroid-based 4D maze
    let scale = mix(1.0, 5.0, u.zoom_params.x);
    let q = p4 * scale;
    let val = sin(q.x) * cos(q.y) + sin(q.y) * cos(q.z) + sin(q.z) * cos(q.w) + sin(q.w) * cos(q.x);

    // Wall thickness
    let thickness = mix(0.1, 1.2, u.zoom_params.w);
    let d = (abs(val) - thickness * 0.5) / scale; // proper scale-corrected distance

    return vec2<f32>(d * 0.5, 1.0); // material ID = 1.0 for walls
}

// Normal calculation
fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

// Raymarch with material support + bounded volumetric proximity glow.
// Returns (t, material, glowAccum). Glow accumulates near walls along the
// whole ray, approximating volumetric neon haze / god-ray bleed.
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec3<f32> {
    var t = 0.0;
    var m = 0.0; // 0 = miss
    var glow = 0.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        let d = res.x;
        // Proximity inscatter, bounded: exp(-|d|*k) <= 1, 100 steps -> <= 2.0
        glow += exp(-abs(d) * 9.0) * 0.02;
        if (d < 0.001 || t > 50.0) {
            if (d < 0.001) { m = res.y; }
            break;
        }
        t += d;
    }
    return vec3<f32>(t, m, glow);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let px = vec2<i32>(global_id.xy);

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;

    // === AUDIO (plasma bands + guarded engine FFT bins 1-8) ===
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    var fftShimmer = 0.0;
    if (arrayLength(&extraBuffer) > 13u) {
        for (var k = 1u; k <= 8u; k = k + 1u) {
            fftShimmer += extraBuffer[5u + k];
        }
        fftShimmer = clamp(fftShimmer * 0.125, 0.0, 1.5);
    }

    // === CAMERA (best of both: main's clean spherical + feature's organic drift) ===
    let mouse = u.zoom_config.yz;
    let angleX = (mouse.x - 0.5) * 6.2832;
    let angleY = (mouse.y - 0.5) * 3.1416;  // y=0 top -> mouse up = look up
    let camDist = 8.0;

    var ro = vec3<f32>(
        camDist * cos(angleY) * sin(angleX),
        camDist * sin(angleY),
        camDist * cos(angleY) * cos(angleX)
    );

    // Gentle camera drift for more life
    let time = u.config.x;
    let drift = vec3<f32>(sin(time * 0.1), cos(time * 0.15), sin(time * 0.07)) * 0.6;
    ro += drift;

    let target_pos = vec3<f32>(0.0);
    let fwd = normalize(target_pos - ro);
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), fwd));
    let up = cross(fwd, right);
    let rd = normalize(fwd + right * uv.x + up * uv.y);

    // Raymarch (+ volumetric proximity glow)
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;
    let volGlow = res.z;

    var color = vec3<f32>(0.0);
    var neon = vec3<f32>(0.0); // HDR emissive, persisted across frames
    var alpha = clamp(0.08 + volGlow * 0.55, 0.0, 0.85); // void: semi-transparent haze

    if (mat > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // === 3-POINT LIGHTING (two different temperatures + rim) ===
        let keyDir = normalize(vec3<f32>(0.5, 0.8, -0.5));
        let keyCol = keyTemperature(time, bass);           // dynamic warm<->white
        let keyDiff = max(dot(n, keyDir), 0.0);
        let fillDir = normalize(vec3<f32>(-0.65, -0.25, 0.55));
        let fillCol = vec3<f32>(0.22, 0.42, 0.85);         // cool cyan-blue fill
        let fillDiff = max(dot(n, fillDir), 0.0);
        let amb = vec3<f32>(0.10, 0.09, 0.14);             // violet ambient

        // Blinn-style key specular (HDR sparkle on metallic walls)
        let halfV = normalize(keyDir - rd);
        let spec = pow(max(dot(n, halfV), 0.0), 32.0) * keyCol * 0.7;

        // Dark metallic base lit by the rig
        let baseCol = vec3<f32>(0.06, 0.05, 0.09);
        var surfCol = baseCol * (keyCol * keyDiff * 1.15 + fillCol * fillDiff * 0.55 + amb) + spec * keyDiff;

        // === NEON GLOW / VEINS (feature's beautiful pattern + main's consistency) ===
        let glowIntensity = mix(0.6, 3.5, u.zoom_params.z);

        let speed = mix(0.1, 2.0, u.zoom_params.y);
        let time4d = u.config.x * speed;

        var p4 = vec4<f32>(p, 1.0);
        p4 = rotate4D(p4, time4d);

        // Match the map's extra rotation
        let rotYZ = u.config.x * 0.1;
        let cy = cos(rotYZ);
        let sy = sin(rotYZ);
        let tempY = p4.y * cy - p4.z * sy;
        let tempZ = p4.y * sy + p4.z * cy;
        p4.y = tempY;
        p4.z = tempZ;

        let scale = mix(1.0, 5.0, u.zoom_params.x);
        let q = p4 * scale * 2.0;
        let pattern = sin(q.x) * sin(q.y) * sin(q.z) * sin(q.w);

        // Bass-driven pulse: veins breathe with the low end
        let pulse = (0.5 + 0.5 * sin(time * 2.2 + p.x * 1.3 + p.z * 0.7)) * (0.75 + bass * 0.6);

        var glowCol = vec3<f32>(0.0, 0.85, 1.0); // cyan
        if (pattern > 0.0) {
            glowCol = vec3<f32>(1.0, 0.25, 0.9); // magenta
        }

        let patternFactor = smoothstep(0.35, 0.55, abs(pattern));
        // HDR veins (>1.0 at high glow), FFT bins add spectral shimmer
        neon = glowCol * patternFactor * glowIntensity * pulse * (1.0 + fftShimmer * 0.8);

        // Cyber Fresnel rim, treble-reactive, cool electric tint
        let fresnel = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let rim = vec3<f32>(0.35, 0.60, 1.30) * fresnel * (2.2 + treble * 1.5);

        color = surfCol + rim;
        alpha = 1.0; // walls are opaque by design
    } else {
        // Deep void background, tinted by nearby neon haze
        color = vec3<f32>(0.0, 0.0, 0.045) + volGlow * vec3<f32>(0.04, 0.10, 0.20);
    }

    // === EMISSIVE PERSISTENCE (dataTextureA = neon history) ===
    // Previous frame's veins decay 10%/frame and are re-excited by the
    // current frame -> afterglow smear while orbiting the labyrinth.
    let prevNeon = textureLoad(dataTextureC, px, 0).rgb;
    let persistedNeon = max(neon, prevNeon * 0.90);
    color += persistedNeon;

    // === ATMOSPHERE: depth fog + neon inscatter (volumetric haze) ===
    let fogAmount = 1.0 - exp(-t * 0.065);
    let scatterCol = vec3<f32>(0.010, 0.014, 0.035)
                   + persistedNeon * 0.05
                   + volGlow * vec3<f32>(0.05, 0.12, 0.22);
    color = mix(color, scatterCol, fogAmount);

    // === GRADE: ACES tone map, mids-driven exposure ===
    color = acesToneMap(color * (0.85 + mids * 0.25));

    // Near-is-one hit depth (miss ray t=50 -> ~0.0025, effectively far plane)
    let depth = exp(-t * 0.12);

    textureStore(dataTextureA, px, vec4<f32>(persistedNeon, alpha));
    textureStore(writeTexture, px, vec4<f32>(color, alpha));
    textureStore(writeDepthTexture, px, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
