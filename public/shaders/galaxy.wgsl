// ═══════════════════════════════════════════════════════════════════
//  Galaxy Simulation v2 - Audio-reactive spiral galaxy
//  Category: generative
//  Features: upgraded-rgba, depth-aware, audio-reactive, mouse-driven,
//            procedural, animated
//  Upgraded: 2026-05-02 (Tier-1 integration pass), 2026-11-19
//  Ideas: arm dust lanes (Beer-Lambert extinction, §12.2F); arm-born stellar population + HII knots
//  A packing: (density, armDensity, starBright, alpha) raw fields; ACES on display RGB only
//  CRITICAL FIX: replaced legacy u.config.yzw audio with plasmaBuffer
//  Creative additions: bass-driven breathing arms, diffraction-spike stars,
//                      reverse-flow during silence
//  Rescue 2026-11-19: integer arm count (a fractional count put a hard seam on the atan2 branch
//                     cut); star hash no longer takes time (it re-rolled every frame); round star cores
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    let q = vec3<f32>(
        dot(p, vec3<f32>(127.1, 311.7, 74.7)),
        dot(p, vec3<f32>(269.5, 183.3, 246.1)),
        dot(p, vec3<f32>(113.5, 271.9, 124.6))
    );
    return fract(sin(q) * 43758.5453);
}

// Sin-free integer-lattice hash for the HII knot cells — bodies copied verbatim from
// public/shaders/_std/_std_hash.wgsl (pcg3d, u32ToUnit, hashCell33).
fn pcg3d(v_in: vec3<u32>) -> vec3<u32> {
  var v = v_in * 1664525u + 1013904223u;
  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;
  v = v ^ (v >> vec3<u32>(16u));
  v.x += v.y * v.z;
  v.y += v.z * v.x;
  v.z += v.x * v.y;
  return v;
}

fn u32ToUnit(x: u32) -> f32 {
  return f32(x >> 8u) * (1.0 / 16777216.0);
}

