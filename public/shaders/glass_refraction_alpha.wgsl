// ═══════════════════════════════════════════════════════════════════════════════
//  glass_refraction_alpha.wgsl - Glass Refraction with Transparency
//  
//  RGBA Focus: Alpha = transparency/thickness of glass
//  Techniques:
//    - Snell's law refraction with chromatic dispersion
//    - Fresnel reflectivity based on viewing angle
//    - Alpha accumulation for multi-layer glass
//    - Thickness-based absorption
//    - Caustic highlights
//  
//  Target: 4.8★ rating
//  Upgraded: 2026-10-17
//  Ideas: Cauchy dispersion n(lambda) = A + B/lambda^2; per-band FFT caustic focusing; exit-interface secondary refraction & critical-angle TIR bevel corona; smooth-union neck photoelastic stress birefringence
//  A packing: ACES display RGBA in A (surface normal + interiorPath in B)
//
//  FIXED IN THIS PASS — fake audio. `plasmaBuffer` was bound at binding 12 and
//  never read, while a variable literally named `audioPulse` was assigned
//  `u.zoom_config.w` — the MOUSE BUTTON state — and used to modulate the
//  refractive index, the edge glow and the dispersion. So the shader's
//  "audio" response was really just "is the button held", and real sound did
//  nothing. Audio now comes from `plasmaBuffer[0].xyz` with per-band detail
//  from `[1..8]`, and the mouse-down term is named honestly.
//
//  Also: the ray march declared `exitT` and never wrote it, so the glass had no
//  exit point and the absorption path length was the DISTANCE TO THE SURFACE
//  rather than the distance through the glass. The march now finds the exit and
//  Beer-Lambert runs over the real interior path.
//
//  FOUR STRUCTURES
//
//    1. Cauchy dispersion — n(λ) = A + B/λ² per channel.
//    2. Per-band caustic focusing — convergence of refracted rays modulated per FFT band.
//    3. Exit-interface secondary refraction & critical-angle TIR bevel corona —
//       evaluates the outward back-wall normal at exitT for two-surface lens bending
//       and wavelength-split total-internal-reflection rim arcs.
//    4. Smooth-union neck photoelastic stress birefringence — cross-polarized
//       stress-retardation fringes inside the coalescing bridges between glass blobs.
// ═══════════════════════════════════════════════════════════════════════════════

#include "_prelude.wgsl"

const PI: f32 = 3.14159265359;
const ETA: f32 = 1.5; // Glass refractive index

// SDF primitives
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

// Smooth union for glass blobs
fn smoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

// Scene SDF
fn map(p: vec3<f32>, time: f32) -> f32 {
    // Animated glass blobs
    let blob1 = sdSphere(p - vec3<f32>(sin(time * 0.5) * 0.2, 0.0, 0.0), 0.25);
    let blob2 = sdSphere(p - vec3<f32>(cos(time * 0.3) * 0.2, sin(time * 0.4) * 0.15, 0.1), 0.2);
    let blob3 = sdSphere(p - vec3<f32>(0.0, cos(time * 0.6) * 0.15, sin(time * 0.5) * 0.1), 0.18);
    
    return smoothUnion(smoothUnion(blob1, blob2, 0.1), blob3, 0.08);
}

// Coalescing neck stress where smooth-union glass bridges meet
fn blobNeckStress(p: vec3<f32>, time: f32) -> f32 {
    let blob1 = sdSphere(p - vec3<f32>(sin(time * 0.5) * 0.2, 0.0, 0.0), 0.25);
    let blob2 = sdSphere(p - vec3<f32>(cos(time * 0.3) * 0.2, sin(time * 0.4) * 0.15, 0.1), 0.2);
    let blob3 = sdSphere(p - vec3<f32>(0.0, cos(time * 0.6) * 0.15, sin(time * 0.5) * 0.1), 0.18);
    let s12 = exp(-abs(blob1 - blob2) * 16.0) * smoothstep(0.14, -0.02, max(blob1, blob2));
    let s23 = exp(-abs(blob2 - blob3) * 16.0) * smoothstep(0.14, -0.02, max(blob2, blob3));
    let s13 = exp(-abs(blob1 - blob3) * 16.0) * smoothstep(0.14, -0.02, max(blob1, blob3));
    return clamp(s12 + s23 + s13, 0.0, 1.5);
}

// Calculate normal
fn calcNormal(p: vec3<f32>, time: f32) -> vec3<f32> {
    let eps = 0.001;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(eps, 0.0, 0.0), time) - map(p - vec3<f32>(eps, 0.0, 0.0), time),
        map(p + vec3<f32>(0.0, eps, 0.0), time) - map(p - vec3<f32>(0.0, eps, 0.0), time),
        map(p + vec3<f32>(0.0, 0.0, eps), time) - map(p - vec3<f32>(0.0, 0.0, eps), time)
    ));
}

