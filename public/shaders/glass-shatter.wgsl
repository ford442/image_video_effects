// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Use for persistence/trail history
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Glass Shatter Shader
// Param1: Shard Scale (Density)
// Param2: Displacement Strength (Mouse influence)
// Param3: Edge Thickness / Crack visibility
// Param4: Chromatic Aberration

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// Returns vec3(minDist, cellIndex, centerOfCell)
// Actually we need the center to calculate displacement
struct VoronoiResult {
    dist: f32,
    id: vec2<f32>,
    center: vec2<f32>
};

fn voronoi(uv: vec2<f32>, scale: f32) -> VoronoiResult {
    let g = floor(uv * scale);
    let f = fract(uv * scale);

    var res = VoronoiResult(8.0, vec2<f32>(0.0), vec2<f32>(0.0));

    for(var y: i32 = -1; y <= 1; y = y + 1) {
        for(var x: i32 = -1; x <= 1; x = x + 1) {
            let lattice = vec2<f32>(f32(x), f32(y));
            let offset = hash22(g + lattice);
            let p = lattice + offset - f;
            let d = dot(p, p);

            if(d < res.dist) {
                res.dist = d;
                res.id = g + lattice;
                res.center = (g + lattice + offset) / scale; // Back to UV space
            }
        }
    }

    res.dist = sqrt(res.dist);
    return res;
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    let mousePos = u.zoom_config.yz;

    // Parameters
    let shardScale = u.zoom_params.x * 20.0 + 3.0;
    let displaceStr = u.zoom_params.y * 0.5;
    let edgeWidth = u.zoom_params.z * 0.1;
    let aberration = u.zoom_params.w * 0.05;

    // Voronoi for shards
    // Adjust UV for aspect ratio for consistent cell size
    let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
    let v = voronoi(aspectUV, shardScale);

    // Calculate vector from mouse to shard center
    let cellCenter = v.center;
    // We need to map cellCenter back to aspect-corrected UV space if it isn't already?
    // In voronoi function above, 'center' is returned in UV space (0-1 range approx if scale was handled right).
    // Actually, in the function: (g + lattice + offset) / scale.
    // If input was aspectUV, output is in aspectUV space.

    // Distance from mouse to the CENTER of the shard (so whole shard moves together)
    let mouseVec = cellCenter - vec2<f32>(mousePos.x * aspect, mousePos.y);
    let dist = length(mouseVec);

    // Repulsion force
    var offset = vec2<f32>(0.0);
    if (dist < 0.5 && dist > 0.001) {
        let force = (1.0 - smoothstep(0.0, 0.5, dist)) * displaceStr;
        offset = normalize(mouseVec) * force;
    }

    // Each shard might have a slight random tilt/offset based on its ID
    let randOffset = (hash22(v.id) - 0.5) * 0.02 * displaceStr;

    // Final sampling UV
    // We apply the offset to the texture coordinates.
    // To make it look like the shard is moving *away*, we sample *backwards*?
    // If shard moves Right, we see pixels from Left. So UV - offset.
    let finalUV = uv - offset - randOffset;

    // Edge detection (distance to cell border)
    // To find borders properly in Voronoi is expensive (checking 2nd closest).
    // Cheap cheat: use the distance field gradient or just a threshold on v.dist?
    // v.dist is distance to center. It's max at edges? No, min at center.
    // Actually 2nd pass voronoi for borders is better but slow.
    // Let's rely on the discontinuity of UVs to create "edges" naturally, or just darken based on v.dist if we want smooth borders.
    // But glass shards have sharp edges.

    // Let's add chromatic aberration by sampling channels with slight offsets
    var color: vec4<f32>;
    if (aberration > 0.001) {
        let r = textureSampleLevel(readTexture, u_sampler, clamp(finalUV + vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
        let g = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, clamp(finalUV - vec2<f32>(aberration, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b;
        color = vec4<f32>(r, g, b, 1.0);
    } else {
        color = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    }

    // Highlight edges - "Cheap" edge: if d(uv) is high?
    // Let's just add some "specular" based on the random tilt we calculated
    let lightDir = normalize(vec2<f32>(0.5, -0.5));
    let tilt = normalize(offset + randOffset + vec2<f32>(0.001)); // Avoid 0
    let light = dot(tilt, lightDir);
    color = color + max(light, 0.0) * 0.2; // Reflection

    // Darken cracks?
    // We don't have true distance-to-edge here.
    // But we can visualize the ID change? No.

    textureStore(writeTexture, global_id.xy, color);
}
