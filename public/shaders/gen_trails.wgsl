// ═══════════════════════════════════════════════════════════════════
//  Boids Flocking v2 - Audio-reactive Reynolds boids
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven,
//            particles, flocking, motion-trails, temporal
//  Upgraded: 2026-05-02 (Tier-1 integration pass)
//  FIX: mouse-down detection now uses zoom_config.w (was always-true length)
//  Creative additions: pheromone trails in dataTextureA, motion-blur streaks
//  Upgraded: 2026-11-01
//  Ideas: real pheromone trails (A = pheromone, read as exact C, screen-composited under the live boids); continuous flight paths (fixed per-boid hash, wrapped straight drift - HEAD re-rolled every boid every frame); wing beat
//  A packing: CHANGED - A = (pheromone RGB, pheromone luma), read as C .rgb. HEAD's A velocity/density tuple was read back as colour (packing lie) and had no other reader. B unchanged (pheromone + alpha).
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash3(p: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(
        fract(sin(dot(p.xy, vec2<f32>(12.9898, 78.233))) * 43758.5453),
        fract(sin(dot(p.yz + 0.5, vec2<f32>(93.9898, 67.345))) * 23421.631),
        fract(sin(dot(p.zx + 1.0, vec2<f32>(43.212, 12.123))) * 54235.231)
    );
}

// Per-boid constants. HEAD hashed continuous time (time * 0.01 / 0.02) through fract(sin(x) * 43758),
// so every boid position and heading was re-rolled to a new random value every frame; the "flock" was
// frame-rate noise. The hash is now a fixed function of the boid id.
fn boidBaseVelocity(id: u32) -> vec2<f32> {
    let idf = f32(id);
    let h = hash3(vec3<f32>(idf * 0.2 + 100.0, 0.0, idf * 0.05));
    let angle = h.x * 6.28318530718;
    return vec2<f32>(cos(angle), sin(angle)) * (0.3 + h.y * 0.5);
}

// Idea 2: continuous flight. Straight drift from a fixed start, wrapped to the screen box.
fn getBoidPosition(id: u32, time: f32, aspect: f32) -> vec2<f32> {
    let idf = f32(id);
    let h = hash3(vec3<f32>(idf * 0.1, 0.0, idf * 0.01));
    let ext = vec2<f32>(aspect, 1.0);
    let start = (h.xy * 2.0 - 1.0) * ext;
    let drift = start + boidBaseVelocity(id) * time * 0.12;
    return (fract((drift + ext) / (2.0 * ext)) * 2.0 - 1.0) * ext;
}

// Heading: the fixed base heading with a slow per-boid wander, so rules steer from a moving baseline.
fn getBoidVelocity(id: u32, time: f32) -> vec2<f32> {
    let idf = f32(id);
    let base = boidBaseVelocity(id);
    let wander = 0.35 * sin(time * 0.3 + idf * 1.7);
    let c = cos(wander);
    let s = sin(wander);
    return vec2<f32>(base.x * c - base.y * s, base.x * s + base.y * c);
}

fn getBoidColor(id: u32, time: f32) -> vec3<f32> {
    let flockId = id / 30u;
    let flockCount = 6u;
    let hue = (f32(flockId % flockCount) / f32(flockCount)) + time * 0.05;
    let h = fract(hue) * 6.0;
    let c = 1.0;
    let x = c * (1.0 - abs((h % 2.0) - 1.0));
    if (h < 1.0) { return vec3<f32>(c, x, 0.0); }
    if (h < 2.0) { return vec3<f32>(x, c, 0.0); }
    if (h < 3.0) { return vec3<f32>(0.0, c, x); }
    if (h < 4.0) { return vec3<f32>(0.0, x, c); }
    if (h < 5.0) { return vec3<f32>(x, 0.0, c); }
    return vec3<f32>(c, 0.0, x);
}

fn softParticleAlpha(dist: f32, radius: f32) -> f32 {
    let t = dist / max(radius, 0.0001);
    return exp(-t * t * 2.0);
}

