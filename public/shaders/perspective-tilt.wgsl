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
  zoom_params: vec4<f32>,  // x=Tilt Sensitivity, y=Distance, z=Pitch Enable, w=Unused
  ripples: array<vec4<f32>, 50>,
};

// Perspective Tilt
// Implements a simple 3D plane rotation.
// Mouse X controls Yaw (rotation around Y axis).
// Mouse Y controls Pitch (rotation around X axis).

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz; // 0..1

    // Parameters
    let tiltStrength = u.zoom_params.x * 2.0; // Max tilt angle multiplier
    let dist = max(0.5, u.zoom_params.y + 1.0); // Camera distance
    let enablePitch = u.zoom_params.z;

    // Center is (0.5, 0.5)
    let mouseOffset = (mouse - vec2<f32>(0.5)) * 2.0; // -1 to 1

    // Angles in radians
    let yaw = -mouseOffset.x * tiltStrength;
    let pitch = mouseOffset.y * tiltStrength * enablePitch;

    let aspect = resolution.x / resolution.y;
    let screenUV = uv - vec2<f32>(0.5);

    // Camera Setup
    // Camera at (0, 0, -dist)
    // Looking at (0, 0, 0)
    // Ray Direction per pixel:
    let rayOrigin = vec3<f32>(0.0, 0.0, -dist);
    let rayDir = normalize(vec3<f32>(screenUV.x * aspect, -screenUV.y, dist));

    // Plane Setup (Rotated)
    // Original Plane: Center (0,0,0), Normal (0,0,1)
    // Basis Vectors: Right (1,0,0), Up (0,1,0)

    // Rotation Matrices
    let cY = cos(yaw);
    let sY = sin(yaw);
    let cP = cos(pitch);
    let sP = sin(pitch);

    // Rotate Normal (0,0,1)
    // Pitch (X): y' = y*cP - z*sP, z' = y*sP + z*cP -> z' = cP, y' = -sP
    // Yaw (Y): x'' = x'*cY + z'*sY, z'' = -x'*sY + z'*cY -> x'' = cP*sY, z'' = cP*cY

    // Actually let's just rotate basis vectors

    // Rotated Basis
    // Right (1,0,0) -> Pitch (unchanged) -> Yaw (cY, 0, -sY)
    let planeRight = vec3<f32>(cY, 0.0, -sY);

    // Up (0,1,0) -> Pitch (0, cP, -sP) -> Yaw (0, cP, -sP) *Yaw only mixes X and Z* -> (-sP*-sY, cP, -sP*cY)?
    // Wait, let's do full rotation of (0,1,0)
    // P: (0, cP, sP) ? No, rotX(theta) on (0,1,0): y' = c*1 - s*0 = c. z' = s*1 + c*0 = s.
    // So (0, cP, sP).
    // Y: rotY(phi) on (0, cP, sP): x' = 0*c + sP*s, z' = -0*s + sP*c.
    // So (sP*sY, cP, sP*cY).
    let planeUp = vec3<f32>(sP * sY, cP, sP * cY);

    // Normal (0,0,1) -> Pitch (0, -sP, cP) -> Yaw (-cP*sY, -sP, cP*cY) ??
    // Cross product Right x Up to be sure.
    let planeNormal = cross(planeRight, planeUp);

    // Plane Equation: dot(P - PlaneCenter, Normal) = 0
    // PlaneCenter = (0,0,0)
    // dot(P, Normal) = 0

    // Ray Intersect Plane
    // P = O + t*D
    // dot(O + t*D, Normal) = 0
    // dot(O, N) + t * dot(D, N) = 0
    // t = -dot(O, N) / dot(D, N)

    let denom = dot(rayDir, planeNormal);

    var color = vec4<f32>(0.0);
    var depth_val = 0.0;

    // Check if ray is parallel or pointing away (backface culling optional, but if denom approx 0 -> parallel)
    if (abs(denom) > 0.0001) {
        let t = -dot(rayOrigin, planeNormal) / denom;

        if (t > 0.0) {
            let hitPoint = rayOrigin + rayDir * t;

            // Project Hit Point onto Plane Basis to get UV
            // P = u * Right + v * Up + Center
            // u = dot(P, Right) (if normalized)
            // v = dot(P, Up)

            let u_plane = dot(hitPoint, planeRight);
            let v_plane = dot(hitPoint, planeUp);

            // Map back to 0..1
            // Original plane width/height matches screen at z=0?
            // Our standard image is -0.5*aspect to 0.5*aspect in X?
            // Let's assume texture covers the square -0.5 to 0.5?
            // Or matches aspect?
            // Usually texture is mapped to 0..1.
            // Let's assume the plane is a unit square centered at origin if aspect=1.
            // If aspect != 1, we need to handle it.
            // Let's say u maps to [-aspect/2, aspect/2] and v to [-0.5, 0.5].

            let texU = u_plane / aspect + 0.5;
            let texV = -v_plane + 0.5; // Flip Y back

            if (texU >= 0.0 && texU <= 1.0 && texV >= 0.0 && texV <= 1.0) {
                color = textureSampleLevel(readTexture, u_sampler, vec2<f32>(texU, texV), 0.0);

                // Depth writing
                // We should write the depth of the plane.
                // t is the distance from camera to hit point.
                // But depth buffer usually expects 0..1 where 0 is far? Or linear?
                // The engine uses 0=background, 1=foreground logic often, or raw depth.
                // Let's sample the original depth? No, the geometry changed.
                // We should create new depth.
                // Let's just output 1.0/t or something if we want Z-sorting,
                // but for single layer simple shader, we can just pass through 0.0 or 1.0.
                // However, to allow "Depth of Field" effects later, we might want real depth.
                // Let's sample the texture's depth at that point?
                // Yes, if the image has depth information (from depth estimation), we should map it onto the plane.

                let texDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, vec2<f32>(texU, texV), 0.0).r;
                // Modulate it by the plane's Z position?
                // This is getting complex. Let's just use the texture depth.
                depth_val = texDepth;
            }
        }
    }

    textureStore(writeTexture, global_id.xy, color);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_val, 0.0, 0.0, 0.0));
}
