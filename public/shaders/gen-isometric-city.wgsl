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
@group(0) @binding(9) var dataTextureC: texture_2d<f32>; // Previous frame (A)
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>; // Or generic object data
// ---------------------------------------------------

struct Uniforms {
  config: vec4<f32>,       // x=Time, y=MouseClickCount/Generic1, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=ZoomTime, y=MouseX, z=MouseY, w=Generic2
  zoom_params: vec4<f32>,  // x=Param1, y=Param2, z=Param3, w=Param4
  ripples: array<vec4<f32>, 50>,
};

// Parameters mapping
// u.zoom_params.x -> Density / Height Variance
// u.zoom_params.y -> Traffic Speed
// u.zoom_params.z -> Glow Intensity

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Scene Distance Function
fn map(p: vec3<f32>) -> vec2<f32> {
    // Floor
    var d = p.y;
    var mat = 0.0; // 0 = floor, 1 = building

    // Grid Repetition
    let gridSize = 2.0;
    let cell = floor(p.xz / gridSize);
    let local = (fract(p.xz / gridSize) - 0.5) * gridSize;

    // Building properties based on cell hash
    let h_rnd = hash12(cell);

    // Param 1: Density/Height
    // Default 0.5 if not set (avoid 0)
    let density = mix(0.2, 1.5, u.zoom_params.x);

    var height = 0.0;
    // Only place buildings if hash is above a threshold or scale height
    if (h_rnd > 0.3) {
        height = pow(h_rnd, 2.0) * 8.0 * density;
    }

    // Building SDF
    // Center the box vertically so it sits on the floor.
    // Box height is 'height', center at y = height/2
    let boxSize = vec3<f32>(0.6, height * 0.5, 0.6);
    let boxPos = vec3<f32>(local.x, p.y - height * 0.5, local.y);
    let dBox = sdBox(boxPos, boxSize);

    if (dBox < d) {
        d = dBox;
        mat = 1.0;
        // Use fractional part of mat to store building ID/hash for coloring?
        // Let's just store 1.0 + h_rnd for variety
        mat = 1.0 + h_rnd;
    }

    return vec2<f32>(d, mat);
}

fn calcNormal(p: vec3<f32>) -> vec3<f32> {
    let e = 0.001;
    let d = map(p).x;
    return normalize(vec3<f32>(
        map(p + vec3<f32>(e, 0.0, 0.0)).x - d,
        map(p + vec3<f32>(0.0, e, 0.0)).x - d,
        map(p + vec3<f32>(0.0, 0.0, e)).x - d
    ));
}

// Raymarching
fn raymarch(ro: vec3<f32>, rd: vec3<f32>) -> vec2<f32> {
    var t = 0.0;
    var m = -1.0;
    for (var i = 0; i < 100; i++) {
        let p = ro + rd * t;
        let res = map(p);
        if (res.x < 0.001 || t > 100.0) {
            if (res.x < 0.001) { m = res.y; }
            break;
        }
        t += res.x;
    }
    if (t > 100.0) { m = -1.0; }
    return vec2<f32>(t, m);
}