fn hashCell33(c: vec3<i32>) -> vec3<f32> {
  let h = pcg3d(bitcast<vec3<u32>>(c));
  return vec3<f32>(u32ToUnit(h.x), u32ToUnit(h.y), u32ToUnit(h.z));
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
    let uv = vec2<f32>(global_id.xy) / resolution;
    let coord = vec2<i32>(global_id.xy);
    let time = u.config.x;

    let inputColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let inputDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ═══ AUDIO from plasmaBuffer (replaces u.config.yzw) ═══
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioOverall = (bass + mids + treble) / 3.0;
    let silence = smoothstep(0.08, 0.0, audioOverall);

    // Domain-specific params
    let opacityP = u.zoom_params.x;        // Opacity
    let armCountP = u.zoom_params.y;       // Arm Count
    let rotationP = u.zoom_params.z;       // Rotation Speed
    let armSpread = u.zoom_params.w;       // Arm Spread

    let opacity = mix(0.5, 1.0, opacityP);
    // Integer: cos(spiralAngle * arms) over an atan2 angle only closes on the branch cut for whole arms.
    let arms = floor(mix(2.0, 6.0, armCountP) + 0.5);
    let rotation = mix(0.5, 3.0, rotationP);
    let spread = mix(0.1, 0.5, armSpread);

    // Mouse-driven center offset (parallax)
    let aspect = resolution.x / max(resolution.y, 1.0);
    let mouseUV = u.zoom_config.yz - vec2<f32>(0.5);
    let centerOffset = mouseUV * 0.4;
    var screenP = (uv - 0.5 - centerOffset * 0.5) * 2.0;
    screenP.x = screenP.x * aspect;

    let radius = length(screenP);
    let angle = atan2(screenP.y, screenP.x);

    // Bass drives spiral rotation; silence reverses time
    let timeFlow = mix(time, -time, silence);
    let bassRot = rotation * timeFlow * 0.1 * (1.0 + bass * 1.2);
    // Mids twist arms (more arm-relative shear)
    let armTwist = radius * (2.0 + mids * 1.5);
    let spiralAngle = angle + bassRot - armTwist;
    let armModulation = cos(spiralAngle * arms);

    // ─── Creative: bass-driven breathing arms ───
    let breath = 1.0 + sin(timeFlow * 0.7) * 0.05 + bass * 0.18;
    let breathRadius = radius / max(breath, 0.001);

    let coreDensity = exp(-breathRadius * 3.0);
    let radialFall = exp(-breathRadius * 1.5);
    let armCore = smoothstep(1.0 - spread, 1.0, armModulation);
    let armDensity = armCore * radialFall;
    let density = (coreDensity * 0.6 + armDensity * 0.4) * 1.25;

    // ── Idea 1: arm dust lanes (Beer-Lambert, §12.2F). Gas shocks on the inner (concave, larger
    // spiral phase) edge of each arm and the dust there eats the disc light behind it, blue most.
    // Lane sits at 0.6 of the arm half-width so it stays inside the arm at any Arm Spread.
    // acos(1 - spread) ≈ sqrt(2·spread) (≤ 0.03 rad off over the slider range); cos(0.3·w) ≈ 1 - 0.09·spread.
    let armHalfW = sqrt(2.0 * spread);
    let lane = smoothstep(1.0 - 0.09 * spread, 1.0, cos(spiralAngle * arms - 0.6 * armHalfW))
             * smoothstep(0.06, 0.22, radius) * radialFall;
    // one exp: tau ∝ 1 : 2 : 3 across R : G : B, so G and B are powers of the R transmittance
    let dustR = exp(-0.9 * lane);
    let dustTrans = vec3<f32>(dustR, dustR * dustR, dustR * dustR * dustR);

    // ── Idea 2: arm-born stellar population. Young clusters follow the arms (star density and a
    // blue-white tint rise with arm mask), the bulge/disc stays old yellow-orange.
    let armMask = armCore * sqrt(radialFall);

    // Stars (time-free hash: the field is stable; treble twinkle below is the scintillation)
    let starHash = hash3(vec3<f32>(floor(screenP * 50.0), 0.0));
    let starThresh = 0.997 - 0.011 * armMask;
    let isStar = step(starThresh, starHash.x);
    let starCoreF = fract(screenP * 50.0) - 0.5;
    let starBright = isStar * starHash.y * (1.0 - smoothstep(0.0324, 0.25, dot(starCoreF, starCoreF)));

    // ─── Creative: diffraction-spike stars (4-point cross) ───
    let starCell = floor(screenP * 50.0);
    let starOffset = (fract(screenP * 50.0) - 0.5) / 50.0;
    let spikeLen = (0.002 + starHash.y * 0.012) * (1.0 + bass * 0.3);
    let spikeH = spikeLen / max(abs(starOffset.y) + 0.0005, 0.0005) * smoothstep(spikeLen, 0.0, abs(starOffset.x));
    let spikeV = spikeLen / max(abs(starOffset.x) + 0.0005, 0.0005) * smoothstep(spikeLen, 0.0, abs(starOffset.y));
    let spike = (spikeH + spikeV) * 0.0008 * isStar * starHash.y;
    // Star colour: the HEAD random blue (young/hot) → red (old/cool) temperature by hash.z,
    // pulled 65% toward the arm-born population colour (Idea 2): blue-white in arms, yellow-orange elsewhere.
    let randTemp = mix(vec3<f32>(0.6, 0.7, 1.0), vec3<f32>(1.0, 0.7, 0.5), starHash.z);
    let popTemp = mix(vec3<f32>(1.0, 0.74, 0.48), vec3<f32>(0.62, 0.74, 1.0), smoothstep(0.15, 0.7, armMask));
    let starTempColor = mix(randTemp, popTemp, 0.65);

    // HII knots: sparse pink star-forming nebulae on the arms (coarse jittered cells)
    let knotCell = floor(screenP * 16.0);
    let knotHash = hashCell33(vec3<i32>(vec2<i32>(knotCell), 7));
    let knotOff = screenP * 16.0 - (knotCell + 0.3 + 0.4 * knotHash.xy);
    let knotFall = max(1.0 - dot(knotOff, knotOff) * 8.0, 0.0);
    let knot = step(0.78, knotHash.z) * knotFall * knotFall * smoothstep(0.25, 0.8, armMask)
             * smoothstep(0.1, 0.25, radius);

    // Galaxy palette
    let coreColor = vec3<f32>(0.3, 0.5, 1.0);
    let armColor = vec3<f32>(1.0, 0.8, 0.4);
    let baseColor = mix(coreColor, armColor, smoothstep(0.0, 0.5, breathRadius));

    var generatedColor = baseColor * density * dustTrans;
    generatedColor = generatedColor + starTempColor * starBright;
    generatedColor = generatedColor + starTempColor * spike;
    generatedColor = generatedColor + vec3<f32>(1.0, 0.38, 0.6) * knot * 0.5;

    // Treble drives twinkle frequency
    let twinkleFreq = 3.0 + treble * 18.0;
    let twinkle = sin(time * twinkleFreq + breathRadius * 10.0) * 0.1 + 0.9;
    generatedColor = generatedColor * twinkle;

    // Central pulsing eye (singularity)
    let eye = exp(-radius * 60.0) * (1.0 + bass * 2.0);
    generatedColor = generatedColor + vec3<f32>(1.0, 0.95, 0.8) * eye * 0.6;

    // Vignette
    let vignette = 1.0 - radius * 0.5;
    generatedColor = generatedColor * vignette;

    // Tone map
    generatedColor = acesToneMapping(generatedColor);

    let luma = dot(generatedColor, vec3<f32>(0.299, 0.587, 0.114));
    let presence = smoothstep(0.05, 0.2, luma);
    // The dust lane is an opaque absorber over lit disc, not a hole to the photo behind it: it
    // keeps the alpha the undusted glow would have had (and none where there was no glow).
    // (raw-luma thresholds 0.055..0.14 are where the ACES luma crosses presence's 0.05..0.2)
    let litLuma = dot(baseColor * density * vignette, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = max(presence, lane * smoothstep(0.055, 0.14, litLuma));

    let finalColor = mix(inputColor.rgb, generatedColor, alpha * opacity);
    let finalAlpha = max(inputColor.a, alpha * opacity);

    let generatedDepth = 1.0 - radius * 0.5;
    let finalDepth = mix(inputDepth, generatedDepth, alpha * opacity);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, finalAlpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));

    // Star density field for downstream multi-pass glow
    textureStore(dataTextureA, coord, vec4<f32>(density, armDensity, starBright, alpha));
}
