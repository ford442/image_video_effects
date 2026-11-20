// ═══════════════════════════════════════════════════════════════════
//  Kinetic Dispersion
//  Category: interactive-mouse
//  Features: mouse-driven, dispersion, kinetic, audio-shatter, depth-fragments, prismatic-motion, click-bursts, fft-voices
//  Complexity: Medium
//  Updated: 2026-07-31
//  By: Grok (visual flourish — richer motion, audio-reactive shattering, atmospheric fragments)
//      + Kimi Optimizer (spring-damped influence, click shatter bursts, per-block FFT voices)
// ═══════════════════════════════════════════════════════════════════
//  Created: 2026-05-10
//  Upgraded: 2026-05-31, 2026-11-20
//  Optimized: 2026-07-31
//  Ideas: Schmitt-trigger shatter latch via exact C (§12.2B); block-boundary seam from neighbour displacement jump (§12.2B)
//  A packing: display RGB + A.a = -shatter latch (writeTexture alpha stays semantic)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Sensitivity, y=Scatter, z=Aberration, w=BlockSize

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn bass_env(bass: f32, mids: f32) -> f32 {
  return 1.0 + bass * 0.5 + mids * 0.2;
}

fn curl2D(p: vec2<f32>, t: f32) -> vec2<f32> {
  let eps = 0.01;
  let n1 = hash12(p + vec2<f32>(eps, 0.0) + t * 0.1);
  let n2 = hash12(p - vec2<f32>(eps, 0.0) + t * 0.1);
  let n3 = hash12(p + vec2<f32>(0.0, eps) + t * 0.1);
  let n4 = hash12(p - vec2<f32>(0.0, eps) + t * 0.1);
  let dy = (n1 - n2) / (2.0 * eps);
  let dx = (n3 - n4) / (2.0 * eps);
  return vec2<f32>(dx, -dy);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    let coords = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / u.config.zw;
    let time = u.config.x;
    let mouseRaw = u.zoom_config.yz;  // raw cursor = spring target

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // ── Slider wiring (fixed roles) ──────────────────────────────
    // x=Sensitivity scales the dispersion field strength, z=Aberration
    // scales the r/g/b split, w=BlockSize sets the quantization cell.
    let sensitivity = u.zoom_params.x * 50.0 * bass_env(bass, mids);
    let aberration = u.zoom_params.z * 0.05 * (1.0 + treble * 0.5);
    let granularity = max(1.0, u.zoom_params.w * 50.0);

    let blockUV = floor(uv * u.config.zw / granularity) * granularity / u.config.zw;

    // ── Per-block FFT voices ─────────────────────────────────────
    // Each block listens to its own engine FFT bin (bins live at
    // extraBuffer[5..132]) and shatters to that frequency: the block's
    // scatter amplitude is modulated by ±30%.
    let voiceBin = u32(hash12(blockUV * 7.0) * 8.0) % 8u + 1u;
    var voice = 0.0;
    if (arrayLength(&extraBuffer) > 4u + voiceBin) {
        voice = extraBuffer[4u + voiceBin];
    }
    let voiceGain = 1.0 + (clamp(voice, 0.0, 1.0) - 0.5) * 0.6;
    // y=Scatter scales the per-block displacement kick.
    let scatter = u.zoom_params.y * 0.1 * voiceGain;

    // ── Influence center (rescue) ────────────────────────────────
    // HEAD kept a spring in extraBuffer[133..137]. The engine re-uploads all 256
    // floats of extraBuffer every frame (audioDepth.ts writeExtraBuffer), zeroing
    // 133..138, so the spring never persisted (velocity always 0) and every pixel
    // thread read the centre from a buffer that only thread (0,0) wrote, unordered:
    // a nondeterministic patchwork of "top-left corner" and "cursor" centres on a
    // real GPU. The centre is the cursor, read directly.
    let mouse = mouseRaw;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthScatter = mix(1.3, 0.7, depth);

    let mouseDist = distance(uv, mouse);
    let velocity = (1.0 - smoothstep(0.0, 0.3, mouseDist)) * bass_env(bass, mids);

    // ── Click shatter bursts ─────────────────────────────────────
    // Each live ripple cracks the field at its click point: a decaying
    // dispersion burst (local intensity spike + radial displacement
    // kick) with a ~1.0s fade.
    var burst = 0.0;
    var burstKick = vec2<f32>(0.0, 0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 1.0) { continue; }
        let rpDelta = uv - rp.xy;
        let rpDist = length(rpDelta);
        let crack = (1.0 - smoothstep(0.0, 0.25, rpDist)) * (1.0 - age);
        burst = burst + crack * crack;
        burstKick = burstKick + (rpDelta / max(rpDist, 0.001)) * crack * (1.0 - age);
    }
    burst = min(burst, 1.0);

    let drive = clamp(velocity * sensitivity + burst * 0.5, 0.0, 1.0);

    // ── Idea 1: Schmitt-trigger shatter latch (§12.2B) ───────────
    // A field that cracks does not heal instantly. Per pixel: engage above 0.6,
    // hold while the field is still above 0.25, otherwise relax x0.955 / frame, from
    // the EXACT previous frame (dataTextureC, never filtered). The latch rides in
    // A.a as a NEGATIVE number (HEAD's A.a was the semantic alpha, always >= 0, so a
    // foreign shader's alpha left in a shared A can never read back as a latch).
    // The cursor now leaves a fading wake of still-shattered blocks, and click
    // cracks linger - motion becomes visible without the dead velocity state.
    let prevLatch = clamp(-textureLoad(dataTextureC, coords, 0).a, 0.0, 1.0);
    let engaged = step(0.6, drive);
    let holding = step(0.25, drive);
    let latch = max(prevLatch * mix(0.955, 1.0, holding), engaged);
    let intensity = max(drive, latch * 0.7);

    let safeTime = max(time, 0.001);
    let rnd = hash12(blockUV + vec2<f32>(safeTime * 10.0, safeTime * 20.0));

    let curl = curl2D(blockUV * 3.0, time * 0.2) * intensity * 0.02;
    var displacement = (rnd - 0.5) * intensity * scatter * depthScatter + curl.x;
    // Click bursts kick the block displacement radially outward.
    displacement = displacement + burstKick.x * 0.05;
    let rgbSplit = intensity * aberration * depthScatter;

    // ── Idea 2: block-boundary seam (§12.2B block-domain) ────────
    // The tear IS the difference between neighbouring blocks' offsets, which HEAD
    // never compares. Find the nearest block edge, hash the block across it with the
    // same time term, and glint a 1 px seam where the two displacements differ.
    // Scaled by the Scatter-driven kick (scatter = 0 -> no seam) and faded out for
    // 1-4 px blocks, where "edges" would be every pixel.
    let inCell = fract(vec2<f32>(coords) / granularity);
    let toEdge = min(inCell, vec2<f32>(1.0) - inCell) * granularity;     // px to nearest edge, per axis
    let edgeIsX = toEdge.x <= toEdge.y;
    let nbStep = select(vec2<f32>(0.0, select(-1.0, 1.0, inCell.y > 0.5)),
                        vec2<f32>(select(-1.0, 1.0, inCell.x > 0.5), 0.0), edgeIsX);
    let rndNb = hash12(blockUV + nbStep * granularity / u.config.zw + vec2<f32>(safeTime * 10.0, safeTime * 20.0));
    let gapPx = abs(rnd - rndNb) * intensity * scatter * depthScatter * u.config.z;
    let seam = (1.0 - smoothstep(0.4, 1.4, min(toEdge.x, toEdge.y)))
             * clamp(gapPx * 0.15, 0.0, 1.0) * smoothstep(2.0, 5.0, granularity);

    let r = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement - rgbSplit, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(uv + vec2<f32>(displacement + rgbSplit, displacement), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;

    var color = vec3<f32>(r, g, b);
    let noise = hash12(uv * safeTime);
    color = mix(color, vec3<f32>(noise), intensity * 0.2);

    // Click flash: cracked blocks brighten briefly as the burst decays.
    color = color + vec3<f32>(burst * 0.15, burst * 0.12, burst * 0.2);
    // Idea 2: cracked-edge glint
    color = color + vec3<f32>(0.55, 0.68, 1.0) * seam * 0.35;

    // Audio shockwave on bass hits
    let shock = sin(mouseDist * 30.0 - time * 10.0) * exp(-mouseDist * 2.0) * bass * 0.5;
    color = color + vec3<f32>(shock * 0.3, shock * 0.5, shock * 0.7);

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(0.5 + intensity * 0.35 + luma * 0.15 + bass * 0.1, 0.0, 1.0);

    let finalRGBA = vec4<f32>(color, alpha);

    textureStore(writeTexture, coords, finalRGBA);
    // A packing: display RGB + A.a = -latch (read back above as max(-C.a, 0))
    textureStore(dataTextureA, coords, vec4<f32>(color, -latch));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
