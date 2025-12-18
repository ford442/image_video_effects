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

// Raindrop Ripples
// Param1: Rain Intensity
// Param2: Wave Decay (Damping)
// Param3: Wave Speed
// Param4: Mouse Shield Radius

// Hash function for random drops
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mousePos = u.zoom_config.yz;
    let aspect = resolution.x / resolution.y;

    // Params
    let rainIntensity = u.zoom_params.x; // Probability of new drop
    let decay = 0.9 + (u.zoom_params.y * 0.09); // 0.9 to 0.99
    let speed = u.zoom_params.z * 0.2 + 0.1;
    let shieldRadius = u.zoom_params.w * 0.3;

    // 1. Read previous state from dataTextureC (binding 9)
    // We store: r = height, g = prev_height (velocity implicit), b = unused, a = unused
    // Wait, typical wave eq: h_new = 2*h - h_prev + Laplacian * c
    // Or simplified buffer ripple:
    // current = (average_neighbors - current) * damping
    // But we need 2 buffers for that. We have dataTextureC (read) and dataTextureA (write).
    // And next frame dataTextureA becomes dataTextureC?
    // Yes, memory says "Renderer.ts executes a copy command from dataTextureA to dataTextureC at the end of the frame."

    // dataTextureC is a texture_2d<f32>, sampled
    // We should sample it at pixel center
    let oldState = textureSampleLevel(dataTextureC, non_filtering_sampler, uv, 0.0);
    let height = oldState.r;
    let prevHeight = oldState.g;

    // Laplacian (average of neighbors)
    let pixelSize = 1.0 / resolution;
    let n = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let s = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(0.0, pixelSize.y), 0.0).r;
    let e = textureSampleLevel(dataTextureC, non_filtering_sampler, uv + vec2<f32>(pixelSize.x, 0.0), 0.0).r;
    let w = textureSampleLevel(dataTextureC, non_filtering_sampler, uv - vec2<f32>(pixelSize.x, 0.0), 0.0).r;

    // Wave equation integration (Verlet-ish)
    // h_new = (n+s+e+w)/2 - h_prev
    // Then apply damping.
    // NOTE: This can be unstable if not tuned carefully.
    // Let's use a smoother kernel or simpler damping.
    var newHeight = (n + s + e + w) * 0.5 - prevHeight;
    newHeight = newHeight * decay;

    // 2. Add Rain drops
    // Use hash of (coord, time) to decide if a drop falls here
    // Coordinate needs to be coarse grid to avoid single-pixel spikes
    let gridSize = 20.0;
    let gridUV = floor(uv * resolution / gridSize); // Random drops on a grid
    // Hash includes time (quantized to frame or slower)
    let dropTime = floor(time * 60.0); // frames
    let rand = hash12(gridUV + vec2<f32>(dropTime * 12.34));

    if (rand > (1.0 - rainIntensity * 0.01)) { // very low probability per frame per grid block
        // Check if pixel is center of grid block to create a smooth spot
        // Actually, just add to height if we are close to grid center?
        // Let's just punch it.
        newHeight = newHeight + 5.0;
    }

    // 3. Mouse Interaction (Shield / Deflector)
    // If mouse is present, force height to 0 (or constant) in radius
    // Or create ripples? "Shield" sounds like it blocks rain.
    // If we clamp height to 0 inside radius, waves will reflect off it!
    if (mousePos.x >= 0.0 && shieldRadius > 0.0) {
        let dVec = uv - mousePos;
        let d = length(vec2<f32>(dVec.x * aspect, dVec.y));
        if (d < shieldRadius) {
            newHeight = newHeight * smoothstep(0.0, shieldRadius, d); // Dampen inside shield
            // Add a rim ripple at the edge?
            if (d > shieldRadius * 0.9) {
                 newHeight = newHeight + 0.1; // Small wake
            }
        }
    }

    // Clamp to prevent explosion
    newHeight = clamp(newHeight, -10.0, 10.0);

    // Write state for next frame
    // Store current height in R, and "current" becomes "prev" in G for next frame
    // wait: next frame: prevHeight = oldState.g (which is what we write to G now? No)
    // Formula: next_val = f(curr, prev).
    // Next frame: curr becomes prev.
    // So we write (newHeight, height(current), ...)
    textureStore(dataTextureA, global_id.xy, vec4<f32>(newHeight, height, 0.0, 1.0));

    // 4. Render
    // Calculate slope for refraction
    let slopeX = e - w;
    let slopeY = n - s;
    let distortion = vec2<f32>(slopeX, slopeY) * 0.05; // Strength

    let finalUV = uv + distortion;
    var color = textureSampleLevel(readTexture, u_sampler, clamp(finalUV, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    // Specular highlight
    let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
    let normal = normalize(vec3<f32>(-slopeX * 2.0, -slopeY * 2.0, 1.0));
    let spec = pow(max(dot(normal, lightDir), 0.0), 20.0);

    color = color + spec * 0.3;

    textureStore(writeTexture, global_id.xy, color);
}
