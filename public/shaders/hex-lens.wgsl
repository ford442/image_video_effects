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
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=GridSize, y=LensZoom, z=Rotation, w=MouseRadius
  ripples: array<vec4<f32>, 50>,
};

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;
    let aspectVec = vec2<f32>(aspect, 1.0);
    let mousePos = u.zoom_config.yz;

    // Parameters
    let gridSize = mix(10.0, 100.0, u.zoom_params.x);
    let baseZoom = mix(0.5, 2.0, u.zoom_params.y);
    let baseRot = (u.zoom_params.z - 0.5) * 6.28;
    let mouseRadius = u.zoom_params.w * 0.5;

    // Hex Coordinates
    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;

    // Scale UV for grid
    let uvScaled = uv * aspectVec * gridSize;

    let uvA = uvScaled / r;
    let idA = floor(uvA + 0.5);
    let uvB = (uvScaled - h) / r;
    let idB = floor(uvB + 0.5);

    let centerA = idA * r;
    let centerB = idB * r + h;

    let distA = distance(uvScaled, centerA);
    let distB = distance(uvScaled, centerB);

    let center = select(centerB, centerA, distA < distB);

    // Convert back to 0-1 space for distance to mouse
    let centerUV = center / gridSize / aspectVec;
    let centerScreen = centerUV * aspectVec;
    let mouseScreen = mousePos * aspectVec;

    let distToMouse = distance(centerScreen, mouseScreen);

    // Mouse Interaction
    // Influence 1 near mouse, 0 far
    let influence = smoothstep(mouseRadius + 0.1, mouseRadius, distToMouse);

    // Modulate Zoom and Rotation based on influence
    // E.g. Near mouse, zoom increases, rotation spins
    let currentZoom = baseZoom + influence * 1.0;
    let currentRot = baseRot + influence * 3.14;

    // Local UV within the hex
    // Vector from hex center to current pixel
    let localVec = uvScaled - center;

    // Rotate localVec
    let c = cos(currentRot);
    let s = sin(currentRot);
    let rotatedVec = vec2<f32>(
        localVec.x * c - localVec.y * s,
        localVec.x * s + localVec.y * c
    );

    // Scale localVec (Lens effect)
    // If zoom > 1, we show smaller area (magnify). So we multiply UV delta by 1/zoom?
    // No, if we want to magnify, we sample closer to center.
    // sampleUV = center + localVec / zoom
    let lensVec = rotatedVec / currentZoom;

    // Map back to 0-1
    let sampleUV = (center + lensVec) / gridSize / aspectVec;

    // Mask edges of hex?
    // Hex distance field for border?
    // distA or distB is distance to center. Hex radius is 0.5 (in 'r' units approx).
    // Let's just sample.

    let color = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);

    textureStore(writeTexture, global_id.xy, color);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r;
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
