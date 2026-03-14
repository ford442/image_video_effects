// ═══════════════════════════════════════════════════════════════
//  Scanline Tear - Analog Video Interlacing Simulation
//  Category: retro-glitch
//  Features: interlaced fields, HSync/VSync errors, color burst
// ═══════════════════════════════════════════════════════════════
//
//  SCIENTIFIC BASIS:
//  Analog video interlacing displays frames as two separate fields:
//  - Even field: lines 0, 2, 4... (captured at time t)
//  - Odd field: lines 1, 3, 5... (captured at time t+1/60s)
//  
//  Fast motion creates "combing" artifacts because each field
//  captures the scene at a different moment in time.
//
//  Sync pulses control display timing:
//  - HSync: triggers horizontal line scan (~15.7kHz for NTSC)
//  - VSync: triggers vertical frame retrace (~60Hz)
//  
//  Sync loss creates rolling bars and image displacement.
//
//  Color burst provides reference phase for chroma demodulation.
//  Burst errors cause hue shifts and chroma noise.

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
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
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// Hash function for noise generation
fn hash(n: vec2<f32>) -> f32 {
    return fract(sin(dot(n, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(n: f32) -> f32 {
    return fract(sin(n) * 43758.5453123);
}

// NTSC color burst simulation - phase shift chroma
fn colorBurstShift(color: vec3<f32>, phaseError: f32) -> vec3<f32> {
    // Convert to YIQ (NTSC color space)
    let Y = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
    let I = 0.596 * color.r - 0.275 * color.g - 0.321 * color.b;
    let Q = 0.212 * color.r - 0.523 * color.g + 0.311 * color.b;
    
    // Rotate chroma by phase error
    let angle = phaseError * 3.14159;
    let I_rot = I * cos(angle) - Q * sin(angle);
    let Q_rot = I * sin(angle) + Q * cos(angle);
    
    // Convert back to RGB
    var result: vec3<f32>;
    result.r = Y + 0.956 * I_rot + 0.621 * Q_rot;
    result.g = Y - 0.272 * I_rot - 0.647 * Q_rot;
    result.b = Y - 1.106 * I_rot + 1.703 * Q_rot;
    
    return clamp(result, vec3<f32>(0.0), vec3<f32>(1.0));
}

// VHS tracking error simulation
fn trackingError(uv: vec2<f32>, intensity: f32, time: f32) -> vec2<f32> {
    var result = uv;
    
    // Random tracking jumps
    let jumpNoise = hash(vec2<f32>(floor(time * 5.0), 0.0));
    if (jumpNoise > 0.97) {
        let jumpAmount = (hash(vec2<f32>(floor(time * 10.0), 1.0)) - 0.5) * 0.1 * intensity;
        result.y = fract(result.y + jumpAmount);
    }
    
    // Horizontal tracking noise bands
    let bandY = hash(vec2<f32>(0.0, floor(uv.y * 100.0))) * 0.02 * intensity;
    result.x = fract(result.x + bandY * sin(time * 50.0));
    
    return result;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(coord) / vec2<f32>(dims);
    
    let time = u.config.x;
    let resolution = vec2<f32>(dims);
    
    // Parameters
    let interlaceStrength = u.zoom_params.x;        // 0-1: Interlacing artifact intensity
    let hsyncError = u.zoom_params.y;               // 0-1: Horizontal sync instability
    let vsyncError = u.zoom_params.z;               // 0-1: Vertical sync roll
    let colorBurstError = u.zoom_params.w;          // 0-1: Chroma phase errors
    
    // ═══════════════════════════════════════════════════════════════
    // FIELD-BASED INTERLACING SIMULATION
    // ═══════════════════════════════════════════════════════════════
    
    // Determine current field (even/odd alternates each frame)
    // Field rate = 2x frame rate for interlaced video
    let frameTime = floor(time * 60.0) / 60.0;  // Quantize to frame boundaries
    let fieldPhase = floor(time * 120.0) % 2u;  // 0 = even field, 1 = odd field
    let scanline = coord.y;
    let isEvenLine = (scanline % 2) == 0;
    let isOddLine = !isEvenLine;
    
    // Field mask - current field lines are visible
    let inCurrentField = (fieldPhase == 0u && isEvenLine) || 
                          (fieldPhase == 1u && isOddLine);
    
    // ═══════════════════════════════════════════════════════════════
    // SYNC ERROR SIMULATION
    // ═══════════════════════════════════════════════════════════════
    
    var sampleUV = uv;
    
    // HSync error: rolling horizontal displacement
    // Simulates loss of horizontal hold control
    if (hsyncError > 0.0) {
        // Rolling bar effect
        let hsyncRollSpeed = time * 2.0;
        let hsyncRollPos = fract(hsyncRollSpeed);
        let rollDist = abs(uv.y - hsyncRollPos);
        let inRollZone = smoothstep(0.15, 0.0, rollDist);
        
        // Horizontal shift during roll
        let hShift = sin(time * 30.0 + uv.y * 50.0) * 0.02 * hsyncError * inRollZone;
        
        // Random HSync instability
        let hInstability = noise(time * 10.0 + uv.y * 100.0) * 0.01 * hsyncError;
        
        sampleUV.x = fract(sampleUV.x + hShift + hInstability);
    }
    
    // VSync error: vertical rolling
    // Simulates loss of vertical hold - image rolls up or down
    if (vsyncError > 0.0) {
        // Continuous vertical roll
        let vsyncRollSpeed = time * 0.5 * (0.5 + vsyncError * 2.0);
        let vRoll = fract(vsyncRollSpeed);
        sampleUV.y = fract(sampleUV.y - vRoll + 1.0);
        
        // VSync roll bar (black bar during retrace)
        let retraceHeight = 0.05 * vsyncError;
        let retracePos = fract(vsyncRollSpeed);
        let distFromRetrace = min(
            abs(sampleUV.y - retracePos),
            abs(sampleUV.y - (retracePos + 1.0 - retraceHeight))
        );
        let inRetrace = distFromRetrace < retraceHeight;
    }
    
    // ═══════════════════════════════════════════════════════════════
    // TRACKING ERRORS (VHS-style)
    // ═══════════════════════════════════════════════════════════════
    
    let trackingIntensity = interlaceStrength * 0.5;
    sampleUV = trackingError(sampleUV, trackingIntensity, time);
    
    // ═══════════════════════════════════════════════════════════════
    // INTERLACED FIELD SAMPLING WITH MOTION DETECTION
    // ═══════════════════════════════════════════════════════════════
    
    // Sample current frame at field position
    var fieldSample = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    
    // Try to read previous frame from dataTextureC for motion detection
    // dataTextureC stores previous frame data
    var prevFrameSample = textureSampleLevel(dataTextureC, filteringSampler, sampleUV, 0.0);
    
    // Detect motion by comparing current and previous frame
    let motionDelta = length(fieldSample.rgb - prevFrameSample.rgb);
    let isMoving = motionDelta > 0.05;
    
    // Calculate combing artifact based on motion
    // In true interlaced video, fast motion creates "comb" edges
    var combAmount = 0.0;
    if (interlaceStrength > 0.0 && isMoving) {
        // Sample from neighboring lines to simulate field offset
        let lineOffset = 1.0 / resolution.y;
        let neighborUV = sampleUV + vec2<f32>(0.0, lineOffset * select(-1.0, 1.0, isEvenLine));
        let neighborSample = textureSampleLevel(readTexture, u_sampler, neighborUV, 0.0);
        
        // Motion blur based on field temporal offset
        let temporalOffset = 0.5;  // Half frame delay between fields
        combAmount = motionDelta * interlaceStrength * temporalOffset;
        
        // Blend current field with neighbor for comb effect
        fieldSample = mix(fieldSample, neighborSample, combAmount * 0.3);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // FIELD PERSISTENCE (PHOSPHOR GLOW)
    // ═══════════════════════════════════════════════════════════════
    
    // Previous field persistence creates "ghost" image
    let persistence = 0.3 * interlaceStrength;
    var outputColor = mix(fieldSample, prevFrameSample, persistence * (1.0 - f32(inCurrentField)));
    
    // ═══════════════════════════════════════════════════════════════
    // COLOR BURST ERROR SIMULATION
    // ═══════════════════════════════════════════════════════════════
    
    if (colorBurstError > 0.0) {
        // Random phase errors
        let phaseNoise = hash(vec2<f32>(floor(uv.y * 50.0), floor(time * 60.0)));
        let phaseError = (phaseNoise - 0.5) * 2.0 * colorBurstError;
        
        // Line-to-line hue shift (common in VHS)
        let lineHueShift = sin(uv.y * 100.0 + time * 10.0) * 0.1 * colorBurstError;
        
        // Apply chroma shifts
        outputColor = vec4<f32>(
            colorBurstShift(outputColor.rgb, phaseError + lineHueShift),
            outputColor.a
        );
        
        // Chroma noise (speckles in color)
        let chromaNoise = hash(vec2<f32>(uv.x * 200.0 + time, uv.y * 200.0)) * 0.1 * colorBurstError;
        outputColor.rgb += vec3<f32>(chromaNoise * 0.5, chromaNoise, chromaNoise * 0.3);
    }
    
    // ═══════════════════════════════════════════════════════════════
    // SCANLINE RENDERING
    // ═══════════════════════════════════════════════════════════════
    
    // Darken inactive field lines
    let fieldDimming = 0.7 + 0.3 * f32(inCurrentField);
    outputColor.rgb *= mix(1.0, fieldDimming, interlaceStrength * 0.5);
    
    // Scanline intensity
    let scanlineIntensity = 0.15 * interlaceStrength;
    let scanlinePattern = sin(uv.y * resolution.y * 3.14159) * 0.5 + 0.5;
    outputColor.rgb *= 1.0 - scanlineIntensity * scanlinePattern;
    
    // ═══════════════════════════════════════════════════════════════
    // SYNC LOSS ARTIFACTS
    // ═══════════════════════════════════════════════════════════════
    
    // Vertical hold roll bar (dark band during retrace)
    if (vsyncError > 0.0) {
        let rollPos = fract(time * 0.5 * (0.5 + vsyncError * 2.0));
        let rollDist = abs(uv.y - rollPos);
        let inRollBar = rollDist < 0.02;
        outputColor.rgb *= 1.0 - f32(inRollBar) * 0.5 * vsyncError;
    }
    
    // Horizontal tearing at edges during HSync loss
    if (hsyncError > 0.0) {
        let edgeTear = hash(vec2<f32>(time * 100.0, uv.y * 10.0)) * hsyncError * 0.1;
        if (uv.x < 0.05 || uv.x > 0.95) {
            outputColor.rgb = mix(outputColor.rgb, vec3<f32>(0.0), edgeTear);
        }
    }
    
    // ═══════════════════════════════════════════════════════════════
    // NOISE & INTERFERENCE
    // ═══════════════════════════════════════════════════════════════
    
    // Analog signal noise
    let signalNoise = hash(uv * time) * 0.05 * interlaceStrength;
    outputColor.rgb += vec3<f32>(signalNoise);
    
    // RF interference lines
    let rfLines = sin(uv.y * 200.0 + time * 20.0) > 0.99 ? 0.1 : 0.0;
    outputColor.rgb += vec3<f32>(rfLines * interlaceStrength * 0.5);
    
    // Clamp output
    outputColor = clamp(outputColor, vec4<f32>(0.0), vec4<f32>(1.0));
    
    // ═══════════════════════════════════════════════════════════════
    // OUTPUT
    // ═══════════════════════════════════════════════════════════════
    
    // Write color output
    textureStore(writeTexture, coord, outputColor);
    
    // Store current frame in data texture for next frame's motion detection
    textureStore(dataTextureA, coord, outputColor);
    
    // Pass through depth
    let depth = textureSampleLevel(readDepthTexture, filteringSampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
