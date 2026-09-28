// ----------------------------------------------------------------
// Cyber-Organic Void-Mycelium Pulsar
// Category: generative
// ----------------------------------------------------------------

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config: vec4<f32>,       // x=Time, y=RippleCount, z=ResX, w=ResY
    zoom_config: vec4<f32>,  // x=ZoomTime, yz=MouseUV, w=MouseDown
    zoom_params: vec4<f32>,  // x=Density, y=Spore Glow, z=Twist, w=Fog
    ripples: array<vec4<f32>, 50>,
};

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

const MAX_STEPS: i32 = 100;
const SURF_DIST: f32 = 0.001;
const MAX_DIST: f32 = 100.0;

fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a);
    let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}

fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * k * (1.0 / 4.0);
}

fn hash3(p: vec3<f32>) -> vec3<f32> {
    var p2 = vec3<f32>(dot(p, vec3<f32>(127.1, 311.7, 74.7)),
                       dot(p, vec3<f32>(269.5, 183.3, 246.1)),
                       dot(p, vec3<f32>(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(p2) * 43758.5453123);
}

fn map(p: vec3<f32>, time: f32, bass: f32, density: f32, twist_str: f32) -> vec2<f32> {
    var q = p;

    // Domain repetition / Grid
    let cell_size = 4.0 / density;
    let grid_id = floor(q / cell_size);
    q = (fract(q / cell_size) - 0.5) * cell_size;

    // Twisting
    let angle = length(p.xy) * twist_str * 0.1 + time * 0.2;
    q.x = q.x * cos(angle) - q.y * sin(angle);
    q.y = q.y * cos(angle) + q.x * sin(angle);

    // Mycelium branches (cylinders)
    let r1 = length(q.xy) - 0.1 - bass * 0.05;
    let r2 = length(q.yz) - 0.1 - bass * 0.05;
    let r3 = length(q.xz) - 0.1 - bass * 0.05;
    var d = smin(r1, r2, 0.5);
    d = smin(d, r3, 0.5);

    // Nodes (spheres)
    let node_dist = length(q) - (0.3 + bass * 0.2);
    d = smin(d, node_dist, 0.8);

    // Add some noise displacement
    let disp = sin(10.0*p.x)*sin(10.0*p.y)*sin(10.0*p.z) * 0.05;
    d += disp;

    // Distinguish materials: 1.0 for branch, 2.0 for node
    let mat = select(1.0, 2.0, node_dist < d + 0.1);

    return vec2<f32>(d, mat);
}

fn getNormal(p: vec3<f32>, time: f32, bass: f32, density: f32, twist_str: f32) -> vec3<f32> {
    let e = vec2<f32>(0.001, 0.0);
    let n = vec3<f32>(
        map(p + e.xyy, time, bass, density, twist_str).x - map(p - e.xyy, time, bass, density, twist_str).x,
        map(p + e.yxy, time, bass, density, twist_str).x - map(p - e.yxy, time, bass, density, twist_str).x,
        map(p + e.yyx, time, bass, density, twist_str).x - map(p - e.yyx, time, bass, density, twist_str).x
    );
    return normalize(n);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let res = vec2<f32>(u.config.z, u.config.w);
    let coords = vec2<i32>(global_id.xy);
    if (f32(coords.x) >= res.x || f32(coords.y) >= res.y) {
        return;
    }
    let uv = (vec2<f32>(coords) - 0.5 * res) / res.y;
    let time = u.config.x;

    let bass = extraBuffer[0];

    let density = u.zoom_params.x;
    let spore_glow = u.zoom_params.y;
    let twist_str = u.zoom_params.z;
    let fog_dens = u.zoom_params.w;

    // Camera setup
    var ro = vec3<f32>(time, 0.0, -time * 2.0); // Moving through the void
    let lookAtTarget = ro + vec3<f32>(-1.0, 0.0, 2.0);

    // Mouse Interaction
    var rd = normalize(vec3<f32>(uv, 1.0));
    if (u.zoom_config.w > 0.0) {
        let mouse_uv = (u.zoom_config.yz - 0.5) * vec2<f32>(res.x/res.y, 1.0);
        let m = vec2<f32>(mouse_uv.x * 3.14, mouse_uv.y * 3.14);

        let rotM = rot(m.y);
        rd.y = rd.y * rotM[0][0] + rd.z * rotM[0][1];
        rd.z = rd.y * rotM[1][0] + rd.z * rotM[1][1];

        let rotM2 = rot(m.x);
        rd.x = rd.x * rotM2[0][0] + rd.z * rotM2[0][1];
        rd.z = rd.x * rotM2[1][0] + rd.z * rotM2[1][1];
    } else {
        // Default camera orientation
        let f = normalize(lookAtTarget - ro);
        let r = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), f));
        let u_vec = cross(f, r);
        rd = normalize(r * uv.x + u_vec * uv.y + f * 1.0);
    }

    // Raymarching
    var dO: f32 = 0.0;
    var dS: f32 = 0.0;
    var p: vec3<f32>;
    var mat: f32 = 0.0;
    var steps: i32 = 0;
    var min_dist_to_spore: f32 = 1000.0;

    for (var i = 0; i < MAX_STEPS; i++) {
        p = ro + rd * dO;
        let map_res = map(p, time, bass, density, twist_str);
        dS = map_res.x;
        mat = map_res.y;

        // Track closest distance to nodes (spores) for glow
        if (mat == 2.0) {
            min_dist_to_spore = min(min_dist_to_spore, dS);
        }

        if (abs(dS) < SURF_DIST || dO > MAX_DIST) {
            steps = i;
            break;
        }
        dO += dS;
    }

    var col = vec3<f32>(0.0);
    let depth = dO;

    if (dO < MAX_DIST) {
        let n = getNormal(p, time, bass, density, twist_str);

        // Lighting
        let lightDir = normalize(vec3<f32>(1.0, 2.0, -1.0));
        let diff = max(dot(n, lightDir), 0.0);
        let ao = 1.0 - f32(steps) / f32(MAX_STEPS);

        // Obsidian material
        col = vec3<f32>(0.05, 0.05, 0.06) * diff * ao;

        // Specular
        let refl = reflect(-lightDir, n);
        let spec = pow(max(dot(refl, -rd), 0.0), 32.0);
        col += vec3<f32>(0.2) * spec;

        // Node Bioluminescence (Cyan, Magenta, Green)
        if (mat == 2.0) {
             let emit_color = vec3<f32>(
                 0.5 + 0.5 * sin(p.x * 2.0 + time),
                 0.5 + 0.5 * sin(p.y * 2.0 + time + 2.0),
                 0.5 + 0.5 * sin(p.z * 2.0 + time + 4.0)
             );
             // Boost emission on bass
             col += emit_color * (1.0 + bass * 2.0) * spore_glow;
        }
    }

    // Subspace fog (dark abyssal purple/blue)
    let fogColor = vec3<f32>(0.02, 0.0, 0.05);
    let fogFactor = 1.0 - exp(-dO * 0.05 * fog_dens);
    col = mix(col, fogColor, fogFactor);

    // Volumetric Spore Bloom
    let bloomCol = vec3<f32>(0.0, 1.0, 0.5); // Toxic green
    let bloom = exp(-min_dist_to_spore * 2.0) * spore_glow * bass;
    col += bloomCol * bloom;

    textureStore(writeTexture, coords, vec4<f32>(col, 1.0));
    textureStore(writeDepthTexture, coords, vec4<f32>(depth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coords, vec4<f32>(col, 1.0));
}
