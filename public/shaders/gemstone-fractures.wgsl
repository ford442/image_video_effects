// ═══════════════════════════════════════════════════════════════
//  Gemstone Fractures - Physical Light Transmission with Alpha
//  Category: distortion
//  Features: voronoi shards, rotation, internal fractures
//  Simulates fractured gemstone with variable purity/transmission
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

const IOR_QUARTZ: f32 = 1.54;
const IOR_DIAMOND: f32 = 2.42;

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a);
    let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: scale (facet size)
    // y: refraction + IOR
    // z: rotationBase
    // w: fractureDensity (affects transmission)
    // ═══════════════════════════════════════════════════════════════
    
    let scale = u.zoom_params.x * 20.0 + 2.0;
    let iorMix = u.zoom_params.y;
    let refraction = u.zoom_params.y * 0.05;
    let rotationBase = u.zoom_params.z;
    let fractureDensity = u.zoom_params.w; // 0 = pure, 1 = heavily fractured
    
    let ior = mix(IOR_QUARTZ, IOR_DIAMOND, iorMix);
    let F0 = pow((ior - 1.0) / (ior + 1.0), 2.0);

    let st = uv * vec2<f32>(aspect, 1.0) * scale;
    let i_st = floor(st);
    let f_st = fract(st);

    // Voronoi / Cellular logic
    var m_dist = 1.0;
    var second_dist = 1.0;
    var m_point = vec2<f32>(0.0);
    var cell_id = vec2<f32>(0.0);

    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let point = hash22(i_st + neighbor);
            // Animate point
            let animPoint = 0.5 + 0.5 * sin(u.config.x * 0.5 + 6.2831 * point);
            let diff = neighbor + animPoint - f_st;
            let dist = length(diff);

            if (dist < m_dist) {
                second_dist = m_dist;
                m_dist = dist;
                m_point = point;
                cell_id = i_st + neighbor;
            } else if (dist < second_dist) {
                second_dist = dist;
            }
        }
    }

    // Refraction based on cell ID
    let rotAngle = (hash22(cell_id).x - 0.5) * rotationBase * 10.0 + u.config.x * (hash22(cell_id).y - 0.5) * rotationBase;
    let c = cos(rotAngle);
    let s = sin(rotAngle);

    // Rotate the UV space locally around the center
    var center = vec2<f32>(0.5 * aspect, 0.5);
    let fromCenter = uv * vec2<f32>(aspect, 1.0) - center;
    let rotFromCenter = vec2<f32>(
        fromCenter.x * c - fromCenter.y * s,
        fromCenter.x * s + fromCenter.y * c
    );
    let sampleUV = (rotFromCenter + center) / vec2<f32>(aspect, 1.0);

    // Chromatic aberration with dispersion
    let dispersion = (ior - 1.0) * 0.3;
    let r = textureSampleLevel(readTexture, u_sampler, sampleUV + vec2<f32>(refraction * (1.0 + dispersion), 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, sampleUV - vec2<f32>(refraction * (1.0 - dispersion), 0.0), 0.0).b;

    var color = vec3<f32>(r, g, b);

    // ═══════════════════════════════════════════════════════════════
    // Physical Transmission & Fracture Effects
    // ═══════════════════════════════════════════════════════════════
    
    // Per-cell fracture amount
    let cellFracture = hash21(cell_id);
    let effectiveFracture = fractureDensity * (0.5 + 0.5 * cellFracture);
    
    // Purity: inverse of fracture
    let purity = 1.0 - effectiveFracture;
    
    // Distance from cell center affects angle
    let cosTheta = 1.0 - m_dist; // Approximate
    let fresnel = fresnelSchlick(max(cosTheta, 0.0), F0);
    
    // Path length (longer near edges)
    let pathLength = mix(0.05, 0.4, m_dist) / max(purity, 0.1);
    
    // Absorption increases with fractures
    let absorptionCoeff = mix(0.2, 4.0, effectiveFracture);
    let absorption = exp(-absorptionCoeff * pathLength);
    
    // Edge distance for highlighting
    let edgeDist = second_dist - m_dist;
    let edgeFactor = smoothstep(0.02, 0.0, edgeDist);
    
    // Transmission coefficient
    let transmission = absorption * (1.0 - fresnel) * purity;
    
    // Add fracture lines (reduce transmission at cell boundaries)
    let fractureLine = smoothstep(0.01, 0.0, edgeDist) * effectiveFracture;
    
    // Specular on edges
    let specular = edgeFactor * fresnel * 0.5;
    color += vec3<f32>(specular);
    
    // Fracture tint (internal scattering)
    let fractureTint = mix(vec3<f32>(1.0), vec3<f32>(0.9, 0.85, 0.8), effectiveFracture);
    color = color * fractureTint;

    // Alpha based on transmission
    let alpha = clamp(transmission * (1.0 - fractureLine), 0.3, 1.0);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(color, alpha));
    
    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(d, 0.0, 0.0, 0.0));
}
