// ═══════════════════════════════════════════════════════════════
//  Honey Melt - Image Effect with Viscous Honey Material Properties
//  Category: image
//  Features: Viscous honey, light transmission, amber translucency
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Scale, y=Radius, z=Distort, w=Softness
  ripples: array<vec4<f32>, 50>,
};

// Honey Material Properties
const HONEY_DENSITY: f32 = 1.4;           // Honey is denser than water
const HONEY_SCATTERING: f32 = 2.0;        // Strong forward scattering
const AMBER_ABSORPTION: vec3<f32> = vec3<f32>(0.3, 0.15, 0.5); // Amber absorbs blue most
const THICK_HONEY_ALPHA: f32 = 0.82;      // Thick honey is semi-opaque
const THIN_HONEY_ALPHA: f32 = 0.45;       // Thin honey is translucent

fn hash2(p: vec2<f32>) -> vec2<f32> {
    var p2 = vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(dot(hash2(i + vec2<f32>(0.0, 0.0)), f - vec2<f32>(0.0, 0.0)),
                   dot(hash2(i + vec2<f32>(1.0, 0.0)), f - vec2<f32>(1.0, 0.0)), u.x),
               mix(dot(hash2(i + vec2<f32>(0.0, 1.0)), f - vec2<f32>(0.0, 1.0)),
                   dot(hash2(i + vec2<f32>(1.0, 1.0)), f - vec2<f32>(1.0, 1.0)), u.x), u.y);
}

// Calculate honey thickness from hex cell bulge
fn calculateHoneyThickness(len: f32, bulge: f32) -> f32 {
    // Honey thickness is highest at center of hex, thins at edges
    let centerThickness = (1.0 - len * 0.5) * bulge;
    return max(0.05, centerThickness);
}

// Honey subsurface scattering (amber glow)
fn honeySSS(viewDir: vec3<f32>, lightDir: vec3<f32>, thickness: f32) -> vec3<f32> {
    // Strong forward scattering through honey
    let forwardDot = max(0.0, dot(viewDir, -lightDir));
    let forwardScatter = pow(forwardDot, 3.0) * HONEY_SCATTERING;
    
    // Amber honey color
    let honeyColor = vec3<f32>(1.0, 0.7, 0.15);
    
    // Beer-Lambert absorption (amber absorbs blue most)
    let absorption = exp(-thickness * HONEY_DENSITY * AMBER_ABSORPTION);
    
    // Backlit honey glows golden
    let backlit = vec3<f32>(1.0, 0.85, 0.3) * absorption * forwardScatter;
    
    return honeyColor * absorption + backlit * 0.5;
}

// Calculate alpha for honey based on thickness
fn calculateHoneyAlpha(thickness: f32, meltFactor: f32) -> f32 {
    // Solid honeycomb is more opaque, melted honey varies
    let solidAlpha = mix(0.9, THICK_HONEY_ALPHA, meltFactor * 0.5);
    
    // Melted honey transparency varies with thickness
    let meltedAlpha = mix(THIN_HONEY_ALPHA, THICK_HONEY_ALPHA, thickness * 2.0);
    
    // Blend based on melt state
    let alpha = mix(solidAlpha, meltedAlpha, meltFactor);
    
    // Beer-Lambert absorption
    let absorption = exp(-thickness * HONEY_DENSITY * 0.3);
    let finalAlpha = mix(THIN_HONEY_ALPHA, alpha, absorption);
    
    return clamp(finalAlpha, 0.35, 0.92);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);
    var mousePos = u.zoom_config.yz;

    // Params
    let gridSize = mix(10.0, 80.0, u.zoom_params.x);
    let meltRadius = u.zoom_params.y * 0.5;
    let distortStr = u.zoom_params.z;
    let softness = u.zoom_params.w;
    let time = u.config.x;

    // --- Hex Grid Logic ---
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let uvScaled = uv * aspectVec * gridSize;
    let uvA = uvScaled / r;
    let idA = floor(uvA + 0.5);
    let uvB = (uvScaled - h) / r;
    let idB = floor(uvB + 0.5);
    let centerA = idA * r;
    let centerB = idB * r + h;
    let distA = distance(uvScaled, centerA);
    let distB = distance(uvScaled, centerB);
    var center = select(centerB, centerA, distA < distB);
    let localVec = uvScaled - center;

    // Grid UV (Center of hex)
    let gridUV = center / gridSize / aspectVec;

    // --- Melt Interaction ---
    let centerScreen = gridUV * aspectVec;
    let mouseScreen = mousePos * aspectVec;
    let distToMouse = distance(centerScreen, mouseScreen);

    // Melt Factor: 1.0 = Fully Melted (Near mouse), 0.0 = Solid (Far)
    let melt = 1.0 - smoothstep(meltRadius, meltRadius + softness + 0.01, distToMouse);

    // --- Rendering ---

    // 1. Solid State: Distorted UV inside hex to look like a lens/honey drop
    let len = length(localVec);
    let bulge = localVec * (1.0 - len * 0.8);
    let solidUV = (center + bulge) / gridSize / aspectVec;

    // Golden rim/highlight for honeycomb look
    let rim = smoothstep(0.4, 0.5, len);

    // 2. Melted State: Fluid distortion
    let noiseVal = noise(uv * 10.0 + time * 0.5);
    let fluidUV = uv + vec2<f32>(noiseVal, -noiseVal) * 0.05 * distortStr;

    // Sample colors
    var colSolid = textureSampleLevel(readTexture, u_sampler, solidUV, 0.0);
    // Golden tint for solid honey
    colSolid = mix(colSolid, vec4<f32>(1.0, 0.75, 0.15, 1.0), 0.25);
    colSolid = mix(colSolid, vec4<f32>(0.3, 0.15, 0.0, 1.0), rim * 0.6);

    let colFluid = textureSampleLevel(readTexture, u_sampler, fluidUV, 0.0);

    // Calculate honey thickness at this point
    let honeyThickness = calculateHoneyThickness(len, 1.0 - rim * 0.5);
    
    // Apply honey SSS to solid cells
    let lightDir = normalize(vec3<f32>(0.5, 0.8, 0.3));
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    let honeyColor = honeySSS(viewDir, lightDir, honeyThickness);
    
    // Blend honey color with solid
    colSolid = mix(colSolid, vec4<f32>(honeyColor, colSolid.a), 0.4 * (1.0 - melt));

    // Final Mix
    let finalColor = mix(colSolid, colFluid, melt);
    
    // Calculate honey alpha
    let honeyAlpha = calculateHoneyAlpha(honeyThickness, melt);
    
    // Blend alpha between solid (more opaque) and melted (varies)
    let finalAlpha = mix(honeyAlpha, mix(honeyAlpha, 0.7, 0.3), melt * 0.5);

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(finalColor.rgb, finalAlpha));
}