@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }

    let uv = (vec2<f32>(global_id.xy) - 0.5 * resolution) / resolution.y;
    let time = u.config.x;

    // Camera Setup (Isometric / Orthographic)
    // Isometric view: look at (0,0,0) from (1,1,1) (normalized)
    // Or rather, rotate 45 deg Y, then 35.264 deg X.

    let camDist = 50.0;
    let target = vec3<f32>(0.0, 0.0, 0.0);

    // Mouse interaction: Pan the camera
    let mouse = u.zoom_config.yz; // 0..1
    let pan = (mouse - 0.5) * 40.0; // Pan range -20 to 20

    // Ray Direction is constant for orthographic
    let rd = normalize(vec3<f32>(-1.0, -1.0, -1.0));

    // Right and Up vectors for the camera plane
    let forward = -rd;
    let right = normalize(cross(vec3<f32>(0.0, 1.0, 0.0), forward));
    let up = cross(forward, right);

    // Ray Origin varies with UV
    // 'zoom' factor
    let zoom = 15.0;
    var ro = target + (right * uv.x + up * uv.y) * zoom - forward * camDist;

    // Apply panning
    ro.x += pan.x + pan.y; // Diagonal movement for isometric feel
    ro.z += pan.y - pan.x;

    // Flyover animation
    // u.zoom_params.y is Speed.
    let speed = mix(0.5, 5.0, u.zoom_params.y);
    ro.z += time * speed;
    ro.x += time * speed * 0.5;

    // Raymarch
    let res = raymarch(ro, rd);
    let t = res.x;
    let mat = res.y;

    var col = vec3<f32>(0.05, 0.05, 0.1); // Background / Fog color (Dark Blue)

    if (mat > 0.0) {
        let p = ro + rd * t;
        let n = calcNormal(p);

        // Lighting
        let lightDir = normalize(vec3<f32>(0.5, 1.0, -0.5));
        let diff = max(dot(n, lightDir), 0.0);

        // Material Coloring
        if (mat >= 1.0) { // Building
            let h_rnd = mat - 1.0; // recovered hash

            // Base building color (dark grey/blue)
            var baseCol = vec3<f32>(0.1, 0.1, 0.15);

            // Window / Neon Logic
            // Map position to local building UV
            let gridSize = 2.0;
            let local = (fract(p.xz / gridSize) - 0.5) * gridSize;
            // Height fraction
            // approximate building height from p.y (since box is centered at h/2, top is h, bottom is 0)
            // Wait, map function: boxPos y is p.y - h*0.5.
            // So relative to box center: p.y - h*0.5.
            // Let's just use world p.y

            // Generate windows grid
            let winGrid = vec2<f32>(0.0);

            // Determine which face we are on
            var isSide = 0.0;
            var windowPattern = 0.0;

            if (abs(n.y) < 0.1) { // Side walls
                isSide = 1.0;
                // create window pattern
                let wx = floor(p.x * 4.0 + p.z * 4.0); // Coordinate along the wall
                let wy = floor(p.y * 8.0);
                let w_hash = hash12(vec2<f32>(wx, wy) + h_rnd * 10.0);

                if (w_hash > 0.6) {
                    windowPattern = 1.0;
                }
            }

            // Neon Glow Color
            // Palette: Cyan, Magenta, Blue
            var glowCol = vec3<f32>(0.0);
            if (h_rnd < 0.33) { glowCol = vec3<f32>(0.0, 1.0, 1.0); } // Cyan
            else if (h_rnd < 0.66) { glowCol = vec3<f32>(1.0, 0.0, 1.0); } // Magenta
            else { glowCol = vec3<f32>(0.2, 0.2, 1.0); } // Blue

            let glowIntensity = mix(1.0, 5.0, u.zoom_params.z);

            if (isSide > 0.5 && windowPattern > 0.5) {
                // Window light
                 baseCol += glowCol * glowIntensity;
            } else if (n.y > 0.9) {
                // Roof lights or rim
                if (fract(p.x*2.0) < 0.1 || fract(p.z*2.0) < 0.1) {
                     baseCol += glowCol * 0.5 * glowIntensity;
                }
            }

            col = baseCol * (diff * 0.5 + 0.5); // ambient + diffuse
        } else {
            // Floor (shouldn't happen with current map logic as floor is mat 0, but if we add floor ID...)
            col = vec3<f32>(0.05);
        }

        // Fog
        let fogAmount = 1.0 - exp(-t * 0.02);
        col = mix(col, vec3<f32>(0.05, 0.05, 0.1), fogAmount);
    }

    // Traffic / Street lights
    // Add glow from streets based on ray proximity to floor traffic lanes
    // Simple way: if ray hit nothing or hit far, or just check 2D grid of ray path?
    // Easier: Just draw lines on the floor texture if we hit the floor.
    // But we are doing SDF.
    // Let's add traffic glow to the floor in the map/render logic?
    // Or post-process?
    // Let's add it to the floor color if t hit the floor (y=0).

    // Re-check floor intersection if we hit floor (mat==0 would be floor if we distinguished it)
    // In map(), floor d is p.y. Building d can be lower.
    // If t corresponds to p.y approx 0.
    let p_hit = ro + rd * t;
    if (p_hit.y < 0.1) {
       // Street Coordinates
       let gridSize = 2.0;
       let gridUV = abs(fract(p_hit.xz / gridSize) - 0.5) * gridSize; // 0 at center, 1 at edge? No.
       // Grid lines are at integer multiples of gridSize.
       // fract() goes 0..1. -0.5 -> -0.5..0.5. abs -> 0..0.5. *2.0 -> 0..1 (1 is edge)

       let edgeDist = min(gridUV.x, gridUV.y);
       // Streets are at the edges of the cells.
       // So when edgeDist is close to 0.5 (which is the edge of the cell? wait)
       // fract(x) is 0 at integer.
       // Center of cell is 0.5.
       // Edges are 0.0 and 1.0.
       // abs(fract - 0.5) -> center is 0.0, edge is 0.5.
       // So we want values close to 0.5.

       if (edgeDist > 0.4) { // Street area
           // Traffic pulse
           // Direction based on x or z
           // Random traffic speed/offset
           let laneID = floor(p_hit.xz / gridSize);
           let laneHash = hash12(laneID);
           let trafficSpeed = speed * (laneHash * 2.0 + 1.0);
           let trafficPos = fract(time * trafficSpeed + laneHash * 100.0);

           // Determine if we are on X street or Z street
           var isTraffic = 0.0;
           // If gridUV.x is high, we are near Z edge (X varies). NO.
           // gridUV.x = abs(fract(x) - 0.5). High means x is near integer.
           // So we are on a line where x is constant integer. That is a Z-aligned street.

           if (gridUV.x > 0.45) { // Z-street
               let flow = fract(p_hit.z * 0.5 + time * trafficSpeed); // movement along Z
               if (flow > 0.9) { isTraffic = 1.0; }
           }
           if (gridUV.y > 0.45) { // X-street
               let flow = fract(p_hit.x * 0.5 - time * trafficSpeed); // movement along X
               if (flow > 0.9) { isTraffic = 1.0; }
           }

           if (isTraffic > 0.0) {
               col += vec3<f32>(1.0, 0.8, 0.2) * 2.0; // Orange headlights
           }
       }
    }

    textureStore(writeTexture, global_id.xy, vec4<f32>(col, 1.0));

    // Write depth
    // Map t to 0..1 for depth buffer?
    // Standard depth is usually 1/z or similar. Here we just store linear t or something useful.
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(t / 100.0, 0.0, 0.0, 0.0));
}
