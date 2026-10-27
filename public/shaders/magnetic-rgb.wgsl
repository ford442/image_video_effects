// ═══════════════════════════════════════════════════════════════════
//  magnetic-rgb
//  Category: interactive-mouse
//  Features: mouse-driven, chromatic-aberration, magnetic, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-27
//  Ideas: dipole return path for the filings; filing density tracks |B|
//  A packing: ACES display RGBA (C unread)
// ═══════════════════════════════════════════════════════════════════
#include "_prelude.wgsl"

// ═══ UNIQUE VISUAL IDEA helpers: iron-filing field lines ═══
fn mrHash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn mrNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mrHash(i), mrHash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(mrHash(i + vec2<f32>(0.0, 1.0)), mrHash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn aces_tonemap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Mouse Config
    var mouse = u.zoom_config.yz;
    let hasMouse = u.zoom_config.y >= 0.0;
    var center = select(vec2<f32>(0.5, 0.5), mouse, hasMouse);

    // Idea 2: bass-driven field surge — the whole dipole pumps with the beat.
    let bass = plasmaBuffer[0].x;

    // Params
    let strength = u.zoom_params.x * (1.0 + bass * 0.4); // Field Strength
    let radius = u.zoom_params.y;   // Effect Radius
    let swirl = u.zoom_params.z;    // Rotation/Swirl amount
    let chaos = u.zoom_params.w;    // Random jitter

    // Calculate vectors
    let dVec = uv - center;
    let dVecAspect = vec2<f32>(dVec.x * aspect, dVec.y);
    let dist = length(dVecAspect);

    // Normalized direction from center
    var dir = normalize(dVecAspect);
    if (length(dVecAspect) < 0.0001) { dir = vec2<f32>(0.0, 0.0); } // Avoid NaN

    // Perpendicular direction (for swirl)
    let swirlDir = vec2<f32>(-dir.y, dir.x);

    // Field Falloff
    // Effect is strong near mouse, fades out at radius
    let field = smoothstep(radius, 0.0, dist);

    // Base displacement vector
    // Scale by strength and field intensity
    let displace = strength * field * 0.2;

    // --- Red Channel Physics (Attraction) ---
    // Pulls towards the center
    let offsetR = -dir * displace;

    // --- Green Channel Physics (Swirl) ---
    // Swirls around the center
    let offsetG = swirlDir * displace * (0.5 + swirl * 2.0);

    // --- Blue Channel Physics (Repulsion) ---
    // Pushes away from center
    let offsetB = dir * displace;

    // --- Chaos / Jitter ---
    // Add high frequency noise based on UV and time
    var noise = vec2<f32>(0.0);
    if (chaos > 0.0) {
        let t = u.config.x;
        let n1 = sin(uv.x * 100.0 + t * 10.0);
        let n2 = cos(uv.y * 100.0 + t * 15.0);
        noise = vec2<f32>(n1, n2) * chaos * 0.01 * field;
    }

    // Apply Offsets
    // Un-aspect correct the direction for UV addition?
    // dir is unit length in aspect-corrected space.
    // real UV offset x needs to be divided by aspect to maintain circularity.

    let realOffsetR = vec2<f32>(offsetR.x / aspect, offsetR.y) + noise;
    let realOffsetG = vec2<f32>(offsetG.x / aspect, offsetG.y) + noise;
    let realOffsetB = vec2<f32>(offsetB.x / aspect, offsetB.y) + noise;

    let uvR = clamp(uv + realOffsetR, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + realOffsetG, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + realOffsetB, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample Texture
    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    var outColor = vec3<f32>(r, g, b);

    // ═══ Idea 1: iron-filing field-line visualization ═══
    // The local magnetic field is the blend of the radial (attraction) and the
    // tangential (swirl) components. Iron filings align ALONG that field, so we
    // sample noise compressed perpendicular to the field direction — producing the
    // characteristic dipole field-line filaments of a classroom magnet demo.
    // ── Idea 1: dipole return path ──────────────────────────────────
    // RGB offsets stay attract / swirl / repel. Filings follow a short
    // bar, leaving one side of the cursor and entering the other.
    let bar = vec2<f32>(1.0, 0.0);
    let mdot = dot(bar, dir);
    let dipole = (2.0 * mdot * dir - bar) / max(dist * dist, 0.02);
    let fieldDir = normalize(dipole + vec2<f32>(1e-4, 0.0));
    let fieldPerp = vec2<f32>(-fieldDir.y, fieldDir.x);
    let along = dot(dVecAspect, fieldDir);
    let across = dot(dVecAspect, fieldPerp);
    let filingUV = vec2<f32>(along * 18.0, across * 90.0);
    let flow = mrNoise(filingUV + vec2<f32>(u.config.x * 0.6, 0.0));
    // ── Idea 2: filing density tracks |B| ───────────────────────────
    // Lines pack up where the field is strong and open at the edge.
    let lineFreq = mix(48.0, 150.0, clamp(field, 0.0, 1.0));
    let filing = pow(abs(sin(across * lineFreq + flow * 6.0)), 6.0);
    // Filings only appear inside the field's reach, brightest where it is strong.
    let filingMask = field * smoothstep(0.0, 0.15, strength);
    let filingColor = vec3<f32>(0.55, 0.6, 0.7); // cold iron sheen
    outColor = outColor + filingColor * filing * filingMask * 0.7;

    // Idea 3: semantic alpha from channel divergence — alpha now encodes how
    // far the R/G/B sample taps have actually separated (the magnet's local
    // strength at this pixel), instead of a flat opaque 1.0.
    let divergence = (length(realOffsetR - realOffsetG) + length(realOffsetG - realOffsetB) + length(realOffsetR - realOffsetB)) / 3.0;
    let alpha = clamp(divergence * 12.0 + filingMask * 0.3, 0.0, 1.0);

    let display = aces_tonemap(max(outColor, vec3<f32>(0.0)));
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(display, alpha));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(display, alpha));

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
