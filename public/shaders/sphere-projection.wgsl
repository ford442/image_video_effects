struct Uniforms {
    time: f32,
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    zoom: f32,
    rotation: f32,
    light: f32,
};

@group(0) @binding(0) var<uniform> uni: Uniforms;
@group(0) @binding(1) var mySampler: sampler;
@group(0) @binding(2) var myTexture: texture_2d<f32>;

const PI: f32 = 3.14159265359;

@fragment
fn main(@builtin(position) FragCoord: vec4<f32>) -> @location(0) vec4<f32> {
    // Normalized device coordinates (-1 to 1)
    let uv = (FragCoord.xy * 2.0 - uni.resolution.xy) / min(uni.resolution.x, uni.resolution.y);

    // Camera Setup
    // Camera is at (0, 0, -dist) look at (0, 0, 0)
    // Zoom param controls distance. Default zoom 1.0 -> dist 2.5
    let dist = 3.0 / max(0.01, uni.zoom);
    let ro = vec3<f32>(0.0, 0.0, -dist);
    let rd = normalize(vec3<f32>(uv, 1.0)); // FOV related to Z component

    // Sphere Intersection
    // Sphere center (0,0,0), radius 1.0
    let radius = 1.0;

    // Ray-Sphere intersection analytic solution
    // |ro + t*rd|^2 = r^2
    // dot(ro, ro) + 2*t*dot(ro, rd) + t^2*dot(rd, rd) = r^2
    // t^2 + 2*b*t + c = 0

    let b = dot(ro, rd);
    let c = dot(ro, ro) - radius * radius;
    let h = b * b - c;

    if (h < 0.0) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0); // Background color
    }

    let t = -b - sqrt(h);
    let p = ro + rd * t;
    let n = normalize(p); // Normal is just p for unit sphere at origin

    // UV Mapping (Equirectangular)
    // Map normal to longitude/latitude
    // atan2(z, x) returns angle in [-PI, PI]
    // acos(y) returns angle in [0, PI]

    // We want to rotate the sphere based on mouse.
    // Instead of rotating geometry, we offset the UVs.

    // Interaction: Mouse X rotates Yaw (Longitude), Mouse Y rotates Pitch (Latitude)
    let mouse_rot_x = (uni.mouse.x - 0.5) * 2.0 * PI; // -PI to PI
    let mouse_rot_y = (uni.mouse.y - 0.5) * PI;       // -PI/2 to PI/2

    // Auto rotation
    let auto_rot = uni.time * uni.rotation;

    // Note: To properly rotate 3D, we should rotate the Normal 'n' using a rotation matrix
    // BEFORE mapping to UV. UV offset is a cheap hack that distorts at poles.
    // Let's do proper rotation matrix for Yaw (Y-axis) and Pitch (X-axis).

    // Rotate Y (Yaw) - controlled by Mouse X + Auto
    let yaw = -mouse_rot_x - auto_rot;
    let cy = cos(yaw);
    let sy = sin(yaw);
    let rotY = mat3x3<f32>(
        cy, 0.0, sy,
        0.0, 1.0, 0.0,
        -sy, 0.0, cy
    );

    // Rotate X (Pitch) - controlled by Mouse Y
    let pitch = mouse_rot_y;
    let cx = cos(pitch);
    let sx = sin(pitch);
    let rotX = mat3x3<f32>(
        1.0, 0.0, 0.0,
        0.0, cx, -sx,
        0.0, sx, cx
    );

    let n_rot = rotX * (rotY * n);

    // Standard mapping
    let u = atan2(n_rot.z, n_rot.x) / (2.0 * PI) + 0.5;
    let v = acos(clamp(n_rot.y, -1.0, 1.0)) / PI;

    // Sample texture
    // Fix mirror/repeat issues at seam?
    // Texture sampler usually handles wrapping if set to 'repeat'.
    // If clamped, we might see a seam. Assuming standard sampler is Repeat or Clamp.
    // Use fract just in case.
    let tex_uv = vec2<f32>(fract(u), clamp(v, 0.0, 1.0));

    var color = textureSample(myTexture, mySampler, tex_uv);

    // Lighting
    // Directional light from camera view (0,0,-1) roughly
    let lightDir = normalize(vec3<f32>(-0.5, 0.5, -1.0));
    let diff = max(0.0, dot(n, lightDir));

    // Ambient
    let ambient = 0.2;
    let lighting = mix(1.0, ambient + diff, uni.light);

    return vec4<f32>(color.rgb * lighting, 1.0);
}
