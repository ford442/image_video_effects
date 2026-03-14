// ═══════════════════════════════════════════════════════════════
//  Crystal Freeze - Physical Light Transmission with Alpha
//  Category: interactive-mouse
//  Features: mouse-driven, persistence, voronoi crystals
//  Simulates ice crystal formation with light transmission
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

// Ice IOR
const IOR_ICE: f32 = 1.31;
const IOR_GLASS: f32 = 1.5;

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

// Fresnel-Schlick approximation
fn fresnelSchlick(cosTheta: f32, F0: f32) -> f32 {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // ═══════════════════════════════════════════════════════════════
    // Parameters:
    // x: decay / Freeze persistence
    // y: crystalScale (affects cell density)
    // z: refraction (IOR mix)
    // w: ice purity (affects transmission)
    // ═══════════════════════════════════════════════════════════════
    
    let decay = u.zoom_params.x;
    let crystalScale = 10.0 + u.zoom_params.y * 40.0;
    let iorMix = u.zoom_params.z; // 0 = ice, 1 = glass
    let icePurity = 1.0 - u.zoom_params.w * 0.5; // Purity decreases with param
    
    // Fixed brush radius
    let brushRadius = 0.08;

    var mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Update Freeze State (Persistence)
    let oldFreeze = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Mouse interaction
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    var dist = length(distVec);
    let brush = smoothstep(brushRadius, brushRadius * 0.5, dist);

    // New freeze value: max of decayed old value and new brush input
    let newFreeze = max(oldFreeze * decay, brush);

    // Write state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newFreeze, 0.0, 0.0, 1.0));

    // Calculate IOR based on freeze state (frozen areas have higher IOR)
    let baseIOR = mix(IOR_ICE, IOR_GLASS, iorMix);
    let frozenIOR = mix(1.0, baseIOR, newFreeze); // Unfrozen = air (IOR 1.0)
    let F0 = pow((frozenIOR - 1.0) / (frozenIOR + 1.0), 2.0);

    // Crystal Effect Logic (Voronoi)
    var finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    var transmissionAlpha = 1.0; // Full transmission where no crystal

    if (newFreeze > 0.01) {
        // Simple Voronoi
        let g = floor(uv * crystalScale);
        let f = fract(uv * crystalScale);

        var minLoading = 1.0;
        var center = vec2<f32>(0.0);
        var cellId = vec2<f32>(0.0);

        // 3x3 search
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                let lattice = vec2<f32>(f32(x), f32(y));
                let offset = hash22(g + lattice);
                var dist = distance(lattice + offset, f);

                if (dist < minLoading) {
                    minLoading = dist;
                    center = lattice + offset;
                    cellId = g + lattice;
                }
            }
        }

        // Calculate vector from pixel to cell center
        let toCenter = (center - f) / crystalScale;

        // Per-cell purity variation
        let cellPurity = icePurity * (0.5 + 0.5 * hash21(cellId));
        
        // Refraction strength varies by frozen amount and purity
        let refraction = 0.1 * newFreeze * (0.5 + 0.5 / max(cellPurity, 0.1));
        let refractUV = uv + toCenter * refraction;

        // Chromatic aberration based on freeze intensity and dispersion
        let dispersion = (frozenIOR - 1.0) * 0.02 * newFreeze;
        let r = textureSampleLevel(readTexture, u_sampler, refractUV + vec2<f32>(0.002, 0.0) * newFreeze, 0.0).r;
        let g_val = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, refractUV - vec2<f32>(0.002, 0.0) * newFreeze, 0.0).b;

        var crystalColor = vec3<f32>(r, g_val, b);

        // Ice tint based on thickness/freeze amount
        let iceTint = mix(vec3<f32>(1.0), vec3<f32>(0.85, 0.92, 1.0), newFreeze);
        crystalColor = crystalColor * iceTint;

        // ═══════════════════════════════════════════════════════════════
        // Physical Transmission Calculation
        // ═══════════════════════════════════════════════════════════════
        
        // Angle to crystal surface (approximate from distance to center)
        let distToCenter = minLoading; // 0 at center, ~0.5 at edge
        let cosTheta = 1.0 - distToCenter; // Approximate: 1 = face-on, 0 = edge
        
        // Fresnel reflection at ice surface
        let fresnel = fresnelSchlick(cosTheta, F0);
        
        // Path length through crystal cell (longer at edges)
        let pathLength = mix(0.1, 0.5, distToCenter) * newFreeze;
        
        // Absorption based on path length and purity
        let absorptionCoeff = mix(0.5, 3.0, 1.0 - cellPurity);
        let absorption = exp(-absorptionCoeff * pathLength);
        
        // Transmission coefficient
        let transmission = absorption * (1.0 - fresnel) * cellPurity;
        
        // Facet brightness for gem look
        let facet = smoothstep(0.0, 1.0, 1.0 - minLoading);
        
        // Blend between original and crystal based on freeze
        // Alpha represents how much light passes through (transmission)
        let crystalAlpha = mix(1.0, transmission, newFreeze);
        
        // Add specular highlights on crystal surfaces
        let specular = fresnel * newFreeze * 0.3;
        crystalColor += vec3<f32>(specular);
        
        finalColor = mix(finalColor, vec4<f32>(crystalColor * (0.8 + facet * 0.4), 1.0), newFreeze);
        transmissionAlpha = crystalAlpha;
    }

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor.rgb, transmissionAlpha));

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