// Fresnel reflectance
fn fresnel(cosTheta: f32, eta: f32) -> f32 {
    let c = abs(cosTheta);
    let g = sqrt(eta * eta - 1.0 + c * c);
    let gmc = g - c;
    let gpc = g + c;
    let a = (gmc / gpc) * (gmc / gpc);
    let b = (c * gpc - 1.0) / (c * gmc + 1.0);
    return 0.5 * a * (1.0 + b * b);
}

// Refraction with Snell's law
fn refractRay(I: vec3<f32>, N: vec3<f32>, eta: f32) -> vec3<f32> {
    let NdotI = dot(N, I);
    let k = 1.0 - eta * eta * (1.0 - NdotI * NdotI);
    if (k < 0.0) {
        return vec3<f32>(0.0); // Total internal reflection
    }
    return eta * I - (eta * NdotI + sqrt(k)) * N;
}

// Chromatic dispersion
fn refractChromatic(I: vec3<f32>, N: vec3<f32>, eta: f32, dispersion: f32) -> vec3<f32> {
    let etaR = eta - dispersion;
    let etaG = eta;
    let etaB = eta + dispersion;
    
    return vec3<f32>(
        refractRay(I, N, etaR).x,
        refractRay(I, N, etaG).y,
        refractRay(I, N, etaB).z
    );
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Parameters
    let transparency = 0.3 + u.zoom_params.x * 0.5; // 0.3-0.8
    let thicknessScale = 0.5 + u.zoom_params.z; // Absorption thickness
    let roughness = u.zoom_params.w * 0.1; // Surface roughness

    let mousePos = (u.zoom_config.yz - 0.5) * 2.0;
    // Honest names: this is the button, not audio (see header).
    let mouseDown = u.zoom_config.w;
    let isMouseDown = mouseDown > 0.5;
    let mouseUV = u.zoom_config.yz;
    let distToMouse = length(uv - mouseUV);
    let mouseGravity = 1.0 - smoothstep(0.0, 0.35, distToMouse);

    // ── Real audio ────────────────────────────────────────────────────────
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    // Radial FFT banding: each annulus around the cursor owns one bin.
    let bandIdx = u32(clamp(distToMouse * 8.0, 0.0, 7.999));
    let band = plasmaBuffer[bandIdx + 1u].x;

    // ── Bounded click pressure fronts ─────────────────────────────────────
    var clickFront = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var ri = 0u; ri < rippleCount; ri = ri + 1u) {
        let rp = u.ripples[ri];
        let age = time - rp.z;
        if (age >= 0.0 && age < 2.4) {
            let r = length(uv - rp.xy);
            let front = r - age * 0.5;
            clickFront += exp(-front * front * 170.0) * exp(-age * 1.4);
        }
    }
    clickFront = min(clickFront, 1.5);

    let dispersion = u.zoom_params.y * 0.1 * (1.0 + mouseGravity * 2.0 + treble * 1.2);
    // Camera ray
    let ro = vec3<f32>(mousePos.x * 0.5, mousePos.y * 0.5, -1.5);
    let rd = normalize(vec3<f32>(uv.x - 0.5, uv.y - 0.5, 1.0));
    
    // Ray march through glass
    var t = 0.0;
    var hit = false;
    var enterT = 0.0;
    var exitT = 0.0;
    var normal = vec3<f32>(0.0);
    
    // Find entry point
    for (var i: i32 = 0; i < 64; i = i + 1) {
        let p = ro + rd * t;
        let d = map(p, time);
        
        if (!hit && d < 0.001) {
            hit = true;
            enterT = t;
            normal = calcNormal(p, time);
            break;
        }
        
        t += max(d * 0.5, 0.001);
        if (t > 3.0) { break; }
    }

    // Find the EXIT point. `exitT` was declared and never written, so the
    // absorption below ran over the distance to the surface instead of the
    // distance through the glass — thin and thick glass absorbed identically.
    if (hit) {
        var te = enterT + 0.01;
        for (var j: i32 = 0; j < 64; j = j + 1) {
            let pe = ro + rd * te;
            let de = map(pe, time);
            if (de > 0.001) { break; }
            te += max(abs(de) * 0.5, 0.002);
            if (te > 3.0) { break; }
        }
        exitT = te;
    }
    let interiorPath = max(exitT - enterT, 0.0);
    
    // Sample background
    var bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    
    var finalRGB = bgColor;
    var finalAlpha = 0.0;
    
    if (hit) {
        // ── Structure 1: Cauchy dispersion n(lambda) = A + B/lambda^2 ────────
        // Blue has the highest index and bends hardest; the old code perturbed
        // eta by a flat constant per channel, which reversed the ordering.
        let cauchyB = 0.0042 + dispersion * 0.06;
        let nR = ETA + cauchyB / (0.650 * 0.650);
        let nG = ETA + cauchyB / (0.532 * 0.532);
        let nB = ETA + cauchyB / (0.450 * 0.450);
        let bassSwell = bass * 0.08;

        let eta = 1.0 / (nG + bassSwell);
        let dirInR = refractRay(rd, normal, 1.0 / (nR + bassSwell));
        let dirInG = refractRay(rd, normal, eta);
        let dirInB = refractRay(rd, normal, 1.0 / (nB + bassSwell));

        // ── Structure 3: Exit-interface secondary refraction & TIR bevel corona ──
        let exitPos = ro + rd * exitT;
        let exitNormal = calcNormal(exitPos, time);
        let exitRefrR = refractRay(dirInR, -exitNormal, nR + bassSwell);
        let exitRefrG = refractRay(dirInG, -exitNormal, nG + bassSwell);
        let exitRefrB = refractRay(dirInB, -exitNormal, nB + bassSwell);

        let refractR = mix(dirInR.xy, exitRefrR.xy, step(0.01, length(exitRefrR)) * 0.38);
        let refractG = mix(dirInG.xy, exitRefrG.xy, step(0.01, length(exitRefrG)) * 0.38);
        let refractB = mix(dirInB.xy, exitRefrB.xy, step(0.01, length(exitRefrB)) * 0.38);

        let cosExit = abs(dot(dirInG, -exitNormal));
        let sin2Exit = max(1.0 - cosExit * cosExit, 0.0);
        let kExitR = 1.0 - (nR + bassSwell) * (nR + bassSwell) * sin2Exit;
        let kExitG = 1.0 - (nG + bassSwell) * (nG + bassSwell) * sin2Exit;
        let kExitB = 1.0 - (nB + bassSwell) * (nB + bassSwell) * sin2Exit;
        let tirCorona = vec3<f32>(
            smoothstep(0.28, -0.05, kExitR),
            smoothstep(0.28, -0.05, kExitG),
            smoothstep(0.28, -0.05, kExitB)
        ) * (0.42 + treble * 0.55);

        // ── Structure 4: Smooth-union neck photoelastic stress birefringence ──
        let midPos = ro + rd * (enterT + interiorPath * 0.5);
        let neckStress = blobNeckStress(midPos, time);
        let stressOPD = neckStress * interiorPath * (1.4 + dispersion * 9.0 + bass * 0.6);
        let stressFringe = 0.5 + 0.5 * cos(stressOPD * vec3<f32>(9.6, 11.8, 14.2) + vec3<f32>(0.0, 2.094, 4.188));

        // ── Structure 2: per-band caustic focusing ───────────────────────────
        // Caustics form where the refracted direction field converges. The
        // divergence of that field across the three wavelengths is a cheap,
        // honest proxy for the focusing strength.
        let spreadRB = length(refractR - refractB);
        let convergence = 1.0 - clamp(spreadRB * 26.0, 0.0, 1.0);
        let caustic = pow(convergence, 5.0) * (0.35 + band * 2.1 + clickFront * 0.9);
        
        let refractUV = vec2<f32>(refractG.x, refractG.y) * 0.3 + uv;
        let refractUVR = vec2<f32>(refractR.x, refractR.y) * 0.3 + uv;
        let refractUVB = vec2<f32>(refractB.x, refractB.y) * 0.3 + uv;
        
        // Sample refracted background with chromatic dispersion
        let refractColor = vec3<f32>(
            textureSampleLevel(readTexture, u_sampler, refractUVR, 0.0).r,
            textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).g,
            textureSampleLevel(readTexture, u_sampler, refractUVB, 0.0).b
        );
        
        // Fresnel for reflectivity
        let viewDotNormal = dot(-rd, normal);
        let fresnelFactor = fresnel(viewDotNormal, eta);
        
        // Glass tint (subtle color) modulated by photoelastic neck stress
        let glassTint = mix(vec3<f32>(0.95, 0.98, 1.0), stressFringe, clamp(neckStress * 0.48, 0.0, 0.65));
        
        // Beer-Lambert over the REAL interior path (see header: exitT was never
        // written, so this used the distance to the surface).
        let absorption = exp(-vec3<f32>(0.1, 0.05, 0.15) * thicknessScale
                             * (0.35 + interiorPath * 2.4));
        
        // Combine reflection and refraction
        finalRGB = mix(refractColor * absorption * glassTint, bgColor, fresnelFactor * 0.3);
        // Caustic filaments where the refracted rays converge + critical-angle TIR bevel corona
        finalRGB += vec3<f32>(1.0, 0.94, 0.82) * caustic * 0.55 + tirCorona * 0.36 + stressFringe * neckStress * 0.18;
        
        // Specular highlight
        let lightDir = normalize(vec3<f32>(0.5, 1.0, 0.5));
        let halfDir = normalize(lightDir - rd);
        let specAngle = max(dot(normal, halfDir), 0.0);
        let specular = pow(specAngle, 128.0) * (1.0 - roughness) * (1.0 + mouseGravity * 2.0);
        finalRGB += vec3<f32>(1.0) * specular;
        
        // Alpha based on Fresnel and transparency setting
        finalAlpha = (1.0 - transparency) + fresnelFactor * transparency;
        finalAlpha = clamp(finalAlpha * 0.8, 0.0, 0.95);
    } else {
        // No hit - fully transparent
        finalAlpha = 0.0;
    }
    
    // Add caustic-like glow at edges
    var edgeGlow = smoothstep(0.02, 0.0, map(ro + rd * enterT, time)) * (mouseDown + mids * 0.5);
    edgeGlow = edgeGlow + mouseGravity * 0.3;
    finalRGB += vec3<f32>(0.8, 0.9, 1.0) * edgeGlow * 0.5;
    finalAlpha = max(finalAlpha, edgeGlow * 0.5);
    
    finalRGB += vec3<f32>(1.0, 0.86, 0.65) * clickFront * 0.4;

    // Temporal glow (exact load — dataTextureC is rgba32float).
    let prev = textureLoad(dataTextureC, coord, 0);
    finalRGB = max(finalRGB, prev.rgb * (0.76 + mids * 0.08));

    finalRGB = acesFilm(finalRGB);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    
    // Advanced Alpha: physical transmittance over the interior path.
    let alpha = clamp(calculateAdvancedAlpha(finalRGB, finalAlpha, interiorPath, normal, hit)
                      + clickFront * 0.2, 0.0, 1.0);
    let outColor = vec4<f32>(finalRGB * vignette, alpha);

    textureStore(writeTexture, coord, outColor);
    // A carries DISPLAY RGBA so the feedback read above is meaningful; the
    // surface normal that used to live here (and that nothing read) moves to B.
    textureStore(dataTextureA, coord, outColor);
    textureStore(dataTextureB, coord, vec4<f32>(normal * 0.5 + 0.5, interiorPath));

    // Depth: scene geometry preserved (was overwritten with the glass alpha),
    // pulled forward where the glass body sits in front of the plate.
    let sceneDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let glassDepth = select(sceneDepth, min(sceneDepth, enterT / 3.0), hit);
    textureStore(writeDepthTexture, coord, vec4<f32>(clamp(glassDepth, 0.0, 1.0), 0.0, 0.0, 1.0));
}

