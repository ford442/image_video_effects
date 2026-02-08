// ═══════════════════════════════════════════════════════════════
//  Sphere Projection - 3D sphere projection with mouse-controlled rotation
//  Category: geometric
//  Features: mouse-driven, 3d
// ═══════════════════════════════════════════════════════════════

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
  config: vec4<f32>,       // x=Time, y=FrameCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=unused, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Zoom, y=Rotation, z=Light, w=unused
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    
    let uv = vec2<f32>(global_id.xy) / resolution;
    
    // Normalized device coordinates (-1 to 1)
    let min_res = min(resolution.x, resolution.y);
    let ndc = (vec2<f32>(global_id.xy) * 2.0 - resolution) / min_res;

    // Parameters from zoom_params
    let zoom_param = u.zoom_params.x;      // Zoom
    let rotation_param = u.zoom_params.y;  // Rotation speed
    let light_param = u.zoom_params.z;     // Lighting amount

    // Camera Setup
    // Camera is at (0, 0, -dist) look at (0, 0, 0)
    let dist = 3.0 / max(0.01, zoom_param);
    let ro = vec3<f32>(0.0, 0.0, -dist);
    let rd = normalize(vec3<f32>(ndc, 1.0)); // FOV related to Z component

    // Sphere Intersection
    // Sphere center (0,0,0), radius 1.0
    let radius = 1.0;

    // Ray-Sphere intersection analytic solution
    let b = dot(ro, rd);
    let c = dot(ro, ro) - radius * radius;
    let h = b * b - c;

    var final_color: vec3<f32>;
    var depth_out: f32 = 1.0;

    if (h < 0.0) {
        // Background - sample original texture
        final_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    } else {
        let t = -b - sqrt(h);
        let p = ro + rd * t;
        let n = normalize(p); // Normal is just p for unit sphere at origin

        // Mouse position from zoom_config.yz
        let mouse = u.zoom_config.yz;

        // Interaction: Mouse X rotates Yaw (Longitude), Mouse Y rotates Pitch (Latitude)
        let mouse_rot_x = (mouse.x - 0.5) * 2.0 * PI; // -PI to PI
        let mouse_rot_y = (mouse.y - 0.5) * PI;       // -PI/2 to PI/2

        // Auto rotation
        let time = u.config.x;
        let auto_rot = time * rotation_param;

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

        // Standard equirectangular mapping
        let u_coord = atan2(n_rot.z, n_rot.x) / (2.0 * PI) + 0.5;
        let v_coord = acos(clamp(n_rot.y, -1.0, 1.0)) / PI;

        // Sample texture
        let tex_uv = vec2<f32>(fract(u_coord), clamp(v_coord, 0.0, 1.0));
        var color = textureSampleLevel(readTexture, u_sampler, tex_uv, 0.0);

        // Lighting
        let lightDir = normalize(vec3<f32>(-0.5, 0.5, -1.0));
        let diff = max(0.0, dot(n, lightDir));
        let ambient = 0.2;
        let lighting = mix(1.0, ambient + diff, light_param);

        final_color = color.rgb * lighting;
        
        // Calculate depth based on intersection distance
        depth_out = t / 10.0; // Normalize somewhat
    }

    // Output
    textureStore(writeTexture, global_id.xy, vec4<f32>(final_color, 1.0));
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth_out, 0.0, 0.0, 0.0));
}
