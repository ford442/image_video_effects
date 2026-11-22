#include "_prelude.wgsl"
//  Upgraded: 2026-10-17, 2026-11-22
//  Ideas: slice drift at foreground and background speeds; focal sheet on the focus plane; light-facing rim glint (edge specular gated by the silhouette normal against the orbiting light); focal-plane iso-depth contour (the sheet traces where the swept focal plane cuts the scene)
//  A packing: display RGBA on writeTexture only
//  Rescue: HEAD read its light / ambient / normal / DOF / camera tunables from extraBuffer[0..4], which the engine owns
//          (bass, mid, treble, reserved, historyHead): silence meant ambient = 0 and light = 0, so the photo was black
//          (only fog and rings), fog falloff 0, DOF 0. The edge specular compared the UNZOOMED map with the ZOOMED blend,
//          lighting whole regions instead of edges. mousePos divided an already-0..1 uv by the resolution, so the
//          Parallax slider was dead. The focal sweep used fract() and snapped back once per period.

// ═══════════════════════════════════════════════════════════════
//  Volumetric Depth Zoom - PASS 1 of 2
//  Raymarched volumetric zoom using multiple depth slices with
//  depth-of-field, parallax, and edge specular lighting.
//  
//  Outputs:
//    - writeTexture: Volumetric zoom with DOF and lighting
//    - writeDepthTexture: Accumulated depth from raymarch slices
//  
//  Next Pass: parallax-glow-compositor.wgsl
// ═══════════════════════════════════════════════════════════════

// Mapping (engine conventions):
// - time -> u.config.x
// - zoomTime -> u.zoom_config.x
// - zoom center -> u.zoom_config.yz
// - depth_threshold -> u.zoom_config.w
// - zoom_params.x = fg_speed, y = bg_speed, z = parallax_str, w = fog_density
// - lighting / camera tunables are literals below. They were once read from extraBuffer[0..7], but those slots are
//   engine-owned (0..2 bass/mid/treble, 3 reserved, 4 historyHead, 5.. FFT bins), never parameters.
// - audio: plasmaBuffer[0].xyz (bass pumps the light, mids cycle the ring hue, treble speeds the rings)

const NORMAL_STRENGTH: f32 = 1.0;
const FOG_FALLOFF: f32 = 1.0;
const DOF_AMOUNT: f32 = 1.0;
const LIGHT_BASE: f32 = 1.0;
const AMBIENT: f32 = 0.2;
const CAMERA_Z: f32 = 0.0;        // HEAD's effective value (historyHead bits ~ 0): perspective stays 1, framing unchanged
const PARALLAX_REACH: f32 = 0.2;  // uv shift of the nearest slice at Parallax = 1 and the pointer at the frame edge x 2

fn ping_pong(a: f32) -> f32 {
  return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0);
}

fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> {
  return vec2<f32>(ping_pong(v.x), ping_pong(v.y));
}

// xyz = relief normal, w = |central depth gradient| per pixel (the same four taps feed both, so the
// edge specular is measured on the map the normal comes from)
fn reconstruct_normal(uv: vec2<f32>, depth: f32, resolution: vec2<f32>) -> vec4<f32> {
    let normal_strength = NORMAL_STRENGTH;
    let offset_x = vec2<f32>(1.0 / resolution.x, 0.0);
    let offset_y = vec2<f32>(0.0, 1.0 / resolution.y);

    let depth_x1 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - offset_x, 0.0).r;
    let depth_x2 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset_x, 0.0).r;
    let depth_y1 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - offset_y, 0.0).r;
    let depth_y2 = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + offset_y, 0.0).r;

    let p_dx = vec3<f32>(offset_x.x * 2.0, 0.0, (depth_x2 - depth_x1) * normal_strength);
    let p_dy = vec3<f32>(0.0, offset_y.y * 2.0, (depth_y2 - depth_y1) * normal_strength);
    let edge = length(vec2<f32>(depth_x2 - depth_x1, depth_y2 - depth_y1)) * 0.5;
    return vec4<f32>(normalize(cross(p_dy, p_dx)), edge);
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn calculate_fog(depth: f32, color: vec3<f32>) -> vec3<f32> {
    let fog_density = u.zoom_params.w;
    let fog_color = vec3<f32>(0.05, 0.1, 0.08);
    let fog_factor = 1.0 - exp(-pow(max(depth, 0.0), FOG_FALLOFF) * fog_density);
    return mix(color, fog_color, clamp(fog_factor, 0.0, 1.0));
}

