struct Uniforms {
    config: vec4<f32>,
    zoom_config: vec4<f32>,
    zoom_params: vec4<f32>,
    ripples: array<vec4<f32>, 50>,
}

@group(0) @binding(0) 
var u_sampler: sampler;
@group(0) @binding(1) 
var readTexture: texture_2d<f32>;
@group(0) @binding(2) 
var writeTexture: texture_storage_2d<rgba32float,write>;
@group(0) @binding(3) 
var<uniform> u: Uniforms;
@group(0) @binding(4) 
var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) 
var non_filtering_sampler: sampler;
@group(0) @binding(6) 
var writeDepthTexture: texture_storage_2d<r32float,write>;
@group(0) @binding(7) 
var dataTextureA: texture_storage_2d<rgba32float,write>;
@group(0) @binding(8) 
var dataTextureB: texture_storage_2d<rgba32float,write>;
@group(0) @binding(9) 
var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) 
var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) 
var comparison_sampler: sampler_comparison;
@group(0) @binding(12) 
var<storage> plasmaBuffer: array<vec4<f32>>;

fn ping_pong(a: f32) -> f32 {
    return (1.0 - abs(((fract((a * 0.5)) * 2.0) - 1.0)));
}

fn ping_pong_v2_(v: vec2<f32>) -> vec2<f32> {
    let _e2 = ping_pong(v.x);
    let _e4 = ping_pong(v.y);
    return vec2<f32>(_e2, _e4);
}

fn hash21_(p: vec2<f32>) -> f32 {
    var p3_: vec3<f32>;

    p3_ = fract((vec3<f32>(p.x, p.y, p.x) * 0.1031));
    let _e9 = p3_;
    let _e10 = p3_;
    let _e11 = p3_;
    p3_ = (_e9 + vec3(dot(_e10, (_e11 + vec3(33.33)))));
    let _e19 = p3_.x;
    let _e21 = p3_.y;
    let _e24 = p3_.z;
    return fract(((_e19 + _e21) * _e24));
}

fn noise(p_1: vec2<f32>) -> f32 {
    var i_1: vec2<f32>;

    i_1 = floor(p_1);
    let f = fract(p_1);
    let u2_ = ((f * f) * (vec2(3.0) - (2.0 * f)));
    let _e11 = i_1;
    let _e16 = hash21_((_e11 + vec2<f32>(0.0, 0.0)));
    let _e17 = i_1;
    let _e22 = hash21_((_e17 + vec2<f32>(1.0, 0.0)));
    let _e25 = i_1;
    let _e30 = hash21_((_e25 + vec2<f32>(0.0, 1.0)));
    let _e31 = i_1;
    let _e36 = hash21_((_e31 + vec2<f32>(1.0, 1.0)));
    return mix(mix(_e16, _e22, u2_.x), mix(_e30, _e36, u2_.x), u2_.y);
}

fn hsv2rgb(h: f32, s: f32, v_1: f32) -> vec3<f32> {
    var rgb: vec3<f32> = vec3(0.0);

    let c = (v_1 * s);
    let h6_ = (h * 6.0);
    let x = (c * (1.0 - abs(((fract(h6_) * 2.0) - 1.0))));
    if (h6_ < 1.0) {
        rgb = vec3<f32>(c, x, 0.0);
    } else {
        if (h6_ < 2.0) {
            rgb = vec3<f32>(x, c, 0.0);
        } else {
            if (h6_ < 3.0) {
                rgb = vec3<f32>(0.0, c, x);
            } else {
                if (h6_ < 4.0) {
                    rgb = vec3<f32>(0.0, x, c);
                } else {
                    if (h6_ < 5.0) {
                        rgb = vec3<f32>(x, 0.0, c);
                    } else {
                        rgb = vec3<f32>(c, 0.0, x);
                    }
                }
            }
        }
    }
    let _e40 = rgb;
    return (_e40 + vec3((v_1 - c)));
}

fn reconstruct_normal(uv_1: vec2<f32>, depth: f32) -> vec3<f32> {
    var resolution_1: vec2<f32>;

    let _e5 = u.config.z;
    let _e9 = u.config.w;
    resolution_1 = vec2<f32>(_e5, _e9);
    let _e14 = resolution_1.x;
    let _e18 = resolution_1.y;
    let offset = vec2<f32>((1.0 / _e14), (1.0 / _e18));
    let _e28 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 + vec2<f32>(offset.x, 0.0)), 0.0);
    let _e37 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 - vec2<f32>(offset.x, 0.0)), 0.0);
    let dx = (_e28.x - _e37.x);
    let _e47 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 + vec2<f32>(0.0, offset.y)), 0.0);
    let _e56 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (uv_1 - vec2<f32>(0.0, offset.y)), 0.0);
    let dy = (_e47.x - _e56.x);
    let n = vec3<f32>(-(dx), -(dy), 1.0);
    return normalize(n);
}

