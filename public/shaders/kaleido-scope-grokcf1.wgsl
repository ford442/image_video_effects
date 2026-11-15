// ═══════════════════════════════════════════════════════════════════
//  Kaleido-Scope Prism grokcf1
//  Category: geometric
//  Features: mouse-driven, audio-reactive, temporal, upgraded-rgba,
//            depth-aware, stained-glass-facets, oil-slick-prism
//  Complexity: High
//  Created: 2026-05-10
//  Upgraded: 2026-09-11, 2026-11-15
//  Ideas: segment seam glow on mirror beat; counter-rotating inner ring wedge; mirror-bounce attenuation + cool cast (energy accounting); eyepiece barrel + field stop (Brown-Conrady, §12.2B)
//  A packing: display RGBA + bass env/spring state at (0,0); ACES only on the added emissive terms (photo base keeps its levels)
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=segments, y=rotation, z=zoom, w=ring offset

const TAU: f32 = 6.28318530718;

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hsv2rgb(hsv: vec3<f32>) -> vec3<f32> {
    let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    let p = abs(fract(hsv.xxx + k.xyz) * 6.0 - k.www);
    return hsv.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), hsv.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }

    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let prev = textureLoad(dataTextureC, pixel, 0);
    let time = u.config.x;
    let held = f32(u.zoom_config.w > 0.5);

    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let isStatePixel = global_id.x == 0u && global_id.y == 0u;
    let stateRead = textureLoad(dataTextureC, vec2<i32>(0, 0), 0);

    let mouse_target = u.zoom_config.yz;
    let dt = 0.016;
    let dir = mouse_target - stateRead.gb;
    let dist_to_target = length(dir);
    let ndir = select(vec2<f32>(0.0), dir / max(dist_to_target, 0.0001), dist_to_target > 0.001);
    let prevVel = stateRead.a;
    let force = dist_to_target * 12.0 - prevVel * 3.0;
    let newVel = prevVel + force * dt;
    let newSpring = stateRead.gb + ndir * newVel * dt;
    let attack = select(0.15, 0.8, bass > stateRead.r);
    let newEnv = mix(stateRead.r, bass, attack);

    let env = select(stateRead.r, newEnv, isStatePixel);
    let mouse = select(stateRead.gb, newSpring, isStatePixel);
    let stateOut = vec4<f32>(newEnv, newSpring, newVel);

    let segments_param = u.zoom_params.x;
    let rot_speed = u.zoom_params.y;
    let zoom = u.zoom_params.z;
    let offset_param = u.zoom_params.w;

    let num_segments = 3.0 + floor(segments_param * 12.0);
    let rel_uv = uv - mouse;
    let aspect_uv = vec2<f32>(rel_uv.x * aspect, rel_uv.y);

    let dist = length(aspect_uv);
    var angle = atan2(aspect_uv.y, aspect_uv.x);

    let segment_angle = TAU / max(num_segments, 1.0);
    let spin = time * (rot_speed - 0.5) * 2.0;
    angle = angle + spin + held * (mouse.y - 0.5) * 0.9 * exp(-dist * 3.0);

    // ── Idea 3: mirror-bounce attenuation + cool cast (energy accounting) ──
    // Mirrors sit every half-wedge; the half-wedge index around the circle is the number of
    // reflections that image has taken (0 for the object wedge, up to n on the far side). Each
    // bounce loses light and a little red (silvered glass), so far images are dimmer and cooler.
    let halfSeg = segment_angle * 0.5;
    let ringHalf = 2.0 * max(num_segments, 1.0);
    let halfIdx = floor(angle / halfSeg);
    let halfWrapped = halfIdx - ringHalf * floor(halfIdx / ringHalf);
    let bounces = min(halfWrapped, ringHalf - halfWrapped);
    // Capped at 4 reflections: the loss reads as a modest far-side dimming at any segment count
    // (uncapped, a 15-wedge chamber lost ~21 % of its mean luma).
    let bounceAtt = exp(log(vec3<f32>(0.92, 0.945, 0.96)) * min(bounces, 4.0));

    let folded = angle - segment_angle * floor(angle / segment_angle);
    angle = select(folded, segment_angle - folded, folded > segment_angle * 0.5);

    // Idea 2 — counter-rotating inner ring wedge at half angular speed
    let innerSpin = time * (rot_speed - 0.5) * 1.0;
    let innerAngleRaw = atan2(aspect_uv.y, aspect_uv.x) + innerSpin + held * (mouse.y - 0.5) * 0.45 * exp(-dist * 3.0);
    let innerFolded = innerAngleRaw - segment_angle * floor(innerAngleRaw / segment_angle);
    let innerAngle = select(innerFolded, segment_angle - innerFolded, innerFolded > segment_angle * 0.5);
    let innerBlend = smoothstep(0.42, 0.0, dist);

    let scale = (2.0 - zoom * 1.8) * (1.0 - held * 0.12);
    let radius = dist * scale + offset_param * 0.5;
    // ── Idea 4: eyepiece barrel (Brown-Conrady r' = r(1 + k1 r^2), §12.2B) ──
    // The object field is magnified through an eyepiece lens: it samples outward faster toward the
    // rim, bulging the picture. Overlays (grout/packets/hue) stay on the undistorted radius.
    let radiusObj = radius * (1.0 + 0.14 * radius * radius);
    let new_vec = vec2<f32>(cos(angle), sin(angle)) * radiusObj;
    let inner_vec = vec2<f32>(cos(innerAngle), sin(innerAngle)) * radiusObj * 0.62;
    let sample_uv = clamp(vec2<f32>(0.5, 0.5) + vec2<f32>(new_vec.x / aspect, new_vec.y), vec2<f32>(0.0), vec2<f32>(1.0));
    let inner_sample_uv = clamp(vec2<f32>(0.5, 0.5) + vec2<f32>(inner_vec.x / aspect, inner_vec.y), vec2<f32>(0.0), vec2<f32>(1.0));

    var color = textureSampleLevel(readTexture, u_sampler, sample_uv, 0.0).rgb;
    let innerColor = textureSampleLevel(readTexture, u_sampler, inner_sample_uv, 0.0).rgb;
    color = mix(color, innerColor, innerBlend * 0.58);

    let prism_shift = sin(angle * 6.0 + spin) * (0.02 + env * 0.06);
    let r = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv + vec2<f32>(prism_shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    let b = textureSampleLevel(readTexture, u_sampler, clamp(sample_uv - vec2<f32>(prism_shift, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
    color = vec3<f32>(r, color.g, b);

    let reflect_uv = clamp(vec2<f32>(0.5, 0.5) - vec2<f32>(new_vec.x / aspect, new_vec.y), vec2<f32>(0.0), vec2<f32>(1.0));
    color += textureSampleLevel(readTexture, u_sampler, reflect_uv, 0.0).rgb * (0.3 + env * 0.4);

    // Idea 3 + 4 act on the PHOTO base only (mirror loss, lens field stop); the emissive overlays
    // below are lights on the glass, not images in the mirrors.
    let framePos = (uv - vec2<f32>(0.5)) * vec2<f32>(aspect, 1.0);
    let frameR = length(framePos) / max(length(vec2<f32>(aspect, 1.0) * 0.5), 0.0001);
    let fieldStop = 1.0 - 0.45 * smoothstep(0.75, 1.0, frameR);
    color = color * bounceAtt * fieldStop;

    let seam = smoothstep(0.035, 0.0, min(angle, segment_angle - angle));
    // Idea 1 — segment seam glow pulsing on kaleido beat (bass-driven mirror boundary)
    let seamBeat = seam * (0.55 + bass * 0.85 + 0.35 * sin(time * (4.0 + bass * 6.0)));
    let grout = smoothstep(0.08, 0.0, abs(fract(radius * 5.0 + offset_param) - 0.5));
    let conveyor = smoothstep(0.09, 0.0, abs(fract(angle / segment_angle * 4.0 - time * (2.4 + rot_speed * 3.0)) - 0.5));
    let packets = smoothstep(0.08, 0.0, abs(fract(radius * 7.0 - time * (2.8 + bass * 2.0)) - 0.5));

    var iris = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
            // ── Rescue 1: aspect-correct ring (HEAD measured uv distance → elliptical on wide frames) ──
            let ringD = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
            iris = max(iris, exp(-abs(ringD - age * 0.48) * 64.0) * (1.0 - age / 1.5));
        }
    }

    let hue = fract(angle / segment_angle + time * 0.12 + mids * 0.25 + radius * 0.35);
    let slick = hsv2rgb(vec3<f32>(hue, 0.72 + treble * 0.2, 0.92));
    color = mix(color, color * slick * 1.35, 0.32 + treble * 0.22);
    // ── Rescue 2: HEAD tagged upgraded-rgba with no ACES. Tone-map only the emissive overlay terms
    // (clamped >= 0) so the photo base keeps its levels. ──
    let emissive = slick * (seamBeat * 0.55 + grout * 0.22 + conveyor * 0.28 + packets * 0.24 + iris * 0.55);
    color += acesToneMap(max(emissive, vec3<f32>(0.0)));
    color *= (1.0 + bass * 0.1 + mids * 0.05 + treble * 0.05) * (1.0 + held * 0.12 + iris * 0.35);

    let luminance = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let effect_intensity = clamp(0.5 + dist * 0.5 + seamBeat * 0.2 + iris * 0.3, 0.0, 1.0);
    let alpha = clamp(0.25 + luminance * 0.7 * effect_intensity, 0.0, 1.0);

    let decay = 0.88;
    let trail_rgb = mix(color, prev.rgb * decay, select(0.35, 0.0, isStatePixel));
    let trail_alpha = mix(alpha, prev.a * decay, select(0.35, 0.0, isStatePixel));
    let trailColor = vec4<f32>(trail_rgb, trail_alpha);
    let centerColor = vec4<f32>(color, alpha);

    let finalColor = select(trailColor, centerColor, isStatePixel);
    let dataAOut = select(trailColor, stateOut, isStatePixel);

    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let outDepth = clamp(depth + seamBeat * 0.08 + grout * 0.04, 0.0, 1.0);
    textureStore(writeTexture, pixel, finalColor);
    textureStore(dataTextureA, pixel, dataAOut);
    textureStore(writeDepthTexture, pixel, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
}
