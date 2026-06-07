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
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4 (Use these for ANY float sliders)
  ripples: array<vec4<f32>, 50>,
};

// ═══ UNIQUE VISUAL IDEA helpers: iron-filing field lines ═══
fn mrHash(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}
fn mrNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(mrHash(i), mrHash(i + vec2<f32>(1.0, 0.0)), u.x),
               mix(mrHash(i + vec2<f32>(0.0, 1.0)), mrHash(i + vec2<f32>(1.0, 1.0)), u.x), u.y);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    // Mouse Config
    var mouse = u.zoom_config.yz;
    let hasMouse = u.zoom_config.y >= 0.0;
    var center = select(vec2<f32>(0.5, 0.5), mouse, hasMouse);

    // Params
    let strength = u.zoom_params.x; // Field Strength
    let radius = u.zoom_params.y;   // Effect Radius
    let swirl = u.zoom_params.z;    // Rotation/Swirl amount
    let chaos = u.zoom_params.w;    // Random jitter

    // Calculate vectors
    let dVec = uv - center;
    let dVecAspect = vec2<f32>(dVec.x * aspect, dVec.y);
    let dist = length(dVecAspect);

    // Normalized direction from center
    var dir = normalize(dVecAspect);
    if (length(dVecAspect) < 0.0001) { dir = vec2<f32>(0.0, 0.0); } // Avoid NaN

    // Perpendicular direction (for swirl)
    let swirlDir = vec2<f32>(-dir.y, dir.x);

    // Field Falloff
    // Effect is strong near mouse, fades out at radius
    let field = smoothstep(radius, 0.0, dist);

    // Base displacement vector
    // Scale by strength and field intensity
    let displace = strength * field * 0.2;

    // --- Red Channel Physics (Attraction) ---
    // Pulls towards the center
    let offsetR = -dir * displace;

    // --- Green Channel Physics (Swirl) ---
    // Swirls around the center
    let offsetG = swirlDir * displace * (0.5 + swirl * 2.0);

    // --- Blue Channel Physics (Repulsion) ---
    // Pushes away from center
    let offsetB = dir * displace;

    // --- Chaos / Jitter ---
    // Add high frequency noise based on UV and time
    var noise = vec2<f32>(0.0);
    if (chaos > 0.0) {
        let t = u.config.x;
        let n1 = sin(uv.x * 100.0 + t * 10.0);
        let n2 = cos(uv.y * 100.0 + t * 15.0);
        noise = vec2<f32>(n1, n2) * chaos * 0.01 * field;
    }

    // Apply Offsets
    // Un-aspect correct the direction for UV addition?
    // dir is unit length in aspect-corrected space.
    // real UV offset x needs to be divided by aspect to maintain circularity.

    let realOffsetR = vec2<f32>(offsetR.x / aspect, offsetR.y) + noise;
    let realOffsetG = vec2<f32>(offsetG.x / aspect, offsetG.y) + noise;
    let realOffsetB = vec2<f32>(offsetB.x / aspect, offsetB.y) + noise;

    let uvR = clamp(uv + realOffsetR, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + realOffsetG, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + realOffsetB, vec2<f32>(0.0), vec2<f32>(1.0));

    // Sample Texture
    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, uvB, 0.0).b;

    var outColor = vec3<f32>(r, g, b);

    // ═══ UNIQUE VISUAL IDEA: iron-filing field-line visualization ═══
    // The local magnetic field is the blend of the radial (attraction) and the
    // tangential (swirl) components. Iron filings align ALONG that field, so we
    // sample noise compressed perpendicular to the field direction — producing the
    // characteristic dipole field-line filaments of a classroom magnet demo.
    let fieldDir = normalize(mix(dir, swirlDir, clamp(swirl, 0.0, 1.0)) + vec2<f32>(1e-4));
    let fieldPerp = vec2<f32>(-fieldDir.y, fieldDir.x);
    // Coordinates: stretched along the field, tight across it → thin streaks.
    let along = dot(dVecAspect, fieldDir);
    let across = dot(dVecAspect, fieldPerp);
    let filingUV = vec2<f32>(along * 18.0, across * 90.0);
    // Animate filings drifting along the field lines (current flowing).
    let flow = mrNoise(filingUV + vec2<f32>(u.config.x * 0.6, 0.0));
    let filing = pow(abs(sin(across * 120.0 + flow * 6.0)), 6.0);
    // Filings only appear inside the field's reach, brightest where it is strong.
    let filingMask = field * smoothstep(0.0, 0.15, strength);
    let filingColor = vec3<f32>(0.55, 0.6, 0.7); // cold iron sheen
    outColor = outColor + filingColor * filing * filingMask * 0.7;

    textureStore(writeTexture, vec2<i32>(global_id.xy), vec4<f32>(outColor, 1.0));

    // Pass depth
    let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(d, 0.0, 0.0, 0.0));
}
