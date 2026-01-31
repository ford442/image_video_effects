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
  zoom_params: vec4<f32>,  // x=RotationScale, y=Distance, z=Scale, w=BgAlpha
  ripples: array<vec4<f32>, 50>,
};

// Perspective Tilt Shader
// Implements a 3D plane rotation by raytracing against a rotated plane (or rotating the ray).

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / resolution.y;

    let mouse = u.zoom_config.yz;

    // Parameters
    let rotScale = u.zoom_params.x * 1.5 + 0.5; // Max rotation angle scale
    let distance = u.zoom_params.y * 2.0 + 1.0; // Camera distance
    let scale = u.zoom_params.z * 1.0 + 1.0;    // Texture scale
    let bgAlpha = u.zoom_params.w;

    // Calculate rotation angles based on mouse from center
    // Mouse (0.5, 0.5) = No rotation
    let pitch = (mouse.y - 0.5) * -3.0 * rotScale; // Rotate around X
    let yaw = (mouse.x - 0.5) * 3.0 * rotScale;    // Rotate around Y

    // Camera Setup
    // Camera at (0, 0, distance) looking at (0, 0, 0)
    let origin = vec3<f32>(0.0, 0.0, distance);

    // Screen plane at Z = distance - 1.0 (arbitrary focal length of 1.0)
    // Pixel coordinate on screen plane
    let uv_centered = (uv - 0.5) * vec2<f32>(aspect, 1.0);
    let rayDir = normalize(vec3<f32>(uv_centered, -1.0)); // Towards negative Z

    // To intersect a rotated plane at (0,0,0) with normal (0,0,1):
    // It is equivalent to intersecting the Z=0 plane with a ray rotated by the INVERSE angles.
    // Inverse rotation: Rotate by -Yaw, then -Pitch? Or Transpose matrix.
    // Order matters. rotate3D above does X then Y.
    // Inverse should do -Y then -X.

    // Let's implement inverse rotation manually for correctness
    // Un-rotate Y (Yaw)
    let cY = cos(-yaw);
    let sY = sin(-yaw);
    var r = rayDir;
    let rx = r.x * cY + r.z * sY;
    let rz = -r.x * sY + r.z * cY;
    r.x = rx;
    r.z = rz;

    // Un-rotate X (Pitch)
    let cX = cos(-pitch);
    let sX = sin(-pitch);
    let ry = r.y * cX - r.z * sX;
    let rz2 = r.y * sX + r.z * cX;
    r.y = ry;
    r.z = rz2;

    // Now intersect ray (Origin, r) with Plane Z=0.
    // However, we must also rotate the Origin if the Camera was fixed and the Plane moved.
    // But here we are simulating Moving Camera / Fixed Plane relative motion.
    // If the Plane rotates, the Camera stays.
    // We want to find where the ray hits the Plane.
    // Transforming the Ray into Plane space works.
    // We must also transform the Origin!

    var o = origin;
    // Rotate Origin by inverse Y
    let ox = o.x * cY + o.z * sY;
    let oz = -o.x * sY + o.z * cY;
    o.x = ox;
    o.z = oz;

    // Rotate Origin by inverse X
    let oy = o.y * cX - o.z * sX;
    let oz2 = o.y * sX + o.z * cX;
    o.y = oy;
    o.z = oz2;

    // Intersection: P = O + t * D
    // P.z = 0 => O.z + t * D.z = 0 => t = -O.z / D.z

    var finalColor = vec4<f32>(0.0, 0.0, 0.0, 1.0);
    var finalDepth = 1.0; // Far

    if (abs(r.z) > 0.0001) {
        let t = -o.z / r.z;
        if (t > 0.0) {
            let p = o + r * t;

            // Map p.xy back to UV
            // Undo aspect correction and centering
            // Scale parameter applies here (zooming the texture on the plane)
            // p.x is world space. p.x / scale?

            let texUV_centered = vec2<f32>(p.x, p.y) / scale;
            let texUV = vec2<f32>(texUV_centered.x / aspect, texUV_centered.y) + 0.5;

            if (texUV.x >= 0.0 && texUV.x <= 1.0 && texUV.y >= 0.0 && texUV.y <= 1.0) {
                finalColor = textureSampleLevel(readTexture, u_sampler, texUV, 0.0);

                // Depth logic:
                // We should sample the depth texture at the hit point?
                // Or calculate the depth of the plane?
                // Visual depth of the plane: t is the distance from camera.
                // depth buffer expects 0..1 (1=near, 0=far? or reversed? usually 1=near in this engine)
                // Let's assume linear mapping for now or pass through.

                // If we want the 3D depth of the plane to interact with other things,
                // we should write `1.0 / t` or similar.
                // But for "Image" effects, usually we just pass the texture depth.
                // Let's sample the texture depth at the new UV coordinates.
                let d = textureSampleLevel(readDepthTexture, non_filtering_sampler, texUV, 0.0).r;
                finalDepth = d;
            } else {
                // Out of bounds
                if (bgAlpha > 0.0) {
                     // Sample original UV for background?
                     let bg = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
                     finalColor = vec4<f32>(bg.rgb * bgAlpha, 1.0);
                     finalDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
                }
            }
        }
    }

    textureStore(writeTexture, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(finalDepth, 0.0, 0.0, 0.0));
}
