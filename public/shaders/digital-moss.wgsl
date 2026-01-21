struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 30>,
};

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var filteringSampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read> extraBuffer: array<f32>;
@group(0) @binding(11) var comparisonSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(16, 16)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let dims = vec2<i32>(textureDimensions(writeTexture));
    if (global_id.x >= u32(dims.x) || global_id.y >= u32(dims.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);

    // Uniforms
    let time = u.config.x;
    let mouse = u.zoom_config.yz;
    let aspect = f32(dims.x) / f32(dims.y);

    // Sample Image Luma
    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let luma = dot(imgColor, vec3<f32>(0.299, 0.587, 0.114));

    // Sample Previous Moss State from dataTextureC
    let oldState = textureLoad(dataTextureC, coord, 0).r;

    // Random seed that varies with time slightly for spontaneous growth
    let seed = hash12(uv + vec2<f32>(time * 0.1, time * 0.05));

    var grown = oldState;

    // 1. Spontaneous growth in very dark areas
    if (luma < 0.15 && seed > 0.995) {
        grown = 1.0;
    }

    // 2. Propagation (Cellular Automata-ish)
    // If not fully grown, check neighbors
    if (grown < 0.9) {
        // Sample a random neighbor based on noise
        let angle = hash12(uv * 10.0 + time) * 6.28;
        let dist = 2.0; // Check 2 pixels away
        let offset = vec2<f32>(cos(angle), sin(angle)) * dist;
        let neighborCoord = coord + vec2<i32>(offset);

        let neighborState = textureLoad(dataTextureC, clamp(neighborCoord, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;

        // If neighbor has moss and this area is dark enough, spread
        if (neighborState > 0.5 && luma < 0.4) {
             grown = min(1.0, grown + 0.05); // Slow growth
        }
    }

    // 3. Environmental Decay
    // Bright light kills the moss
    if (luma > 0.6) {
        grown *= 0.9;
    }

    // 4. Mouse Interaction (Cleaning)
    let p_aspect = vec2<f32>(uv.x * aspect, uv.y);
    let m_aspect = vec2<f32>(mouse.x * aspect, mouse.y);
    let mouseDist = length(p_aspect - m_aspect);

    // Mouse brush size
    if (mouseDist < 0.05) {
        grown = 0.0;
    }

    // Write State for next frame
    textureStore(dataTextureA, coord, vec4<f32>(grown, 0.0, 0.0, 1.0));

    // Render
    // Moss look: Digital Matrix Green with scanlines
    let scan = 0.8 + 0.2 * sin(uv.y * 500.0);
    let mossColor = vec3<f32>(0.1, 0.9, 0.3) * scan;

    // Mix based on growth
    let finalColor = mix(imgColor, mossColor, grown * 0.9);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, 1.0));
}
