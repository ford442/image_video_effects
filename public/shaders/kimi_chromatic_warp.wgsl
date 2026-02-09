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

// Kimi Chromatic Warp - RGB channel separation based on mouse distance
// Creates prismatic distortion effects that intensify near the cursor

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    
    // Mouse position
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    
    // Aspect correction
    let aspect = resolution.x / resolution.y;
    var p = uv;
    p.x *= aspect;
    
    let mousePos = mouse;
    mousePos.x *= aspect;
    
    // Vector from mouse to pixel
    let delta = p - mousePos;
    let dist = length(delta);
    let dir = normalize(delta + vec2<f32>(0.0001));
    
    // Parameters from zoom_params
    let warpRadius = u.zoom_params.x * 0.8 + 0.05;    // Affected radius
    let warpStrength = u.zoom_params.y * 0.1 + 0.01;  // Distortion amount
    let chromaticSpread = u.zoom_params.z * 0.05;      // RGB separation
    let rotationSpeed = u.zoom_params.w * 5.0;        // Twist speed
    
    // Distance falloff (stronger near mouse)
    let falloff = smoothstep(warpRadius, 0.0, dist);
    
    // Rotation based on distance from mouse and time
    let angle = dist * 10.0 - time * rotationSpeed + mouseDown * 2.0;
    let rotDir = vec2<f32>(
        dir.x * cos(angle) - dir.y * sin(angle),
        dir.x * sin(angle) + dir.y * cos(angle)
    );
    
    // RGB channel offsets
    let rOffset = rotDir * (warpStrength + chromaticSpread) * falloff;
    let gOffset = rotDir * warpStrength * falloff;
    let bOffset = rotDir * (warpStrength - chromaticSpread) * falloff * 0.5;
    
    // Sample each channel at different offsets
    let r = textureSampleLevel(readTexture, u_sampler, uv - rOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv - gOffset, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - bOffset, 0.0).b;
    
    var color = vec3<f32>(r, g, b);
    
    // Add prismatic glow ring at edge of warp radius
    let ringWidth = 0.02;
    let ringDist = abs(dist - warpRadius * 0.7);
    let ring = smoothstep(ringWidth, 0.0, ringDist) * falloff;
    
    // Rainbow colors based on angle
    let hue = atan2(delta.y, delta.x) / 6.28318 + 0.5;
    let rainbow = vec3<f32>(
        sin(hue * 6.28318) * 0.5 + 0.5,
        sin(hue * 6.28318 + 2.094) * 0.5 + 0.5,
        sin(hue * 6.28318 + 4.188) * 0.5 + 0.5
    );
    color = mix(color, rainbow, ring * 0.3);
    
    // Vignette darkening near edges of warp
    let innerVignette = smoothstep(warpRadius * 0.3, warpRadius * 0.8, dist);
    color *= 0.7 + 0.3 * innerVignette;
    
    // Mouse click creates burst effect
    let burst = mouseDown * exp(-dist * 3.0) * sin(dist * 30.0 - time * 15.0);
    color += vec3<f32>(burst * 0.2);
    
    // Film grain
    let grain = hash(uv + vec2<f32>(time)) * 0.04 - 0.02;
    color += grain;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, 1.0));
}
