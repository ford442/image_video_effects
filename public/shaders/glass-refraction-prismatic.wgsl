// ═══════════════════════════════════════════════════════════════════
//  glass-refraction-prismatic
//  Category: advanced-hybrid
//  Features: raymarched, spectral-dispersion, physical-refraction, mouse-driven
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

const PI: f32 = 3.14159265359;

fn sdSphere(p: vec3<f32>, r: f32) -> f32 {
    return length(p) - r;
}

fn smoothUnion(d1: f32, d2: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

fn map(p: vec3<f32>, time: f32, bass: f32, mid: f32, pointerSpring: f32) -> f32 {
    let t = time * 0.5;
    let baseScale = 1.0 + mid * 0.2 + pointerSpring * 0.3;
    let blob1 = sdSphere(p - vec3<f32>(sin(t) * 0.3, 0.0, 0.0), 0.25 * baseScale);
    let blob2 = sdSphere(p - vec3<f32>(cos(t * 0.7) * 0.2, sin(t * 0.8) * 0.2, 0.1), 0.2 * baseScale);
    let blob3 = sdSphere(p - vec3<f32>(0.0, cos(t * 1.1) * 0.15, sin(t * 0.9) * 0.1), 0.18 * baseScale);
    let blobs = smoothUnion(smoothUnion(blob1, blob2, 0.15), blob3, 0.1);
    
    // Continuous geometry
    let torusD = vec2<f32>(length(p.xz) - 0.3 - bass * 0.1, p.y + sin(p.x * 3.0 + time) * 0.1);
    let torus = length(torusD) - 0.05;
    
    return smoothUnion(blobs, torus, 0.2);
}

fn calcNormal(p: vec3<f32>, time: f32, bass: f32, mid: f32, pointerSpring: f32) -> vec3<f32> {
    let eps = 0.001;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(eps, 0.0, 0.0), time, bass, mid, pointerSpring) - map(p - vec3<f32>(eps, 0.0, 0.0), time, bass, mid, pointerSpring),
        map(p + vec3<f32>(0.0, eps, 0.0), time, bass, mid, pointerSpring) - map(p - vec3<f32>(0.0, eps, 0.0), time, bass, mid, pointerSpring),
        map(p + vec3<f32>(0.0, 0.0, eps), time, bass, mid, pointerSpring) - map(p - vec3<f32>(0.0, 0.0, eps), time, bass, mid, pointerSpring)
    ));
}

fn fresnel(cosTheta: f32, eta: f32) -> f32 {
    let c = abs(cosTheta);
    let g = sqrt(eta * eta - 1.0 + c * c);
    let gmc = g - c;
    let gpc = g + c;
    let a = (gmc / gpc) * (gmc / gpc);
    let b = (c * gpc - 1.0) / (c * gmc + 1.0);
    return 0.5 * a * (1.0 + b * b);
}