fn schlickFresnel(cosTheta: f32, F0_: f32) -> f32 {
    return (F0_ + ((1.0 - F0_) * pow((1.0 - cosTheta), 5.0)));
}

fn calculateVolumetricAlpha(layerDepth: f32, fogDensity: f32, viewDotNormal: f32, accumulatedWeight: f32) -> f32 {
    let _e7 = schlickFresnel(max(0.0, viewDotNormal), 0.03);
    let fogAmount = exp(((-(layerDepth) * fogDensity) * 3.0));
    let depthAlpha = mix(0.95, 0.4, fogAmount);
    let weightAlpha = mix(0.5, 0.9, smoothstep(0.0, 1.0, accumulatedWeight));
    let alpha = ((depthAlpha * weightAlpha) * (1.0 - (_e7 * 0.2)));
    return clamp(alpha, 0.0, 1.0);
}

@compute @workgroup_size(16, 16, 1) 
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    var resolution: vec2<f32>;
    var uv: vec2<f32>;
    var mousePos: vec2<f32>;
    var clickIntensity: f32;
    var accumulatedColor: vec3<f32> = vec3(0.0);
    var accumulatedDepth: f32 = 0.0;
    var totalWeight: f32 = 0.0;
    var i: i32 = 0;
    var chroma: f32;

    let _e4 = u.config.z;
    let _e8 = u.config.w;
    resolution = vec2<f32>(_e4, _e8);
    let _e13 = resolution;
    uv = (vec2<f32>(gid.xy) / _e13);
    let time = u.config.x;
    let zoom_time = u.zoom_config.x;
    let _e26 = u.zoom_config;
    let zoom_center = _e26.yz;
    let _e31 = u.zoom_config.y;
    let _e33 = resolution.x;
    let _e38 = u.zoom_config.z;
    let _e40 = resolution.y;
    mousePos = vec2<f32>((_e31 / _e33), (_e38 / _e40));
    if (arrayLength((&extraBuffer)) > 10u) {
        let _e52 = extraBuffer[10];
        clickIntensity = _e52;
    } else {
        clickIntensity = 0.0;
    }
    loop {
        let _e64 = i;
        if (_e64 < 5) {
        } else {
            break;
        }
        {
            let _e66 = i;
            let layerDepth_1 = (f32(_e66) / f32((5 - 1)));
            let _e75 = u.zoom_params.x;
            let _e79 = u.zoom_params.y;
            let layerSpeed = mix(_e75, _e79, layerDepth_1);
            let layerZoom = (1.0 + (fract((zoom_time * layerSpeed)) * 4.0));
            let _e87 = uv;
            let toCenter = (_e87 - zoom_center);
            let angle = atan2(toCenter.y, toCenter.x);
            let dist = length(toCenter);
            let _e93 = clickIntensity;
            let vortexStrength = ((_e93 * 0.3) / (dist + 0.1));
            let spinAngle = ((vortexStrength * layerDepth_1) * (1.0 - layerDepth_1));
            let rotatedUV = (vec2<f32>(((cos(spinAngle) * toCenter.x) - (sin(spinAngle) * toCenter.y)), ((sin(spinAngle) * toCenter.x) + (cos(spinAngle) * toCenter.y))) + zoom_center);
            let _e126 = noise(((rotatedUV * 6.0) + vec2<f32>((time * 0.15), 0.0)));
            let _e132 = noise(((rotatedUV * 6.0) + vec2<f32>(0.0, (time * 0.15))));
            let flowUV = (rotatedUV + ((vec2<f32>(_e126, _e132) * 0.015) * layerDepth_1));
            let transformed = (((flowUV - zoom_center) / vec2(layerZoom)) + zoom_center);
            let _e142 = ping_pong_v2_(transformed);
            let _e146 = textureSampleLevel(readTexture, u_sampler, _e142, 0.0);
            let sampleColor = _e146.xyz;
            let _e151 = textureSampleLevel(readDepthTexture, non_filtering_sampler, _e142, 0.0);
            let sampleDepth = _e151.x;
            let density = exp((-(layerDepth_1) * 1.5));
            let weight = (density * (1.0 + (sampleDepth * 0.5)));
            let _e162 = accumulatedColor;
            accumulatedColor = (_e162 + (sampleColor * weight));
            let _e165 = accumulatedDepth;
            accumulatedDepth = (_e165 + (sampleDepth * weight));
            let _e168 = totalWeight;
            totalWeight = (_e168 + weight);
        }
        continuing {
            let _e170 = i;
            i = (_e170 + 1);
        }
    }
    let _e173 = accumulatedColor;
    let _e174 = totalWeight;
    let baseColor = (_e173 / vec3(max(_e174, 0.0001)));
    let _e179 = accumulatedDepth;
    let _e180 = totalWeight;
    let baseDepth = (_e179 / max(_e180, 0.0001));
    if (arrayLength((&extraBuffer)) > 0u) {
        let _e192 = extraBuffer[0];
        chroma = _e192;
    } else {
        chroma = 0.02;
    }
    let _e196 = uv;
    let _e197 = chroma;
    let _e203 = textureSampleLevel(readTexture, u_sampler, (_e196 + vec2<f32>((_e197 * baseDepth), 0.0)), 0.0);
    let r = _e203.x;
    let _e207 = uv;
    let _e209 = textureSampleLevel(readTexture, u_sampler, _e207, 0.0);
    let g = _e209.y;
    let _e213 = uv;
    let _e214 = chroma;
    let _e220 = textureSampleLevel(readTexture, u_sampler, (_e213 - vec2<f32>((_e214 * baseDepth), 0.0)), 0.0);
    let b = _e220.z;
    let chromaticColor = vec3<f32>(r, g, b);
    let _e225 = resolution.x;
    let _e229 = resolution.y;
    let ps = vec2<f32>((1.0 / _e225), (1.0 / _e229));
    let _e234 = uv;
    let _e240 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (_e234 + vec2<f32>(ps.x, 0.0)), 0.0);
    let depthX = _e240.x;
    let _e244 = uv;
    let _e250 = textureSampleLevel(readDepthTexture, non_filtering_sampler, (_e244 + vec2<f32>(0.0, ps.y)), 0.0);
    let depthY = _e250.x;
    let depthGrad = length(vec2<f32>((depthX - baseDepth), (depthY - baseDepth)));
    let edgeGlow = ((exp((-(depthGrad) * 30.0)) * baseDepth) * 2.0);
    let finalColor = (chromaticColor + vec3<f32>(edgeGlow, (edgeGlow * 0.8), (edgeGlow * 0.6)));
    let fogDensity_1 = u.zoom_params.w;
    let _e273 = uv;
    let _e274 = reconstruct_normal(_e273, baseDepth);
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let viewDotNormal_1 = dot(viewDir, _e274);
    let _e281 = totalWeight;
    let normalizedWeight = (_e281 / f32(5));
    let _e284 = calculateVolumetricAlpha(0.5, fogDensity_1, viewDotNormal_1, normalizedWeight);
    let fog = exp(((-(baseDepth) * fogDensity_1) * 3.0));
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let outColor = mix(finalColor, fogColor, (1.0 - fog));
    
    // Advanced Alpha: Edge-Preserve
    let alpha = calculateAdvancedAlpha(outColor, uv, baseDepth, depthGrad, _e284);
    
    textureStore(writeTexture, vec2<u32>(gid.xy), vec4<f32>(outColor, alpha));
    textureStore(writeDepthTexture, vec2<u32>(gid.xy), vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
    return;
}