// Sample a layer with perspective projection
fn sample_layer(uv: vec2<f32>, zoom_center: vec2<f32>, layer_depth: f32) -> vec4<f32> {
    // Perspective scaling and zoom
    let perspective = 1.0 + CAMERA_Z * (1.0 - layer_depth * 0.5);
    let zoom = 1.0 + layer_depth * 4.0;
    let scale = zoom * perspective;

    let transformed_uv = (uv - zoom_center) / scale + zoom_center;
    let wrapped_uv = ping_pong_v2(transformed_uv);

    var color = textureSampleLevel(readTexture, u_sampler, wrapped_uv, 0.0);
    var depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped_uv, 0.0).r;

    return vec4<f32>(color.rgb, depth);
}

// ═══ ADVANCED ALPHA FUNCTION (moved before main for WGSL compatibility) ═══
fn calculateAdvancedAlpha(color: vec3<f32>, finalDepth: f32, totalWeight: f32) -> f32 {
    // Tunable parameters from zoom_params
    let fgSpeed = u.zoom_params.x;        // Foreground Speed
    let bgSpeed = u.zoom_params.y;        // Background Speed
    let parallaxStr = u.zoom_params.z;    // Parallax
    let fogDensity = u.zoom_params.w;     // Fog Density
    
    // Luminance factor: brighter = more opaque
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let lumaAlpha = mix(0.25, 1.0, luma);
    
    // Depth factor: farther pixels more transparent (atmospheric perspective)
    let depthFade = exp(-finalDepth * fogDensity * 2.0);
    let depthAlpha = mix(0.95, 0.25, depthFade);
    
    // Volumetric weight influence: more accumulated weight = denser = more opaque
    let weightAlpha = smoothstep(0.0, 2.0, totalWeight) * 0.3 + 0.7;
    
    // Combine depth and luminance
    let combinedAlpha = mix(lumaAlpha, depthAlpha, 0.6) * weightAlpha;
    
    return clamp(combinedAlpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let zoom_time = u.zoom_config.x;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let zoom_center = u.zoom_config.yz;

    // Camera and parallax. zoom_config.yz is already a 0..1 uv (HEAD divided it by the resolution again).
    let parallax = (zoom_center - vec2<f32>(0.5, 0.5)) * u.zoom_params.z * PARALLAX_REACH;
    let parallax_uv = uv + parallax;

    // Swept focal plane: ping-pong keeps HEAD's sweep speed but no longer snaps from 1 to 0 each period.
    let focal_depth = ping_pong(zoom_time * u.zoom_params.x);

    // Raymarch through depth slices
    let num_slices: i32 = 5;
    var accumulated_color = vec3<f32>(0.0);
    var accumulated_depth = 0.0;
    var total_weight = 0.0;

    for (var i: i32 = 0; i < num_slices; i = i + 1) {
        let slice_depth = f32(i) / f32(num_slices - 1);
        // Idea 1 — foreground and background slices scroll at their saved speeds
        let sliceSpeed = mix(u.zoom_params.x, u.zoom_params.y, slice_depth);
        let sliceDrift = vec2<f32>(time * sliceSpeed * 0.015, time * sliceSpeed * 0.006);
        let layer = sample_layer(parallax_uv + sliceDrift, zoom_center, slice_depth);
        var color = layer.rgb;
        var depth = layer.a;

        // Depth-of-field: weight based on focal plane
        let dof_factor = exp(-abs(depth - focal_depth) * DOF_AMOUNT * 10.0);

        // Volumetric density falloff
        let density = exp(-slice_depth * 2.0);

        let weight = dof_factor * density;
        // Idea 2 — pale sheet on the current focal plane
        let focalSheet = exp(-abs(slice_depth - focal_depth) * 36.0);
        color = color + vec3<f32>(0.82, 0.9, 1.0) * focalSheet * 0.12;
        // Idea 4 — focal-plane iso-depth contour: the sheet is a flat tint per slice, but where the swept
        // focal plane actually cuts the scene (this slice's sampled depth == focal depth) it lights a thin
        // contour, a scan line traced on the geometry. Promotes the |depth - focal| the DOF weight already uses.
        let focalGap = abs(depth - focal_depth) * 26.0;
        color = color + vec3<f32>(0.82, 0.9, 1.0) * exp(-focalGap * focalGap) * 0.22;
        accumulated_color = accumulated_color + color * weight;
        accumulated_depth = accumulated_depth + depth * weight;
        total_weight = total_weight + weight;
    }

    let final_color = accumulated_color / max(total_weight, 0.0001);
    let final_depth = accumulated_depth / max(total_weight, 0.0001);

    // Relief normal + depth gradient from the same four taps of the unzoomed map. HEAD compared a
    // tap of that map with the zoomed slice blend (final_depth), which is non-zero over whole regions.
    let nrm = reconstruct_normal(uv, final_depth, resolution);
    let normal = nrm.xyz;

    // Lighting
    let light_angle = zoom_time * 0.5;
    let light_pos = vec3<f32>(cos(light_angle), sin(light_angle), -1.5);
    let view_pos = vec3<f32>(uv - vec2<f32>(0.5, 0.5), CAMERA_Z);
    let light_dir = normalize(light_pos - view_pos);
    let light_strength = LIGHT_BASE + bass * 0.6;
    let diffuse = max(dot(normal, light_dir), 0.0) * light_strength;

    // Idea 3 — light-facing rim glint: the edge specular lights only the silhouette that faces the
    // orbiting light (normal.xy against light.xy; a 0.04 floor keeps the far side faintly lit), so the glint
    // travels around each silhouette as the light orbits instead of lighting every edge at once.
    let facing = dot(normal.xy, light_dir.xy) / max(length(normal.xy) * length(light_dir.xy), 1e-5);
    let rim = mix(0.04, 1.0, smoothstep(0.2, 0.85, facing));
    let specular = min(pow(max(nrm.w * 10.0, 0.0), 16.0), 1.5) * light_strength * rim;

    let ambient = AMBIENT;
    let lit_color = final_color * (ambient + diffuse) + vec3<f32>(specular);

    // Fog
    let fogged_color = calculate_fog(final_depth, lit_color);

    // Advanced Alpha: Depth-Layered
    let alpha = calculateAdvancedAlpha(fogged_color, final_depth, total_weight);
    
    
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let event = u.ripples[i];
        let age = max(time - event.z, 0.0);
        clickFront += exp(-age * 1.8) * exp(-abs(length((uv - event.xy) * vec2<f32>(u.config.z/u.config.w, 1.0)) - age * 0.38) * 58.0);
    }
    
    let clockRings = sin(length(uv - vec2<f32>(0.5)) * 95.0 - time * (5.0 + treble * 7.0));
    let spectral = 0.5 + 0.5 * cos(vec3<f32>(0.0, 2.094, 4.188) + clockRings * 3.0 + time * (0.8 + mids));

    let finalRGB = acesToneMap(fogged_color + spectral * (abs(clockRings) * 0.1 + clickFront * 0.25));
    textureStore(writeTexture, vec2<u32>(global_id.xy), vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, vec2<u32>(global_id.xy), vec4<f32>(final_depth, 0.0, 0.0, 0.0));
}
