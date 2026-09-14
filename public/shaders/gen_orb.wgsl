// ═══════════════════════════════════════════════════════════════════
//  Lorenz Strange Attractor
//  Category: generative
//  Features: audio-reactive, mouse-driven, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-14
//  Ideas: lobe-switch sparks where trajectories cross between the two wings; unstable fixed-point eyes C± = (±√(β(ρ−1)), ±√(β(ρ−1)), ρ−1)
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
  zoom_params: vec4<f32>,  // .x = Sigma (σ), .y = Rho (ρ), .z = Beta (β), .w = Trail Persistence
  ripples: array<vec4<f32>, 50>,
};

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

fn lorenzDerivative(pos: vec3<f32>, sigma: f32, rho: f32, beta: f32) -> vec3<f32> {
    let dx = sigma * (pos.y - pos.x);
    let dy = pos.x * (rho - pos.z) - pos.y;
    let dz = pos.x * pos.y - beta * pos.z;
    return vec3<f32>(dx, dy, dz);
}

fn rk4Step(pos: vec3<f32>, dt: f32, sigma: f32, rho: f32, beta: f32) -> vec3<f32> {
    let k1 = lorenzDerivative(pos, sigma, rho, beta);
    let k2 = lorenzDerivative(pos + k1 * dt * 0.5, sigma, rho, beta);
    let k3 = lorenzDerivative(pos + k2 * dt * 0.5, sigma, rho, beta);
    let k4 = lorenzDerivative(pos + k3 * dt, sigma, rho, beta);
    return pos + (k1 + 2.0 * k2 + 2.0 * k3 + k4) * dt / 6.0;
}

// Shared camera projection (Y rotation then X tilt) into screen space.
fn projectLorenz(q: vec3<f32>, cosY: f32, sinY: f32, cosX: f32, sinX: f32, camDist: f32) -> vec3<f32> {
    var rotated = vec3<f32>(q.x * cosY - q.z * sinY, q.y, q.x * sinY + q.z * cosY);
    rotated = vec3<f32>(rotated.x, rotated.y * cosX - rotated.z * sinX, rotated.y * sinX + rotated.z * cosX);
    let z = rotated.z + camDist;
    let scale = 15.0 / max(z, 0.1);
    return vec3<f32>(rotated.x * scale * 0.0015, rotated.y * scale * 0.0015, z);
}

