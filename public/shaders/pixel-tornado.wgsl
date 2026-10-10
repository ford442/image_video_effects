// ═══════════════════════════════════════════════════════════════════
//  Pixel Tornado
//  Category: image
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-05
//  Ideas: tangential motion blur along the swirl arc; debris wall at the funnel radius; calm eye
//  A packing: ACES display RGBA (no C reader)
// ═══════════════════════════════════════════════════════════════════
//  A pixel-level tornado vortex. Each pixel is displaced by a
//  combined translational + rotational field whose eye tracks the
//  mouse. Bass energy widens the funnel; treble adds turbulent
//  jitter to individual pixels. Click ripples send shockwaves.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"
// zoom_params: x=Strength, y=FunnelWidth, z=TurbulenceScale, w=InwardPull

const TAU: f32 = 6.28318530717958647;

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> vec2<f32> {
    return vec2<f32>(
        fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, vec2<f32>(269.5, 183.3))) * 17843.1234)
    ) * 2.0 - 1.0;
}

fn fbmVel(p: vec2<f32>) -> vec2<f32> {
    var v = vec2<f32>(0.0);
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < 4; i++) {
        v += noise2(p * freq) * amp;
        freq *= 2.1;
        amp  *= 0.5;
    }
    return v;
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn rot2(v: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(v.x * c - v.y * s, v.x * s + v.y * c);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims  = u.config.zw;
    if (f32(gid.x) >= dims.x || f32(gid.y) >= dims.y) { return; }

    let uv    = vec2<f32>(gid.xy) / dims;
    let coord = vec2<i32>(gid.xy);
    let time  = u.config.x;
    let aspectV = vec2<f32>(dims.x / dims.y, 1.0);

    // Audio (canonical source; HEAD read the same values from extraBuffer[0]/[2])
    let bass    = plasmaBuffer[0].x;
    let treble  = plasmaBuffer[0].z;

    // Params
    let strength     = mix(0.0, 0.25, u.zoom_params.x);
    let funnelWidth  = mix(0.05, 0.6, u.zoom_params.y) * (1.0 + bass * 0.8);
    let turbScale    = mix(1.0, 6.0,  u.zoom_params.z);
    let inwardPull   = mix(0.0, 1.0,  u.zoom_params.w);

    // Eye position tracks mouse; distances are aspect-correct (round funnel)
    let eye = u.zoom_config.yz;
    let delta = (uv - eye) * aspectV;
    let dist  = length(delta);
    let angle = atan2(delta.y, delta.x);

    // Tornado profile: spiral inward more strongly near centre
    let profile  = exp(-dist * dist / (funnelWidth * funnelWidth));
    let twist    = strength * profile / (dist + 0.02);

    // Idea 3: calm eye — a clear, still disc inside the core.
    let eyeR = max(funnelWidth * 0.18, 0.02);
    let calm = 1.0 - smoothstep(eyeR * 0.55, eyeR, dist);

    // Rotational displacement. HEAD used twist * (1 + 0.5 * time), which winds
    // without bound and shreds into noise within a minute; the gusting phase
    // below stays between 1x and 2.5x twist forever.
    let gust     = 1.75 + 0.75 * sin(time * 0.45);
    let rotAngle = twist * gust * (1.0 - calm);

    // Inward displacement
    let inward   = delta / max(dist, 1e-4) * (-inwardPull * profile * strength * 0.5) * (1.0 - calm);

    // Turbulent micro-jitter driven by treble
    let turbUV = uv * turbScale + vec2<f32>(fract(time * 0.1) * 17.0, fract(time * 0.07) * 13.0);
    let turb   = fbmVel(turbUV) * treble * 0.015 * (1.0 - calm);

    // Click ripple shockwaves
    var rippleOff = vec2<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rip  = u.ripples[i];
        let age  = time - rip.z;
        if (age >= 0.0 && age < 1.5) {
            let rVec  = (uv - rip.xy) * aspectV;
            let rDist = length(rVec);
            let wave  = sin((rDist - age * 0.4) * 40.0) * exp(-age * 3.0) * exp(-rDist * 8.0);
            let dir   = rVec / max(rDist, 1e-4);
            rippleOff += dir / aspectV * wave * 0.02;
        }
    }

    // Idea 1: tangential motion blur — taps trail back along the swirl arc,
    // longer where the funnel spins faster, so rotation reads as speed.
    let blurArc = clamp(twist * 0.15, 0.0, 0.4) * (1.0 - calm);
    var acc = vec4<f32>(0.0);
    var sampleUV = uv;
    for (var k = 0; k < 5; k++) {
        let a = rotAngle - blurArc * f32(k) * 0.25;
        let tapUV = clamp(eye + (rot2(delta, a) + inward) / aspectV + turb + rippleOff, vec2<f32>(0.0), vec2<f32>(1.0));
        if (k == 0) { sampleUV = tapUV; }
        acc += textureSampleLevel(readTexture, u_sampler, tapUV, 0.0) * (1.0 - 0.12 * f32(k));
    }
    let col = acc / (5.0 - 0.12 * 10.0);

    // Tint toward cyan/magenta near eye based on rotation direction
    // (smooth in angle — HEAD's fract() put a rotating seam through the funnel).
    let tintAngle = 0.5 + 0.5 * sin(angle + time * 0.3);
    let tint = mix(
        vec3<f32>(0.8, 1.0, 1.1),
        vec3<f32>(1.1, 0.85, 1.0),
        tintAngle
    );
    let tintStr = profile * 0.25 * (1.0 + bass) * (1.0 - calm);
    var finalRGB = mix(col.rgb, col.rgb * tint, tintStr);

    // Idea 2: debris wall — brightened, desaturated chunks of image pulled in
    // from further out, piled in an annulus at the funnel radius and spinning.
    let funnelR = funnelWidth * 0.75;
    let wallW   = max(funnelWidth * 0.2, 0.01);
    let wd      = (dist - funnelR) / wallW;
    let wall    = exp(-wd * wd) * u.zoom_params.x;
    let spin    = fract(angle / TAU + time * (0.05 + strength * 0.6));
    let chunk   = hash(vec2<f32>(floor(spin * 64.0), floor(dist / wallW * 3.0)));
    let chunkMask = smoothstep(0.4, 0.6, chunk);
    let debrisUV = clamp(eye + rot2(delta * 1.3, rotAngle * 1.2 + 0.4) / aspectV, vec2<f32>(0.0), vec2<f32>(1.0));
    let debrisSrc = textureSampleLevel(readTexture, u_sampler, debrisUV, 0.0).rgb;
    let dLum = dot(debrisSrc, vec3<f32>(0.299, 0.587, 0.114));
    let debris = mix(vec3<f32>(dLum), debrisSrc, 0.35) * 1.3 + vec3<f32>(0.06);
    finalRGB = mix(finalRGB, debris, clamp(wall * chunkMask * 0.65, 0.0, 1.0));

    let display = aces(max(finalRGB, vec3<f32>(0.0)));

    // Semantic alpha: source coverage plus funnel and debris density
    let alpha = clamp(col.a + profile * 0.2 + wall * chunkMask * 0.15, 0.0, 1.0);

    // Depth: scene depth carried along the swirl, debris lifted slightly forward
    let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    let depth = clamp(sceneDepth + wall * chunkMask * 0.1, 0.0, 1.0);

    let outColor = vec4<f32>(display, alpha);
    textureStore(writeTexture, coord, outColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, outColor);
}
