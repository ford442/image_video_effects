@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>; // Write New State
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Read Old State
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,       // x=Time
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=IsMouseDown
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Paper Burn Interactive
// Param1: Burn Speed
// Param2: Spread Speed (Diffusion)
// Param3: Char Width (Edge darkness)
// Param4: Reset/Regrow (If > 0.5, clears burn)

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;

    let burnSpeed = u.zoom_params.x * 0.1;
    let spreadSpeed = u.zoom_params.y * 2.0; // Pixel radius
    let charWidth = u.zoom_params.z;
    let reset = u.zoom_params.w;

    // Read previous burn state (R channel)
    // 0.0 = paper, 1.0 = burnt hole
    var burnVal = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).r;

    if (reset > 0.5) {
        burnVal = 0.0;
    }

    // Mouse Interaction: Start fire
    // Only burn if mouse is down? Or always? Let's say always if close, but stronger if down.
    if (mousePos.x >= 0.0) {
        let aspect = resolution.x / resolution.y;
        let d = vec2<f32>((uv.x - mousePos.x) * aspect, uv.y - mousePos.y);
        let dist = length(d);
        let brushSize = 0.05;

        if (dist < brushSize) {
            let intensity = 1.0 - smoothstep(brushSize * 0.5, brushSize, dist);
            burnVal += intensity * burnSpeed * 2.0;
        }
    }

    // Diffusion / Spread
    // Sample neighbors to spread the fire
    // Since we are in compute shader, we can sample texture C arbitrarily.
    // Simple box blur spread logic
    let pixelSize = 1.0 / resolution;
    var avgNeighbor = 0.0;

    // Small kernel for performance
    let offsets = array<vec2<f32>, 4>(
        vec2<f32>(1.0, 0.0), vec2<f32>(-1.0, 0.0),
        vec2<f32>(0.0, 1.0), vec2<f32>(0.0, -1.0)
    );

    for (var i = 0; i < 4; i++) {
        avgNeighbor += textureSampleLevel(dataTextureC, u_sampler, uv + offsets[i] * pixelSize * spreadSpeed, 0.0).r;
    }
    avgNeighbor /= 4.0;

    // If neighbors are burning, catch fire
    // Threshold: if neighbor > 0.1, we start increasing slowly
    if (avgNeighbor > 0.1) {
        burnVal += burnSpeed * 0.2;
    }

    burnVal = clamp(burnVal, 0.0, 1.0);

    // Store new state
    textureStore(dataTextureA, global_id.xy, vec4<f32>(burnVal, 0.0, 0.0, 1.0));

    // Render
    let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

    // Visual mapping
    // Burn < 0.5: Darkening/Charring
    // Burn > 0.5: Disintegrating/Transparent

    var finalColor = imgColor.rgb;
    var alpha = 1.0;

    // Edge charring
    // Create a gradient for the edge
    let edge = smoothstep(0.4, 0.6, burnVal); // 0 at 0.4, 1 at 0.6

    // Char color (dark brown/black)
    let charColor = vec3<f32>(0.1, 0.05, 0.0);

    // Fire color at the very edge of the burn
    // Active burning happens where burnVal is increasing? Or just at the transition zone.
    let fireZone = smoothstep(0.45, 0.55, burnVal) * (1.0 - smoothstep(0.6, 0.7, burnVal));
    let fireColor = vec3<f32>(1.0, 0.6, 0.1) * 2.0; // Bright orange

    if (burnVal > 0.0) {
       // Mix image with char based on burnVal up to 0.5
       let charMix = smoothstep(0.0, 0.5, burnVal);
       finalColor = mix(finalColor, charColor, charMix);

       // Add fire glow
       finalColor += fireColor * fireZone;

       // Transparency/Black hole for fully burnt
       if (burnVal > 0.6) {
           finalColor = vec3<f32>(0.0); // Or transparent? Texture storage format is rgba32float.
           // Note: The render pipeline usually treats alpha=0 as transparent if blending is on.
           // But here we are writing to a texture that is later composited.
           // Let's set alpha to 0.
           alpha = 1.0 - smoothstep(0.6, 0.8, burnVal);
       }
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(finalColor, alpha));

    // Passthrough depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
