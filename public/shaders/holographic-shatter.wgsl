// --- COPY PASTE THIS HEADER INTO EVERY NEW SHADER ---
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
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Holographic Shatter
// P1: Cell Scale
// P2: Hologram Intensity (Scanlines + Color Shift)
// P3: Displacement (Mouse Influence)
// P4: Glitch Speed

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

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
                res.center = (g + lattice + offset) / scale;
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
    let scale = u.zoom_params.x * 30.0 + 5.0;
    let holoIntensity = u.zoom_params.y;
    let displaceStr = u.zoom_params.z;
    let speed = u.zoom_params.w * 5.0;

    // Voronoi Grid
    let aspectUV = vec2<f32>(uv.x * aspect, uv.y);
    let v = voronoi(aspectUV, scale);

    // Mouse Interaction
    let cellCenter = v.center;
    let mouseVec = cellCenter - vec2<f32>(mousePos.x * aspect, mousePos.y);
    let distToMouse = length(mouseVec);

    // Animate shard offset
    var offset = vec2<f32>(0.0);
    var active = 0.0;

    // Only affect shards near mouse
    if (distToMouse < 0.4 && distToMouse > 0.001) {
        let falloff = 1.0 - smoothstep(0.0, 0.4, distToMouse);
        active = falloff;

        // Push shards away and rotate slightly
        let dir = normalize(mouseVec);
        offset = dir * falloff * displaceStr * 0.2;

        // Add some jitter based on ID
        let jitter = (hash22(v.id) - 0.5) * 0.05 * falloff * displaceStr;
        offset = offset + jitter;
    }

    let finalUV = clamp(uv - offset, vec2<f32>(0.0), vec2<f32>(1.0));
    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    // Apply Holographic Effect to "active" shards or all shards with low intensity
    // Scanlines
    let scanPos = (uv.y + uv.x * 0.1) * 100.0 + u.config.x * speed;
    let scanline = sin(scanPos) * 0.5 + 0.5;

    // Interference color (Cyan/Magenta shift)
    if (holoIntensity > 0.0) {
        let idVal = v.id.x * 12.9898 + v.id.y * 78.233;
        let shift = sin(u.config.x * speed + idVal) * 0.5 + 0.5;

        // Mix in scanline
        let holoColor = vec3<f32>(0.0, 1.0, 1.0) * shift + vec3<f32>(1.0, 0.0, 1.0) * (1.0 - shift);

        // Effect strength blends based on mouse proximity (active) + base intensity
        let effectStr = max(active * displaceStr * 2.0, holoIntensity * 0.3);

        // Additive blend with scanline modulation
        color = color + vec4<f32>(holoColor * effectStr * scanline, 0.0);

        // Desaturate slightly to look more "digital"
        let gray = dot(color.rgb, vec3<f32>(0.299, 0.587, 0.114));
        color = mix(color, vec4<f32>(vec3<f32>(gray), color.a), effectStr * 0.5);
    }

    // Highlight edges of shards
    // Use the stored distance to center. If v.dist is large?
    // Actually in voronoi, v.dist is 0 at center.
    // We don't have edge distance.
    // But we can just use the activity to brighten the shards.
    if (active > 0.0) {
        color = color + vec4<f32>(0.1, 0.1, 0.2, 0.0) * active;
    }

    textureStore(writeTexture, global_id.xy, color);
}
