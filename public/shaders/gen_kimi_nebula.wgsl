@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(7) var dataTextureA : texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC : texture_2d<f32>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Kimi Nebula - Cosmic Cloud Swirls
// Ethereal gas clouds with twinkling stars and mouse-driven stellar winds

fn hash3(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    let n = i.x + i.y * 57.0 + i.z * 113.0;
    var res = mix(mix(mix(hash3(vec3<f32>(n)), hash3(vec3<f32>(n + 1.0)), f.x),
                      mix(hash3(vec3<f32>(n + 57.0)), hash3(vec3<f32>(n + 58.0)), f.x), f.y),
                 mix(mix(hash3(vec3<f32>(n + 113.0)), hash3(vec3<f32>(n + 114.0)), f.x),
                     mix(hash3(vec3<f32>(n + 170.0)), hash3(vec3<f32>(n + 171.0)), f.x), f.y), f.z);
    return res;
}

fn fbm3(p: vec3<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        value += amplitude * noise3(p * freq);
        amplitude *= 0.5;
        freq *= 2.0;
    }
    return value;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x * 0.1;
    let px = vec2<i32>(global_id.xy);
    
    // Mouse interaction
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Create swirling nebula effect
    var p = uv * 2.0 - 1.0;
    p.x *= resolution.x / resolution.y;
    
    // Mouse creates stellar wind
    let mousePos = mouse * 2.0 - 1.0;
    mousePos.x *= resolution.x / resolution.y;
    let dist = length(p - mousePos);
    let windStrength = smoothstep(0.8, 0.0, dist) * (0.5 + mouseDown * 0.5);
    
    // Animated 3D noise for gas clouds
    var noisePos = vec3<f32>(p * 1.5, time * 0.2);
    
    // Add swirling motion from mouse
    let angle = windStrength * 2.0;
    let rot = vec2<f32>(
        noisePos.x * cos(angle) - noisePos.y * sin(angle),
        noisePos.x * sin(angle) + noisePos.y * cos(angle)
    );
    noisePos.x = mix(noisePos.x, rot.x, windStrength);
    noisePos.y = mix(noisePos.y, rot.y, windStrength);
    
    // Multi-octave nebula density
    let density1 = fbm3(noisePos, 4);
    let density2 = fbm3(noisePos * 2.0 + vec3<f32>(100.0), 3);
    let density3 = fbm3(noisePos * 4.0 + vec3<f32>(200.0), 2);
    
    let nebulaDensity = density1 * 0.5 + density2 * 0.3 + density3 * 0.2;
    
    // Color palette - deep purples, blues, and pink accents
    let color1 = vec3<f32>(0.1, 0.05, 0.2);  // Deep purple
    let color2 = vec3<f32>(0.2, 0.1, 0.4);   // Purple
    let color3 = vec3<f32>(0.4, 0.2, 0.6);   // Magenta
    let color4 = vec3<f32>(0.8, 0.6, 0.9);   // Pink highlight
    let color5 = vec3<f32>(0.1, 0.3, 0.5);   // Blue
    
    var color = color1;
    color = mix(color, color2, smoothstep(0.2, 0.4, nebulaDensity));
    color = mix(color, color3, smoothstep(0.4, 0.6, nebulaDensity));
    color = mix(color, color4, smoothstep(0.7, 0.9, nebulaDensity + windStrength * 0.3));
    color = mix(color, color5, smoothstep(0.5, 0.8, density3));
    
    // Add stars
    let starNoise = hash3(vec3<f32>(floor(p * 100.0), time * 0.01));
    let star = select(0.0, 1.0, starNoise > 0.995 && nebulaDensity < 0.6);
    
    // Twinkling stars near mouse
    let starTwinkle = sin(time * 5.0 + starNoise * 10.0) * 0.5 + 0.5;
    color += vec3<f32>(star) * (0.5 + starTwinkle * 0.5) * (1.0 + windStrength);
    
    // Bright core near mouse
    color += vec3<f32>(0.6, 0.8, 1.0) * windStrength * 0.5;
    
    // Gamma correction and intensity
    color = pow(color, vec3<f32>(0.8)) * 1.2;
    
    // Store for feedback
    textureStore(writeTexture, px, vec4<f32>(color, 1.0));
    textureStore(dataTextureA, px, vec4<f32>(color, nebulaDensity, 0.0, 1.0));
}
