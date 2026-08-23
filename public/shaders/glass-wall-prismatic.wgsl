// ═══════════════════════════════════════════════════════════════════
//  Glass Wall Prismatic
//  Category: advanced-hybrid
//  Features: mouse-driven, spectral-rendering, physical-dispersion, refraction
//  Complexity: Very High
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn cauchyIOR(wavelengthNm: f32, A: f32, B: f32) -> f32 {
    let lambdaUm = wavelengthNm * 0.001;
    return A + B / (lambdaUm * lambdaUm);
}

fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 440.0) / (680.0 - 440.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.8, t) + smoothstep(0.0, 0.15, t) * 0.3;
    let g = 1.0 - abs(t - 0.4) * 3.0;
    let b = 1.0 - smoothstep(0.0, 0.4, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn aces_tone_map(color: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    let isMaster = (gid.x == 0u && gid.y == 0u);
    if (isMaster) {
        let is_held = u.zoom_config.w > 0.0;
        let pointer_x = u.zoom_config.y;
        let pointer_y = u.zoom_config.z;
        var curr_x = extraBuffer[133];
        var curr_y = extraBuffer[134];
        var vel_x = extraBuffer[135];
        var vel_y = extraBuffer[136];

        let target_x = select(curr_x, pointer_x, is_held);
        let target_y = select(curr_y, pointer_y, is_held);
        let dt = 0.016;
        let spring = 200.0;
        let damp = 15.0;
        
        vel_x += (target_x - curr_x) * spring * dt - vel_x * damp * dt;
        vel_y += (target_y - curr_y) * spring * dt - vel_y * damp * dt;
        curr_x += vel_x * dt;
        curr_y += vel_y * dt;
        
        curr_x = clamp(curr_x, 0.0, 1.0);
        curr_y = clamp(curr_y, 0.0, 1.0);
        
        extraBuffer[133] = curr_x;
        extraBuffer[134] = curr_y;
        extraBuffer[135] = clamp(vel_x, -50.0, 50.0);
        extraBuffer[136] = clamp(vel_y, -50.0, 50.0);
    }
    workgroupBarrier();

    let uv = vec2<f32>(gid.xy) / dims;
    let aspect = dims.x / dims.y;
    let time = u.config.x;
    let smooth_mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);

    let bass = plasmaBuffer[1].x;
    let mid = plasmaBuffer[1].y;
    let treble = plasmaBuffer[1].z;

    // Parameters
    let gridSize = mix(5.0, 30.0, u.zoom_params.x);
    let glassCurvature = mix(0.1, 1.2, u.zoom_params.y);
    let cauchyB = mix(0.01, 0.08, u.zoom_params.z);
    let glassThickness = mix(0.3, 1.5, u.zoom_params.w);

    var ripple_offset = vec2<f32>(0.0);
    var ripple_z = 0.0;
    for(var i = 0u; i < 50u; i++) {
        let r = u.ripples[i];
        let r_xy = r.xy;
        let r_age = r.z;
        let r_force = r.w;
        if(r_force > 0.0 && r_age > 0.0) {
            let max_age = 2.0;
            if(r_age < max_age) {
                let r_uv = uv * vec2<f32>(aspect, 1.0);
                let r_center = r_xy * vec2<f32>(aspect, 1.0);
                let to_rip = r_uv - r_center;
                let dist = length(to_rip);
                let env = smoothstep(max_age, 0.0, r_age);
                let phase = dist * 40.0 - r_age * 15.0;
                let wave = sin(phase) * exp(-dist * 5.0) * env;
                let cap_wave = clamp(wave, -1.0, 1.0);
                ripple_offset += normalize(to_rip + 0.001) * cap_wave * 0.05 * r_force;
                ripple_z += cap_wave * 0.1 * r_force;
            }
        }
    }

    let scale = vec2<f32>(gridSize * aspect, gridSize);
    let scaled_uv = uv * scale + ripple_offset * scale * 0.2;
    let cellID = floor(scaled_uv);
    let cellUV = fract(scaled_uv);
    let cellCenter = (cellID + 0.5) / scale;

    let aspectVec = vec2<f32>(aspect, 1.0);
    let vecToMouse = (smooth_mouse - cellCenter) * aspectVec;
    let dist = length(vecToMouse);
    let influence = smoothstep(1.0, 0.0, dist);

    var tilt = vec2<f32>(0.0);
    if (dist > 0.001) {
        tilt = normalize(vecToMouse) * influence * (0.5 + mid * 0.5);
    }

    let bevelX = smoothstep(0.0, 0.1, cellUV.x) * (1.0 - smoothstep(0.9, 1.0, cellUV.x));
    let bevelY = smoothstep(0.0, 0.1, cellUV.y) * (1.0 - smoothstep(0.9, 1.0, cellUV.y));
    let bevel = bevelX * bevelY;

    let nx = -(smoothstep(0.0, 0.1, cellUV.x) - smoothstep(0.9, 1.0, cellUV.x)) * bevelY;
    let ny = -(smoothstep(0.0, 0.1, cellUV.y) - smoothstep(0.9, 1.0, cellUV.y)) * bevelX;
    var normal = normalize(vec3<f32>(nx, ny, 2.0));
    normal = normalize(normal + vec3<f32>(tilt * 2.0, 0.0) + vec3<f32>(ripple_offset * 10.0, 0.0));

    let tileCenter = cellCenter + tilt * 0.3 + ripple_offset * 0.5;
    let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
    var finalColor = vec3<f32>(0.0);
    var totalIntensity = 0.0;

    for (var i: i32 = 0; i < 4; i++) {
        let ior = cauchyIOR(WAVELENGTHS[i], 1.5, cauchyB + bass * 0.05);
        let toCenter = uv - tileCenter;
        let d = length(toCenter);
        let lensStrength = glassCurvature * 0.4;
        let refractDir = refract(vec3<f32>(0.0, 0.0, -1.0), normal, 1.0 / ior);
        let refractOffset = refractDir.xy * lensStrength;
        
        let refractedUV = fract(uv + refractOffset);
        let sample = textureSampleLevel(readTexture, u_sampler, refractedUV, 0.0).rgb;
        let absorption = exp(-glassThickness * (4.0 - f32(i)) * 0.15);
        let bandIntensity = sample * absorption;
        
        let wCol = wavelengthToRGB(WAVELENGTHS[i]);
        finalColor += wCol * bandIntensity;
        totalIntensity += absorption;
    }
    
    finalColor *= 2.0 / max(totalIntensity, 0.001);

    let glassColor = mix(vec3<f32>(0.93, 0.96, 1.0), vec3<f32>(1.0, 0.9, 0.95), treble);
    let thickness = 0.05 + (1.0 - bevel) * 0.1 + length(tilt) * 0.05;
    let absorptionGlass = exp(-(vec3<f32>(1.0) - glassColor) * thickness * 2.0);
    let transmission = (absorptionGlass.r + absorptionGlass.g + absorptionGlass.b) / 3.0;

    finalColor = finalColor * glassColor;

    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);

    let lightDir = normalize(vec3<f32>(vecToMouse, 0.5));
    let spec = pow(max(dot(normal, lightDir), 0.0), 32.0) * influence;
    finalColor += spec * 0.8;

    let prevData = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0).rgb;
    finalColor = mix(finalColor, prevData, 0.1);

    let mortar = smoothstep(0.0, 0.05, cellUV.x) * smoothstep(1.0, 0.95, cellUV.x) *
                 smoothstep(0.0, 0.05, cellUV.y) * smoothstep(1.0, 0.95, cellUV.y);
    let mortarTransmission = transmission * 0.3;
    let blendedTransmission = mix(mortarTransmission, transmission, mortar);
    
    finalColor = aces_tone_map(finalColor);
    
    let alpha = saturate(blendedTransmission + fresnel * 0.5 + dot(finalColor, vec3<f32>(0.33)));
    let outColor = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, gid.xy, outColor);
    textureStore(dataTextureA, gid.xy, outColor);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
