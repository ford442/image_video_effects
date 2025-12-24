// ---------------------------------------------------------------
//  Pixel Storm – Mouse-driven chaos
// ---------------------------------------------------------------
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
  config:      vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,       // x=time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,       // x=Strength, y=Chaos, z=Trail, w=Radius
  ripples:     array<vec4<f32>, 50>,
};

fn hash12(p: vec2<f32>) -> f32 {
	var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8,8,1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;

    // Params
    let strength = u.zoom_params.x * 0.05; // Max displacement per frame
    let chaos = u.zoom_params.y;
    let trail = u.zoom_params.z; // 0=no history (clear), 1=full history
    let radiusParam = u.zoom_params.w * 0.5 + 0.05; // Effect radius

    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;

    // Read previous state (history of displacement) or just prev image?
    // Let's make it so pixels drift. We read from the location where the pixel CAME FROM.
    // But compute shader writes to specific pixel.
    // So we calculate "where do I sample from?" (inverse advection).

    let aspect = resolution.x / resolution.y;
    let dx = (uv.x - mousePos.x) * aspect;
    let dy = uv.y - mousePos.y;
    let dist = sqrt(dx*dx + dy*dy);

    // Wind vector (blows away from mouse)
    var wind = vec2<f32>(0.0);
    if (dist < radiusParam) {
        let dir = normalize(vec2<f32>(dx, dy));
        let force = (1.0 - dist/radiusParam); // Stronger at center
        wind = dir * force * strength;

        // Add chaos
        if (chaos > 0.0) {
            let noise = hash12(uv * 100.0 + time) - 0.5;
            let angle = noise * 6.28 * chaos;
            let c = cos(angle);
            let s = sin(angle);
            // Rotate wind
            wind = vec2<f32>(wind.x*c - wind.y*s, wind.x*s + wind.y*c);
        }
    }

    // If mouse down, suck in? Or blow harder? Let's reverse direction (suck in black hole style)
    if (mouseDown > 0.5) {
        wind = -wind * 2.0;
    }

    // Where to sample from? (uv - wind)
    let samplePos = uv - wind;

    // Sample current video frame (fresh pixels)
    let fresh = textureSampleLevel(readTexture, u_sampler, samplePos, 0.0).rgb;

    // Sample history (previous displaced pixels)
    // We also advect the history?
    // If we just read history at 'samplePos', we get the smear.
    let history = textureSampleLevel(dataTextureC, non_filtering_sampler, samplePos, 0.0).rgb;

    // Mix fresh and history based on Trail parameter
    // If Trail is high, we see mostly history (smear). If low, we see fresh video.
    // But we only want history where the effect is happening?
    // Let's mix globally.
    // Trail 1.0 = infinite feedback (don't update with fresh unless we have to?)
    // Usually mix(fresh, history, trail)

    var outCol = mix(fresh, history, trail * 0.95); // Limit max trail to avoid total freeze

    // If wind is zero, we should probably just show fresh video to reset?
    // Or if trail is high, the screen freezes.
    // Let's fade to fresh if no wind?
    if (length(wind) < 0.0001) {
       outCol = mix(outCol, fresh, 0.1); // Slow recovery
    }

    // Store
    textureStore(writeTexture, gid.xy, vec4<f32>(outCol, 1.0));

    // Store for history (dataTextureA is next frame's C)
    textureStore(dataTextureA, gid.xy, vec4<f32>(outCol, 1.0));

    // Passthrough depth
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
