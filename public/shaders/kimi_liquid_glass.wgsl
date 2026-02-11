@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Kimi Liquid Glass - Caustics and chromatic refraction

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
        value += amp * noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return value;
}

// Caustic pattern
fn caustics(uv: vec2<f32>, time: f32) -> f32 {
    var c = 0.0;
    let layers = 4;
    for (var i = 0; i < layers; i++) {
        let fi = f32(i);
        let scale = 2.0 + fi * 2.0;
        let speed = 0.3 + fi * 0.1;
        let offset = vec2<f32>(
            noise(uv * scale + vec2<f32>(time * speed, 0.0)),
            noise(uv * scale + vec2<f32>(0.0, time * speed))
        );
        c += noise(uv * scale + offset * 2.0);
    }
    return c / f32(layers);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Mouse position
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Liquid surface height
    var height = 0.0;
    
    // Mouse ripple
    let dist = length(uv - mouse);
    let ripple = sin(dist * 50.0 - time * 5.0) * exp(-dist * 3.0) * (0.5 + mouseDown);
    height += ripple;
    
    // FBM waves
    height += fbm(uv * 3.0 + vec2<f32>(time * 0.2), 4) * 0.3;
    height += fbm(uv * 8.0 - vec2<f32>(time * 0.1), 3) * 0.1;
    
    // Calculate gradient for refraction
    let texel = 1.0 / resolution;
    let hL = fbm((uv + vec2<f32>(-texel.x, 0.0)) * 3.0 + vec2<f32>(time * 0.2), 4) * 0.3;
    let hR = fbm((uv + vec2<f32>(texel.x, 0.0)) * 3.0 + vec2<f32>(time * 0.2), 4) * 0.3;
    let hU = fbm((uv + vec2<f32>(0.0, -texel.y)) * 3.0 + vec2<f32>(time * 0.2), 4) * 0.3;
    let hD = fbm((uv + vec2<f32>(0.0, texel.y)) * 3.0 + vec2<f32>(time * 0.2), 4) * 0.3;
    
    let grad = vec2<f32>(hR - hL, hD - hU);
    
    // Chromatic refraction
    let refractStrength = u.zoom_params.x * 0.05 + 0.02;
    
    let rOffset = grad * refractStrength * 1.5;
    let gOffset = grad * refractStrength;
    let bOffset = grad * refractStrength * 0.5;
    
    let r = textureSampleLevel(readTexture, u_sampler, uv + rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv + gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv + bOffset, 0.0).b;
    
    var col = vec3<f32>(r, g, b);
    
    // Caustic overlay
    let causticUV = uv * 2.0 + grad * 0.5;
    let caustic = caustics(causticUV, time * 0.5);
    let causticMask = smoothstep(0.2, 0.8, height + 0.5);
    col += vec3<f32>(0.6, 0.9, 1.0) * caustic * causticMask * 0.3;
    
    // Specular highlight
    let lightDir = normalize(vec2<f32>(0.3, 0.5));
    let spec = pow(max(0.0, dot(normalize(grad + vec2<f32>(0.0, 1.0)), lightDir)), 32.0);
    col += vec3<f32>(1.0) * spec * 0.5;
    
    // Deep water tint
    let depth = smoothstep(-0.5, 0.5, height);
    let waterColor = mix(
        vec3<f32>(0.0, 0.1, 0.3),
        vec3<f32>(0.0, 0.4, 0.6),
        depth
    );
    col = mix(col, col * waterColor, 0.3);
    
    // Fresnel edge
    let fresnel = pow(1.0 - abs(height) * 2.0, 3.0);
    col += vec3<f32>(0.8, 0.95, 1.0) * fresnel * 0.3;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(col, 1.0));
}
