// ═══════════════════════════════════════════════════════════════
// Glass Shatter - Physical glass transmission with Beer-Lambert law
// Category: distortion
// Features: Voronoi shards, chromatic aberration, physically-based alpha
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=ShardScale, y=DisplacementStr, z=EdgeThickness, w=GlassDensity
  ripples: array<vec4<f32>, 50>,
};

struct VoronoiResult {
    dist: f32,
    id: vec2<f32>,
    center: vec2<f32>
};

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn voronoi(uv: vec2<f32>, scale: f32) -> VoronoiResult {
    var g = floor(uv * scale);
    let f = fract(uv * scale);

    var res = VoronoiResult(8.0, vec2<f32>(0.0), vec2<f32>(0.0));

    for(var y: i32 = -1; y <= 1; y = y + 1) {
        for(var x: i32 = -1; x <= 1; x = x + 1) {
            let lattice = vec2<f32>(f32(x), f32(y));
            var offset = hash22(g + lattice);
            var p = lattice + offset - f;
            let d = dot(p, p);

            if(d < res.dist) {
                res.dist = d;
                res.id = g + lattice;
                res.center = (g + lattice + offset) / scale;
            }
        }
    }

    res.dist = sqrt(res.dist);
    return res;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    var mousePos = u.zoom_config.yz;

    // Parameters
    let shardScale = u.zoom_params.x * 20.0 + 3.0;
    let displaceStr = u.zoom_params.y * 0.5;
    let edgeWidth = u.zoom_params.z * 0.1;
    let glassDensity = u.zoom_params.w * 2.0 + 0.5; // Beer-Lambert density

    // Voronoi for shards
    let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
    let v = voronoi(aspectUV, shardScale);

    // Calculate vector from mouse to shard center
    let cellCenter = v.center;
    let mouseVec = cellCenter - vec2<f32>(mousePos.x * aspect, mousePos.y);
    var dist = length(mouseVec);

    // Repulsion force
    var offset = vec2<f32>(0.0);
    if (dist < 0.5 && dist > 0.001) {
        let force = (1.0 - smoothstep(0.0, 0.5, dist)) * displaceStr;
        offset = normalize(mouseVec) * force;
    }

    // Each shard might have a slight random tilt/offset
    let randOffset = (hash22(v.id) - 0.5) * 0.02 * displaceStr;

    // Final sampling UV
    let finalUV = uv - offset - randOffset;

    // Calculate shard normal for fresnel effect
    let shardTilt = normalize(offset + randOffset + vec2<f32>(0.001));
    let normal = normalize(vec3<f32>(shardTilt * 2.0, 1.0));
    
    // View direction
    let viewDir = vec3<f32>(0.0, 0.0, 1.0);
    
    // Fresnel: more reflection at shard edges/tips
    let cos_theta = max(dot(viewDir, normal), 0.0);
    let R0 = 0.04;
    let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
    
    // Glass thickness varies by shard position (thinner at edges)
    let thickness = 0.05 + (1.0 - v.dist) * 0.1;
    
    // Glass absorption color (slight green tint)
    let glassColor = vec3<f32>(0.92, 0.98, 0.95);
    
    // Beer-Lambert law
    let absorption = exp(-(1.0 - glassColor) * thickness * glassDensity);
    
    // Transmission coefficient
    let transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;

    // Chromatic aberration by sampling channels with slight offsets
    let aberration = u.zoom_params.z * 0.05;
    var color: vec4<f32>;
    if (aberration > 0.001) {
        let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        var g = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
        color = vec4<f32>(r, g, b, transmission);
    } else {
        color = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
        color.a = transmission;
    }

    // Apply glass tint
    color = vec4<f32>(color.rgb * glassColor, transmission);

    // Highlight edges with specular
    let lightDir = normalize(vec2<f32>(0.5, -0.5));
    let tilt = normalize(offset + randOffset + vec2<f32>(0.001));
    let light = dot(tilt, lightDir);
    color = color + max(light, 0.0) * 0.2;

    textureStore(writeTexture, vec2<i32>(global_id.xy), color);
}
