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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=HexSize, y=GlowIntensity, z=RevealRadius, w=Generic
  ripples: array<vec4<f32>, 50>,
};

// Hexagon SDF (Distance from center to edge)
fn hexDist(p: vec2<f32>) -> f32 {
    var p2 = abs(p);
    // dot product with (1, sqrt(3)) normalized
    let c = dot(p2, normalize(vec2<f32>(1.0, 1.7320508)));
    return max(c, p2.x);
}

// Hexagon Grid Logic
// Returns: vec4(local_uv.x, local_uv.y, id.x, id.y)
fn hexCoords(uv: vec2<f32>) -> vec4<f32> {
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;

    let a = uv - (floor(uv / r + 0.5) * r);
    let b = uv - (floor((uv - h) / r + 0.5) * r + h);

    let gv = select(b, a, dot(a, a) < dot(b, b));
    let id = uv - gv;

    return vec4<f32>(gv.x, gv.y, id.x, id.y);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3  = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;

    // Correct aspect ratio for grid
    let aspect = resolution.x / resolution.y;
    let gridUV = vec2<f32>(uv.x * aspect, uv.y);
    let mousePos = u.zoom_config.yz;
    let mouseGridPos = vec2<f32>(mousePos.x * aspect, mousePos.y);

    // Params
    let hexSize = 20.0 + u.zoom_params.x * 50.0;
    let glowIntensity = u.zoom_params.y * 2.0;
    let revealRadius = 0.1 + u.zoom_params.z * 0.5;

    // Scale UV for hex grid
    let scaledUV = gridUV * hexSize;
    let hc = hexCoords(scaledUV);
    let localUV = hc.xy;
    let id = hc.zw;

    // Calculate hex center in world space (approx)
    let hexCenter = id / hexSize;

    // Distance from mouse to hex center
    let distToMouse = length(hexCenter - mouseGridPos);

    // Calculate "Openness" of the armor
    // Near mouse = Open (scale 0), Far = Closed (scale 1)
    // Add some noise/randomness to the opening
    let noise = hash12(id);
    let opening = smoothstep(revealRadius, revealRadius + 0.2 + noise * 0.1, distToMouse);

    // If mouse is offscreen, everything is closed
    let effectiveOpen = select(opening, 1.0, mousePos.x < 0.0);

    // Scale the hex visually based on openness
    // We want the hex to shrink as it opens
    let hexScale = effectiveOpen; // 0.0 to 1.0

    // SDF of hexagon
    // Radius of standard hex in this grid system is roughly 0.5 (h.y is 0.866)
    // Let's normalize it roughly
    let dist = hexDist(localUV);

    // Edge thickness
    let border = 0.05;
    let radius = 0.5 * hexScale - border;

    var finalColor = vec4<f32>(0.0);

    if (radius < 0.0) {
        // Hex is completely vanished
        finalColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    } else {
        // Smoothstep for anti-aliasing edge
        let edge = smoothstep(radius, radius + 0.05, dist);

        if (edge < 0.5) {
            // Inside Hex Armor
            // Create a tech texture
            let techColor = vec3<f32>(0.1, 0.12, 0.15); // Dark blue-grey
            let highlight = smoothstep(0.4, 0.5, dist) * glowIntensity; // Glow at edge

            // Add some "circuit" details inside
            let detail = step(0.9, fract(localUV.x * 10.0 + localUV.y * 10.0));

            let armorColor = techColor + vec3<f32>(0.0, 0.8, 1.0) * highlight + vec3<f32>(detail * 0.05);

            finalColor = vec4<f32>(armorColor, 1.0);

        } else {
            // Outside Hex (Gap) -> Show Image
            // Add a glow from the hex border onto the image
            let glow = exp(-20.0 * (dist - radius)) * glowIntensity;
            let imgColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);

            finalColor = imgColor + vec4<f32>(0.0, 0.5, 1.0, 0.0) * glow;
        }
    }

    // Pass-through depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));

    textureStore(writeTexture, global_id.xy, finalColor);
}