fn acesFilm(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// ═══ ADVANCED ALPHA FUNCTION ═══
fn calculateAdvancedAlpha(color: vec3<f32>, baseAlpha: f32, interiorPath: f32, normal: vec3<f32>, hit: bool) -> f32 {
    // Tunable parameters from zoom_params
    let transparency = 0.3 + u.zoom_params.x * 0.5; // Transparency
    let dispersion = u.zoom_params.y * 0.1;         // Dispersion
    let thicknessScale = 0.5 + u.zoom_params.z;     // Thickness
    let roughness = u.zoom_params.w * 0.1;          // Roughness
    
    if (!hit) {
        return 0.0;
    }
    
    // Beer's Law absorption
    let absorptionCoeff = vec3<f32>(0.12, 0.06, 0.18) * (1.0 + dispersion * 2.0);
    let opticalDepth = thicknessScale * (0.2 + interiorPath * 2.0);
    let absorption = exp(-absorptionCoeff * opticalDepth);
    
    // Fresnel factor from normal
    let viewDotNormal = abs(normal.z);
    let F0 = pow((1.5 - 1.0) / (1.5 + 1.0), 2.0);
    let fresnel = F0 + (1.0 - F0) * pow(1.0 - viewDotNormal, 5.0);
    
    // Volumetric alpha from optical thickness
    let density = (1.0 - transparency) * thicknessScale;
    let volumetricAlpha = 1.0 - exp(-density * opticalDepth * 3.0);
    
    // Base alpha modulated by absorption and Fresnel
    let transmittanceAlpha = baseAlpha * dot(absorption, vec3<f32>(0.333)) * (1.0 - fresnel * 0.5);
    
    // Combine physical transmittance with volumetric density
    let alpha = mix(transmittanceAlpha, volumetricAlpha, 0.5) + roughness * 0.1;
    
    return clamp(alpha, 0.0, 0.98);
}