fn transmittance(density: f32) -> f32 {
    return exp(-density);
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
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let px = vec2<i32>(global_id.xy);
    let coord = px;
    let time = u.config.x;

    // Audio
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let aspect = resolution.x / max(resolution.y, 1.0);
    var screenUV = uv * 2.0 - 1.0;
    screenUV.x = screenUV.x * aspect;

    // Mouse position + correct mouse-down detection (uses zoom_config.w)
    var mouse = u.zoom_config.yz * 2.0 - 1.0;
    mouse.x = mouse.x * aspect;
    let mouseDown = u.zoom_config.w > 0.5;

    // Domain-specific params: Separation, Alignment, Cohesion, Max Speed
    let separationWeight = u.zoom_params.x * 2.0;
    let alignmentWeight = u.zoom_params.y * 1.5;
    let cohesionWeight = u.zoom_params.z * 1.0 * (1.0 + mids * 0.7);   // mids → cohesion boost
    let maxSpeed = (0.5 + u.zoom_params.w * 1.5) * (1.0 + bass * 0.7);  // bass → panic speed

    let neighborRadius = 0.25;
    let separationRadius = 0.08 * (1.0 + bass * 1.0);  // bass → larger separation
    let numBoids = 180u;

    let particle_radius = 0.015;
    let particle_opacity = 0.7;

    // Read history (previous accumulated frame for trails)
    let history = textureLoad(dataTextureC, px, 0);

    var accumulated_color = vec3<f32>(0.0);
    var accumulated_density: f32 = 0.0;
    var total_energy: f32 = 0.0;

    for (var i: u32 = 0u; i < numBoids; i = i + 1u) {
        var boidPos = getBoidPosition(i, time, aspect);
        var boidVel = getBoidVelocity(i, time);
        // Distance cull (exact within bounds): this boid can only reach pixels within streak length
        // 0.4 of its final position, which is at most maxSpeed * 0.016 <= 0.08 from here. Boids near the
        // wrap edge are never culled because a step can teleport them to the far side.
        let edgeSafe = abs(boidPos.x) < aspect - 0.1 && abs(boidPos.y) < 0.9;
        if (edgeSafe && length(screenUV - boidPos) > 0.6) { continue; }
        let boidColor = getBoidColor(i, time);

        var separation = vec2<f32>(0.0);
        var alignment = vec2<f32>(0.0);
        var cohesion = vec2<f32>(0.0);
        var neighborCount: u32 = 0u;
        var separationCount: u32 = 0u;

        for (var j: u32 = 0u; j < numBoids; j = j + 1u) {
            if (i == j) { continue; }
            let neighborPos = getBoidPosition(j, time, aspect);
            let neighborVel = getBoidVelocity(j, time);
            let diff = boidPos - neighborPos;
            let dist = length(diff);

            if (dist < separationRadius && dist > 0.001) {
                separation = separation + normalize(diff) / dist;
                separationCount = separationCount + 1u;
            }
            if (dist < neighborRadius) {
                alignment = alignment + neighborVel;
                cohesion = cohesion + neighborPos;
                neighborCount = neighborCount + 1u;
            }
        }

        if (separationCount > 0u) { separation = separation / f32(separationCount); }
        if (neighborCount > 0u) {
            alignment = alignment / f32(neighborCount);
            cohesion = (cohesion / f32(neighborCount)) - boidPos;
        }
        if (length(separation) > 0.0) { separation = normalize(separation) * separationWeight; }
        if (length(alignment) > 0.0) { alignment = normalize(alignment - boidVel) * alignmentWeight; }
        if (length(cohesion) > 0.0) { cohesion = normalize(cohesion) * cohesionWeight; }

        var mouseForce = vec2<f32>(0.0);
        if (mouseDown) {
            let toMouse = mouse - boidPos;
            let distToMouse = length(toMouse);
            if (distToMouse > 0.01) { mouseForce = normalize(toMouse) * 0.5; }
        }

        boidVel = boidVel + separation + alignment + cohesion + mouseForce;
        let speed = length(boidVel);
        if (speed > maxSpeed) { boidVel = normalize(boidVel) * maxSpeed; }
        boidPos = boidPos + boidVel * 0.016;

        if (boidPos.x > aspect) { boidPos.x = -aspect; }
        if (boidPos.x < -aspect) { boidPos.x = aspect; }
        if (boidPos.y > 1.0) { boidPos.y = -1.0; }
        if (boidPos.y < -1.0) { boidPos.y = 1.0; }

        let pixelToBoid = screenUV - boidPos;
        let dist = length(pixelToBoid);
        let current_speed = length(boidVel);

        let body_alpha = softParticleAlpha(dist, particle_radius);

        // Velocity-aligned trail
        let velNorm = select(vec2<f32>(1.0, 0.0), boidVel / max(current_speed, 0.0001), current_speed > 0.0001);
        let trailDir = -velNorm;
        let trailLen = 0.15 * (current_speed / maxSpeed);
        let alongTrail = dot(pixelToBoid, trailDir);
        let perpTrail = length(pixelToBoid - trailDir * alongTrail);

        var trail_alpha: f32 = 0.0;
        if (alongTrail > 0.0 && alongTrail < trailLen) {
            let t = alongTrail / max(trailLen, 0.0001);
            let trailWidth = particle_radius * (1.0 - t * 0.8);
            trail_alpha = (1.0 - t * t) * softParticleAlpha(perpTrail, trailWidth);
        }

        // ─── Creative: motion-blur streak (longer, narrower than trail) ───
        let streakLen = 0.4 * (current_speed / maxSpeed);
        var streak_alpha: f32 = 0.0;
        if (alongTrail > 0.0 && alongTrail < streakLen) {
            let t = alongTrail / max(streakLen, 0.0001);
            let streakWidth = particle_radius * 0.3 * (1.0 - t);
            streak_alpha = (1.0 - t) * (1.0 - t) * softParticleAlpha(perpTrail, streakWidth) * 0.6;
        }

        let perpVel = vec2<f32>(-velNorm.y, velNorm.x);
        let wingOffset = abs(dot(pixelToBoid, perpVel));
        // Idea 3: wing beat — the wing span flaps, faster the faster the boid flies.
        let flap = 0.65 + 0.35 * sin(time * (6.0 + current_speed * 8.0) + f32(i) * 1.3);
        let wingShape = 1.0 - smoothstep(0.0, particle_radius * 2.0 * flap, wingOffset);
        let headDist = length(pixelToBoid - velNorm * particle_radius * 0.5);
        let wing_alpha = wingShape * (1.0 - smoothstep(0.0, particle_radius, headDist)) * 0.5;

        let total_alpha = body_alpha * 1.5 + trail_alpha * 0.7 + wing_alpha * 0.3 + streak_alpha;

        // Treble: random boids flash bright
        let flashSeed = fract(sin(f32(i) * 12.9898 + floor(time * 8.0) * 78.233) * 43758.5453);
        let flash = step(1.0 - treble * 0.35, flashSeed) * 2.0;
        let emission = 1.0 + current_speed * 2.0 + flash;
        let hdr_color = boidColor * emission;

        accumulated_color = accumulated_color + hdr_color * total_alpha * particle_opacity;
        accumulated_density = accumulated_density + total_alpha * particle_opacity;
        total_energy = total_energy + total_alpha * emission;

    }

    // Audio-reactive bass burst spawn (extra glow on bass hits)
    let burst = pow(bass, 3.0) * 0.6;
    accumulated_color = accumulated_color + vec3<f32>(0.9, 0.5, 1.0) * burst * 0.3;

    // Tone mapping (ACES)
    accumulated_color = acesToneMapping(accumulated_color * 0.7);

    let trans = transmittance(accumulated_density * 0.3);
    let final_alpha = 1.0 - trans;
    let energy_boost = min(total_energy * 0.01, 0.3);
    let final_alpha_boosted = min(final_alpha + energy_boost, 1.0);

    // History blend (pheromone trails)
    let trailDecay = 0.92;
    let history_contrib = history.rgb * trailDecay;
    let new_pheromone = max(history_contrib, accumulated_color * 0.45);

    if (mouseDown) { accumulated_color = accumulated_color * 1.3; }

    let output_color = mix(history_contrib, accumulated_color, final_alpha_boosted);

    // Sample input
    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let opacity = 0.85;
    let liveColor = mix(inputColor.rgb, output_color, final_alpha_boosted * opacity);
    // Idea 1: pheromone trails. The memory (read back through exact C, evaporating 0.92 per frame) is
    // screen-composited under the live boids, so a deposit stays visible where the boid was.
    let pheromoneVis = new_pheromone * (1.0 - final_alpha_boosted);
    let finalColor = vec3<f32>(1.0) - (vec3<f32>(1.0) - liveColor) * (vec3<f32>(1.0) - pheromoneVis * 0.8);
    let finalAlpha = max(inputColor.a, final_alpha_boosted * opacity);

    textureStore(writeTexture, coord, vec4<f32>(clamp(finalColor, vec3<f32>(0.0), vec3<f32>(3.0)), finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(inputDepth, 0.0, 0.0, 0.0));

    // dataTextureA: pheromone memory (RGB) + its luma (A). C is read as colour next frame, so A must
    // be a colour history; HEAD stored velocity/density here and read them back as colour.
    let pherLuma = dot(new_pheromone, vec3<f32>(0.299, 0.587, 0.114));
    textureStore(dataTextureA, coord, vec4<f32>(new_pheromone, pherLuma));

    // dataTextureB: store accumulated color for downstream advection / pheromone field
    textureStore(dataTextureB, coord, vec4<f32>(new_pheromone, final_alpha_boosted));
}
