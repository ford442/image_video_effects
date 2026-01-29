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
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

// Random / Noise functions
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i + vec2<f32>(0.0, 0.0)), hash12(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(hash12(i + vec2<f32>(0.0, 1.0)), hash12(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

fn sobel(uv: vec2<f32>, res: vec2<f32>) -> f32 {
    let x = 1.0 / res.x;
    let y = 1.0 / res.y;

    // Sample luminance only
    let tl = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x, -y), 0.0).rgb, vec3(0.333));
    let t  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( 0.0, -y), 0.0).rgb, vec3(0.333));
    let tr = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x, -y), 0.0).rgb, vec3(0.333));
    let l  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x,  0.0), 0.0).rgb, vec3(0.333));
    let r  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x,  0.0), 0.0).rgb, vec3(0.333));
    let bl = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2(-x,  y), 0.0).rgb, vec3(0.333));
    let b  = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( 0.0,  y), 0.0).rgb, vec3(0.333));
    let br = dot(textureSampleLevel(readTexture, u_sampler, uv + vec2( x,  y), 0.0).rgb, vec3(0.333));

    let gx = tl * -1.0 + tr * 1.0 + l * -2.0 + r * 2.0 + bl * -1.0 + br * 1.0;
    let gy = tl * -1.0 + t * -2.0 + tr * -1.0 + bl * 1.0 + b * 2.0 + br * 1.0;

    return sqrt(gx * gx + gy * gy);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let time = u.config.x;
    let mouse = u.zoom_config.yz;

    // Params
    let radiusBase = u.zoom_params.x * 0.4 + 0.1; // Portal Size
    let glitchSpeed = u.zoom_params.y * 5.0 + 1.0; // Jitter Speed
    let edgeNoiseScale = 10.0;

    // Portal Shape
    // Correct for aspect ratio for circular portal
    let uvAspect = vec2<f32>(uv.x * aspect, uv.y);
    let mouseAspect = vec2<f32>(mouse.x * aspect, mouse.y);

    // Angle for noise
    let angle = atan2(uvAspect.y - mouseAspect.y, uvAspect.x - mouseAspect.x);
    // Noise offset based on angle and time
    let n = noise(vec2<f32>(angle * 3.0, time * glitchSpeed));
    // Add high freq noise
    let n2 = noise(vec2<f32>(angle * 20.0, time * glitchSpeed * 2.0));

    let radius = radiusBase + (n * 0.1) + (n2 * 0.02);

    let dist = distance(uvAspect, mouseAspect);

    var color = vec3<f32>(0.0);

    // Smoothstep for anti-aliased edge
    let edgeWidth = 0.02;
    let portalMask = 1.0 - smoothstep(radius, radius + edgeWidth, dist);
    let borderMask = smoothstep(radius, radius + edgeWidth * 0.5, dist) - smoothstep(radius + edgeWidth * 0.5, radius + edgeWidth, dist);
    // Actually border is just the transition area
    // Let's make a distinct glowing border
    let glow = exp(-abs(dist - radius) * 20.0);

    if (portalMask > 0.01) {
        // Inside Portal: Cyber View
        let edge = sobel(uv, resolution);

        // Scanlines
        let scanline = sin(uv.y * resolution.y * 0.5 + time * 5.0) * 0.5 + 0.5;
        let scanlineEffect = mix(0.8, 1.0, scanline);

        // Grid
        let grid = step(0.98, fract(uv.x * 20.0)) + step(0.98, fract(uv.y * 20.0));

        // Matrix Green / Cyan Palette
        let cyberColor = vec3<f32>(0.0, edge * 2.0, edge * 0.5); // Green dominant
        let gridColor = vec3<f32>(0.0, 0.5, 0.5) * grid * 0.3;

        let insideColor = (cyberColor + gridColor) * scanlineEffect;

        // Add original image faintly
        let orig = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
        let finalInside = mix(insideColor, orig * vec3<f32>(0.0, 1.0, 0.0), 0.5); // Tinted original

        if (portalMask >= 0.99) {
            color = finalInside;
        } else {
             // Blend with outside
             let outsideColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
             color = mix(outsideColor, finalInside, portalMask);
        }
    } else {
        // Outside: Normal
        color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    }

    // Add Glowing Edge
    let edgeColor = vec3<f32>(0.2, 1.0, 0.8); // Cyan Glow
    color += edgeColor * glow * 2.0;

    textureStore(writeTexture, global_id.xy, vec4<f32>(color, 1.0));

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
