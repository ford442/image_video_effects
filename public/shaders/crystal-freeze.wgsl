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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let aspect = resolution.x / resolution.y;

    // Params
    let decay = u.zoom_params.x; // Default 0.99
    let crystalScale = 10.0 + u.zoom_params.y * 40.0; // 10 to 50
    let refraction = u.zoom_params.z * 0.1; // Strength
    let brushRadius = 0.05 + u.zoom_params.w * 0.1;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);

    // Update Freeze State (Persistence)
    // Read previous state from dataTextureC (channel R)
    let oldFreeze = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0).r;

    // Mouse interaction
    let distVec = (uv - mouse) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let brush = smoothstep(brushRadius, brushRadius * 0.5, dist); // 1.0 at center, 0 at edge

    // New freeze value: max of decayed old value and new brush input
    let newFreeze = max(oldFreeze * decay, brush);

    // Write state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newFreeze, 0.0, 0.0, 1.0));

    // Crystal Effect Logic (Voronoi)
    var finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    if (newFreeze > 0.01) {
        // Simple Voronoi
        let g = floor(uv * crystalScale);
        let f = fract(uv * crystalScale);

        var minLoading = 1.0;
        var center = vec2<f32>(0.0);

        // 3x3 search
        for (var y: i32 = -1; y <= 1; y++) {
            for (var x: i32 = -1; x <= 1; x++) {
                let lattice = vec2<f32>(f32(x), f32(y));
                let offset = hash22(g + lattice);
                let dist = distance(lattice + offset, f);

                if (dist < minLoading) {
                    minLoading = dist;
                    center = lattice + offset;
                }
            }
        }

        // Calculate vector from pixel to cell center
        let toCenter = (center - f) / crystalScale;

        // Refraction vector
        let refractUV = uv + toCenter * refraction * newFreeze;

        // Chromatic Aberration based on freeze intensity
        let r = textureSampleLevel(readTexture, u_sampler, refractUV + vec2<f32>(0.002, 0.0) * newFreeze, 0.0).r;
        let g_val = textureSampleLevel(readTexture, u_sampler, refractUV, 0.0).g;
        let b = textureSampleLevel(readTexture, u_sampler, refractUV - vec2<f32>(0.002, 0.0) * newFreeze, 0.0).b;

        let crystalColor = vec4<f32>(r, g_val, b, 1.0);

        // Add some specular highlight on edges (distance to center close to something?)
        // Actually minLoading is distance to center. The edges are where minLoading is large? No, max loading is at corners.
        // Voronoi edges are where the distance to the two closest centers is equal.
        // But for visual flair, we can just use the distance `minLoading` to darken the center or lighten the edge?
        // Let's lighten the center for a "gem" look.

        // Actually, let's just use minLoading. 0 at center, 0.5+ at edges.
        let facet = smoothstep(0.0, 1.0, 1.0 - minLoading);

        finalColor = mix(finalColor, crystalColor * (0.8 + facet * 0.4), newFreeze);
    }

    textureStore(writeTexture, global_id.xy, finalColor);

    // Pass depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
