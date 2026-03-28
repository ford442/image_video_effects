// ═══════════════════════════════════════════════════════════════
//  Encaustic Wax - Physical Media Simulation with Alpha
//  Category: artistic
//  Features: wax thickness → alpha, translucency, surface pooling
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

fn hash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(12.9898, 78.233))) * 43758.5453);
}

fn noise(p: vec2<f32>) -> f32 {
    var i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2<f32>(0.0, 0.0)), hash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash(i + vec2<f32>(0.0, 1.0)), hash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var shift = vec2<f32>(100.0);
    let rot = mat2x2<f32>(cos(0.5), sin(0.5), -sin(0.5), cos(0.5));
    var pp = p;
    for (var i = 0; i < 5; i++) {
        v += a * noise(pp);
        pp = rot * pp * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    var mouse = u.zoom_config.yz;

    // Parameters
    let waxThickness = u.zoom_params.x * 10.0;
    let textureStrength = u.zoom_params.y;
    let meltRadius = u.zoom_params.z;
    let meltIntensity = u.zoom_params.w;

    // Calculate Melting from Mouse
    let dist = distance(uv * vec2<f32>(aspect, 1.0), mouse * vec2<f32>(aspect, 1.0));
    let meltFactor = smoothstep(meltRadius + 0.1, meltRadius, dist) * meltIntensity;

    // Adjust blur and texture based on melt
    let currentBlur = waxThickness + meltFactor * 10.0;
    let currentTexture = textureStrength * (1.0 - meltFactor * 0.5);

    // Generate Wax Texture (Height map for thickness variation)
    let waxHeight = fbm(uv * 10.0);
    let waxDetail = fbm(uv * 25.0 + 100.0) * 0.5;
    let totalWaxHeight = waxHeight + waxDetail * 0.3;

    // Distort UV slightly based on height (Refraction)
    let distortUV = uv + vec2<f32>(waxHeight - 0.5) * 0.01 * currentTexture;

    // Blur Loop (Box Blur approximation)
    var colorSum = vec3<f32>(0.0);
    var totalWeight = 0.0;
    let texel = 1.0 / resolution;

    let samples = 5.0;
    for (var x = -2.0; x <= 2.0; x += 1.0) {
        for (var y = -2.0; y <= 2.0; y += 1.0) {
            let offset = vec2<f32>(x, y) * currentBlur * texel;
            let weight = 1.0 / (1.0 + length(vec2<f32>(x, y)));
            colorSum += textureSampleLevel(readTexture, u_sampler, distortUV + offset, 0.0).rgb * weight;
            totalWeight += weight;
        }
    }

    var finalColor = colorSum / totalWeight;

    // Add specular highlights for wax surface
    let h1 = fbm((uv + vec2<f32>(texel.x, 0.0)) * 10.0);
    let h2 = fbm((uv + vec2<f32>(0.0, texel.y)) * 10.0);
    let normal = normalize(vec3<f32>(h1 - waxHeight, h2 - waxHeight, 0.1));
    let lightDir = normalize(vec3<f32>(mouse.x - uv.x, mouse.y - uv.y, 0.5));

    let spec = pow(max(dot(normal, lightDir), 0.0), 10.0) * currentTexture * 0.5;
    finalColor += spec;

    // Warm tint for melt
    if (meltFactor > 0.0) {
        finalColor = mix(finalColor, finalColor * vec3<f32>(1.1, 1.05, 0.9), meltFactor);
    }

    // ENCAUSTIC WAX ALPHA CALCULATION
    // Wax has unique transparency properties:
    // - Thick areas: more opaque (0.7-0.95 alpha)
    // - Thin areas: semi-translucent (0.3-0.6 alpha)
    // - Melted/pooled areas: higher opacity due to accumulation
    // - Encaustic medium allows light to pass through thin layers
    
    // Base wax thickness from height map
    let base_thickness = 0.3 + totalWaxHeight * 0.7;
    
    // Melted wax pools and becomes thicker
    let melt_thickness = base_thickness + meltFactor * 0.4;
    
    // WAX THICKNESS → ALPHA MAPPING
    // Thin wax glaze = more transparent
    // Thick impasto = more opaque
    var wax_alpha = mix(0.35, 0.92, melt_thickness * (0.5 + textureStrength * 0.5));
    
    // Surface texture creates variation in perceived thickness
    // Raised areas catch light and appear more solid
    let surface_relief = smoothstep(0.3, 0.7, waxHeight);
    wax_alpha *= mix(0.9, 1.0, surface_relief);
    
    // Translucency effect: thin areas allow underlying image to show through
    // Thinner in valleys, thicker on peaks
    let valley_depth = 1.0 - waxDetail;
    let translucency = mix(0.6, 1.0, valley_depth);
    wax_alpha *= translucency;
    
    // Edge feathering for wax drips/flow
    let edge_mask = smoothstep(0.0, 0.15, melt_thickness);
    wax_alpha *= edge_mask;
    
    // Add warm color shift for wax medium
    let wax_tint = vec3<f32>(1.02, 0.98, 0.92); // Warm amber tint
    finalColor *= mix(vec3<f32>(1.0), wax_tint, melt_thickness * 0.5);
    
    // Deepen color in thick areas (more pigment/pigment density)
    let depth_darken = mix(1.0, 0.85, melt_thickness * textureStrength);
    finalColor *= depth_darken;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor, wax_alpha));

    // Store wax thickness in depth
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(melt_thickness, 0.0, 0.0, wax_alpha));
}