fn refractRay(I: vec3<f32>, N: vec3<f32>, eta: f32) -> vec3<f32> {
    let NdotI = dot(N, I);
    let k = 1.0 - eta * eta * (1.0 - NdotI * NdotI);
    if (k < 0.0) {
        return vec3<f32>(0.0);
    }
    return eta * I - (eta * NdotI + sqrt(k)) * N;
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
    let coord = vec2<i32>(global_id.xy);
    if (f32(coord.x) >= resolution.x || f32(coord.y) >= resolution.y) {
        return;
    }
    
    let time = u.config.x;
    
    // Truthful three-band audio
    let bass = plasmaBuffer[0].x;
    let mid = plasmaBuffer[1].x;
    let treble = plasmaBuffer[2].x;
    
    // State management: Bounded spring + click ripples (Single Writer)
    if (global_id.x == 0u && global_id.y == 0u) {
        let isMouseDown = u.zoom_config.w > 0.5;
        var target = 0.0;
        if (isMouseDown) { target = 1.0; }
        
        var pos = extraBuffer[133];
        var vel = extraBuffer[134];
        
        let spring = 0.15;
        let damp = 0.82;
        
        vel += (target - pos) * spring;
        vel *= damp;
        pos += vel;
        
        pos = clamp(pos, 0.0, 1.0);
        vel = clamp(vel, -1.0, 1.0);
        
        extraBuffer[133] = pos;
        extraBuffer[134] = vel;
        
        // Capped click fronts
        if (isMouseDown && extraBuffer[135] == 0.0) {
            extraBuffer[136] = time; // Click time
            extraBuffer[135] = 1.0;  // was down
        } else if (!isMouseDown) {
            extraBuffer[135] = 0.0;
        }
        
        extraBuffer[137] = bass;
        extraBuffer[138] = treble;
    }
    workgroupBarrier();
    
    let pointerSpring = extraBuffer[133];
    let clickTime = extraBuffer[136];
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    
    // Params
    let transparency = 0.3 + u.zoom_params.x * 0.5;
    let cauchyB = mix(0.01, 0.08, u.zoom_params.y);
    let thicknessScale = 0.5 + u.zoom_params.z;
    let roughness = u.zoom_params.w * 0.1;
    
    let mouseUV = u.zoom_config.yz;
    let mousePos = (mouseUV - 0.5) * 2.0;
    
    let distToMouse = length(uv - mouseUV);
    let timeSinceClick = time - clickTime;
    let cappedClickFront = smoothstep(0.0, 0.1, timeSinceClick) * smoothstep(1.5, 0.5, timeSinceClick);
    let clickRipple = sin(distToMouse * 40.0 - timeSinceClick * 12.0) * exp(-distToMouse * 4.0) * cappedClickFront;
    
    let ro = vec3<f32>(mousePos.x * 0.5, mousePos.y * 0.5, -1.5);
    // Apply ripples to ray direction for refraction effect of the ripple itself
    let rd = normalize(vec3<f32>(uv.x - 0.5 + clickRipple * 0.02, uv.y - 0.5 + clickRipple * 0.02, 1.0));

    var t = 0.0;
    var hit = false;
    var enterT = 0.0;
    var normal = vec3<f32>(0.0);

    for (var i: i32 = 0; i < 64; i = i + 1) {
        let p = ro + rd * t;
        let d = map(p, time, bass, mid, pointerSpring);
        if (!hit && d < 0.001) {
            hit = true;
            enterT = t;
            normal = calcNormal(p, time, bass, mid, pointerSpring);
            break;
        }
        t += max(d * 0.5, 0.001);
        if (t > 3.0) { break; }
    }

    var bgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let prevDataC = textureLoad(dataTextureC, coord, 0).rgb;
    bgColor += prevDataC * 0.05; // tiny integration
    
    var finalRGB = bgColor;
    var finalAlpha = 0.0;
    var emissive = vec3<f32>(0.0);

    if (hit) {
        let WAVELENGTHS = array<f32, 4>(450.0, 520.0, 600.0, 680.0);
        var spectralColor = vec3<f32>(0.0);

        let viewDotNormal = dot(-rd, normal);
        let baseEta = 1.0 / (1.5 + bass * 0.1);

        for (var w: i32 = 0; w < 4; w = w + 1) {
            let ior = cauchyIOR(WAVELENGTHS[w], 1.5, cauchyB);
            let eta = 1.0 / ior;
            let refracted = refractRay(rd, normal, eta);
            let refractUV = refracted.xy * 0.3 + uv;
            
            let sampleColor = textureSampleLevel(readTexture, u_sampler, fract(refractUV), 0.0).rgb;
            let absorption = exp(-thicknessScale * (4.0 - f32(w)) * 0.15);
            let bandIntensity = dot(sampleColor, wavelengthToRGB(WAVELENGTHS[w])) * absorption;
            spectralColor += wavelengthToRGB(WAVELENGTHS[w]) * bandIntensity;
        }

        let fresnelFactor = fresnel(viewDotNormal, baseEta);
        let glassTint = vec3<f32>(0.95, 0.98, 1.0);
        let absorption = exp(-vec3<f32>(0.1, 0.05, 0.15) * thicknessScale);
        
        finalRGB = mix(spectralColor * absorption * glassTint, bgColor, fresnelFactor * 0.3);

        let lightDir = normalize(vec3<f32>(0.5, 1.0, -0.5));
        let halfDir = normalize(lightDir - rd);
        let specAngle = max(dot(normal, halfDir), 0.0);
        let specular = pow(specAngle, 128.0) * (1.0 - roughness);
        
        finalRGB += vec3<f32>(1.0) * specular + (vec3<f32>(0.2, 0.5, 1.0) * treble * 0.5 * fresnelFactor);

        finalAlpha = (1.0 - transparency) + fresnelFactor * transparency;
        finalAlpha = clamp(finalAlpha * 0.9 + treble * 0.1, 0.0, 0.98);
        
        // Semantic alpha for hit
        finalAlpha = mix(0.1, 0.95, finalAlpha);
    } else {
        // Semantic alpha for background
        finalAlpha = max(0.0, clickRipple * 0.5);
    }

    var edgeGlow = 0.0;
    if (hit) {
        edgeGlow = smoothstep(0.05, 0.0, map(ro + rd * enterT, time, bass, mid, pointerSpring)) * mid;
    }
    finalRGB += vec3<f32>(0.4, 0.8, 1.0) * edgeGlow * (1.0 + pointerSpring);
    finalAlpha = max(finalAlpha, edgeGlow);

    // Vignette
    let vignette = 1.0 - length(uv - 0.5) * 0.3;
    finalRGB *= vignette;
    
    // ACES Tone Map
    finalRGB = acesToneMap(finalRGB);

    let outputColor = vec4<f32>(finalRGB, finalAlpha);
    
    // Write final display RGBA ONLY to dataTextureA (and writeTexture, of course)
    textureStore(writeTexture, coord, outputColor);
    textureStore(writeDepthTexture, coord, vec4<f32>(finalAlpha, 0.0, 0.0, 1.0));
    textureStore(dataTextureA, coord, outputColor);
}
