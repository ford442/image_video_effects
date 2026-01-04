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
  config: vec4<f32>;       // x=time, y=unused, z=resX, w=resY
  zoom_config: vec4<f32>;  // x=zoomTime, y=centerX, z=centerY, w=depth_threshold
  zoom_params: vec4<f32>;  // x=fg_speed, y=bg_speed, z=parallax_str, w=fog_density
  ripples: array<vec4<f32>, 50>;
};

// Mapping notes:
// - mouse in extraBuffer[8..9] if needed or use u.zoom_config.yz as center
// - comp_params.w (chromatic aberration) read from extraBuffer[0]

fn ping_pong(a: f32) -> f32 { return 1.0 - abs(fract(a * 0.5) * 2.0 - 1.0); }
fn ping_pong_v2(v: vec2<f32>) -> vec2<f32> { return vec2<f32>(ping_pong(v.x), ping_pong(v.y)); }

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 = p3 + (dot(p3, p3 + vec3<f32>(33.33)));
    return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u2 = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i + vec2<f32>(0.0, 0.0)), hash21(i + vec2<f32>(1.0, 0.0)), u2.x),
        mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), u2.x),
        u2.y
    );
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// Reconstruct a simple normal from depth samples
fn reconstruct_normal(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let offset = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
    let dx = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(offset.x, 0.0), 0.0).r - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(offset.x, 0.0), 0.0).r;
    let dy = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, offset.y), 0.0).r - textureSampleLevel(readDepthTexture, non_filtering_sampler, uv - vec2<f32>(0.0, offset.y), 0.0).r;
    let n = vec3<f32>(-dx, -dy, 1.0);
    return normalize(n);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = vec2<f32>(u.config.z, u.config.w);
    let uv = vec2<f32>(gid.xy) / resolution;
    let time = u.config.x;
    let zoom_time = u.zoom_config.x;
    let zoom_center = u.zoom_config.yz;

    let mousePos = vec2<f32>(u.zoom_config.y / resolution.x, u.zoom_config.z / resolution.y);
    let clickIntensity = if (arrayLength(&extraBuffer) > 10u) { extraBuffer[10] } else { 0.0 };

    var accumulatedColor = vec3<f32>(0.0);
    var accumulatedDepth = 0.0;
    var totalWeight = 0.0;

    let layers = 5;
    for (var i: i32 = 0; i < layers; i = i + 1) {
        let layerDepth = f32(i) / f32(layers - 1);
        let layerSpeed = mix(u.zoom_params.x, u.zoom_params.y, layerDepth);
        let layerZoom = 1.0 + fract(zoom_time * layerSpeed) * 4.0;

        // Vortex spin
        let toCenter = uv - zoom_center;
        let angle = atan2(toCenter.y, toCenter.x);
        let dist = length(toCenter);
        let vortexStrength = clickIntensity * 0.3 / (dist + 0.1);
        let spinAngle = vortexStrength * layerDepth * (1.0 - layerDepth);
        let rotatedUV = vec2<f32>(cos(spinAngle) * toCenter.x - sin(spinAngle) * toCenter.y, sin(spinAngle) * toCenter.x + cos(spinAngle) * toCenter.y) + zoom_center;

        // Plasma flow
        let flowScale = 6.0;
        let flowSpeed = 0.15;
        let nX = noise(rotatedUV * flowScale + vec2<f32>(time * flowSpeed, 0.0));
        let nY = noise(rotatedUV * flowScale + vec2<f32>(0.0, time * flowSpeed));
        let flowUV = rotatedUV + vec2<f32>(nX, nY) * 0.015 * layerDepth;

        // Zoom and sample
        let transformed = (flowUV - zoom_center) / layerZoom + zoom_center;
        let wrapped = ping_pong_v2(transformed);
        let sampleColor = textureSampleLevel(readTexture, u_sampler, wrapped, 0.0).rgb;
        let sampleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, wrapped, 0.0).r;

        let density = exp(-layerDepth * 1.5);
        let weight = density * (1.0 + sampleDepth * 0.5);

        accumulatedColor = accumulatedColor + sampleColor * weight;
        accumulatedDepth = accumulatedDepth + sampleDepth * weight;
        totalWeight = totalWeight + weight;
    }

    let baseColor = accumulatedColor / max(totalWeight, 0.0001);
    let baseDepth = accumulatedDepth / max(totalWeight, 0.0001);

    // Chromatic separation
    let chroma = if (arrayLength(&extraBuffer) > 0u) { extraBuffer[0] } else { 0.02 };
    let r = textureSampleLevel(readTexture, u_sampler, uv + vec2<f32>(chroma * baseDepth, 0.0), 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uv, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uv - vec2<f32>(chroma * baseDepth, 0.0), 0.0).b;
    let chromaticColor = vec3<f32>(r, g, b);

    // Edge glow
    let ps = vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y);
    let depthX = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(ps.x, 0.0), 0.0).r;
    let depthY = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv + vec2<f32>(0.0, ps.y), 0.0).r;
    let depthGrad = length(vec2<f32>(depthX - baseDepth, depthY - baseDepth));
    let edgeGlow = exp(-depthGrad * 30.0) * baseDepth * 2.0;

    let final = chromaticColor + vec3<f32>(edgeGlow, edgeGlow * 0.8, edgeGlow * 0.6);

    // Fog
    let fog = exp(-baseDepth * u.zoom_params.w * 3.0);
    let fogColor = vec3<f32>(0.02, 0.05, 0.1);
    let outColor = mix(final, fogColor, 1.0 - fog);

    textureStore(writeTexture, vec2<u32>(gid.xy), vec4<f32>(outColor, 1.0));
    textureStore(writeDepthTexture, vec2<u32>(gid.xy), vec4<f32>(baseDepth, 0.0, 0.0, 0.0));
}