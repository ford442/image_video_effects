// ═══════════════════════════════════════════════════════════════
//  Sphere Projection
//  Category: geometric
//  Features: mouse-driven, 3d, audio-reactive, upgraded-rgba,
//            meridians, held-drag, bounded-click-ripples
//  Complexity: High
//  Upgraded: 2026-08-23, 2026-11-15
//  Ideas: limb Fresnel (§12.2F); directional glint
//  A packing: ACES display RGBA
// ═══════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;

fn aces(x: vec3<f32>) -> vec3<f32> {
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
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let held = f32(u.zoom_config.w > 0.5);
    let mouse = u.zoom_config.yz;
    let prev = textureLoad(dataTextureC, pixel, 0);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let zoom_param = max(u.zoom_params.x, 0.01);
    let rotation_param = u.zoom_params.y;
    let light_param = u.zoom_params.z;
    let ambient_param = u.zoom_params.w;

    let min_res = min(resolution.x, resolution.y);
    let ndc = (vec2<f32>(global_id.xy) * 2.0 - resolution) / min_res;
    let distCam = 3.0 / zoom_param * (1.0 - held * 0.12);
    let ro = vec3<f32>(0.0, 0.0, -distCam);
    let rd = normalize(vec3<f32>(ndc, 1.0));
    let b = dot(ro, rd);
    let c = dot(ro, ro) - 1.0;
    let h = b * b - c;
    let hit = f32(h >= 0.0);
    let t = select(0.0, -b - sqrt(max(h, 0.0)), hit > 0.5);
    let p = ro + rd * t;
    let n = normalize(p);

    let yaw = -(mouse.x - 0.5) * 2.0 * PI - time * rotation_param * (1.0 + bass * 0.4);
    let pitch = (mouse.y - 0.5) * PI;
    let cy = cos(yaw); let sy = sin(yaw);
    let cx = cos(pitch); let sx = sin(pitch);
    let rotY = mat3x3<f32>(cy, 0.0, sy, 0.0, 1.0, 0.0, -sy, 0.0, cy);
    let rotX = mat3x3<f32>(1.0, 0.0, 0.0, 0.0, cx, -sx, 0.0, sx, cx);
    let n_rot = rotX * (rotY * n);
    let tex_uv = vec2<f32>(fract(atan2(n_rot.z, n_rot.x) / (2.0 * PI) + 0.5), clamp(acos(clamp(n_rot.y, -1.0, 1.0)) / PI, 0.0, 1.0));
    let tex = textureSampleLevel(readTexture, u_sampler, tex_uv, 0.0);
    let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let lightDir = normalize(vec3<f32>(-0.5, 0.5, -1.0));
    let lighting = mix(1.0, mix(0.0, 0.6, ambient_param) + max(0.0, dot(n, lightDir)), light_param);
    var color = mix(bg.rgb, tex.rgb * lighting, hit);

    let lon = atan2(n_rot.z, n_rot.x);
    let lat = asin(clamp(n_rot.y, -1.0, 1.0));
    let meridians = smoothstep(0.06, 0.0, abs(fract(lon / PI * 6.0 + time * (0.35 + rotation_param)) - 0.5));
    let parallels = smoothstep(0.06, 0.0, abs(fract(lat / PI * 8.0 - time * 0.55) - 0.5));
    var click = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        if (rp.z > 0.0 && age >= 0.0 && age < 1.5) {
            click = max(click, exp(-abs(distance(uv, rp.xy) - age * 0.5) * 58.0) * (1.0 - age / 1.5));
        }
    }
    let slick = hsv2rgb(vec3<f32>(fract(lon / (2.0 * PI) + time * 0.08 + mids * 0.2), 0.7, 1.0));
    color = mix(color, color * slick * 1.2, hit * (0.22 + treble * 0.2));
    color += slick * hit * (meridians * 0.28 + parallels * 0.22 + click * 0.5);

    // ── Idea 1: limb Fresnel (§12.2F) ────────────────────────────────
    // Grazing the sphere picks up a cool rim. Lambert from Lighting is unchanged.
    let ndv = clamp(dot(n, -rd), 0.0, 1.0);
    let fres = pow(1.0 - ndv, 5.0) * hit;
    color += vec3<f32>(0.45, 0.68, 1.0) * fres * 0.7;

    // ── Idea 2: directional glint ────────────────────────────────────
    // Tight Blinn highlight from the existing key light, scaled by Lighting.
    let halfH = lightDir - rd;
    let halfV = halfH / max(length(halfH), 0.001);
    let spec = pow(max(dot(n, halfV), 0.0), 40.0) * light_param * hit;
    color += vec3<f32>(1.0, 0.97, 0.92) * spec;

    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(mix(bg.a, 0.35 + luma * 0.65, hit), 0.0, 1.0);
    let preRgb = mix(color, prev.rgb * 0.88, 0.2 * hit);
    let outCol = vec4<f32>(aces(max(preRgb, vec3<f32>(0.0))), mix(alpha, prev.a * 0.88, 0.2 * hit));
    let depthSrc = textureLoad(readDepthTexture, pixel, 0).r;
    let depthOut = mix(depthSrc, clamp(t / 10.0 + meridians * 0.05, 0.0, 1.0), hit);
    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
