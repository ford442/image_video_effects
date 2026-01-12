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

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    let size = u.zoom_params.x * 0.15 + 0.01;
    let refrStrength = u.zoom_params.y * 0.2;
    let count = i32(u.zoom_params.z * 15.0) + 1;
    let wobble = u.zoom_params.w;

    let aspect = resolution.x / resolution.y;

    var finalUV = uv;
    var inBubble = false;
    var normal = vec2<f32>(0.0);

    for (var i = 0; i < count; i++) {
        let fi = f32(i);
        // Orbit around mouse
        // Add some complexity to orbits so they aren't all lines
        let angle = time * (wobble + 0.1) * (fi * 0.5 + 1.0) + fi * 137.5;
        let radius = 0.05 + fi * 0.03;

        // Wobble radius
        let rWobble = sin(time * 2.0 + fi) * 0.02 * wobble;

        let offset = vec2<f32>(cos(angle), sin(angle)) * (radius + rWobble);
        let bubblePos = mouse + offset * vec2<f32>(1.0, aspect);

        // Distance to this bubble center
        let dVec = (uv - bubblePos) * vec2<f32>(aspect, 1.0);
        let d = length(dVec);

        if (d < size) {
            // Simple sphere normal approximation (Z component)
            let z = sqrt(max(0.0, size*size - d*d));

            // XY Normal component
            let nXY = dVec / size;
            normal = nXY;

            // Refract: displace UV based on normal
            // Scale by Z to fake lens thickness
            finalUV = uv - nXY * refrStrength * (z / size);
            inBubble = true;
            // Break? No, bubbles might overlap, let's take the last one or blend?
            // Simple overwrite for now.
        }
    }

    var color = textureSampleLevel(readTexture, u_sampler, finalUV, 0.0);

    if (inBubble) {
        // Add specular highlight
        let lightDir = normalize(vec2<f32>(-0.5, -0.5));
        let specBase = max(dot(normal, lightDir), 0.0);
        let spec = pow(specBase, 15.0);
        color = color + vec4<f32>(spec, spec, spec, 0.0) * 0.8;

        // Fresnel edge
        let fresnel = pow(length(normal), 3.0);
        color = mix(color, vec4<f32>(0.8, 0.9, 1.0, 1.0), fresnel * 0.3);
    }

    textureStore(writeTexture, global_id.xy, color);
}
