# New Shader Plan: Fractal Clockwork

## 1. Overview
The "Fractal Clockwork" shader is a generative 3D visualization of an infinite lattice of interlocking, rotating gears. It leverages raymarching with domain repetition to create a dense, steampunk-inspired mechanical environment. The rotation of the gears is synchronized based on their grid position to simulate a cohesive mechanism.

## 2. Technical Implementation

### Category
- `generative`

### Filenames
- WGSL: `public/shaders/fractal-clockwork.wgsl`
- JSON: `shader_definitions/generative/fractal-clockwork.json`

### ID
- `fractal-clockwork`

### Tags
- `steampunk`, `gears`, `clockwork`, `infinite`, `3d`, `raymarching`, `generative`, `mechanical`

### Core Technique: Raymarching with Domain Repetition
The scene is constructed using Signed Distance Functions (SDFs). Instead of defining thousands of individual gears, we define a single gear SDF and repeat it infinitely across space using the modulo operator (`mod`).

### Logic Details
1.  **Gear SDF (`sdGear`)**:
    -   Base shape: A cylinder with a central hole.
    -   Teeth: A radial repetition of a tooth shape (e.g., box or trapezoid) added to the cylinder's outer radius.
    -   Spokes/Details: Subtractive shapes to create spokes or patterns on the gear face.
2.  **Domain Repetition**:
    -   Space is divided into a grid (e.g., `spacing = 4.0`).
    -   `p_local = mod(p, spacing) - spacing * 0.5`.
    -   This creates an infinite field of cells, each containing a gear.
3.  **Synchronized Rotation**:
    -   To simulate meshing gears, adjacent gears must rotate in opposite directions.
    -   We determine the "grid cell index": `cell_id = floor(p / spacing)`.
    -   Rotation Direction: `dir = ((cell_id.x + cell_id.y + cell_id.z) % 2.0 == 0.0) ? 1.0 : -1.0`.
    -   Rotation Angle: `angle = time * speed * dir`.
    -   The coordinate space for the gear is rotated by this angle *before* evaluating the SDF.
4.  **Camera**:
    -   Orbit camera controlled by mouse (`u.zoom_config.yz`).
    -   Allows the user to fly through or orbit the mechanism.
5.  **Lighting & Material**:
    -   Material: Metallic (high specular, low roughness).
    -   Lighting: Directional light + Rim lighting to accentuate edges.
    -   Fog: Applied based on distance to fade out distant gears and add depth.

## 3. Parameter Mapping (`u.zoom_params`)
| Param | Name | Description | Range | Default |
| :--- | :--- | :--- | :--- | :--- |
| `x` | **Gear Density / Scale** | Controls the spacing and size of the gears. | 0.1 - 2.0 | 0.5 |
| `y` | **Rotation Speed** | Controls how fast the gears spin. | 0.0 - 5.0 | 1.0 |
| `z` | **Complexity** | Controls the number of teeth and detail level. | 4 - 32 (int) | 0.5 (mapped) |
| `w` | **Metallic / Color** | Adjusts the metallic shine or color tint (Brass vs Chrome). | 0.0 - 1.0 | 0.8 |

## 4. Proposed Code Skeleton (WGSL)

```wgsl
// ... Standard Header ...

struct Uniforms { ... };

// Rotation helper
fn rot2D(p: vec2<f32>, angle: f32) -> vec2<f32> {
    let c = cos(angle);
    let s = sin(angle);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

// SDF for a single Gear
fn sdGear(p: vec3<f32>, radius: f32, thickness: f32, teeth: f32) -> f32 {
    // 1. Cylinder body
    let d_cyl = length(p.xy) - radius;
    let d_thick = abs(p.z) - thickness;
    let base = max(d_cyl, d_thick);

    // 2. Teeth (Radial repetition)
    let angle = atan2(p.y, p.x);
    let r = length(p.xy);

    // Teeth logic: add bumps to radius
    // sector = round(angle / (2pi/teeth))
    // ... logic to shape teeth ...

    // Return combined distance
    return base; // Placeholder
}

fn map(p: vec3<f32>) -> vec2<f32> {
    let spacing = 4.0;
    let id = floor(p / spacing);
    let p_local = (fract(p / spacing) - 0.5) * spacing;

    // Alternate rotation based on checkerboard pattern of IDs
    let check = mod(id.x + id.y + id.z, 2.0);
    let dir = sign(check - 0.5); // -1 or 1

    let time = u.config.x * u.zoom_params.y;

    // Rotate gear in local space
    // Assuming gears lie flat on XY plane? No, let's make a 3D lattice.
    // Maybe interlocking perpendicular gears? That's harder.
    // Let's stick to a stack of gears or a grid of gears on a plane first,
    // or simply 3D grid of floating gears.

    // Let's rotate p_local.xy
    let p_rot = vec3<f32>(rot2D(p_local.xy, time * dir), p_local.z);

    let d = sdGear(p_rot, 1.0, 0.2, 12.0);

    return vec2<f32>(d, 1.0); // 1.0 = material ID
}

// ... Raymarch Loop & Main ...
```

## 5. Potential Challenges
-   **Interlocking in 3D**: Real 3D gears (like worm gears or bevel gears) are complex to model with simple SDFs. A grid of parallel gears (like a clock interior) is easier and visually effective. We can offset layers (Z-axis) to make them look like they are stacked on shafts.
-   **Aliasing**: High frequency details (teeth) might shimmer. Raymarching steps need to be careful, or use TAA (not available here). Smoothstep teeth edges can help.
-   **Performance**: Infinite repetition is cheap, but complex SDFs can be slow. Keep the gear SDF efficient.
