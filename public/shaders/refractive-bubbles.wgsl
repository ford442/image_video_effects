// ═══════════════════════════════════════════════════════════════════
//  Refractive Bubbles
//  Category: distortion
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-05-23
// ═══════════════════════════════════════════════════════════════════

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let coord = vec2<i32>(global_id.xy);
    if (coord.x >= i32(resolution.x) || coord.y >= i32(resolution.y)) { return; }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    var mouse = u.zoom_config.yz;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    // Bass pulses bubble size and refraction strength
    let size = (u.zoom_params.x * 0.15 + 0.01) * (1.0 + bass * 0.3);
    let refrStrength = u.zoom_params.y * 0.2 * (1.0 + mids * 0.4);
    let count = i32(u.zoom_params.z * 15.0) + 1;
    let wobble = u.zoom_params.w;
    let glassDensity = 0.8 + u.zoom_params.w * 1.5;

    let aspect = resolution.x / resolution.y;

    var finalUV = uv;
    var inBubble = false;
    var bubbleNormal = vec3<f32>(0.0, 0.0, 1.0);
    var bubbleDepth = 0.0;
    var bubbleThickness = 0.0;
    var minBubbleDist = 9.9;

    for (var i = 0; i < count; i++) {
        let fi = f32(i);
        // Orbit around mouse
        let angle = time * (wobble + 0.1) * (fi * 0.5 + 1.0) + fi * 137.5;
        let radius = 0.05 + fi * 0.03;

        // Wobble radius
        let rWobble = sin(time * 2.0 + fi) * 0.02 * wobble;

        let offset = vec2<f32>(cos(angle), sin(angle)) * (radius + rWobble);
        let bubblePos = mouse + offset * vec2<f32>(1.0, aspect);

        // Distance to this bubble center
        let dVec = (uv - bubblePos) * vec2<f32>(aspect, 1.0);
        let d = length(dVec);
        minBubbleDist = min(minBubbleDist, d);

        if (d < size) {
            // Sphere normal approximation
            let z = sqrt(max(0.0, size*size - d*d));
            let nXY = dVec / size;
            bubbleNormal = normalize(vec3<f32>(nXY, z / size));
            bubbleDepth = z;
            
            // Refract: displace UV based on normal
            finalUV = uv - nXY * refrStrength * (z / size);
            inBubble = true;
            
            // Calculate bubble wall thickness (thin film approximation)
            // Bubbles have thin walls, thicker near edges
            bubbleThickness = 0.01 + (d / size) * 0.02;
        }
    }

    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    if (inBubble) {
        // View direction
        let viewDir = vec3<f32>(0.0, 0.0, 1.0);
        
        // Fresnel effect (strong at bubble edges)
        let cos_theta = max(dot(viewDir, bubbleNormal), 0.0);
        let R0 = 0.04; // Glass-air
        let fresnel = R0 + (1.0 - R0) * pow(1.0 - cos_theta, 5.0);
        
        // Thin-film interference would go here for soap bubbles
        // For glass bubbles, use Beer-Lambert
        
        // Bubble glass color (very slight tint)
        let bubbleColor = vec3<f32>(0.96, 0.98, 1.0);
        
        // Beer-Lambert for thin glass
        let absorption = exp(-(1.0 - bubbleColor) * bubbleThickness * glassDensity);
        
        // Transmission coefficient
        let transmission = (1.0 - fresnel) * (absorption.r + absorption.g + absorption.b) / 3.0;
        
        // Apply bubble tint and alpha
        color = vec4<f32>(color.rgb * bubbleColor, transmission);
        
        // Add specular highlight
        let lightDir = normalize(vec3<f32>(-0.5, -0.5, 1.0));
        let specBase = max(dot(bubbleNormal, lightDir), 0.0);
        let spec = pow(specBase, 15.0);
        color = color + vec4<f32>(spec, spec, spec, 0.0) * 0.8;

        // Fresnel edge enhancement
        let fresnelEdge = pow(length(bubbleNormal.xy), 3.0);
        color = mix(color, vec4<f32>(0.8, 0.9, 1.0, 1.0), fresnelEdge * 0.3);
    } else {
        // Outside bubble — alpha encodes proximity to nearest bubble edge
        let edgeProx = clamp(1.0 - minBubbleDist / max(size, 0.001) * 0.5, 0.0, 1.0) * 0.2 + bass * 0.05;
        color = vec4<f32>(color.rgb, clamp(edgeProx, 0.0, 1.0));
    }

    let depthVal = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeTexture, coord, color);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthVal, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, color);
}
