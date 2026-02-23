// ═══════════════════════════════════════════════════════════════
//  Iridescent Oil Slick - Thin-film interference simulation
//  Category: artistic
//  Features: mouse-driven
//  Description: Creates mesmerizing oil-on-water interference patterns
//               with flowing organic motion and rainbow color shifts.
// ═══════════════════════════════════════════════════════════════

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

// Simplex noise functions for organic flow
fn mod289_3(x: vec3<f32>) -> vec3<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn mod289_4(x: vec4<f32>) -> vec4<f32> { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn permute(x: vec4<f32>) -> vec4<f32> { return mod289_4(((x * 34.0) + 1.0) * x); }
fn taylorInvSqrt(r: vec4<f32>) -> vec4<f32> { return 1.79284291400159 - 0.85373472095314 * r; }

fn snoise(v: vec3<f32>) -> f32 {
    let C = vec2<f32>(1.0 / 6.0, 1.0 / 3.0);
    let D = vec4<f32>(0.0, 0.5, 1.0, 2.0);
    
    var i = floor(v + dot(v, C.yyy));
    let x0 = v - i + dot(i, C.xxx);
    
    let g = step(x0.yzx, x0.xyz);
    let l = 1.0 - g;
    let i1 = min(g.xyz, l.zxy);
    let i2 = max(g.xyz, l.zxy);
    
    let x1 = x0 - i1 + C.xxx;
    let x2 = x0 - i2 + C.yyy;
    let x3 = x0 - D.yyy;
    
    i = mod289_3(i);
    let p = permute(permute(permute(
        i.z + vec4<f32>(0.0, i1.z, i2.z, 1.0))
        + i.y + vec4<f32>(0.0, i1.y, i2.y, 1.0))
        + i.x + vec4<f32>(0.0, i1.x, i2.x, 1.0));
    
    let n_ = 0.142857142857;
    let ns = n_ * D.wyz - D.xzx;
    
    let j = p - 49.0 * floor(p * ns.z * ns.z);
    
    let x_ = floor(j * ns.z);
    let y_ = floor(j - 7.0 * x_);
    
    let x = x_ *ns.x + ns.yyyy;
    let y = y_ *ns.x + ns.yyyy;
    let h = 1.0 - abs(x) - abs(y);
    
    let b0 = vec4<f32>(x.xy, y.xy);
    let b1 = vec4<f32>(x.zw, y.zw);
    
    let s0 = floor(b0) * 2.0 + 1.0;
    let s1 = floor(b1) * 2.0 + 1.0;
    let sh = -step(h, vec4<f32>(0.0));
    
    let a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    let a1 = b1.xzyw + s1.xzyw * sh.zzww;
    
    var p0 = vec3<f32>(a0.xy, h.x);
    var p1 = vec3<f32>(a0.zw, h.y);
    var p2 = vec3<f32>(a1.xy, h.z);
    var p3 = vec3<f32>(a1.zw, h.w);
    
    let norm = taylorInvSqrt(vec4<f32>(dot(p0,p0), dot(p1,p1), dot(p2,p2), dot(p3,p3)));
    p0 = p0 * norm.x;
    p1 = p1 * norm.y;
    p2 = p2 * norm.z;
    p3 = p3 * norm.w;
    
    var m = max(0.6 - vec4<f32>(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), vec4<f32>(0.0));
    m = m * m;
    return 42.0 * dot(m*m, vec4<f32>(dot(p0,x0), dot(p1,x1), dot(p2,x2), dot(p3,x3)));
}

// FBM for organic thickness variation
fn fbm(p: vec3<f32>) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    
    for (var i: i32 = 0; i < 5; i++) {
        value += amplitude * snoise(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    return value;
}

// Thin-film interference - calculates iridescent colors based on film thickness
fn thinFilmInterference(thickness: f32, viewAngle: f32) -> vec3<f32> {
    // Refractive indices
    let nFilm = 1.33; // Water/oil
    let nAir = 1.0;
    
    // Phase shift due to reflection
    let phase = 4.0 * 3.14159 * nFilm * thickness * sqrt(1.0 - (nAir/nFilm) * (nAir/nFilm) * viewAngle * viewAngle);
    
    // Constructive/destructive interference for RGB channels
    // Different wavelengths produce different colors
    let rPhase = phase / 650.0; // Red
    let gPhase = phase / 530.0; // Green  
    let bPhase = phase / 460.0; // Blue
    
    let r = 0.5 + 0.5 * cos(rPhase);
    let g = 0.5 + 0.5 * cos(gPhase);
    let b = 0.5 + 0.5 * cos(bPhase);
    
    // Enhance saturation
    return vec3<f32>(r, g, b);
}

// Rotate UV for kaleidoscope effect
fn rotateUV(uv: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(uv.x * c - uv.y * s, uv.x * s + uv.y * c);
}

// Hexagonal pattern for oil bubble cells
fn hexPattern(uv: vec2<f32>) -> f32 {
    let r = vec2<f32>(1.0, 1.732);
    let h = r * 0.5;
    
    var p = uv;
    
    let a = vec2<f32>(dot(p, r), p.y);
    let b = vec2<f32>(dot(p, r - h * 2.0), p.y);
    
    let ai = floor(a);
    let bi = floor(b);
    
    var v = vec2<f32>(0.0);
    var m = 1.0;
    
    for (var j: i32 = -1; j <= 1; j++) {
        for (var i: i32 = -1; i <= 1; i++) {
            let o = vec2<f32>(f32(i), f32(j));
            let d = length(a - ai - o);
            if (d < m) {
                m = d;
                v = ai + o;
            }
        }
    }
    
    return m;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    
    // Parameters
    let filmScale = mix(2.0, 8.0, u.zoom_params.x);      // Film thickness scale
    let flowSpeed = mix(0.1, 0.8, u.zoom_params.y);       // Animation speed
    let turbulence = mix(0.5, 3.0, u.zoom_params.z);      // Noise intensity
    let colorShift = u.zoom_params.w * 6.28318;           // Hue rotation
    
    // Aspect ratio correction
    let aspect = resolution.x / resolution.y;
    var p = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    
    // Mouse interaction - create ripples/disturbances
    let mousePos = (mouse - 0.5) * vec2<f32>(aspect, 1.0);
    let mouseDist = length(p - mousePos);
    let mouseInfluence = exp(-mouseDist * 3.0) * 0.5;
    
    // Animated flow coordinates
    var flowUV = p * filmScale;
    flowUV += vec2<f32>(
        snoise(vec3<f32>(p * 2.0, time * flowSpeed * 0.3)),
        snoise(vec3<f32>(p * 2.0 + 100.0, time * flowSpeed * 0.3))
    ) * turbulence;
    
    // Add swirling motion
    let swirlAngle = time * flowSpeed * 0.2 + mouseInfluence * 2.0;
    flowUV = rotateUV(flowUV, swirlAngle);
    
    // Generate film thickness using FBM
    let thicknessBase = fbm(vec3<f32>(flowUV, time * flowSpeed * 0.1));
    let thicknessDetail = snoise(vec3<f32>(flowUV * 3.0, time * flowSpeed)) * 0.3;
    let thickness = (thicknessBase + thicknessDetail) * 0.5 + 0.5;
    
    // Add hexagonal cell variation for bubble effect
    let hex = hexPattern(flowUV * 2.0);
    let cellVariation = smoothstep(0.3, 0.0, hex) * 0.2;
    
    // Final thickness with all contributions
    let finalThickness = thickness * (1.0 + cellVariation) + mouseInfluence * 0.3;
    
    // Calculate view angle (simplified - assume looking from above with slight tilt)
    let viewAngle = length(p) * 0.3;
    
    // Get iridescent color from thin-film interference
    var color = thinFilmInterference(finalThickness * 500.0 + 100.0, viewAngle);
    
    // Apply color shift
    let hueRotation = colorShift + time * flowSpeed * 0.1;
    let cosH = cos(hueRotation);
    let sinH = sin(hueRotation);
    let hueMatrix = mat3x3<f32>(
        vec3<f32>(0.299 + 0.701 * cosH + 0.168 * sinH, 0.587 - 0.587 * cosH + 0.330 * sinH, 0.114 - 0.114 * cosH - 0.497 * sinH),
        vec3<f32>(0.299 - 0.299 * cosH - 0.328 * sinH, 0.587 + 0.413 * cosH + 0.035 * sinH, 0.114 - 0.114 * cosH + 0.292 * sinH),
        vec3<f32>(0.299 - 0.300 * cosH + 1.250 * sinH, 0.587 - 0.588 * cosH - 1.050 * sinH, 0.114 + 0.886 * cosH - 0.203 * sinH)
    );
    color = hueMatrix * color;
    
    // Add specular highlight for wet/oily look
    let highlightPos = rotateUV(p, time * flowSpeed * 0.1) * 2.0;
    let highlight = pow(max(0.0, 1.0 - length(highlightPos)), 3.0) * 0.3;
    color += vec3<f32>(highlight);
    
    // Add subtle vignette
    let vignette = 1.0 - length(p) * 0.4;
    color *= vignette;
    
    // Boost contrast and saturation
    color = pow(color, vec3<f32>(0.8));
    color = color * 1.2;
    
    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(clamp(color, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0));
    
    // Depth pass-through
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