fn acesToneMapping(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;

    // ═══ Audio reactivity from plasmaBuffer[0] ═══
    let bass = clamp(plasmaBuffer[0].x, 0.0, 1.0);
    let mids = clamp(plasmaBuffer[0].y, 0.0, 1.0);
    let treble = clamp(plasmaBuffer[0].z, 0.0, 1.0);

    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ═══ Aspect / pixel coordinate ═══
    let aspect = resolution.x / max(resolution.y, 1.0);
    var p = uv * 2.0 - 1.0;
    p.x = p.x * aspect;

    // ═══ Domain-specific parameters: σ, ρ, β, Trail Persistence ═══
    let sigma = mix(5.0, 20.0, u.zoom_params.x);   // Prandtl number
    let rho = mix(10.0, 45.0, u.zoom_params.y);    // Rayleigh number
    let beta = mix(1.0, 5.0, u.zoom_params.z);     // geometric factor
    let trailPersistence = clamp(u.zoom_params.w, 0.0, 0.98);

    // ═══ Mouse: hold and drag to orbit / tilt the camera ═══
    let mouse = u.zoom_config.yz;
    let held = select(0.0, 1.0, u.zoom_config.w > 0.5);
    let orbitOffset = (mouse.x - 0.5) * 3.14159 * held;
    let tilt = 0.3 + (mouse.y - 0.5) * 1.2 * held;

    // ═══ Click ripples: butterfly-effect kicks perturb every trajectory ═══
    var kick = 0.0;
    var rippleRing = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var r = 0u; r < rippleCount; r = r + 1u) {
        let rp = u.ripples[r];
        let age = time - rp.z;
        if (age < 0.0 || age > 4.0) { continue; }
        let fade = exp(-age * 1.5);
        kick = kick + fade;
        var rc = rp.xy * 2.0 - 1.0;
        rc.x = rc.x * aspect;
        let rd = length(p - rc);
        rippleRing = rippleRing + exp(-abs(rd - age * 0.6) * 40.0) * fade;
    }
    kick = min(kick, 2.0);

    // Mids modulate camera rotation speed
    let rotSpeed = time * (0.15 + mids * 0.45) + orbitOffset;
    let camDist = 35.0;
    let cosY = cos(rotSpeed);
    let sinY = sin(rotSpeed);
    let cosX = cos(tilt);
    let sinX = sin(tilt);

    // Background - deep space
    var generatedColor = vec3<f32>(0.02, 0.02, 0.04);
    var accumColor = vec3<f32>(0.0);
    var maxDepth = 0.0;

    // Bass adds streams (8..14) and boosts glow
    let streamCount = 8 + i32(round(bass * 6.0));
    let stepsPerStream = 400;
    let glowBoost = 1.0 + bass * 0.9;

    // Treble jitter amplitude (in attractor space) + click kicks
    let jitterAmp = treble * 0.35 + kick * 0.8;

    var sparks = 0.0;

    for (var s = 0; s < 14; s = s + 1) {
        if (s >= streamCount) { break; }

        let seed = hash3(vec3<f32>(f32(s) * 12.34, time * 0.1, 0.0));
        var pos = vec3<f32>(
            seed.x * 2.0 - 1.0,
            seed.y * 2.0 - 1.0,
            25.0 + seed.z * 10.0
        );

        var warmup = 0;
        var tempPos = pos;
        loop {
            if (warmup >= 500) { break; }
            tempPos = rk4Step(tempPos, 0.005, sigma, rho, beta);
            warmup = warmup + 1;
        }
        pos = tempPos;

        var prevScreenPos = vec2<f32>(-1000.0);
        var prevVel = 0.0;

        for (var i = 0; i < stepsPerStream; i = i + 1) {
            let currentPos = pos;
            pos = rk4Step(pos, 0.008, sigma, rho, beta);

            // Treble jitter / click kick
            if (jitterAmp > 0.001) {
                let j = hash3(vec3<f32>(f32(s) * 7.13, f32(i) * 0.21, time * 5.0)) * 2.0 - 1.0;
                pos = pos + j * jitterAmp;
            }

            let vel = length(pos - currentPos);
            let avgVel = (vel + prevVel) * 0.5;
            prevVel = vel;

            let proj = projectLorenz(currentPos, cosY, sinY, cosX, sinX, camDist);
            let z = proj.z;
            if (z > 0.1) {
                let screenPos = proj.xy;

                let dist = length(p - screenPos);
                let depth = 1.0 - (z / 60.0);
                maxDepth = max(maxDepth, depth);

                let particleSize = (0.003 + avgVel * 0.5) * (0.5 + depth * 0.5);
                let glow = particleSize / (dist * dist + 0.0001);

                let speedNorm = clamp(avgVel * 50.0, 0.0, 1.0);
                let hue = f32(s) * 0.125 + speedNorm * 0.3 + time * 0.05;

                let h = fract(hue) * 6.0;
                let c = 1.0;
                let x = c * (1.0 - abs((h % 2.0) - 1.0));
                var rgb = vec3<f32>(0.0);
                if (h < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
                else if (h < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
                else if (h < 3.0) { rgb = vec3<f32>(0.0, c, x); }
                else if (h < 4.0) { rgb = vec3<f32>(0.0, x, c); }
                else if (h < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
                else { rgb = vec3<f32>(c, 0.0, x); }

                let trailFade = 1.0 - f32(i) / f32(stepsPerStream);

                // ─── Bioluminescent bloom: near particles get a soft halo ───
                let depthHalo = smoothstep(0.5, 1.0, depth);
                let halo = (particleSize * 4.0) / (dist * dist * 4.0 + 0.001) * depthHalo;

                accumColor = accumColor + rgb * glow * trailFade * depth * 0.3 * glowBoost;
                accumColor = accumColor + rgb * halo * trailFade * 0.06;

                if (prevScreenPos.x > -100.0) {
                    let lineDist = abs(dist - length(p - prevScreenPos));
                    let lineGlow = 0.0005 / (lineDist * lineDist + 0.00001);
                    accumColor = accumColor + rgb * lineGlow * trailFade * depth * 0.1 * glowBoost;
                }

                // ─── Idea 1: lobe-switch sparks — the chaotic hop between wings (x changes sign) ───
                if (currentPos.x * pos.x < 0.0) {
                    sparks = sparks + 0.000004 / (dist * dist + 0.000004) * trailFade * depth;
                }

                prevScreenPos = screenPos;
            }
        }
    }

    // Butterfly wing highlights
    let wingGlow1 = 0.002 / (length(p - vec2<f32>(-0.15, 0.05)) + 0.03);
    let wingGlow2 = 0.002 / (length(p - vec2<f32>(0.15, -0.05)) + 0.03);
    accumColor = accumColor + vec3<f32>(0.8, 0.3, 0.9) * wingGlow1 * 0.2;
    accumColor = accumColor + vec3<f32>(0.3, 0.7, 0.9) * wingGlow2 * 0.2;

    // ─── Idea 2: unstable fixed-point eyes C± that the wings spiral around ───
    let fpR = sqrt(max(beta * (rho - 1.0), 0.0));
    let cPlus = projectLorenz(vec3<f32>(fpR, fpR, rho - 1.0), cosY, sinY, cosX, sinX, camDist);
    let cMinus = projectLorenz(vec3<f32>(-fpR, -fpR, rho - 1.0), cosY, sinY, cosX, sinX, camDist);
    let eyeRadius = fpR * 0.0003 * (1.0 + bass * 0.4);
    let dPlus = length(p - cPlus.xy);
    let dMinus = length(p - cMinus.xy);
    let eyeCore = 0.000002 / (dPlus * dPlus + 0.000002) + 0.000002 / (dMinus * dMinus + 0.000002);
    let eyeRing = exp(-abs(dPlus - eyeRadius) * 800.0) + exp(-abs(dMinus - eyeRadius) * 800.0);
    accumColor = accumColor + vec3<f32>(1.0, 0.85, 0.55) * eyeCore * 2.0;
    accumColor = accumColor + vec3<f32>(0.4, 0.9, 1.0) * eyeRing * (0.6 + mids * 0.4);

    accumColor = accumColor + vec3<f32>(1.0, 0.95, 0.9) * sparks * (1.5 + treble * 1.5);
    accumColor = accumColor + vec3<f32>(0.6, 0.8, 1.0) * rippleRing * 0.5;

    generatedColor = generatedColor + accumColor;

    // ACES tone mapping
    generatedColor = acesToneMapping(generatedColor * 1.1);

    // Subtle vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.5;
    generatedColor = generatedColor * vignette;

    // ─── Persistent scent trail: exact load of previous display frame from dataTextureC ───
    let prevTrail = textureLoad(dataTextureC, clamp(coord, vec2<i32>(0), vec2<i32>(resolution) - vec2<i32>(1)), 0);
    let decayed = prevTrail.rgb * trailPersistence;
    let displayColor = max(generatedColor, decayed);

    // Alpha = glow presence (luminous coverage of attractor + trail)
    let luma = dot(displayColor, vec3<f32>(0.299, 0.587, 0.114));
    let presence = smoothstep(0.02, 0.18, luma);
    let alpha = clamp(max(presence * 0.85, prevTrail.a * trailPersistence), 0.0, 1.0);

    let finalDepth = mix(inputDepth, maxDepth, presence * 0.85);
    let finalColor = vec4<f32>(displayColor, alpha);

    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, finalColor);
}
