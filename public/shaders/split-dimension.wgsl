// ═══════════════════════════════════════════════════════════════════
//  Split Dimension
//  Category: interactive-mouse
//  Features: mouse-driven, glitch, upgraded-rgba, audio-reactive
//  Complexity: Medium
//  Upgraded: 2026-05-23
//  upgraded-rgba
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
  config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GlitchIntensity, y=ColorShift, z=NegativeStr, w=SplitAngle
  ripples: array<vec4<f32>, 50>,
};

fn get_mouse() -> vec2<f32> {
    var mouse = u.zoom_config.yz;
    if (mouse.x < 0.0) { return vec2<f32>(0.5, 0.5); }
    return mouse;
}

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let rawMouse = get_mouse();

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let glitch_amt = u.zoom_params.x * (1.0 + bass * 0.3 + treble * 0.15);
    let color_shift = u.zoom_params.y * (1.0 + mids * 0.1);
    let neg_str = u.zoom_params.z;
    let angle_param = u.zoom_params.w;

    let time = u.config.x;

    // The inter-dimensional seam follows with critically damped weight.
    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mouse = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
        mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
        var springPos = mouse;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 8.0;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    // Base color for alpha preservation
    let baseColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Calculate Split Line
    let angle = angle_param * 3.14159 * 0.5;
    let normal = vec2<f32>(cos(angle), sin(angle));

    let p_vec = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);
    var d = dot(p_vec, normal);

    // Clicks crack the split line locally at normalized ripple positions.
    var clickDamage = 0.0;
    var clickShift = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let safeAge = max(age, 0.0);
        let live = step(0.0, age) * (1.0 - step(1.6, age));
        let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
        let ring = 1.0 - smoothstep(0.015, 0.055, abs(rd - safeAge * 0.36));
        let wave = ring * exp(-safeAge * 1.6) * live;
        clickDamage = max(clickDamage, wave);
        clickShift += wave * sin(rp.x * 37.0 + rp.y * 19.0) * 0.08;
    }
    d += clickShift;

    // Normal side
    let normalColor = baseColor;

    // Glitch side
    let regionBin = (u32(floor(uv.y * 72.0)) % 8u) + 1u;
    let fftRegion = plasmaBuffer[regionBin].x;
    let n = fract(noise(vec2<f32>(uv.y * 50.0, time * 20.0)) + fftRegion * 0.17);
    let glitchActive = select(0.0, 1.0, (n > 0.8 || clickDamage > 0.02) && glitch_amt > 0.0);
    let glitchOffset = (n - 0.5) * glitch_amt * 0.2 * glitchActive;
    var glitch_uv = uv;
    glitch_uv.x = glitch_uv.x + glitchOffset + clickShift * glitch_amt;
    glitch_uv = clamp(glitch_uv, vec2<f32>(0.0), vec2<f32>(1.0));

    let shift = color_shift * 0.05;
    var col = vec3<f32>(0.0);
    col.r = textureSampleLevel(readTexture, u_sampler, glitch_uv + vec2<f32>(shift, 0.0), 0.0).r;
    col.g = textureSampleLevel(readTexture, u_sampler, glitch_uv, 0.0).g;
    col.b = textureSampleLevel(readTexture, u_sampler, glitch_uv - vec2<f32>(shift, 0.0), 0.0).b;
    col = mix(col, 1.0 - col, neg_str);

    var glitchColor = vec4<f32>(col, mix(baseColor.a, 1.0, glitch_amt * 0.7));

    // Add split line highlight
    let lineHighlight = select(vec4<f32>(0.5, 0.5, 0.5, 0.0), vec4<f32>(0.0), d >= 0.01);
    glitchColor = glitchColor + lineHighlight;

    let isNormal = select(0.0, 1.0, d < 0.0);
    var finalColor = mix(glitchColor, normalColor, isNormal);
    let peak = max(max(finalColor.r, finalColor.g), finalColor.b);
    finalColor = vec4<f32>(max(finalColor.rgb, vec3<f32>(0.0)) * min(1.0, 1.8 / max(peak, 0.001)), clamp(finalColor.a, 0.0, 1.0));

    // Depth follows the selected dimension and gives the fracture line relief.
    let depthNormal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthGlitch = textureSampleLevel(readDepthTexture, non_filtering_sampler, glitch_uv, 0.0).r;
    let depth = clamp(mix(depthGlitch, depthNormal, isNormal) - clickDamage * 0.025, 0.0, 1.0);

    textureStore(writeTexture, coord, finalColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0, 0, 0));
    textureStore(dataTextureA, coord, finalColor);
}
