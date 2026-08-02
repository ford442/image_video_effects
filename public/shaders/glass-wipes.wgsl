// ═══════════════════════════════════════════════════════════════
// Glass Wipes - Physical glass transmission with Beer-Lambert law
// Category: liquid-effects
// Features: rain simulation, wiper interaction, physically-based alpha
// Upgrade: spring-damped wiper, click splashes, audio-reactive rain
//          bursts + per-band droplet glint.
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=RainIntensity, y=WiperSize, z=DistortionScale, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mousePos = u.zoom_config.yz;
    let time = u.config.x;

    // Audio: plasmaBuffer[0].x = bass envelope, [1..8] = 8 spectrum bands.
    let bass = plasmaBuffer[0].x;

    // Parameters
    // Bass-driven downpours: rain bursts follow the beat.
    let rainIntensity = (0.005 + u.zoom_params.x * 0.05) * (1.0 + bass * 0.8);
    let wiperSize = 0.05 + u.zoom_params.y * 0.25;
    let distortionScale = u.zoom_params.z * 0.05;
    let evaporation = 0.001 + u.zoom_params.w * 0.01;
    let glassDensity = u.zoom_params.w * 1.5 + 0.3; // Beer-Lambert density for water/glass

    // ── Spring-damper wiper ────────────────────────────────────────
    // The wiper rides a critically-damped spring chasing the raw cursor,
    // so it trails the hand with weight instead of snapping to it.
    // Persistent state: extraBuffer[133..137] = sprung pos xy + vel xy + init
    // ([0..4] reserved, [5..132] = engine FFT bins; state stays in
    // [133..255] only). Thread (0,0) integrates; everyone reads.
    var wiperPos = mousePos;
    let hasSpring = arrayLength(&extraBuffer) > 137u;
    if (hasSpring && extraBuffer[137] > 0.5) {
        wiperPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpring) {
        var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[137] <= 0.5) {
            // First touch: seed the spring at the cursor so it never snaps.
            sPos = mousePos;
            sVel = vec2<f32>(0.0, 0.0);
        }
        // Critically damped spring: stiffness = omega^2, damping = 2*omega.
        let omega = 12.0;
        let dt = 0.016;
        let accel = (mousePos - sPos) * (omega * omega) - sVel * (2.0 * omega);
        sVel = sVel + accel * dt;
        sPos = sPos + sVel * dt;
        extraBuffer[133] = sPos.x;
        extraBuffer[134] = sPos.y;
        extraBuffer[135] = sVel.x;
        extraBuffer[136] = sVel.y;
        extraBuffer[137] = 1.0;
    }

    // Read previous wetness state
    let prevState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    var wetness = prevState.r;

    // Add Rain
    let noise = fract(sin(dot(uv * time, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    if (noise > (1.0 - rainIntensity)) {
        wetness = min(1.0, wetness + 0.3);
    }

    // Click splashes: each live ripple spatters rain onto the glass at its
    // click point. One-shot on young ripples; aspect-corrected ~0.15 radius.
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let rAge = time - ripple.z;
        if (rAge >= 0.0 && rAge < 0.3) {
            let rDelta = vec2<f32>((uv.x - ripple.x) * aspect, uv.y - ripple.y);
            let rDist = length(rDelta);
            let splash = smoothstep(0.15, 0.0, rDist) * max(0.0, 1.0 - rAge / 0.3);
            wetness = min(1.0, wetness + 0.5 * splash);
        }
    }

    // Natural evaporation
    wetness = max(0.0, wetness - evaporation);

    // Mouse Wiper Interaction (aspect-corrected distance preserved)
    if (wiperPos.x >= 0.0) {
        let dVec = uv - wiperPos;
        let dist = length(vec2<f32>(dVec.x * aspect, dVec.y));

        if (dist < wiperSize) {
             let wipeFactor = smoothstep(wiperSize, wiperSize * 0.5, dist);
             wetness = wetness * (1.0 - wipeFactor);
        }
    }

    // Droplet distortion
    let dripNoiseX = fract(sin(dot(uv + vec2<f32>(0.0, time * 0.1), vec2<f32>(12.9898, 78.233))) * 43758.5453) - 0.5;
    let dripNoiseY = fract(sin(dot(uv + vec2<f32>(0.0, time * 0.1), vec2<f32>(39.346, 11.135))) * 43758.5453) - 0.5;
    let distortion = vec2<f32>(dripNoiseX, dripNoiseY) * wetness * distortionScale;

    // Save state (wetness, 0, 0, wetness) — raw state, never tonemapped
    textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(wetness, 0.0, 0.0, wetness));

    // Physical water properties
    // Water has slightly different refractive index (~1.33 vs glass ~1.5)
    // and absorption characteristics
    let waterColor = vec3<f32>(0.85, 0.95, 1.0); // Blue-tinted water

    // Calculate normal from distortion
    let normal = normalize(vec3<f32>(distortion * 100.0, 1.0));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);

    // Fresnel for water
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.02; // Water-air interface (lower than glass)
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

    // Water thickness based on wetness
    let thickness = wetness * 0.05;

    // Beer-Lambert absorption for water
    let absorption = exp(-(1.0 - waterColor) * thickness * glassDensity);

    // Transmission coefficient
    let transmission = mix(1.0, (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0, wetness);

    // Render with distortion
    let distortedUV = clamp(uv + distortion, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, distortedUV, 0.0);

    // Apply water tint and alpha based on wetness
    color = vec4<f32>(mix(color.rgb, color.rgb * waterColor, wetness * 0.5), transmission);

    // Add specular highlight for water droplets
    let lightDir = normalize(vec2<f32>(0.5, 0.5) - uv);
    let light = max(0.0, dot(normal, normalize(vec3<f32>(lightDir, 1.0))));
    let specular = pow(light, 20.0) * wetness * 0.5;

    // Per-band droplet glint: 8 horizontal bands each sparkle their
    // specular with their own spectrum bin, so droplets shimmer in
    // stripes that dance across the audio spectrum.
    let band = min(u32(uv.y * 8.0), 7u);
    let bandGlint = plasmaBuffer[(band % 8u) + 1u].x * 0.3;

    color = color + vec4<f32>(specular, specular, specular, 0.0) * (1.0 + bandGlint);

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
