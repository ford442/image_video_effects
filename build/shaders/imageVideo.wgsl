@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var u_texture: texture_2d<f32>;

struct Uniforms {
    resolutions: vec4<f32>, // canvas.xy, source.xy
    config: vec4<f32>,      // time, rippleCount, mode, unused
    ripples: array<vec4<f32>, 50>, // x, y, startTime, unused
};
@group(0) @binding(2) var<uniform> u: Uniforms;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) fragUV: vec2<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> VertexOutput {
    var output: VertexOutput;
    let x = f32(in_vertex_index / 2u) * 4.0 - 1.0;
    let y = f32(in_vertex_index % 2u) * 4.0 - 1.0;
    output.position = vec4<f32>(x, -y, 0.0, 1.0);
    output.fragUV = vec2<f32>((x + 1.0) * 0.5, (y + 1.0) * 0.5);
    return output;
}

@fragment
fn fs_main(@location(0) fragUV: vec2<f32>) -> @location(0) vec4<f32> {
    let canvasRes = u.resolutions.xy;
    let textureRes = u.resolutions.zw;
    let canvasAspect = canvasRes.x / canvasRes.y;
    let textureAspect = textureRes.x / textureRes.y;
    var scale = vec2(1.0, 1.0);
    
    if (canvasAspect > textureAspect) {
        scale.x = textureAspect / canvasAspect;
    } else {
        scale.y = canvasAspect / textureAspect;
    }

    let scaledUV = (fragUV - 0.5) * scale + 0.5;
    
    var finalUV = scaledUV;
    var totalDisplacement = vec2<f32>(0.0, 0.0);
    
    // Check if we are in ripple mode for any effect
    if (u.config.z > 0.5) { 
        let currentTime = u.config.x;

        // Ambient "still water" effect
        let time = currentTime * 0.5;
        let ambient_strength = 0.003;
        let ambient_freq = 20.0;
        let d1 = sin(scaledUV.x * ambient_freq + time) * ambient_strength;
        let d2 = cos(scaledUV.y * ambient_freq * 0.7 + time) * ambient_strength;
        totalDisplacement += vec2<f32>(d1, d2);

        // Mouse-driven ripple logic
        let rippleCount = u32(u.config.y);
        for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
            let rippleData = u.ripples[i];
            let rippleCenter = rippleData.xy;
            let rippleStartTime = rippleData.z;
            let timeSinceClick = currentTime - rippleStartTime;
            
            if (timeSinceClick > 0.0 && timeSinceClick < 3.0) { // Ripples last for 3 seconds
                let dist = distance(scaledUV, rippleCenter);
                let ripple_speed = 2.0;
                let ripple_frequency = 25.0;
                let ripple_amplitude = 0.015;

                let wave = sin(dist * ripple_frequency - timeSinceClick * ripple_speed);
                let attenuation = 1.0 - smoothstep(0.0, 1.0, timeSinceClick / 3.0);
                let falloff = 1.0 / (dist * 20.0 + 1.0);
                let displacement = wave * ripple_amplitude * attenuation * falloff;
                let direction = normalize(scaledUV - rippleCenter);

                totalDisplacement += direction * displacement;
            }
        }
    }
    finalUV += totalDisplacement;

    let textureColor = textureSample(u_texture, u_sampler, finalUV);
    let outOfBounds = f32(scaledUV.x < 0.0 || scaledUV.x > 1.0 || scaledUV.y < 0.0 || scaledUV.y > 1.0);
    let finalColor = mix(vec4(0.0, 0.0, 0.0, 1.0), textureColor, 1.0 - outOfBounds);

    return finalColor;
}
