// ═══════════════════════════════════════════════════════════════════
//  Crystal Facets
//  Category: distortion
//  Features: mouse-driven, refraction, fresnel, dispersion, internal-reflection, audio-caustics, depth-prisms, volumetric-gems
//  Complexity: Medium
//  Updated: 2026-08-23
//  By: Grok (strict conformity, audio-reactive bounded spring, aces, capped ripples)
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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const IOR_GLASS: f32 = 1.5;
const IOR_DIAMOND: f32 = 2.42;

fn hash11(p: f32) -> f32 {
    var p2 = fract(p * .1031);
    p2 *= p2 + 33.33;
    p2 *= p2 + p2;
    return fract(p2);
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

fn pathLengthThroughCrystal(cosTheta: f32, thickness: f32) -> f32 {
    return thickness / max(abs(cosTheta), 0.01);
}

fn acesToneMap(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    
    // Persistent state strictly in extraBuffer[133..138] (single-writer)
    if (global_id.x == 0u && global_id.y == 0u) {
        let dt = 0.016;
        var pos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
        var vel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        
        // Bounded spring + held-pointer response
        let target = u.zoom_config.yz;
        let force = (target - pos) * 50.0 - vel * 8.0;
        vel += force * dt;
        pos += vel * dt;
        
        pos = clamp(pos, vec2<f32>(0.0), vec2<f32>(1.0));
        
        extraBuffer[133] = pos.x;
        extraBuffer[134] = pos.y;
        extraBuffer[135] = vel.x;
        extraBuffer[136] = vel.y;
        extraBuffer[137] = 0.0; // unused
        extraBuffer[138] = 0.0; // unused
    }
    workgroupBarrier();

    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    
    let spring_pos = vec2<f32>(extraBuffer[133], extraBuffer[134]);

    // Preserve existing params exactly:
    // x: Facet Count, y: Refraction Strength + IOR mix, z: Rotation Speed / Fracture density, w: Crystal Thickness
    let facetCount = floor(mix(3.0, 16.0, u.zoom_params.x));
    let iorMix = u.zoom_params.y;
    let fractureDensity = u.zoom_params.z;
    let crystalThickness = mix(0.1, 2.0, u.zoom_params.w);
    
    let ior = mix(IOR_GLASS, IOR_DIAMOND, iorMix);
    let refraction = mix(0.02, 0.15, iorMix);
    let rotation = time * 0.1;

    var center = spring_pos;
    var dir = (uv - center);
    dir.x *= aspect;

    // Capped click fronts
    var ripple_disp = vec2<f32>(0.0);
    for (var i = 0u; i < 50u; i++) {
        let r = u.ripples[i];
        if (r.w > 0.0) {
            let t = r.w;
            let d = length(uv - r.xy);
            let front = t * 2.0;
            if (d < front && d > front - 0.25) {
                let phase = (d - front) * 25.0;
                let env = smoothstep(front - 0.25, front - 0.1, d) * smoothstep(front, front - 0.1, d);
                let amp = exp(-t * 3.0) * env;
                let rDir = normalize(uv - r.xy + vec2<f32>(1e-5));
                ripple_disp += rDir * sin(phase) * amp * r.z * 0.025;
            }
        }
    }
    dir += ripple_disp;
    
    let dist = length(dir);
    var angle = atan2(dir.y, dir.x);
    angle += rotation;
    
    // Continuous geometry via smooth facet transitions
    let rawSector = angle / (6.28318 / facetCount);
    let sector = floor(rawSector);
    let sectorAngle = sector * (6.28318 / facetCount);

    let facetID = sector;
    let randomTilt = (hash11(facetID) - 0.5) * 2.0;
    let facetFracture = hash11(facetID + 100.0);

    let offsetDir = vec2<f32>(cos(sectorAngle), sin(sectorAngle));

    let rOffset = offsetDir * refraction * (1.0 + randomTilt * 0.5);
    let gOffset = offsetDir * refraction * 0.5;
    let bOffset = offsetDir * refraction * (0.0 - randomTilt * 0.5);

    let distDistorted = dist;
    let baseUV = center + vec2<f32>(cos(angle - rotation), sin(angle - rotation)) * distDistorted / vec2<f32>(aspect, 1.0);

    // Exact textureLoad from dataTextureC
    let prev_c = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;

    let r_val = textureSampleLevel(readTexture, u_sampler, baseUV - rOffset, 0.0).r;
    let g_val = textureSampleLevel(readTexture, u_sampler, baseUV - gOffset, 0.0).g;
    let b_val = textureSampleLevel(readTexture, u_sampler, baseUV - bOffset, 0.0).b;
    var color = vec3<f32>(r_val, g_val, b_val);
    
    // Subtle trail integration
    color = mix(color, prev_c, 0.05);

    let angleToNormal = abs(fract(rawSector) - 0.5) * 2.0;
    let cosTheta = cos(angleToNormal * 1.57);
    
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);
    let fresnel = fresnelSchlick(cosTheta, F0);
    let pathLength = pathLengthThroughCrystal(cosTheta, crystalThickness);
    let purity = 1.0 - (fractureDensity * facetFracture);
    let absorptionCoeff = mix(0.5, 5.0, fractureDensity);
    let absorption = exp(-absorptionCoeff * pathLength / max(purity, 0.1));
    
    let angleLocal = fract(rawSector);
    let edgeDist = min(angleLocal, 1.0 - angleLocal);
    let edgeFactor = smoothstep(0.04, 0.0, edgeDist);
    
    let transmission = absorption * (1.0 - fresnel) * purity;
    let specular = edgeFactor * fresnel * 0.8;
    color += vec3<f32>(specular);
    
    let internalScatter = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.95, 1.0), fractureDensity);
    color = color * internalScatter;

    // Truthful three-band audio (plasmaBuffer reactivity)
    let bass = plasmaBuffer[1].x;
    let mids = plasmaBuffer[2].x;
    let treble = plasmaBuffer[3].x;

    let causticPulse = 1.0 + bass * 0.6 + sin(time * 6.0 + facetID) * treble * 0.4;
    let internalTint = vec3<f32>(1.0 + mids * 0.15, 1.0 - mids * 0.08, 1.0 - mids * 0.12);
    let sparkle = pow(hash11(facetID + time * 12.0), 8.0) * treble * 1.5;
    
    color = color * internalTint * causticPulse;
    color += vec3<f32>(0.8, 0.9, 1.0) * sparkle * edgeFactor;

    // Semantic Alpha
    let opticalDepth = pathLength * crystalThickness;
    let abs_coeff = vec3<f32>(0.18, 0.12, 0.25) * (1.0 + fractureDensity * 3.0);
    let abs_val = exp(-abs_coeff * opticalDepth);
    let density = edgeFactor * (1.0 + iorMix) * (1.0 + fractureDensity);
    let volumetricAlpha = 1.0 - exp(-density * opticalDepth * 1.5);
    let transmittanceAlpha = transmission * dot(abs_val, vec3<f32>(0.333)) * purity;
    let fresnelBoost = fresnel * edgeFactor * 0.4;
    
    var alpha = mix(transmittanceAlpha, volumetricAlpha, 0.45) + fresnelBoost;
    alpha = clamp(alpha, 0.0, 1.0);
    
    // ACES Tone Map
    color = acesToneMap(color);

    let outColor = vec4<f32>(color, alpha);
    
    // Write final display RGBA ONLY to dataTextureA (and writeTexture)
    textureStore(writeTexture, vec2<i32>(global_id.xy), outColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), outColor);

    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
