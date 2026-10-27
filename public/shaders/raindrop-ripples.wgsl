// ═══════════════════════════════════════════════════════════════════
//  Raindrop Ripples
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-10-26
//  Ideas: wave-speed in the Laplacian; slope caustic sparkle; isotropic 9-point Laplacian (§12.2D); steep-slope damping
//  A packing: height / prev-height in A.rg (raw). Display ACES RGB.
// ═══════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn heightAt(pixel: vec2<i32>, dims: vec2<i32>) -> vec2<f32> {
    let s = textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0);
    return s.rg;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(global_id.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let time = u.config.x;
    let mousePos = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let aspect = resolution.x / max(resolution.y, 1.0);
    let dims = vec2<i32>(resolution);
    let bass = plasmaBuffer[0].x;
    let treble = plasmaBuffer[0].z;

    let rainIntensity = u.zoom_params.x * (1.0 + bass * 0.35);
    let decay = 0.9 + (u.zoom_params.y * 0.09);
    // Idea 1 — speed slider is c² of the pond (was assigned and unused)
    let waveC = clamp(0.12 + u.zoom_params.z * 0.28, 0.08, 0.45);
    let shieldRadius = u.zoom_params.w * 0.3;

    let old = heightAt(pixel, dims);
    let height = old.x;
    let prevHeight = old.y;
    let n = heightAt(pixel + vec2<i32>(0, 1), dims).x;
    let s = heightAt(pixel + vec2<i32>(0, -1), dims).x;
    let e = heightAt(pixel + vec2<i32>(1, 0), dims).x;
    let w = heightAt(pixel + vec2<i32>(-1, 0), dims).x;
    let ne = heightAt(pixel + vec2<i32>(1, 1), dims).x;
    let nw = heightAt(pixel + vec2<i32>(-1, 1), dims).x;
    let se = heightAt(pixel + vec2<i32>(1, -1), dims).x;
    let sw = heightAt(pixel + vec2<i32>(-1, -1), dims).x;
    // ── Idea 1: isotropic 9-point Laplacian (§12.2D) ───────────────
    // Corner weight 0.2, edge weight 0.8. A constant field and a lone
    // spike match the old 5-point magnitude, so waveC keeps its meaning.
    let lap = 0.8 * (n + s + e + w) + 0.2 * (ne + nw + se + sw) - 4.0 * height;

    var newHeight = height * 2.0 - prevHeight + lap * waveC;
    // ── Idea 2: steep-slope damping ────────────────────────────────
    // Sharp rings spend decay faster than a broad swell.
    let steep = clamp(abs(lap) * 0.06, 0.0, 0.2);
    newHeight = newHeight * decay * (1.0 - steep);

    let gridSize = 20.0;
    let gridUV = floor(vec2<f32>(pixel) / gridSize);
    let dropTime = floor(time * 60.0);
    let rand = hash12(gridUV + vec2<f32>(dropTime * 12.34));
    if (rand > (1.0 - rainIntensity * 0.01)) {
        newHeight = newHeight + 5.0;
    }

    if (shieldRadius > 0.0) {
        let dVec = uv - mousePos;
        let d = length(vec2<f32>(dVec.x * aspect, dVec.y));
        if (d < shieldRadius) {
            newHeight = newHeight * smoothstep(0.0, shieldRadius, d);
            if (d > shieldRadius * 0.9) {
                newHeight = newHeight + 0.1;
            }
        }
    }

    newHeight = clamp(newHeight, -10.0, 10.0);
    textureStore(dataTextureA, pixel, vec4<f32>(newHeight, height, lap, 0.0));

    let slopeX = e - w;
    let slopeY = n - s;
    let distortion = vec2<f32>(slopeX, slopeY) * 0.05;
    let finalUV = clamp(uv + distortion, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
    let normal = normalize(vec3<f32>(-slopeX * 2.0, -slopeY * 2.0, 1.0));
    let spec = pow(max(dot(normal, lightDir), 0.0), 20.0);
    // Idea 2 — caustic from focusing (negative Laplacian)
    let caustic = pow(max(-lap, 0.0), 1.4) * 0.08 * (1.0 + treble * 0.6);
    var hdr = color.rgb + spec * 0.3 + vec3<f32>(caustic * 1.1, caustic * 1.05, caustic * 0.9);
    let mapped = aces(max(hdr, vec3<f32>(0.0)));
    let waveAmt = clamp(abs(newHeight) * 0.12 + spec * 0.4 + caustic * 2.0, 0.0, 1.0);
    let alpha = clamp(color.a * 0.5 + waveAmt * 0.5, 0.0, 1.0);

    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
