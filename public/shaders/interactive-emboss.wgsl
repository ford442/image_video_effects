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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
  let resolution = u.config.zw;
  if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
    return;
  }

  var uv = vec2<f32>(global_id.xy) / resolution;
  let texel = vec2<f32>(1.0) / resolution;
  let time = u.config.x;

  // Audio: bass deepens relief, mids the sample reach, treble the rim glow
  let bass = plasmaBuffer[0].x;
  let mids = plasmaBuffer[0].y;
  let treble = plasmaBuffer[0].z;

  // Mouse acts as the light source
  var mouse = u.zoom_config.yz;

  // Spring-damper the light source: the cursor stays the raw TARGET, but the
  // actual light rides a critically-damped spring so the highlight sweeps
  // smoothly across the relief instead of snapping to the pointer.
  // State: extraBuffer[133..134] = sprung pos, [135..136] = velocity,
  // [137] = last update time. ([0..4] reserved, [5..132] engine FFT — untouched.)
  let hasState = arrayLength(&extraBuffer) > 137u;
  if (global_id.x == 0u && global_id.y == 0u && hasState) {
    let prevTime = extraBuffer[137];
    let dt = clamp(time - prevTime, 0.001, 0.05);
    var sPos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var sVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (prevTime <= 0.0) {
      // First touch: seed the spring at the cursor so the light never snaps in.
      sPos = mouse;
      sVel = vec2<f32>(0.0, 0.0);
    }
    // Critically damped: stiffness = omega^2, damping = 2*omega (no overshoot,
    // fastest settle). omega = 8 gives a weighty-but-responsive light feel.
    let omega = 8.0;
    let accel = (mouse - sPos) * (omega * omega) - sVel * (2.0 * omega);
    sVel = sVel + accel * dt;
    sPos = sPos + sVel * dt;
    extraBuffer[133] = sPos.x;
    extraBuffer[134] = sPos.y;
    extraBuffer[135] = sVel.x;
    extraBuffer[136] = sVel.y;
    extraBuffer[137] = time;
  }
  if (hasState) {
    // Every pixel aims the light at the SPRUNG position, not the raw cursor.
    mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
  }

  // Vector from pixel to mouse (Light Direction)
  // We want the light to come FROM the mouse.
  // So direction is normalize(mouse - uv).
  // But for simple emboss, usually we dot the gradient with light direction.

  let light_vec = mouse - uv;
  // Normalize, but handle zero length
  var light_dir = vec2<f32>(0.0, 0.0);
  if (length(light_vec) > 0.001) {
    light_dir = normalize(light_vec);
  }

  // Depth-aware relief: sample depth once, use it for BOTH the contrast
  // scaling below and the pass-through store at the end. Earn the tag.
  let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

  // Parameters
  let strength = u.zoom_params.x * 5.0 * (1.0 + bass * 0.5); // Scale up for visibility. Default 0.5 -> 2.5
  let mix_amt = u.zoom_params.y;        // 0.0 = Emboss only, 1.0 = Original image
  let color_mode = u.zoom_params.z;     // 0.0 = Gray Emboss, 1.0 = Color Emboss
  var reliefContrast = 0.5 + u.zoom_params.w * 1.5;  // w: relief contrast / depth pop

  // Near geometry embosses harder than the far background (0.7x .. 1.3x).
  reliefContrast = reliefContrast * mix(0.7, 1.3, depth);

  // Sample neighbors for Sobel-ish gradient
  // -1 0 1
  // -2 0 2
  // -1 0 1

  let l = textureSampleLevel(readTexture, u_sampler, uv + vec2(-texel.x, 0.0), 0.0).rgb;
  let r = textureSampleLevel(readTexture, u_sampler, uv + vec2(texel.x, 0.0), 0.0).rgb;
  let t = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, -texel.y), 0.0).rgb;
  let b = textureSampleLevel(readTexture, u_sampler, uv + vec2(0.0, texel.y), 0.0).rgb;

  // Calculate luminance for height map approx
  let l_lum = dot(l, vec3(0.299, 0.587, 0.114));
  let r_lum = dot(r, vec3(0.299, 0.587, 0.114));
  let t_lum = dot(t, vec3(0.299, 0.587, 0.114));
  let b_lum = dot(b, vec3(0.299, 0.587, 0.114));

  // Gradient vector (dx, dy)
  let dx = (l_lum - r_lum); // Left is higher? Or Right?
  // If light comes from right, and right pixel is darker (lower), it's in shadow?
  // Let's just stick to dot product logic.
  let dy = (t_lum - b_lum);

  let grad = vec2<f32>(dx, dy);

  // Emboss value: dot product of gradient and light direction
  var diff = dot(grad, light_dir) * strength * reliefContrast * (1.0 + mids * 0.3);

  // Click relief stamps: every live ripple dents the surface. A click drops a
  // bright pop at its own point and sends a thin expanding ring of extra
  // relief outward; both fade over ~1.2s. Guarded by the engine ripple count.
  var stamp = 0.0;
  let rippleCount = min(u32(u.config.y), 50u);
  for (var i = 0u; i < rippleCount; i = i + 1u) {
    let rp = u.ripples[i];            // xy = click uv, z = click start time
    let age = time - rp.z;
    if (age < 0.0 || age > 1.2) { continue; }
    let fade = 1.0 - age / 1.2;       // linear ~1.2s fade
    let rpDist = distance(uv, rp.xy);
    // Core dent at the click point (strong early, gone quickly).
    let core = exp(-rpDist * rpDist * 240.0) * max(1.0 - age * 4.0, 0.0);
    // Expanding ring of relief riding away from the click.
    let ringRadius = age * 0.5;
    let ringOff = (rpDist - ringRadius) * 28.0;
    let ring = exp(-ringOff * ringOff);
    stamp = stamp + (core * 1.2 + ring * 0.5) * fade * fade;
  }
  // Stamps boost the emboss diff locally — clicks literally dent the surface.
  diff = diff + stamp * (0.3 + 0.1 * strength) * reliefContrast;

  // Gray emboss base
  let gray_emboss = vec3<f32>(0.5 + diff);

  // Color emboss: Add diff to original color
  let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
  let color_emboss = c + vec3<f32>(diff);

  let result_emboss = mix(gray_emboss, color_emboss, step(0.5, color_mode));

  // Soft-knee, hue-preserving clamp to [0,1]: diff can push past 1 at high
  // strength and a hard clip would shift hue. Compress by the peak channel's
  // overshoot instead (channel ratios survive), then guard the low side.
  let peak = max(result_emboss.r, max(result_emboss.g, result_emboss.b));
  let emboss_soft = result_emboss / (1.0 + max(peak - 1.0, 0.0));
  let emboss_final = clamp(emboss_soft, vec3<f32>(0.0), vec3<f32>(1.0));

  // Mix with original based on parameter
  let final_color = mix(emboss_final, c, 1.0 - mix_amt); // If mix_amt is "Effect Strength", then 1.0 means full effect.
  // Wait, I said param y is "mix_amt". Let's name it "Intensity" in JSON.
  // If Intensity = 1.0, we see full emboss.

  // Relief-magnitude alpha: embossed ridges opaque, flat areas recede (treble adds rim glow)
  let alpha = clamp(abs(diff) * 2.0 + mix_amt * 0.3 + treble * 0.2 + 0.15, 0.0, 1.0);
  textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(final_color, alpha));
  textureStore(dataTextureA, vec2<i32>(global_id.xy), vec4<f32>(final_color, alpha));

  // Pass depth
  textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
