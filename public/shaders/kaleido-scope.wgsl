// ═══════════════════════════════════════════════════════════════════
//  Kaleido-Scope
//  Category: geometric
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09, 2026-11-15
//  Ideas: Poincaré hypR geodesic crease; opposite-wedge dihedral sample; mirror loss per bounce (fold count as material, §12.2E); tumbling object cell (native); atan2-cut seam drawn as a mirror junction (rescue)
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn lensDistort(p: vec2<f32>, strength: f32) -> vec2<f32> {
    let r2 = dot(p, p);
    return p * (1.0 + strength * r2 + strength * r2 * r2 * 0.5);
}

struct PoincareOut {
    mirrorAngle: f32,
    hypR: f32,
    edgeDist: f32,
    bounces: f32,   // mirror reflections away from the primary wedge (wedge index wrapped mod segments, nearer way round)
    cutDist: f32,   // angular distance of this pixel from the atan2 branch cut (theta = +-pi)
    cutJump: f32,   // size of the fold jump across that cut (0 when the wedges close the circle)
};

fn poincareMap(p: vec2<f32>, segments: f32, rot: f32) -> PoincareOut {
    let r = length(p);
    let a0 = atan2(p.y, p.x + select(0.0, 1e-6, r < 1e-6));
    let theta = a0 + rot;
    let hypR = r / (1.0 - min(r * 0.94, 0.99) + 0.001);
    let u = theta / 6.28318 * segments;
    let sector = abs(fract(u) - 0.5) * 2.0;
    let edgeDist = min(sector, 1.0 - sector);
    let mirrorAngle = sector * 3.14159265;
    // ── Rescue 1: atan2 branch-cut seam ──────────────────────────────
    // A non-integer segment count cannot close around 2π, so the fold on the two
    // sides of the cut (theta = +π / −π) disagrees. cutJump is that disagreement,
    // evaluated analytically at the cut; main() draws it as a mirror junction.
    let uP = (3.14159265 + rot) / 6.28318 * segments;
    let uM = (-3.14159265 + rot) / 6.28318 * segments;
    let cutJump = abs(abs(fract(uP) - 0.5) - abs(fract(uM) - 0.5)) * 2.0;
    // wedge index k = floor(u) grows with `rot` (time), so wrap it into [0, segments) and take the
    // nearer way round the circle: bounded, and the primary wedge (0) turns with the mirrors.
    let k = floor(u);
    let kw = k - segments * floor(k / segments);
    let bounces = floor(min(kw, segments - kw));
    return PoincareOut(mirrorAngle, hypR, edgeDist, bounces, 3.14159265 - abs(a0), cutJump);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let aspect = resolution.x / max(resolution.y, 0.001);
    let time = u.config.x;
    let morphSpeed = max(u.zoom_params.y, 0.01);
    let zoom = max(u.zoom_params.z, 0.15);
    let ringOffset = u.zoom_params.w;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    let warpStrength = length(mouse - 0.5) * 0.2;
    let warpDir = normalize((mouse - 0.5) + vec2<f32>(0.001, 0.001));
    let center = vec2<f32>(0.5, 0.5) + (mouse - 0.5) * 0.12 + warpDir * warpStrength * 0.06;

    var p = (uv - center) * vec2<f32>(aspect, 1.0);
    p = lensDistort(p, warpStrength * 0.3);

    let morph = sin(time * morphSpeed * (1.0 + bass * 0.6)) * 0.5 + 0.5;
    let tessA = mix(4.0, 7.0, u.zoom_params.x);
    let tessB = mix(6.0, 11.0, u.zoom_params.x);
    let segments = mix(tessA, tessB, morph);
    let rotation = time * morphSpeed * 0.25 * (1.0 + treble * 0.4);

    let pm = poincareMap(p / zoom, segments, rotation);
    let mirrorAngle = pm.mirrorAngle;
    let hypR = pm.hypR;
    let edgeDist = pm.edgeDist;
    let sector = fract(mirrorAngle / 3.14159265);

    // ── Idea 4: tumbling object cell (native; batch-38 card idea 2) ───
    // The beads of a real kaleidoscope drift under gravity relative to the mirror
    // frame, so the picture slides under the mirrors instead of only spinning.
    // The offset moves the SAMPLE window (source space); the mirrors stay put.
    let tumbleAmp = 0.10 * zoom * (0.4 + morphSpeed);
    let tumble = vec2<f32>(sin(time * 0.37 + 1.3), cos(time * 0.29)) * tumbleAmp;

    let mirrored = vec2<f32>(cos(mirrorAngle), sin(mirrorAngle)) * hypR;
    let sampleUV = clamp(center + vec2<f32>(mirrored.x / aspect, mirrored.y) + tumble, vec2<f32>(0.001), vec2<f32>(0.999));

    // Idea 2 — opposite-wedge dihedral pair
    let oppAngle = mirrorAngle + 3.14159265;
    let opposite = vec2<f32>(cos(oppAngle), sin(oppAngle)) * hypR;
    let oppUV = clamp(center + vec2<f32>(opposite.x / aspect, opposite.y) + tumble, vec2<f32>(0.001), vec2<f32>(0.999));

    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r, 0.0, 1.0);
    let sep = (0.004 + depth * 0.014) * (1.0 + mids * 0.5);
    let caR = clamp(center + vec2<f32>((mirrored.x + sep) / aspect, mirrored.y + sep * 0.3) + tumble, vec2<f32>(0.001), vec2<f32>(0.999));
    let caB = clamp(center + vec2<f32>((mirrored.x - sep) / aspect, mirrored.y - sep * 0.3) + tumble, vec2<f32>(0.001), vec2<f32>(0.999));

    let baseR = textureSampleLevel(readTexture, u_sampler, caR, 0.0).r;
    let baseG = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let baseB = textureSampleLevel(readTexture, u_sampler, caB, 0.0).b;
    let oppCol = textureSampleLevel(readTexture, u_sampler, oppUV, 0.0).rgb;
    var baseColor = mix(vec3<f32>(baseR, baseG, baseB), oppCol, 0.28);

    // ── Idea 3: mirror loss per bounce — fold count as material (§12.2E; batch-38 card idea 1) ──
    // Silvered glass reflects ~92 %, so an image that has bounced k times is dimmer
    // (and a touch cooler: red loses a little more) than the primary wedge. The wedge
    // index poincareMap already floors, wrapped mod segments, is the bounce count; the primary wedge is 0.
    let bounces = pm.bounces;
    let oddBounce = bounces - 2.0 * floor(bounces * 0.5);
    baseColor *= exp(-bounces * vec3<f32>(0.080, 0.072, 0.064)) * mix(vec3<f32>(1.0), vec3<f32>(0.975, 0.995, 1.0), oddBounce);

    // Rescue 1 (cont.): the atan2-cut discontinuity is carried by the same metal junction
    // line as every other mirror seam, in proportion to how big the jump actually is.
    let cutSeam = smoothstep(0.012, 0.0, pm.cutDist) * smoothstep(0.02, 0.12, pm.cutJump);
    let boundary = max(smoothstep(0.05 / segments, 0.0, edgeDist), cutSeam);
    let hue = fract(sector * 1.618 + morph * 0.3 + depth * 0.2 + time * 0.05);
    let irid = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * hue + 0.0),
        0.5 + 0.5 * cos(6.28318 * hue + 2.094),
        0.5 + 0.5 * cos(6.28318 * hue + 4.188)
    );
    let metal = mix(irid * 0.6, vec3<f32>(1.0, 0.92, 0.78), 0.4) * boundary * (0.4 + treble * 0.35);

    let ringPos = abs(hypR - (0.22 + ringOffset * 0.38 + bass * 0.1));
    let vertex = smoothstep(0.1, 0.0, ringPos) * boundary;
    let spec = vec3<f32>(1.0, 0.95, 0.85) * vertex * (0.6 + mids * 0.6);

    // Idea 1 — geodesic crease along Poincaré hypR iso-lines
    let geo = abs(fract(hypR * 3.5) - 0.5);
    let crease = smoothstep(0.07, 0.0, geo);
    baseColor = mix(baseColor, baseColor * vec3<f32>(0.55, 0.62, 0.78), crease * 0.55);

    let caStrength = smoothstep(0.035, 0.0, edgeDist) * (0.12 + depth * 0.18);
    baseColor = mix(baseColor, baseColor * vec3<f32>(1.12, 0.96, 0.88), caStrength);

    let finalColor = acesToneMap(baseColor * (0.7 + sector * 0.14) + metal + spec);
    let srcA = textureSampleLevel(readTexture, u_sampler, uv, 0.0).a;
    let alpha = clamp(boundary * 0.45 + depth * 0.2 + vertex * 0.18 + crease * 0.12 + srcA * 0.2 + bass * 0.06, 0.1, 0.95);
    let outDepth = clamp(depth + boundary * 0.06 + vertex * 0.04 + crease * 0.03, 0.0, 1.0);
    let outCol = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
