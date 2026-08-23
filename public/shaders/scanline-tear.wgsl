// ═══════════════════════════════════════════════════════════════
//  Scanline Tear - Analog Video Interlacing Simulation
//  Category: retro-glitch
//  Features: interlaced fields, HSync/VSync errors, color burst, audio-reactive
//  Upgraded: 2026-08-21 (Batch 42 - Audio Sync Loss)
// ═══════════════════════════════════════════════════════════════
struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn hash(n: vec2<f32>) -> f32 {
    return fract(sin(dot(n, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

fn colorBurstShift(color: vec3<f32>, phaseError: f32) -> vec3<f32> {
    let Y = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
    let I = 0.596 * color.r - 0.275 * color.g - 0.321 * color.b;
    let Q = 0.212 * color.r - 0.523 * color.g + 0.311 * color.b;
    
    let angle = phaseError * 3.14159;
    let I_rot = I * cos(angle) - Q * sin(angle);
    let Q_rot = I * sin(angle) + Q * cos(angle);
    
    var result: vec3<f32>;
    result.r = Y + 0.956 * I_rot + 0.621 * Q_rot;
    result.g = Y - 0.272 * I_rot - 0.647 * Q_rot;
    result.b = Y - 1.106 * I_rot + 1.703 * Q_rot;
    
    return clamp(result, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn trackingError(uv: vec2<f32>, intensity: f32, time: f32, audio_punch: f32) -> vec2<f32> {
    var result = uv;
    let jumpNoise = hash(vec2<f32>(floor(time * 5.0), 0.0));
    if (jumpNoise > 0.97 - audio_punch * 0.1) {
        let jumpAmount = (hash(vec2<f32>(floor(time * 10.0), 1.0)) - 0.5) * 0.1 * intensity * (1.0 + audio_punch * 2.0);
        result.y = fract(result.y + jumpAmount);
    }
    let bandY = hash(vec2<f32>(0.0, floor(uv.y * 100.0))) * 0.02 * intensity;
    result.x = fract(result.x + bandY * sin(time * 50.0) * (1.0 + audio_punch));
    return result;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(coord) / vec2<f32>(dims);
    
    let time = u.config.x;
    let resolution = vec2<f32>(dims);
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let interlaceStrength = clamp(u.zoom_params.x + mids * 0.1, 0.0, 1.0);
    let hsyncError = clamp(u.zoom_params.y + bass * 0.4, 0.0, 1.0);
    let vsyncError = clamp(u.zoom_params.z + bass * 0.2, 0.0, 1.0);
    let colorBurstError = clamp(u.zoom_params.w + treble * 0.3, 0.0, 1.0);
    
    let fieldPhase = u32(floor(time * 120.0)) % 2u;
    let scanline = coord.y;
    let isEvenLine = (scanline % 2) == 0;
    let inCurrentField = (fieldPhase == 0u && isEvenLine) || (fieldPhase == 1u && !isEvenLine);
    
    var sampleUV = uv;
    
    if (hsyncError > 0.0) {
        let hsyncRollSpeed = time * 2.0;
        let hsyncRollPos = fract(hsyncRollSpeed);
        let rollDist = abs(uv.y - hsyncRollPos);
        let inRollZone = smoothstep(0.15, 0.0, rollDist);
        let hShift = sin(time * 30.0 + uv.y * 50.0) * 0.02 * hsyncError * inRollZone * (1.0 + bass * 3.0);
        let hInstability = noise(time * 10.0 + uv.y * 100.0) * 0.01 * hsyncError;
        sampleUV.x = fract(sampleUV.x + hShift + hInstability);
    }
    
    if (vsyncError > 0.0) {
        let vsyncRollSpeed = time * 0.5 * (0.5 + vsyncError * 2.0);
        let vRoll = fract(vsyncRollSpeed);
        sampleUV.y = fract(sampleUV.y - vRoll + 1.0);
    }
    
    let trackingIntensity = interlaceStrength * 0.5;
    sampleUV = trackingError(sampleUV, trackingIntensity, time, bass);
    
    var fieldSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    var prevFrameSample = textureSampleLevel(dataTextureC, filteringSampler, sampleUV, 0.0);
    
    let motionDelta = length(fieldSample.rgb - prevFrameSample.rgb);
    let isMoving = motionDelta > 0.05;
    
    var combAmount = 0.0;
    if (interlaceStrength > 0.0 && isMoving) {
        let lineOffset = 1.0 / resolution.y;
        let neighborUV = sampleUV + vec2<f32>(0.0, lineOffset * select(-1.0, 1.0, isEvenLine));
        let neighborSample = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0);
        combAmount = motionDelta * interlaceStrength * 0.5;
        fieldSample = mix(fieldSample, neighborSample, combAmount * 0.3);
    }
    
    let persistence = 0.3 * interlaceStrength;
    var outputColor = mix(fieldSample, prevFrameSample, persistence * (1.0 - f32(inCurrentField)));
    
    if (colorBurstError > 0.0) {
        let phaseNoise = hash(vec2<f32>(floor(uv.y * 50.0), floor(time * 60.0)));
        let phaseError = (phaseNoise - 0.5) * 2.0 * colorBurstError;
        let lineHueShift = sin(uv.y * 100.0 + time * 10.0) * 0.1 * colorBurstError;
        
        outputColor = vec4<f32>(
            colorBurstShift(outputColor.rgb, phaseError + lineHueShift),
            outputColor.a
        );
        
        let chromaNoise = hash(vec2<f32>(uv.x * 200.0 + time, uv.y * 200.0)) * 0.1 * colorBurstError;
        outputColor = vec4<f32>(outputColor.rgb + vec3<f32>(chromaNoise * 0.5, chromaNoise, chromaNoise * 0.3), outputColor.a);
    }
    
    let fieldDimming = 0.7 + 0.3 * f32(inCurrentField);
    outputColor = vec4<f32>(outputColor.rgb * mix(1.0, fieldDimming, interlaceStrength * 0.5), outputColor.a);
    
    let scanlineIntensity = 0.15 * interlaceStrength;
    let scanlinePattern = sin(uv.y * resolution.y * 3.14159) * 0.5 + 0.5;
    outputColor = vec4<f32>(outputColor.rgb - scanlineIntensity * scanlinePattern, outputColor.a);
    
    if (vsyncError > 0.0) {
        let rollPos = fract(time * 0.5 * (0.5 + vsyncError * 2.0));
        let rollDist = abs(uv.y - rollPos);
        let inRollBar = rollDist < 0.02;
        outputColor = vec4<f32>(outputColor.rgb - f32(inRollBar) * 0.5 * vsyncError, outputColor.a);
    }
    
    if (hsyncError > 0.0) {
        let edgeTear = hash(vec2<f32>(time * 100.0, uv.y * 10.0)) * hsyncError * 0.1;
        if (uv.x < 0.05 || uv.x > 0.95) {
            outputColor = vec4<f32>(mix(outputColor.rgb, vec3<f32>(0.0), edgeTear), outputColor.a);
        }
    }
    
    let signalNoise = hash(uv * time) * 0.05 * interlaceStrength;
    outputColor = vec4<f32>(outputColor.rgb + vec3<f32>(signalNoise), outputColor.a);
    
    let rfLines = select(0.0, 0.1, sin(uv.y * 200.0 + time * 20.0) > 0.99);
    outputColor = vec4<f32>(outputColor.rgb + vec3<f32>(rfLines * interlaceStrength * 0.5), outputColor.a);
    
    outputColor = clamp(outputColor, vec4<f32>(0.0), vec4<f32>(1.0));
    
    textureStore(writeTexture, coord, outputColor);
    textureStore(dataTextureA, coord, outputColor);
    
    let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
