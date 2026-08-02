// ---------------------------------------------------------------
//  Spectrum Bleed – vibrant colors bleed outward like ink diffusion
//  Adjustable diffusion speed, hue drift, and saturation boost.
//  Upgraded 2026-08-02 (Batch 29): fixed the catastrophic uniform
//  bug (params were read from zoom_config = time/mouse; the 4 real
//  zoom_params sliders were dead), deleted the idempotent blur-pass
//  loop (sampleBlur is now parameterized by radius), added a sprung
//  mouse bleed lens, click ink splatters, and per-band FFT shimmer.
// ---------------------------------------------------------------
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture:   texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA:   texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC:   texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------------------

struct Uniforms {
  config:      vec4<f32>,       // x=time, y=rippleCount, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=time, y=mouseX, z=mouseY, w=mouseDown
  zoom_params: vec4<f32>,       // x=Intensity, y=Speed, z=Scale, w=Detail
  ripples:     array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Colour utilities
// ---------------------------------------------------------------
fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0/3.0, 2.0/3.0, -1.0);
    var p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ---------------------------------------------------------------
//  Simple Gaussian blur kernel (2x2) for diffusion, radius-scaled
// ---------------------------------------------------------------
fn sampleBlur(uv: vec2<f32>, tex: texture_2d<f32>, sampler_: sampler, radius: f32) -> vec3<f32> {
    let texel = radius / u.config.zw;
    var sum = vec3<f32>(0.0);
    sum += textureSampleLevel(tex, sampler_, clamp(uv + vec2<f32>(-texel.x, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, clamp(uv + vec2<f32>( texel.x, -texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, clamp(uv + vec2<f32>(-texel.x,  texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.25;
    sum += textureSampleLevel(tex, sampler_, clamp(uv + vec2<f32>( texel.x,  texel.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb * 0.25;
    return sum;
}

// ---------------------------------------------------------------
//  Main
// ---------------------------------------------------------------
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (gid.x >= u32(resolution.x) || gid.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // 1️⃣ Read source colour and depth
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // 2️⃣ Slider parameters (zoom_params — the REAL uniforms)
    //    x 'Intensity' -> bleed blend, y 'Speed' -> hue drift rate,
    //    z 'Scale' -> blur radius, w 'Detail' -> saturation boost.
    var blendFactor = u.zoom_params.x * 0.6;               // default 0.3 = mid-bleed
    let hueSpeed    = u.zoom_params.y;                     // hue drift rate
    let blurRadius  = mix(1.0, 4.0, u.zoom_params.z);      // real spread radius
    let satBoost    = u.zoom_params.w * 0.5;               // default 0.25, legal bleed

    // 3️⃣ Sprung mouse lens (extraBuffer[133..136] = pos.xy, vel.xy;
    //    [137] = lastTime, [138] = initialized). The bleed center
    //    chases the raw cursor with a critically-damped spring.
    let mouse = u.zoom_config.yz;
    var springPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    let springInitialized = extraBuffer[138] > 0.5;
    if (!springInitialized) {
        springPos = mouse;
        springVel = vec2<f32>(0.0);
    }
    let lastTime = extraBuffer[137];
    let dt = select(0.0, clamp(time - lastTime, 0.0, 0.05), springInitialized);
    let stiffness = 90.0;
    let damping = 2.0 * sqrt(stiffness); // zeta = 1, critically damped
    let accel = (mouse - springPos) * stiffness - springVel * damping;
    springVel = springVel + accel * dt;
    springPos = springPos + springVel * dt;
    if (gid.x == 0u && gid.y == 0u) {
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    // Bleed lens: near the (aspect-corrected) cursor the blend rises,
    // so colour bleeds outward from the pointer.
    let lensDist = length((uv - springPos) * vec2<f32>(aspect, 1.0));
    let lensMask = smoothstep(0.35, 0.0, lensDist);
    blendFactor = clamp(blendFactor + lensMask * 0.3, 0.0, 1.0);

    // 4️⃣ Diffusion: one radius-parameterized 4-tap blur (Scale slider
    //    makes the spread real — the old multi-pass loop was idempotent).
    let blurred = sampleBlur(uv, readTexture, u_sampler, blurRadius);

    // 5️⃣ Convert to HSV and stamp click ink splatters: each live
    //    ripple blooms saturation at its click point (~1.5s decay).
    var hsv = rgb2hsv(blurred);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (age < 0.0 || age > 1.5) { continue; }
        let splatDist = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
        let falloff = smoothstep(0.3, 0.0, splatDist);
        hsv.y = min(hsv.y + 0.4 * falloff * exp(-age * 2.0), 1.0);
    }

    // 6️⃣ Hue drift over time (Speed slider), with per-region FFT
    //    voices: 8 vertical bands each shift their drift phase by an
    //    FFT bin so the bleed rainbow shimmers across the spectrum.
    let band = u32(clamp(uv.x, 0.0, 0.999) * 8.0);
    let bandPhase = plasmaBuffer[(band % 8u) + 1u].x * 0.2;
    let newHue = fract(hsv.x + hueSpeed * time * 0.1 + bandPhase);

    // 7️⃣ Boost saturation for vivid bleed effect (Detail slider)
    let finalCol = hsv2rgb(newHue, min(hsv.y + satBoost, 1.0), hsv.z);

    // 8️⃣ Blend original with bleed based on intensity + mouse lens
    var outCol = mix(src, finalCol, blendFactor);

    // 9️⃣ Temporal persistence (memory of previous frame)
    let prev = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).rgb;
    let persist = max(prev * 0.93, outCol);
    outCol = max(outCol, persist * 0.2);

    // 🔟 Output colour and depth
    textureStore(writeTexture, gid.xy, vec4<f32>(outCol, 1.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));

    // Also update dataTextureA (dataTextureA)
    textureStore(dataTextureA, gid.xy, vec4<f32>(persist, 1.0));
}
