// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var <uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Persistence buffer
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>; // Velocity field
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Distortion, y=ColorMode, z=Pulse, w=DepthInfluence
  zoom_params: vec4<f32>,  // x=Speed, y=Scale, z=Intensity, w=ColorShift
  ripples: array<vec4<f32>, 50>,
};

// --- Improved Noise Functions ---
fn hash(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// 2D Simplex-style noise for better gradients
fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Fractional Brownian Motion with rotation
fn fbm(p: vec2<f32>, octaves: u32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var freq = 1.0;
    var p2 = p;
    
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    
    for (var i: u32 = 0u; i < octaves; i = i + 1u) {
        value += amplitude * noise(p2 * freq);
        p2 = rot * p2 * 2.0;
        amplitude *= 0.5;
        freq *= 2.0;
    }
    return value;
}

// HSL to RGB conversion
fn hsl2rgb(h: f32, s: f32, l: f32) -> vec3<f32> {
    let c = (1.0 - abs(2.0 * l - 1.0)) * s;
    let x = c * (1.0 - abs(fract(h * 6.0) * 2.0 - 1.0));
    let m = l - c * 0.5;
    
    var rgb = vec3<f32>(0.0);
    if (h < 1.0/6.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h < 2.0/6.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h < 3.0/6.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h < 4.0/6.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h < 5.0/6.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    
    return rgb + m;
}

// Color palette selector
fn palette_color(t: f32, mode: f32, shift: f32) -> vec3<f32> {
    let h = fract(t + shift);
    
    if (mode < 0.25) { // Nebula (Purple-Blue-Pink)
        return hsl2rgb(h * 0.8 + 0.6, 0.9, 0.6);
    } else if (mode < 0.5) { // Aurora (Green-Cyan)
        return hsl2rgb(h * 0.3 + 0.3, 0.8, 0.7);
    } else if (mode < 0.75) { // Toxic (Green-Yellow)
        return hsl2rgb(h * 0.2 + 0.15, 1.0, 0.5);
    } else { // Plasma (Full Spectrum)
        return hsl2rgb(h, 1.0, 0.6);
    }
}

// Calculate surface normal from depth
fn calculate_normal(uv: vec2<f32>, depth: f32, texel: vec2<f32>) -> vec3<f32> {
    let dL = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(texel.x, 0.0), 0.0).r;
    let dR = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(texel.x, 0.0), 0.0).r;
    let dU = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, texel.y), 0.0).r;
    let dD = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, texel.y), 0.0).r;
    
    let dx = (dR - dL) * 0.5;
    let dy = (dD - dU) * 0.5;
    
    return normalize(vec3<f32>(-dx, -dy, 1.0));
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;

    // Parameters
    let speed = u.zoom_params.x * 0.4;
    let scale = mix(0.5, 4.0, u.zoom_params.y);
    let intensity = u.zoom_params.z;
    let color_shift = u.zoom_params.w;
    let distortion = u.zoom_config.x;
    let color_mode = u.zoom_config.y;
    let pulse = u.zoom_config.z;
    let depth_influence = u.zoom_config.w;

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let base_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;

    // --- Domain Warping with 2 octaves ---
    var p = uv * scale;
    
    // First warp layer
    let q = vec2<f32>(
        fbm(p + vec2<f32>(0.0, 0.0) + time * speed, 4u),
        fbm(p + vec2<f32>(5.2, 1.3) + time * speed, 4u)
    );
    
    // Second warp layer (more turbulent)
    let r = vec2<f32>(
        fbm(p + 4.0 * q + vec2<f32>(1.7, 9.2) + time * speed * 0.7, 3u),
        fbm(p + 4.0 * q + vec2<f32>(8.3, 2.8) + time * speed * 0.7, 3u)
    );
    
    // Final noise value
    let f = fbm(p + 4.0 * r + time * speed * 0.3, 5u);
    
    // --- Depth Interaction ---
    var depth_mask = 1.0;
    var flow_direction = vec2<f32>(0.0);
    
    if (depth_influence > 0.01) {
        // Flow avoids foreground objects
        depth_mask = smoothstep(0.2, 0.8, depth);
        
        // Calculate normal to make flow follow surfaces
        let normal = calculate_normal(uv, depth, texel);
        flow_direction = normal.xy * depth_influence * 0.5;
    }
    
    // --- Temporal Persistence (Trails) ---
    var trail = 0.0;
    if (intensity > 0.5) {
        let prev_trail = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - flow_direction, 0.0).r;
        trail = max(prev_trail * 0.95, f * f * intensity);
        textureStore(dataTextureA, global_id.xy, vec4<f32>(trail, 0.0, 0.0, 1.0));
    }
    
    // --- Color & Glow ---
    let warp_length = length(q) * depth_mask;
    let color_t = warp_length + f * 0.3 + trail * 0.2;
    let flow_color = palette_color(color_t, color_mode, color_shift);
    
    // Pulsing glow
    let pulse_beat = sin(time * 2.0 * (pulse + 0.1)) * 0.5 + 0.5;
    let glow = pow(f * 3.0, 2.5) * intensity * (0.7 + pulse_beat * 0.3);
    let final_flow = flow_color * glow * depth_mask;
    
    // --- Chromatic Aberration ---
    var final_color = base_color;
    if (distortion > 0.01) {
        let offset = r * distortion * 0.05;
        final_color.r = textureSampleLevel(readTexture, u_sampler, uv + offset * 0.5, 0.0).r;
        final_color.g = base_color.g;
        final_color.b = textureSampleLevel(readTexture, u_sampler, uv - offset * 0.5, 0.0).b;
    }
    
    // --- Composition (Additive + Screen blend) ---
    let screen_blend = 1.0 - (1.0 - final_color) * (1.0 - final_flow);
    final_color = mix(final_color, screen_blend, glow * 0.8);
    
    // Add sparks/particles
    let spark = smoothstep(0.95, 1.0, hash(uv * 100.0 + time)) * f * intensity;
    final_color += vec3<f32>(1.0, 0.8, 0.5) * spark * 0.5;
    
    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
    
    // Pass depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
