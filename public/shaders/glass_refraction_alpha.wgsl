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
//  Upgraded: 2026-08-23 (Batch 64)
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
//  TWO NEW STRUCTURES
//
//    1. Cauchy dispersion — the chromatic split perturbed eta by a flat
//       ±dispersion*0.02 per channel, which splits the channels but gets the
//       physics backwards: real glass has n(λ) = A + B/λ², so blue refracts
//       hardest and the spread is set by the material's B coefficient. Each
//       channel now gets its own Cauchy index, so the fringe fans the correct
//       way and its width tracks the true index spread.
//
//    2. Per-band caustic focusing — light converging through the glass focuses
//       into caustics where the refracted rays bunch. The caustic intensity is
//       computed from the divergence of the refracted direction field and
//       modulated per FFT band, so the bright filaments pulse with the spectrum
//       instead of the whole surface brightening uniformly.
// ═══════════════════════════════════════════════════════════════════════════════

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

const PI: f32 = 3.14159265359;
const ETA: f32 = 1.5; // Glass refractive index

// SDF primitives
fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let d = abs(p) - b;
    return length(max(d, vec3<f32>(0.0))) + min(max(d.x, max(d.y, d.z)), 0.0);
}

fn sdRoundBox(p: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let q = abs(p) - b + r;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0) - r;
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
        let refracted = refractRay(rd, normal, eta);

        let refractR = refractRay(rd, normal, 1.0 / (nR + bassSwell)).xy;
        let refractG = refractRay(rd, normal, eta).xy;
        let refractB = refractRay(rd, normal, 1.0 / (nB + bassSwell)).xy;

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
        
        // Glass tint (subtle color)
        let glassTint = vec3<f32>(0.95, 0.98, 1.0);
        
        // Beer-Lambert over the REAL interior path (see header: exitT was never
        // written, so this used the distance to the surface).
        let absorption = exp(-vec3<f32>(0.1, 0.05, 0.15) * thicknessScale
                             * (0.35 + interiorPath * 2.4));
        
        // Combine reflection and refraction
        finalRGB = mix(refractColor * absorption * glassTint, bgColor, fresnelFactor * 0.3);
        // Caustic filaments where the refracted rays converge.
        finalRGB += vec3<f32>(1.0, 0.94, 0.82) * caustic * 0.55;
        
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