// ═══ ADVANCED ALPHA FUNCTION ═══
fn calculateAdvancedAlpha(color: vec3<f32>, uv: vec2<f32>, depth: f32, depthGrad: f32, baseAlpha: f32) -> f32 {
    // Tunable parameters from zoom_params
    let edgeThreshold = u.zoom_params.x;   // Edge Threshold
    let pulseSpeed = u.zoom_params.y;      // Pulse Speed
    let glowIntensity = u.zoom_params.z;   // Glow Intensity
    let colorShift = u.zoom_params.w;      // Color Shift
    
    // Edge magnitude from depth gradient
    let edgeMask = smoothstep(edgeThreshold * 0.5, edgeThreshold, depthGrad);
    
    // Glow-driven alpha: brighter glow = more opaque
    let luma = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let glowAlpha = smoothstep(0.05, 0.3, luma) * glowIntensity;
    
    // Combine: edges are opaque, glow areas are opaque, smooth interiors transparent
    let combinedAlpha = max(edgeMask * 0.9, glowAlpha) + baseAlpha * 0.2;
    
    // Depth influence: foreground edges more opaque
    let depthAlpha = mix(0.25, 1.0, depth);
    let alpha = mix(combinedAlpha, depthAlpha, 0.3);
    
    return clamp(alpha, 0.0, 1.0);
}
