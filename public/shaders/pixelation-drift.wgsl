// ---------------------------------------------------------------
//  Pixelation Drift – dynamic pixelated mosaic that drifts
//  Creates chunky pixels that slowly drift and morph over time
//  with depth-aware pixel sizing and color bleeding
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
// ---------------------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=time, y=frame, z=resX, w=resY
  zoom_config: vec4<f32>,  // x=mouseX, y=mouseY, z=unused, w=unused
  zoom_params: vec4<f32>,  // x=pixelSize, y=driftSpeed, z=colorBleed, w=depthInfluence
  ripples: array<vec4<f32>, 50>,
};

// ---------------------------------------------------------------
//  Noise function for organic drift
// ---------------------------------------------------------------
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, vec3<f32>(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

// ---------------------------------------------------------------
//  Constants
// ---------------------------------------------------------------
const PIXEL_SIZE_SCALE: f32 = 100.0;  // Scaling factor for pixel size parameter

// ---------------------------------------------------------------
//  Main compute shader
// ---------------------------------------------------------------
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    
    // Get depth for depth-aware pixelation
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    
    // Parameters from uniform
    let basePixelSize = max(u.zoom_params.x, 0.01) * PIXEL_SIZE_SCALE;  // Base pixel size (1-100)
    let driftSpeed = u.zoom_params.y;  // Drift speed (0-1)
    let colorBleed = u.zoom_params.z;  // Color bleeding (0-1)
    let depthInfluence = u.zoom_params.w;  // How much depth affects pixel size (0-1)
    
    // Depth-aware pixel size - foreground gets smaller pixels
    let depthFactor = mix(1.0, 1.0 - depth * 0.7, depthInfluence);
    let pixelSize = basePixelSize * depthFactor;
    
    // Create drift offset using noise
    let driftScale = 5.0;
    let driftOffset = vec2<f32>(
        noise(uv * driftScale + vec2<f32>(time * driftSpeed * 0.2, 0.0)),
        noise(uv * driftScale + vec2<f32>(0.0, time * driftSpeed * 0.2))
    ) * 2.0 - 1.0;
    
    // Apply drift to UV
    let driftedUV = uv + driftOffset * 0.02 * driftSpeed;
    
    // Pixelate the drifted UV
    let pixelatedUV = floor(driftedUV * resolution / pixelSize) * pixelSize / resolution;
    
    // Sample the pixelated position
    var color = textureSampleLevel(readTexture, u_sampler, pixelatedUV, 0.0);
    
    // Add color bleeding effect
    if (colorBleed > 0.01) {
        let bleedOffset = vec2<f32>(
            sin(time * 0.5 + uv.y * 10.0),
            cos(time * 0.5 + uv.x * 10.0)
        ) * pixelSize / resolution * colorBleed * 2.0;
        
        let bleedColor = textureSampleLevel(readTexture, u_sampler, pixelatedUV + bleedOffset, 0.0);
        color = mix(color, bleedColor, colorBleed * 0.3);
    }
    
    // Add subtle edge glow based on pixel boundaries
    let pixelCenter = (floor(driftedUV * resolution / pixelSize) + 0.5) * pixelSize / resolution;
    let distToCenter = length((driftedUV - pixelCenter) * resolution);
    let edgeGlow = smoothstep(pixelSize * 0.4, pixelSize * 0.5, distToCenter);
    color = vec4<f32>(mix(color.rgb, color.rgb * 1.2, edgeGlow * 0.1), color.a);
    
    // Temporal persistence for smoother transitions
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0);
    let persistence = 0.85;
    let blended = mix(color, prev, persistence);
    textureStore(dataTextureA, gid.xy, blended);
    
    // Output
    textureStore(writeTexture, gid.xy, color);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
