# New Shader Plan: Bubble Chamber

## Overview
This shader simulates the visual aesthetic of a bubble chamber, where subatomic particles leave spiraling ionization trails as they move through a magnetic field. The shader uses a feedback loop to create persistent, fading trails that curve based on a simulated magnetic field centered on the mouse cursor.

## Features
- **Generative Trails**: Particles are probabilistically spawned based on the luminance of the input image. Brighter areas emit more particles.
- **Magnetic Field Simulation**: Trails spiral inwards or outwards based on the "magnetic field" controlled by the mouse position.
- **Feedback Loop**: Uses previous frame data (`dataTextureC`) to advect and decay trails, creating smooth, organic motion.
- **Interactive Control**:
  - **Mouse**: Sets the center of the magnetic field.
  - **Param 1 (Field Strength)**: Controls the tightness and speed of the spiraling motion.
  - **Param 2 (Decay)**: Controls how fast the trails fade (persistence).
  - **Param 3 (Ionization Rate)**: Controls the probability of new particles spawning from the source image.
  - **Param 4 (Color Shift)**: Adds a subtle color shift to the trails over time.

## Technical Implementation
- **File**: `public/shaders/bubble-chamber.wgsl`
- **Type**: Compute Shader
- **Bindings**:
  - `readTexture`: Input image (source for particle generation).
  - `dataTextureC`: Previous frame (source for feedback/advection).
  - `writeTexture`: Output image.
  - `dataTextureA`: Persistent state (next frame's history).
- **Algorithm (Pseudo-code)**:
  ```wgsl
  // 1. Calculate Velocity Field
  let mouse_pos = u.zoom_config.yz;
  let to_mouse = uv - mouse_pos;
  let dist = length(to_mouse);
  // Tangential component (magnetic spiral)
  let tangent = vec2(-to_mouse.y, to_mouse.x) / (dist + 0.001);
  // Radial component (drift)
  let radial = normalize(to_mouse);
  // Combine based on Field Strength
  let strength = u.zoom_params.x * 0.01;
  let velocity = (tangent + radial * 0.1) * strength;

  // 2. Advection (Sample History)
  // Look backwards along the velocity vector
  let sample_uv = uv - velocity;
  let history = textureSampleLevel(dataTextureC, u_sampler, sample_uv, 0.0);

  // 3. Decay
  let decay = u.zoom_params.y; // e.g., 0.95
  let decayed_history = history * decay;

  // 4. Emission (Sparks)
  let input_color = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
  let luminance = dot(input_color.rgb, vec3(0.299, 0.587, 0.114));
  let rand = random(uv, u.config.x); // Helper function
  let spawn_rate = u.zoom_params.z;
  var spark = vec4(0.0);
  if (rand < luminance * spawn_rate) {
    spark = vec4(1.0, 1.0, 1.0, 1.0); // White spark
  }

  // 5. Composition
  let output = max(decayed_history, spark);

  // 6. Write Output
  textureStore(writeTexture, gid.xy, output);
  textureStore(dataTextureA, gid.xy, output);
  ```

## Image Suggestion Draft
*To be added to `public/image_suggestions.md` in the implementation phase:*

```markdown
### Agent Suggestion: Particle Collider Event — @jules — 2024-05-23
- **Prompt:** "A scientific visualization of a high-energy particle collision inside a detector (like the LHC). Tracks of subatomic particles spiral outwards in golden, blue, and red curves from a central collision point. The background is the dark metallic machinery of the detector."
- **Negative prompt:** "space, stars, explosion, fire, cartoon"
- **Tags:** particle physics, science, collider, abstract, visualization
- **Ref image:** `public/images/suggestions/20240523_particle_collision.jpg`
- **Notes / agent context:** Ideally suited for the 'Bubble Chamber' shader which simulates these exact spiraling tracks.
- **Status:** proposed
```

## Execution Steps (Future Implementation)
1. **Create Shader File**: `public/shaders/bubble-chamber.wgsl` with the standard header and the implementation described above.
2. **Register Shader**: Run `node scripts/generate_shader_lists.js` to add the new shader to the application's list.
3. **Add Image Suggestion**: Append the "Image Suggestion Draft" block above to `public/image_suggestions.md`.
4. **Verify**:
   - Check if the shader compiles and runs.
   - Verify `public/shader-lists/*.json` contains the new entry.
