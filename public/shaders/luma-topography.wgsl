// ═══════════════════════════════════════════════════════════════════
//  Luma Topography
//  Category: interactive-mouse
//  Features: mouse-driven, lighting, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-17
//  Batch-20 polish (2026-07-31): critically-damped spring on the
//    mouse light, click fill-light flashes, depth-aware relief
//    height, honest struct/header comments.
//    extraBuffer persistent state lives in [133..255] ONLY.
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=ReliefHeight, y=LightIntensity, z=Shininess, w=Ambient
  ripples: array<vec4<f32>, 50>, // per click: x=uvX, y=uvY, z=startTime
};

fn getLuma(color: vec3<f32>) -> f32 {
    return dot(color, vec3<f32>(0.299, 0.587, 0.114));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;

    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let time = u.config.x;

    // Audio reactivity
    let bass   = plasmaBuffer[0].x;
    let mids   = plasmaBuffer[0].y;

    // Parameters — bass boosts light intensity
    let heightScale = u.zoom_params.x * 20.0 + 1.0;
    let lightIntensity = u.zoom_params.y * 2.0 * (1.0 + bass * 0.4);
    let shininess = u.zoom_params.z * 32.0 + 1.0;
    let ambient = u.zoom_params.w;

    let mousePos = u.zoom_config.yz; // raw cursor = spring goal
    let aspect = resolution.x / max(resolution.y, 0.001);

    // ── Critically-damped spring: the light sweeps with weight ──────
    // extraBuffer map (persistent state in [133..255] ONLY):
    //   [133..134] = sprung light position (uv),
    //   [135..136] = spring velocity,
    //   [137]      = last frame time,
    //   [138]      = init flag.
    //   [0..4] reserved, [5..132] = engine FFT bins — untouched.
    var lightUV = mousePos;
    if (arrayLength(&extraBuffer) > 138u) {
        if (extraBuffer[138] < 0.5) {
            extraBuffer[133] = mousePos.x;
            extraBuffer[134] = mousePos.y;
            extraBuffer[135] = 0.0;
            extraBuffer[136] = 0.0;
            extraBuffer[137] = time;
            extraBuffer[138] = 1.0;
        }
        var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        let dt = clamp(time - extraBuffer[137], 0.0001, 0.05);
        let stiffness = 48.0;
        let damping = 2.0 * sqrt(stiffness); // critical damping
        let accel = (mousePos - sPos) * stiffness - sVel * damping;
        sVel = sVel + accel * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = time;
        lightUV = sPos;
    }

    let colorSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let color = colorSample.rgb;
    let luma = getLuma(color);

    // Depth is sampled BEFORE lighting so near geometry rides higher
    // on the relief and catches more specular.
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let texelSize = 1.0 / resolution;

    let lumaRight = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(texelSize.x, 0.0), 0.0).rgb);
    let lumaTop   = getLuma(textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(0.0, texelSize.y), 0.0).rgb);

    let dX = lumaRight - luma;
    let dY = lumaTop - luma;

    let normal = normalize(vec3<f32>(-dX * heightScale, -dY * heightScale, 1.0));

    let lightHeight = 0.2;
    let pixelPos3D = vec3<f32>(uv.x * aspect, uv.y, luma * 0.2 + depth * 0.1);
    let lightPos3D = vec3<f32>(lightUV.x * aspect, lightUV.y, lightHeight);

    let L = normalize(lightPos3D - pixelPos3D);
    let V = vec3<f32>(0.0, 0.0, 1.0);

    let diff = max(dot(normal, L), 0.0);
    let H = normalize(L + V);
    let spec = pow(max(dot(normal, H), 0.0), shininess);

    // Attenuation falloff measured from the SPRUNG light position.
    let dist = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(lightUV.x * aspect, lightUV.y));
    let atten = 1.0 / (1.0 + dist * 5.0);

    // Mids add warm shimmer to specular
    let lightColor = vec3<f32>(1.0, 0.95 + mids * 0.05, 0.8);

    let finalDiffuse  = diff * lightColor * lightIntensity * atten;
    let finalSpecular = spec * lightColor * lightIntensity * atten;

    // ── Click fill-light flashes: matches struck across the terrain ──
    // Each live ripple adds a decaying warm point light on the same
    // Blinn-Phong path (diff + spec), fading out over ~1.5s.
    var clickDiffuse  = vec3<f32>(0.0);
    var clickSpecular = vec3<f32>(0.0);
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 1.5) {
            let fade = 1.0 - age / 1.5;
            let clickPos3D = vec3<f32>(ripple.x * aspect, ripple.y, lightHeight * 1.5);
            let Lc = normalize(clickPos3D - pixelPos3D);
            let Hc = normalize(Lc + V);
            let diffC = max(dot(normal, Lc), 0.0);
            let specC = pow(max(dot(normal, Hc), 0.0), shininess);
            let distC = distance(vec2<f32>(uv.x * aspect, uv.y), vec2<f32>(ripple.x * aspect, ripple.y));
            let attenC = 1.0 / (1.0 + distC * 5.0);
            let clickColor = vec3<f32>(1.0, 0.75, 0.45); // warm match-strike tint
            clickDiffuse  = clickDiffuse  + diffC * clickColor * attenC * fade * fade;
            clickSpecular = clickSpecular + specC * clickColor * attenC * fade * fade;
        }
    }

    let litColor = clamp(color * (vec3<f32>(ambient) + finalDiffuse + clickDiffuse * 0.8) + finalSpecular + clickSpecular * 0.8, vec3<f32>(0.0), vec3<f32>(1.0));

    // Meaningful alpha: specular highlight + diffuse strength + click
    // flash energy + original alpha
    let clickEnergy = (clickSpecular.r + clickDiffuse.r) * 0.25;
    let alpha = clamp(spec * atten * 0.6 + diff * atten * 0.3 + clickEnergy + colorSample.a * 0.15 + bass * 0.05, 0.0, 1.0);
    let fc = vec4<f32>(litColor, alpha);

    textureStore(writeTexture, vec2<i32>(global_id.xy), fc);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, vec2<i32>(global_id.xy), fc);
}
