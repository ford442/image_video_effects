// ═══════════════════════════════════════════════════════════════════
//  Vortex Pass 2
//  Category: distortion
//  Features: upgraded-rgba, fluid, vortex, iridescent, audio-reactive,
//            chromatic-velocity-blur, temporal-vorticity, audio-swirl
//  Complexity: High
//  Upgraded: 2026-10-17
//  Ideas: sim-field warp with a Rankine eye; Kelvin-Helmholtz eyewall braids
//  A packing: pass 1 owns raw (vx, vy, vorticity, velMag+2); this pass does not write A
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI:  f32 = 3.14159265358979323846;
const TAU: f32 = 6.28318530717958647692;

fn hsv2rgb(c: vec3<f32>) -> vec3<f32> {
  let k = vec4<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  let p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
  return c.z * mix(k.xxx, clamp(p - k.xxx, vec3<f32>(0.0), vec3<f32>(1.0)), c.y);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let swirlStrength = u.zoom_params.x * (1.0 + bass * 0.3);
    let iridescence = u.zoom_params.y;
    let trailLength = u.zoom_params.z;
    let paletteSpeed = u.zoom_params.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let coord = vec2<i32>(global_id.xy);
    let field = textureLoad(dataTextureC, coord, 0);
    // Pass 1 stores velMag+2 in C.a, above any display alpha.
    let simGate = field.a > 1.5;
    let velData = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let imgVel = velData.rg * 2.0 - 1.0;
    let velocity = select(imgVel, field.xy, simGate);
    let curl = select(velData.b, field.z, simGate);
    let pressure = select(velData.a, field.a - 2.0, simGate);

    let speed = length(velocity);
    let flowDir = normalize(velocity + vec2<f32>(1e-4));
    // Idea 1 — when the sim field is live, the trail is centered upstream of the photo.
    let center = select(uv, clamp(uv - velocity * swirlStrength * 0.08, vec2<f32>(0.0), vec2<f32>(1.0)), simGate);

    // Chromatic velocity blur offsets: RGB trail in flow direction
    let blurSteps = i32(trailLength * 5.0 + 1.0);
    var rBlur = vec3<f32>(0.0);
    var gBlur = vec3<f32>(0.0);
    var bBlur = vec3<f32>(0.0);
    for (var i: i32 = 0; i < blurSteps; i = i + 1) {
        let t = f32(i) / f32(blurSteps);
        let rOff = center + flowDir * t * speed * 0.03 * (1.0 + treble * 0.3);
        let gOff = center + flowDir * t * speed * 0.03;
        let bOff = center + flowDir * t * speed * 0.03 * (1.0 - bass * 0.2);
        rBlur += textureSampleLevel(readTexture, u_sampler, clamp(rOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        gBlur += textureSampleLevel(readTexture, u_sampler, clamp(gOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
        bBlur += textureSampleLevel(readTexture, u_sampler, clamp(bOff, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    }
    let invSteps = 1.0 / max(f32(blurSteps), 1.0);
    rBlur *= invSteps;
    gBlur *= invSteps;
    bBlur *= invSteps;

    // Iridescent vorticity tint based on curl
    let hue = fract(abs(curl) * 2.0 + time * paletteSpeed * 0.1 + depth * 0.2);
    let tint = hsv2rgb(vec3<f32>(hue, 0.7 + mids * 0.2, 0.9 + bass * 0.1));

    let vorticityIntensity = abs(curl) * 5.0;
    let vorticityColor = tint * vorticityIntensity * iridescence;

    // Color history only in the photo-as-flow fallback. In sim mode C is velocity.
    let prev = textureLoad(dataTextureC, coord, 0).rgb;
    var velocityColor = mix(vec3<f32>(rBlur.r, gBlur.g, bBlur.b), vorticityColor, clamp(vorticityIntensity, 0.0, 1.0));
    let histMix = select(0.06 + mids * 0.02, 0.0, simGate);
    velocityColor = mix(velocityColor, prev * 0.88, histMix);

    // Palette grading: pressure drives brightness
    var graded = velocityColor * (0.7 + pressure * 0.6);

    // Idea 1 continued — Rankine eye: dark core, bright ring where speed matches the core.
    let eye = exp(-speed * speed * 40.0) * smoothstep(0.04, 0.18, abs(curl));
    let eyewall = exp(-abs(speed - 0.15) * 28.0) * abs(curl);
    graded = graded * (1.0 - eye * 0.72) + tint * eyewall * (0.35 + iridescence);

    // Idea 2 — eyewall braids: a transverse ripple on that speed ring.
    let tangent = vec2<f32>(-flowDir.y, flowDir.x);
    let braid = sin(dot(uv, tangent) * 48.0 + time * 3.0) * eyewall;
    graded = graded + tint * braid * 0.45 * iridescence;

    let alpha = clamp(0.6 + speed * 0.4 + vorticityIntensity * 0.2 + eyewall * 0.2, 0.0, 1.0);

    let shaded = mix(graded, graded * (1.0 + depth * 0.2), 0.3);
    let finalColor = acesToneMap(max(shaded, vec3<f32>(0.0)));

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, alpha));
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
