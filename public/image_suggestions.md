# Image Suggestions 🖼️

## Purpose

This file stores curated image suggestions for text-to-image generation and provides guidance on how to write high-quality prompts.

## Table of Contents

- [Purpose](#purpose)
- [How to store suggestions](#how-to-store-suggestions)
- [Suggestion template](#suggestion-template-copy--paste)
- [How to write useful prompts (tips)](#how-to-write-useful-prompts-tips-)
- [Prompt examples](#prompt-examples)
- [Attribution & legal](#attribution--legal)
- [Workflow suggestions](#workflow-suggestions)
- [Agent suggestions](#agent-suggestions)

---

## How to store suggestions

- Recommended directory for actual image files: `public/images/suggestions/` (or reference an external URL).
- File naming convention suggestion: `YYYYMMDD_slug.ext` (e.g., `20260112_sunset-glass-city.jpg`).
- Each suggestion should be a markdown section with a clear title and metadata (see the template below).
- **IMPORTANT:** Do not truncate prompts. Ensure the full text is preserved. However, please keep prompts under 300 tokens when suggesting them.

---

## Suggestion template (copy & paste)

> **Note:** Please append new suggestions to the **Prompt examples** section, inserting them just before the **Attribution & legal** header.

```md
### Suggestion: <Title>
- **Date:** YYYY-MM-DD
- **Prompt:** "<Write the prompt here — be specific about subject, style, lighting, mood, level of detail>"
- **Negative prompt:** "<Optional: words to exclude (e.g., watermark, lowres)>"
- **Tags:** tag1, tag2, tag3 (e.g., photorealism, cyberpunk, portrait)
- **Style / Reference:** (e.g., photorealistic, watercolor, inspired by [Artist])
- **Composition:** (e.g., wide shot, close-up, rule of thirds)
- **Color palette:** (e.g., warm oranges, teal highlights)
- **Aspect ratio:** (e.g., 16:9, 4:5)
- **Reference images:** `public/images/suggestions/<filename>.jpg` or a URL
- **License / Attribution:** (e.g., CC0, public domain, or proprietary — include required credit)
- **Notes:** (any additional details or tips for tweaking generation)
```

---

## How to write useful prompts (tips) 💡

- **Be specific.** Include subject, environment, mood, and any relevant action.
- **Define style and era.** (e.g., "Victorian oil painting", "digital concept art", "photorealistic").
- **Mention lighting and time of day.** (e.g., "golden hour, rim light, volumetric fog").
- **Specify camera & lens cues for photorealism.** (e.g., "35mm, shallow depth of field, bokeh").
- **Tell the model the level of detail.** (e.g., "ultra-detailed, intricate textures, 8k").
- **Use negative prompts to avoid unwanted artifacts.** (e.g., "lowres, watermark, text, missing fingers").
- **Include composition guidance.** (e.g., "rule of thirds, subject centered, foreground interest").
- **Add color direction.** (e.g., "muted pastels", "high contrast teal and orange").
- **Explore Materiality.** Explicitly describe materials to create texture (e.g., "made of translucent gummy candy", "carved from obsidian", "knitted wool").
- **Style Blending.** Combine two distinct styles for unique results (e.g., "Art Nouveau architecture in a Cyberpunk setting").
- **Iterate & record variants.** Save alternate prompts and parameter changes (seed, steps, scale) so results can be reproduced.

### Quality Assurance Checklist ✅
Before adding a suggestion, ask yourself:
1. **Is the subject clear?** (e.g., "A cat" vs "A fluffy Persian cat sitting on a velvet pillow")
2. **Is the lighting defined?** (e.g., "cinematic lighting", "soft morning sun")
3. **Is the style specified?** (e.g., "oil painting", "3D render", "Polaroid photo")
4. **Is the prompt under 300 tokens?** (Concise but descriptive)
5. **Did I check for duplicates?**

### Standardized Tags Guide
To help organize prompts, please use tags from the following categories:
- **Genre:** sci-fi, fantasy, horror, cyberpunk, steampunk, solarpunk, noir, retro.
- **Subject:** landscape, portrait, interior, nature, macro, architecture, still life.
- **Style:** photorealistic, painterly, 3D, isometric, abstract, surreal, minimalist.
- **Mood:** moody, ethereal, cinematic, whimsical, dark, bright.

---

## Prompt examples

### Example 1 — Photorealistic landscape
- **Prompt:** "A photorealistic landscape photograph captures a hyper-realistic sunset over a futuristic glass city. Reflective skyscrapers stretch into the sky, their mirrored facades catching warm sunlight and reflections of the surrounding structures."
- **Negative prompt:** "lowres, watermark, extra limbs, text, cartoonish"
- **Notes:** Use wide aspect (16:9), emphasize warm color grading and crisp reflections. Include camera cues (lens, DOF) for photorealism.

### Example 2 — Painterly portrait
- **Prompt:** "A close-up painterly portrait of an elderly woman rendered in Rembrandt-style oil painting; soft directional Rembrandt lighting creates strong chiaroscuro; warm earth tones and layered brushstrokes define the texture of the skin and clothing."
- **Negative prompt:** "blurry, disfigured, text, oversaturated"
- **Notes:** Use 4:5 aspect; request visible brushstrokes and canvas texture; specify the level of detail.

### Example 3 — Ancient collapsing flume in old-growth forest (detailed)
- **Prompt:** "A photorealistic landscape photograph captures an ancient, collapsing wooden flume extending into a dense, old-growth forest. Moss and thick ivy drape heavily from the decaying trestles, blurring the line between man-made structure and nature."
- **Negative prompt:** "lowres, watermark, overexposed, text, modern structures"
- **Notes:** Aim for a moody, melancholic atmosphere; emphasize volumetric light shafts, rich texture detail, and film grain.

### Suggestion: Cloisonné Enamel Pin
- **Date:** 2028-05-15
- **Prompt:** "A high-resolution macro studio shot of a vintage Cloisonné enamel pin in the shape of a hummingbird. Thin gold wires separate cells filled with vibrant, glossy vitreous enamel in shades of teal, emerald, and sapphire. The metal edges gleam under the studio light."
- **Negative prompt:** "drawing, vector, flat, low resolution, plastic"
- **Tags:** cloisonné, enamel, jewelry, macro, craft
- **Style / Reference:** Cloisonné, Jewelry Photography
- **Composition:** Extreme close-up
- **Color palette:** Teal, Emerald, Sapphire, Gold
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280515_cloisonne_pin.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the glossy texture of the enamel and the metallic partitions.

### Suggestion: Space Junk Orbit
- **Date:** 2028-05-15
- **Prompt:** "A cinematic wide shot of Earth's orbit cluttered with space junk. Broken satellites, spent rocket stages, and twisted metallic debris float in the foreground against the curvature of the blue Earth. The sun flares off a piece of gold foil, creating lens flare."
- **Negative prompt:** "clean space, stars only, cartoon, painting, low detail"
- **Tags:** space junk, sci-fi, orbit, earth, debris
- **Style / Reference:** Sci-Fi Concept Art, Realistic Space
- **Composition:** Wide shot, orbital perspective
- **Color palette:** Earth Blue, Black, Metallic Silver/Gold
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280515_space_junk.jpg`
- **License / Attribution:** CC0
- **Notes:** The sense of clutter and danger is important.

### Suggestion: Color Field Abstraction
- **Date:** 2028-05-15
- **Prompt:** "A monumental abstract painting in the style of Color Field expressionism (Mark Rothko). Large, soft-edged rectangles of luminous rust-orange and deep maroon float on a dark purple canvas background. The paint texture is thin and stained into the weave, creating an emotional, meditative atmosphere."
- **Negative prompt:** "hard edges, geometric, figures, messy, bright pop colors"
- **Tags:** color field, abstract, painting, rothko, minimalist
- **Style / Reference:** Color Field Painting, Mark Rothko
- **Composition:** Abstract layered rectangles
- **Color palette:** Rust Orange, Maroon, Deep Purple
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20280515_color_field.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the soft transition between the colors.

### Suggestion: Wicker Weave Macro
- **Date:** 2028-05-15
- **Prompt:** "A close-up texture shot of a hand-woven rattan wicker chair. The golden-brown natural fibers are interlaced in a complex pattern. Sunlight rakes across the surface, highlighting the fibrous texture, dust motes, and slight fraying of the material."
- **Negative prompt:** "plastic, smooth, perfect, dark, blurry"
- **Tags:** wicker, rattan, texture, macro, craft
- **Style / Reference:** Macro Photography, Texture
- **Composition:** Extreme close-up
- **Color palette:** Golden Brown, Natural Tan
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280515_wicker_weave.jpg`
- **License / Attribution:** CC0
- **Notes:** The lighting should emphasize the depth of the weave.

### Suggestion: Lava Lamp Flow
- **Date:** 2028-05-15
- **Prompt:** "A mesmerizing close-up of a retro 1970s lava lamp. Large, amorphous blobs of red wax stretch and morph as they float upwards in purple liquid. The backlighting makes the wax glow from within. Tiny bubbles and currents are visible."
- **Negative prompt:** "modern lamp, solid plastic, dark, boring, static"
- **Tags:** lava lamp, retro, 70s, abstract, liquid
- **Style / Reference:** Retro Photography, Abstract
- **Composition:** Close-up on the bottle
- **Color palette:** Neon Red, Purple, Glow
- **Aspect ratio:** 9:16
- **Reference images:** `public/images/suggestions/20280515_lava_lamp.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the translucency and inner glow of the wax.

### Suggestion: Ancient Bonsai
- **Date:** 2028-06-01
- **Prompt:** "A majestic, centuries-old Juniper bonsai tree displayed in a minimalist gallery setting. The gnarled, twisted driftwood trunk (jin and shari) contrasts with the manicured pads of vibrant green foliage. Dramatic spotlighting creates stark shadows on the mossy soil."
- **Negative prompt:** "plastic, fake, outdoor forest, blurry, low resolution"
- **Tags:** bonsai, nature, macro, still life, zen
- **Style / Reference:** Studio Photography, Wabi-Sabi
- **Composition:** Eye level, centered
- **Color palette:** Dark Green, Wood Brown, Black, Moss Green
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20280601_bonsai.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the texture of the bark and the needle pads.

### Suggestion: Deconstructivist Architecture
- **Date:** 2028-06-01
- **Prompt:** "A wide architectural shot of a Deconstructivist building (Frank Gehry style). The structure is a chaotic assemblage of sweeping titanium curves, fragmented glass volumes, and tilted walls. It glimmers silver and gold in the afternoon sun against a deep blue sky."
- **Negative prompt:** "square, boxy, brick, traditional, boring"
- **Tags:** architecture, deconstructivism, abstract, modern, metallic
- **Style / Reference:** Deconstructivism, Frank Gehry, Zaha Hadid
- **Composition:** Low angle, looking up
- **Color palette:** Titanium Silver, Sky Blue, Gold reflection
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20280601_deconstructivist.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the fluid, non-rectilinear forms.

### Suggestion: Harris Tweed Macro
- **Date:** 2028-06-01
- **Prompt:** "A macro photography texture shot of authentic Harris Tweed fabric. The coarse, hairy cheviot wool yarns are woven in a herringbone pattern. Close inspection reveals flecks of dyed wool in heather purple, moss green, and rust orange embedded in the grey yarn."
- **Negative prompt:** "smooth, cotton, polyester, printed pattern, blurry"
- **Tags:** tweed, fabric, texture, macro, wool
- **Style / Reference:** Macro Photography, Textile
- **Composition:** Flat lay texture
- **Color palette:** Grey, Rust, Moss Green, Heather
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280601_harris_tweed.jpg`
- **License / Attribution:** CC0
- **Notes:** The 'hairy' texture of the wool is essential.

### Suggestion: North Sea Oil Rig
- **Date:** 2028-06-01
- **Prompt:** "A cinematic wide shot of a massive offshore oil rig in the North Sea during a heavy storm. Giant waves crash against the rusted steel pylons. The structure is a maze of pipes and cranes, illuminated by harsh industrial floodlights and a roaring gas flare."
- **Negative prompt:** "calm sea, sunny, clean, toy, low detail"
- **Tags:** industrial, ocean, storm, oil rig, cinematic
- **Style / Reference:** Industrial Photography, Cinematic
- **Composition:** Wide shot, slightly low angle
- **Color palette:** Storm Grey, Industrial Yellow, Flare Orange, Seafoam White
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20280601_oil_rig.jpg`
- **License / Attribution:** CC0
- **Notes:** Contrast the warm industrial lights with the cold, dark ocean.

### Suggestion: Tsunami Wave
- **Date:** 2028-06-01
- **Prompt:** "A terrifyingly realistic seascape of a massive tsunami wave moments before breaking. The wall of water towers over the viewer, dark teal and ominous. The crest is a churning mass of white foam. The water surface is textured with ripples and spray."
- **Negative prompt:** "surfing, sunny beach, blue water, painting, cartoon"
- **Tags:** tsunami, wave, ocean, danger, nature
- **Style / Reference:** Landscape Photography, Disaster Movie
- **Composition:** Low angle, looking up at the wave face
- **Color palette:** Deep Teal, Foam White, Dark Grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280601_tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the scale and power of the water.

### Suggestion: Giant's Causeway Basalt
- **Date:** 2028-06-15
- **Prompt:** "A dramatic landscape photograph of hexagonal basalt columns at the Giant's Causeway. The interlocking volcanic stones form natural steps leading into a rough ocean. The wet black rock reflects the moody, overcast sky. Long exposure blurs the crashing waves into a white mist."
- **Negative prompt:** "brick, man-made, square stones, sunny, dry"
- **Tags:** landscape, basalt, geology, nature, dramatic
- **Style / Reference:** Landscape Photography, National Geographic
- **Composition:** Wide angle, leading lines
- **Color palette:** Volcanic Black, Ocean Blue, White Foam, Grey Sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280615_basalt.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the geometric regularity of the natural rock formation.

### Suggestion: Kaleidoscope Mandala
- **Date:** 2028-06-15
- **Prompt:** "A mesmerizing, perfectly symmetrical kaleidoscope pattern. Fragments of translucent colored glass (ruby red, sapphire blue, amber) and mirrors create an intricate, fractal-like mandala. Backlighting makes the colors glow with intense vibrancy against a black void."
- **Negative prompt:** "asymmetrical, messy, painting, dull colors, opaque"
- **Tags:** kaleidoscope, abstract, pattern, glass, mandala
- **Style / Reference:** Abstract Art, Psychedelic
- **Composition:** Centered, radial symmetry
- **Color palette:** Jewel Tones, Black Background
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280615_kaleidoscope.jpg`
- **License / Attribution:** CC0
- **Notes:** Symmetrical precision and translucency are key.

### Suggestion: Savanna Termite Mound
- **Date:** 2028-06-15
- **Prompt:** "A low-angle shot of a massive, cathedral-like termite mound rising from the African savanna. The red clay structure is tall and jagged, glowing in the warm light of a setting sun. In the background, a flat-topped acacia tree is silhouetted against a purple twilight sky."
- **Negative prompt:** "small mound, dirt pile, forest, daytime, snow"
- **Tags:** nature, landscape, insect architecture, africa, sunset
- **Style / Reference:** Nature Photography, Documentary
- **Composition:** Low angle, environmental portrait
- **Color palette:** Red Clay, Sunset Orange, Twilight Purple, Silhouette Black
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20280615_termite_mound.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the architectural scale of the mound.

### Suggestion: Synthetist Breton Landscape
- **Date:** 2028-06-15
- **Prompt:** "A landscape painting in the style of Synthetism (Paul Gauguin). Bold, flat areas of pure, unnatural color (red grass, yellow sky) are separated by dark, rhythmic outlines. The composition is flattened, emphasizing the decorative pattern of the rolling hills and trees."
- **Negative prompt:** "realistic, detailed shading, gradient, impressionist, 3D"
- **Tags:** synthetism, painting, cloisonnism, landscape, abstract
- **Style / Reference:** Synthetism, Paul Gauguin, Émile Bernard
- **Composition:** Flat, decorative
- **Color palette:** Red, Yellow, Dark Blue, Green
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20280615_synthetism.jpg`
- **License / Attribution:** CC0
- **Notes:** The dark outlines (Cloisonnism) and flat color fields are essential.

### Suggestion: Corduroy Fabric Macro
- **Date:** 2028-06-15
- **Prompt:** "A macro photography texture shot of vintage mustard yellow corduroy fabric. The parallel vertical ridges (wales) are soft and velvety. The lighting is directional, creating deep shadows in the channels between the ridges, highlighting the tactile weave of the cotton."
- **Negative prompt:** "smooth, denim, silk, flat, printed pattern"
- **Tags:** corduroy, fabric, texture, macro, vintage
- **Style / Reference:** Macro Photography, Texture
- **Composition:** Flat lay texture
- **Color palette:** Mustard Yellow, Shadow Brown
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280615_corduroy.jpg`
- **License / Attribution:** CC0
- **Notes:** The lighting must reveal the depth of the ridges.
### Suggestion: Hard Surface Mecha Helmet
- **Date:** 2028-06-15
- **Prompt:** "A clean, high-fidelity 3D render of a sci-fi mecha helmet in the 'Hard Surface' modeling style. The design features precise panel lines, functional vents, and a mix of matte grey and glossy white materials. Studio lighting emphasizes the smooth curves and sharp edges."
- **Negative prompt:** "organic, bio-mechanical, messy, rusty, low poly"
- **Tags:** hard surface, 3d, sci-fi, mecha, helmet
- **Style / Reference:** Hard Surface Modeling, Industrial Design
- **Composition:** 3/4 view, studio background
- **Color palette:** White, Grey, Orange accents
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280615_hard_surface.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the precision of the geometry.

### Suggestion: Sandpaper Desert Abstract
- **Date:** 2028-06-15
- **Prompt:** "A macro photography shot of coarse-grit brown sandpaper. The lighting is low and raking, casting long shadows from the individual abrasive grains, making the texture look like a rocky Martian desert landscape from above."
- **Negative prompt:** "smooth, paper, flat lighting, blurry"
- **Tags:** sandpaper, macro, texture, abstract, landscape
- **Style / Reference:** Macro Photography, Abstract
- **Composition:** Top-down macro
- **Color palette:** Rust Brown, Tan, Shadow Black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280615_sandpaper.jpg`
- **License / Attribution:** CC0
- **Notes:** Use the scale ambiguity to create a landscape effect.

### Suggestion: Morning Dew Spiderweb
- **Date:** 2028-06-15
- **Prompt:** "A delicate macro shot of a spiderweb covered in morning dew. Thousands of tiny water droplets cling to the silk strands. Each droplet acts as a lens, refracting the green garden background. The depth of field is very shallow."
- **Negative prompt:** "dry web, messy background, scary spider, cartoon"
- **Tags:** spiderweb, dew, macro, nature, bokeh
- **Style / Reference:** Macro Photography, Nature
- **Composition:** Centered web
- **Color palette:** Silver (web), blurred Green background
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20280615_spiderweb.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the refraction in the droplets.

### Suggestion: Ashcan School Boxing Match
- **Date:** 2028-06-15
- **Prompt:** "A gritty, dynamic oil painting in the style of the Ashcan School (George Bellows). Two boxers fight in a smoky, dimly lit ring. The brushwork is loose, dark, and energetic. The crowd in the shadows is a sea of vague faces."
- **Negative prompt:** "bright, clean, modern, digital art, photorealistic"
- **Tags:** ashcan school, painting, boxing, gritty, american realism
- **Style / Reference:** Ashcan School, George Bellows
- **Composition:** Eye level, dynamic action
- **Color palette:** Dark Brown, Black, Smoky Grey, Flesh Tones
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20280615_ashcan_boxing.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the raw energy and the dark atmosphere.

### Suggestion: Wet Slate Texture
- **Date:** 2028-06-15
- **Prompt:** "A top-down texture shot of wet, dark grey slate tiles. Rainwater coats the uneven, flaky surface of the rock, creating specular highlights. The layers of the sedimentary stone are visible at the chipped edges."
- **Negative prompt:** "dry, smooth, concrete, artificial tile, seamless texture"
- **Tags:** slate, rock, texture, wet, rain
- **Style / Reference:** Texture Photography, Nature
- **Composition:** Flat lay
- **Color palette:** Dark Grey, Blue-Grey, White reflections
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280615_wet_slate.jpg`
- **License / Attribution:** CC0
- **Notes:** The wetness enhances the color and contrast of the stone.

### Suggestion: Graphene Lattice
- **Date:** 2028-07-01
- **Prompt:** "A high-fidelity scientific visualization of a single sheet of Graphene. The hexagonal honeycomb lattice of carbon atoms floats in a dark void. The atoms are represented as glowing spheres connected by bonds. The sheet ripples like a nanoscopic fabric."
- **Negative prompt:** "complex 3D structure, diamond, messy, low resolution, drawing"
- **Tags:** science, graphene, material, physics, 3d
- **Style / Reference:** Scientific Visualization
- **Composition:** Centered, abstract
- **Color palette:** Glowing Blue, Black, White
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280701_graphene.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the hexagonal pattern.

### Suggestion: Neon Gas Tube
- **Date:** 2028-07-01
- **Prompt:** "A close-up macro photography shot of a lit neon sign tube. The glass tube glows with an intense, buzzing red light from the neon gas inside. Dark paint blocks out sections of the tube. Dust motes dance in the red glow against a dark brick background."
- **Negative prompt:** "led, digital sign, flat, cartoon, daylight"
- **Tags:** neon, light, macro, texture, urban
- **Style / Reference:** Macro Photography, Urban
- **Composition:** Extreme close-up
- **Color palette:** Neon Red, Brick Black, Orange glow
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20280701_neon_tube.jpg`
- **License / Attribution:** CC0
- **Notes:** The glow should look volumetric.

### Suggestion: Synthetism Landscape
- **Date:** 2028-07-01
- **Prompt:** "A vibrant landscape painting in the style of Synthetism (Paul Gauguin, Émile Bernard). Large, flat areas of bold, unnatural color are separated by dark outlines (Cloisonnism). A red meadow sits beneath a yellow sky. The forms are simplified and symbolic, lacking detail."
- **Negative prompt:** "realistic, gradient, shading, 3D, detailed"
- **Tags:** synthetism, painting, cloisonnism, abstract, landscape
- **Style / Reference:** Synthetism, Post-Impressionism
- **Composition:** Simplified, flat
- **Color palette:** Red, Yellow, Blue, Black outlines
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20280701_synthetism.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the flatness and the outlines.

### Suggestion: Corduroy Texture
- **Date:** 2028-07-01
- **Prompt:** "A macro texture shot of vintage mustard-yellow corduroy fabric. The parallel vertical ridges (wales) are soft and velvety, catching the light. The grooves between them show the weave of the base fabric. The material looks worn and comfortable."
- **Negative prompt:** "denim, smooth, silk, pattern, distant"
- **Tags:** corduroy, fabric, texture, macro, vintage
- **Style / Reference:** Macro Photography, Texture
- **Composition:** Flat lay texture
- **Color palette:** Mustard Yellow, shadow brown
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280701_corduroy.jpg`
- **License / Attribution:** CC0
- **Notes:** The light should rake across the ridges.

### Suggestion: Offshore Wind Farm
- **Date:** 2028-07-01
- **Prompt:** "A majestic landscape shot of an offshore wind farm at twilight. Rows of massive white turbines extend to the horizon in the calm sea. The blades are blurred by motion. The sky is a deep indigo with a faint orange glow on the horizon."
- **Negative prompt:** "land, mountains, sunny, noisy, chaotic"
- **Tags:** wind farm, energy, landscape, ocean, calm
- **Style / Reference:** Landscape Photography, Minimalist
- **Composition:** Wide shot, repetition
- **Color palette:** Indigo, White, Sunset Orange
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20280701_wind_farm.jpg`
- **License / Attribution:** CC0
- **Notes:** Use slow shutter speed for the blades.
### Suggestion: Graphene Atomic Lattice
- **Date:** 2028-06-15
- **Prompt:** "A scientific visualization of a single sheet of Graphene. The hexagonal lattice structure of carbon atoms glows with a faint blue electric field. The background is a dark void. Shallow depth of field focuses on the foreground atoms, blurring the distant grid."
- **Negative prompt:** "messy, organic, blurry, low resolution, drawing"
- **Tags:** graphene, science, atomic, 3d, macro
- **Style / Reference:** Scientific Visualization, 3D Render
- **Composition:** Macro texture, depth of field
- **Color palette:** Electric Blue, Carbon Black, Void
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280615_graphene.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the hexagonal geometry and the glow.

### Suggestion: Crosshatch Seafarer
- **Date:** 2028-06-15
- **Prompt:** "A detailed pen and ink crosshatching portrait of an old weathered sailor. Thousands of intersecting fine black ink lines create the shading and texture of his wrinkled skin and thick beard. The style resembles an old engraving or banknote portrait."
- **Negative prompt:** "color, grey wash, pencil, smudge, smooth shading"
- **Tags:** crosshatching, ink, portrait, engraving, art
- **Style / Reference:** Pen and Ink, Engraving
- **Composition:** Portrait, centered
- **Color palette:** Black Ink, White Paper
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20280615_crosshatch_sailor.jpg`
- **License / Attribution:** CC0
- **Notes:** The shading must come from the density of the lines, not grey wash.

### Suggestion: Wind Tunnel Streamlines
- **Date:** 2028-06-15
- **Prompt:** "A sleek silver concept car inside an industrial wind tunnel. Streams of white smoke flow smoothly over the aerodynamic curves of the vehicle. A sheet of green laser light slices through the smoke, revealing the turbulence. Dark, technical background."
- **Negative prompt:** "static smoke, messy, cartoon, drawing, daylight"
- **Tags:** wind tunnel, aerodynamic, car, smoke, industrial
- **Style / Reference:** Industrial Photography, Scientific
- **Composition:** Side profile, dynamic flow
- **Color palette:** Silver, Laser Green, Smoke White, Black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20280615_wind_tunnel.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the smooth laminar flow of the smoke.

### Suggestion: Neon Sign Boneyard
- **Date:** 2028-07-01
- **Prompt:** "A cinematic shot of a 'neon boneyard' at night. Piles of discarded, rusted vintage neon signs (motel, diner, cocktails) lie in tall grass. Some are still flickering and buzzing, casting eerie red and blue light on the wet ground. Rain falls softly."
- **Negative prompt:** "clean, new signs, city street, daylight, flat"
- **Tags:** neon, abandoned, vintage, atmospheric, night
- **Style / Reference:** Urban Exploration, Cinematic
- **Composition:** Wide shot, chaotic piles
- **Color palette:** Neon Red, Blue, Rust, Grass Green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280701_neon_boneyard.jpg`
- **License / Attribution:** CC0
- **Notes:** The juxtaposition of light and decay is the theme.

### Suggestion: Basalt Column Coast
- **Date:** 2028-07-01
- **Prompt:** "A dramatic landscape photograph of a coastline made of hexagonal basalt columns (like the Giant's Causeway). The dark, geometric rock formations step down into a rough, foaming ocean. The sky is overcast and moody, enhancing the alien look of the geology."
- **Negative prompt:** "round rocks, sand beach, sunny, bright, boring"
- **Tags:** basalt, geology, landscape, coast, geometric
- **Style / Reference:** Landscape Photography, National Geographic
- **Composition:** Wide shot, leading lines
- **Color palette:** Basalt Black, Ocean Blue, Foam White, Grey Sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280701_basalt_coast.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the hexagonal geometry of the rocks.

### Suggestion: Tachisme Action Painting
- **Date:** 2028-07-15
- **Prompt:** "A chaotic, energetic abstract painting in the style of Tachisme. Spontaneous splotches, drips, and blobs of thick oil paint are flung onto the canvas. There is no central focal point, just a field of raw emotion and gesture. Colors are deep crimson, jet black, and splashes of titanium white."
- **Negative prompt:** "realistic, figurative, smooth, digital art, vector"
- **Tags:** tachisme, abstract, painting, energetic, chaos
- **Style / Reference:** Tachisme, Abstract Expressionism
- **Composition:** All-over composition
- **Color palette:** Crimson, Black, White
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20280715_tachisme.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the spontaneity and texture of the paint drips.

### Suggestion: Kaleidoscopic Flower Mandala
- **Date:** 2028-07-15
- **Prompt:** "A mesmerizing kaleidoscope pattern formed from photographic elements of vibrant tropical flowers (orchids, hibiscus, bird of paradise). The image is perfectly symmetrical, radiating from the center in complex, repeating geometric layers. The background is deep black to make the colors pop."
- **Negative prompt:** "asymmetrical, messy, drawing, low resolution, blurry"
- **Tags:** kaleidoscope, mandala, floral, geometric, pattern
- **Style / Reference:** Kaleidoscope Photography, Psychedelic Art
- **Composition:** Centered, radial symmetry
- **Color palette:** Hot Pink, Orange, Purple, Black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280715_kaleidoscope.jpg`
- **License / Attribution:** CC0
- **Notes:** The symmetry must be perfect.

### Suggestion: Hard Edge Geometric Abstraction
- **Date:** 2028-07-15
- **Prompt:** "A minimalist Hard Edge painting featuring sharp, clean transitions between flat areas of uniform color. Large geometric shapes (circles, arcs, and squares) intersect with precise edges. The paint application is smooth with no visible brushstrokes."
- **Negative prompt:** "texture, brushstrokes, gradient, messy, realistic"
- **Tags:** hard edge, abstract, geometric, painting, minimalist
- **Style / Reference:** Hard Edge Painting, Ellsworth Kelly
- **Composition:** Geometric, balanced
- **Color palette:** Cobalt Blue, Canary Yellow, Stark White
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20280715_hard_edge.jpg`
- **License / Attribution:** CC0
- **Notes:** The edges must be razor-sharp.

### Suggestion: Floating Chiffon Scarf
- **Date:** 2028-08-01
- **Prompt:** "A dreamy, ethereal photography shot of a long piece of sheer pink chiffon fabric floating in the wind against a clear blue sky. Sunlight filters through the translucent material, creating soft folds and varying levels of opacity. The fabric looks weightless."
- **Negative prompt:** "heavy fabric, opaque, cotton, dark, indoor"
- **Tags:** chiffon, fabric, ethereal, wind, texture
- **Style / Reference:** Fashion Photography, Abstract
- **Composition:** Centered, floating
- **Color palette:** Pastel Pink, Sky Blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280801_chiffon.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the translucency and the fluid shape of the fabric.

### Suggestion: Synthetism Breton Landscape
- **Date:** 2028-08-01
- **Prompt:** "A landscape painting of the Brittany coast in the style of Synthetism (Paul Gauguin). Flat areas of bold, unnatural color (red ground, yellow trees, blue rocks) are separated by dark, rhythmic outlines. The composition is simplified, decorative, and expressive."
- **Negative prompt:** "realistic, detailed, 3D, perspective, impressionist"
- **Tags:** synthetism, painting, landscape, cloisonnism, art
- **Style / Reference:** Synthetism, Paul Gauguin, Emile Bernard
- **Composition:** Flat, decorative
- **Color palette:** Red, Yellow, Indigo, Black outlines
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20280801_synthetism.jpg`
- **License / Attribution:** CC0
- **Notes:** The dark outlines and flat colors are the defining features.

### Suggestion: Neoclassical Marble Hall
- **Date:** 2028-09-01
- **Prompt:** "A grand, photorealistic interior shot of a Neoclassical hall. Massive white marble columns with Corinthian capitals line the room. A polished checkerboard floor reflects the light. Statues of greek heroes stand in alcoves. Soft, natural light streams in from high clerestory windows."
- **Negative prompt:** "modern, clutter, dark, dirt, low resolution"
- **Tags:** neoclassicism, architecture, marble, interior, grand
- **Style / Reference:** Neoclassical Architecture, Photorealism
- **Composition:** One-point perspective, wide angle
- **Color palette:** Marble White, Gold, Stone Grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280901_neoclassical.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the symmetry and the pristine nature of the marble.

### Suggestion: Iridescent Cellophane Sculpture
- **Date:** 2028-09-01
- **Prompt:** "A studio macro shot of an abstract sculpture made of crumpled iridescent cellophane. The material is translucent and crinkled, refracting light into sharp shards of cyan, magenta, and yellow. It floats against a stark black background."
- **Negative prompt:** "smooth, opaque, plastic bag, dull, blurry"
- **Tags:** cellophane, plastic, iridescent, abstract, macro
- **Style / Reference:** Studio Photography, Abstract
- **Composition:** Centered object
- **Color palette:** Iridescent Cyan, Magenta, Yellow, Black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280901_cellophane.jpg`
- **License / Attribution:** CC0
- **Notes:** The sharp, crinkled texture is the key.

### Suggestion: Supernova Remnant
- **Date:** 2028-09-01
- **Prompt:** "A spectacular space telescope image of a supernova remnant. Expanding shells of ionized gas glow in vibrant shockwaves of red (sulfur), green (hydrogen), and blue (oxygen). A dense starfield fills the background. The structure is chaotic and filamentary."
- **Negative prompt:** "planet, atmosphere, cartoon, painting, lowres"
- **Tags:** supernova, space, astronomy, nebula, colorful
- **Style / Reference:** Astrophotography, Hubble/Webb
- **Composition:** Wide cosmic view
- **Color palette:** Nebula Red, Green, Blue, Star White
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20280901_supernova.jpg`
- **License / Attribution:** CC0
- **Notes:** Mimic the false-color palette used in scientific astrophotography.

### Suggestion: Tide Pool Microcosm
- **Date:** 2028-09-01
- **Prompt:** "A top-down, crystal-clear view into a rocky tide pool. Colorful starfish (ochre and purple) cling to the rocks. Green sea anemones wave their tentacles. Barnacles and small crabs are visible. The water surface is still, reflecting the sky."
- **Negative prompt:** "murky, dry, sand only, blurry, drawing"
- **Tags:** tide pool, nature, ocean, marine life, colorful
- **Style / Reference:** Nature Photography, National Geographic
- **Composition:** Top-down (flat lay)
- **Color palette:** Starfish Orange, Purple, Anemone Green, Rock Grey
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20280901_tide_pool.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the water looks transparent but present.

### Suggestion: Misty Fjord Kayak
- **Date:** 2028-09-01
- **Prompt:** "A serene, moody landscape shot of a kayak floating in a massive Norwegian fjord. Towering, steep cliffs rise vertically from the dark, glassy water, disappearing into low-hanging mist. The scale is immense. The lighting is soft and diffuse."
- **Negative prompt:** "sunny, bright, busy, motorboat, tropical"
- **Tags:** fjord, landscape, moody, nature, kayak
- **Style / Reference:** Landscape Photography, Cinematic
- **Composition:** Wide shot, tiny subject (kayak) for scale
- **Color palette:** Slate Grey, Deep Blue, Mist White, Kayak Red
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280901_fjord.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the verticality of the cliffs and the smallness of the kayak.

### Suggestion: Gothic Revival Skyscraper
- **Date:** 2028-09-15
- **Prompt:** "A towering Neo-Gothic skyscraper rising above a modern metropolis at twilight. The building features flying buttresses, pointed arches, and gargoyles, but is constructed from sleek steel and glass. Fog swirls around the illuminated spire."
- **Negative prompt:** "old stone, ruins, medieval, blurry, low angle"
- **Tags:** gothic revival, architecture, skyscraper, city, atmospheric
- **Style / Reference:** Architectural Visualization, Gotham City
- **Composition:** Low angle, looking up
- **Color palette:** Steel Blue, Fog Grey, Warm Window Light
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20280915_gothic_skyscraper.jpg`
- **License / Attribution:** CC0
- **Notes:** Contrast the historic style with modern materials.

### Suggestion: Iceberg Underwater Cathedral
- **Date:** 2028-09-15
- **Prompt:** "A split-level landscape shot of a massive iceberg in the Antarctic. Above the water, it is a blinding white jagged peak. Below the waterline, the ice forms a deep blue, cathedral-like structure with caves and ridges fading into the abyss."
- **Negative prompt:** "water only, sky only, dark, scary, dirty ice"
- **Tags:** iceberg, underwater, landscape, nature, split-level
- **Style / Reference:** Nature Photography, National Geographic
- **Composition:** Split-level (half over/under water)
- **Color palette:** Ice White, Deep Ocean Blue, Cyan
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20280915_iceberg.jpg`
- **License / Attribution:** CC0
- **Notes:** The gradient of blue in the underwater ice is crucial.

### Suggestion: Cathedral Termite Mound
- **Date:** 2028-09-15
- **Prompt:** "A majestic, castle-like termite mound standing tall in the African savanna at golden hour. The red clay structure is incredibly detailed, with spires and ventilation chimneys. Silhouetted acacia trees and a setting sun are in the background."
- **Negative prompt:** "small ant hill, dirt pile, blurry, noon lighting"
- **Tags:** termite mound, nature, landscape, texture, savanna
- **Style / Reference:** Nature Photography, Macro texture
- **Composition:** Eye level, environmental portrait
- **Color palette:** Red Clay, Golden Sunlight, Savanna Green
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20280915_termite_mound.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the architectural complexity of the mound.

### Suggestion: Fireworks Reflection
- **Date:** 2028-09-15
- **Prompt:** "A long-exposure photograph of a grand fireworks display over a calm bay. Bursts of red, gold, and green light flower in the night sky. The smooth water surface acts as a mirror, creating perfect, elongated reflections of the explosions."
- **Negative prompt:** "smoke obscuring view, short exposure, dots, daytime"
- **Tags:** fireworks, long exposure, night, reflection, celebration
- **Style / Reference:** Night Photography, Long Exposure
- **Composition:** Wide shot, symmetry
- **Color palette:** Black, Neon Red, Gold, Green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20280915_fireworks.jpg`
- **License / Attribution:** CC0
- **Notes:** The long exposure trails are the key aesthetic.

### Suggestion: Weaver Bird Nests
- **Date:** 2028-09-15
- **Prompt:** "A telephoto shot of a colony of intricate weaver bird nests hanging from the branches of a thorny acacia tree. The nests are spherical and woven from green and yellow grass blades. A bright yellow weaver bird is perched at the entrance of one nest."
- **Negative prompt:** "messy, studio, drawing, cartoon, dead tree"
- **Tags:** bird nest, nature, wildlife, texture, weaving
- **Style / Reference:** Wildlife Photography, National Geographic
- **Composition:** Close-up, depth of field
- **Color palette:** Grass Green, Straw Yellow, Sky Blue
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20280915_weaver_nests.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the woven texture of the grass.

### Suggestion: Mannerist Hologram Portrait
- **Date:** 2028-10-01
- **Prompt:** "A futuristic holographic portrait of a noble figure, rendered in the style of Mannerism (Parmigianino). The figure has an elongated neck and fingers, glowing with neon blue and pink light. The hologram flickers slightly, revealing a dark, tech-noir city in the background."
- **Negative prompt:** "photorealistic, proportional, normal, daylight, solid"
- **Tags:** mannerism, hologram, sci-fi, portrait, neon
- **Style / Reference:** Mannerism, Cyberpunk
- **Composition:** Portrait, elongated verticality
- **Color palette:** Neon Blue, Hot Pink, Black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20281001_mannerist_hologram.jpg`
- **License / Attribution:** CC0
- **Notes:** The elongation of the figure is the key Mannerist element.

### Suggestion: Iridescent Metamorphosis
- **Date:** 2028-10-01
- **Prompt:** "A macro photography shot of a translucent alien cocoon hanging from a bioluminescent vine in a dark forest. Inside the cocoon, a glowing, shifting silhouette of a creature is visible. The surface of the cocoon is wet and iridescent, reflecting the surrounding jungle lights."
- **Negative prompt:** "dry, opaque, butterfly, daylight, cartoon"
- **Tags:** cocoon, alien, macro, nature, bioluminescence
- **Style / Reference:** Macro Photography, Sci-Fi Nature
- **Composition:** Close-up, centered
- **Color palette:** Bioluminescent Green, Iridescent Pearl, Black
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20281001_alien_cocoon.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the translucency and the mystery of what's inside.

### Suggestion: Holographic Concert
- **Date:** 2028-10-01
- **Prompt:** "A massive stadium concert scene where the performers are giant, towering holographic avatars made of pure light. They loom over a sea of thousands of fans holding glow sticks. Lasers cut through the stage fog. The scale is immense and electric."
- **Negative prompt:** "small stage, empty, daytime, acoustic, boring"
- **Tags:** concert, hologram, cyberpunk, crowd, atmospheric
- **Style / Reference:** Concert Photography, Cyberpunk
- **Composition:** Wide angle, looking over the crowd
- **Color palette:** Laser Green, Stage Purple, Electric Blue
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20281001_holographic_concert.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the scale of the holograms compared to the crowd.

### Suggestion: Offshore Wind Array
- **Date:** 2028-10-01
- **Prompt:** "A minimalist, high-angle aerial drone shot of an endless grid of white offshore wind turbines emerging from heavy morning fog. The dark grey ocean is calm. The turbines fade into the white mist in the distance, creating a sense of infinity and silence."
- **Negative prompt:** "sunny, blue sky, land, birds, messy"
- **Tags:** wind farm, ocean, minimalist, fog, aerial
- **Style / Reference:** Aerial Photography, Minimalism
- **Composition:** Symmetrical, repetition
- **Color palette:** Fog White, Turbine White, Ocean Grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20281001_wind_farm.jpg`
- **License / Attribution:** CC0
- **Notes:** The repetition and the fading into fog are crucial.

### Suggestion: Perseid Meteor Shower
- **Date:** 2028-10-01
- **Prompt:** "A breathtaking long-exposure landscape shot of the Perseid meteor shower over a red rock desert canyon. Star trails form concentric circles around Polaris. Bright, colorful meteor streaks (green and gold) cut across the purple night sky. The canyon is dimly lit by starlight."
- **Negative prompt:** "daylight, clouds, airplane trails, noisy, short exposure"
- **Tags:** meteor shower, astronomy, landscape, desert, long exposure
- **Style / Reference:** Astrophotography, Long Exposure
- **Composition:** Wide landscape, sky dominant
- **Color palette:** Night Sky Purple, Star Trail White, Meteor Green/Gold
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20281001_meteor_shower.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the meteor streaks look like light trails, not solid objects.

### Suggestion: Arashiyama Bamboo Lanterns
- **Date:** 2028-10-15
- **Prompt:** "A magical night scene in the Arashiyama Bamboo Grove. Towering green bamboo stalks stretch endlessly upwards. The path is illuminated by hundreds of warm, glowing paper lanterns floating in the air. Fireflies dance in the mist. The atmosphere is ethereal and serene."
- **Negative prompt:** "daylight, sun, tourists, messy, scary, dark"
- **Tags:** bamboo, forest, lantern, night, atmospheric
- **Style / Reference:** Landscape Photography, Fantasy
- **Composition:** Vertical, leading lines
- **Color palette:** Bamboo Green, Lantern Gold, Mist White, Night Blue
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20281015_bamboo_lanterns.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the verticality of the bamboo and the glow of the lanterns.

### Suggestion: Coral Spawning Spectacle
- **Date:** 2028-10-15
- **Prompt:** "A spectacular underwater macro shot of a coral reef during a mass spawning event. Billions of tiny pink and orange gametes are released into the water column like an underwater snowstorm. The scene is lit by moonlight filtering from the surface and bioluminescence."
- **Negative prompt:** "fish, murky, daylight, low resolution, blurry"
- **Tags:** coral, spawning, underwater, macro, nature
- **Style / Reference:** Underwater Photography, National Geographic
- **Composition:** Macro, chaotic but beautiful
- **Color palette:** Coral Pink, Orange, Deep Blue, Moonlight White
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20281015_coral_spawning.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the density of the spawn.

### Suggestion: Glacial Blue Cave
- **Date:** 2028-10-15
- **Prompt:** "Inside a mesmerizing glacial ice cave. The walls are made of translucent, scalloped blue ice that glows with transmitted sunlight. The floor is a frozen river. The texture of the ice bubbles and cracks is visible in high detail."
- **Negative prompt:** "rock cave, dark, dirty ice, snow, surface"
- **Tags:** glacier, ice cave, nature, texture, blue
- **Style / Reference:** Landscape Photography, Abstract
- **Composition:** Interior view, leading lines
- **Color palette:** Ice Blue, Cyan, White, Deep Blue
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20281015_ice_cave.jpg`
- **License / Attribution:** CC0
- **Notes:** The translucency of the blue ice is the key visual.

### Suggestion: Golden Hive Interior
- **Date:** 2028-10-15
- **Prompt:** "A macro photography shot from inside a honeybee hive. Golden hexagonal honeycomb cells are filled with glistening honey and pollen. Worker bees crawl over the surface. The lighting is warm and amber, creating a cozy, busy atmosphere."
- **Negative prompt:** "outside hive, swarm, scary, wasp, dirt"
- **Tags:** beehive, honey, macro, nature, texture
- **Style / Reference:** Macro Photography, Nature
- **Composition:** Extreme close-up
- **Color palette:** Honey Gold, Amber, Bee Yellow/Black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20281015_beehive.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the geometric perfection of the honeycomb.

### Suggestion: Futuristic Eco-Airport
- **Date:** 2028-10-15
- **Prompt:** "A wide, cinematic shot of a futuristic Solarpunk airport hub. The terminal is a massive organic structure made of glass and timber, filled with hanging gardens. Silent, electric aircraft with blended-wing bodies are docked at the gates. Sunlight floods the atrium."
- **Negative prompt:** "concrete, smog, grey, traditional plane, busy crowds"
- **Tags:** airport, solarpunk, futuristic, architecture, sci-fi
- **Style / Reference:** Architectural Visualization, Solarpunk
- **Composition:** Wide interior/exterior blend
- **Color palette:** Sky Blue, Leaf Green, Timber Brown, Glass White
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20281015_eco_airport.jpg`
- **License / Attribution:** CC0
- **Notes:** Combine high-tech transport with lush nature.

### Micro-Cosmos
- **Date:** 2024-05-27
- **Prompt:** "A microscopic view of a teeming liquid universe, filled with procedural microorganisms, drifting particles, and organic structures. Deep blue/cyan/purple fluid background with vignettes."
- **Negative prompt:** macroscopic, blurry, low resolution, artifacts, solid background
- **Tags:** biological, organic, microscopic, liquid, life, floating, generative
- **Style / Reference:** Scientific Visualization, Electron Microscope
- **Composition:** Close-up, Depth of Field
- **Color palette:** Deep Blue, Cyan, Purple, Bioluminescent Orange
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/micro_cosmos.jpg`
- **License / Attribution:** CC0
- **Notes:** Generative shader concept 'Micro-Cosmos'.
### Suggestion: Orphic Sound Waves
- **Date:** 2028-11-01
- **Prompt:** "A vibrant abstract painting in the style of Orphism (Robert Delaunay). Circular forms and colorful discs intersect to visualize the rhythm of music. Bright, contrasting colors (orange, blue, green) create a sensation of movement and vibration. The composition is dynamic and non-representational."
- **Negative prompt:** "realistic, figurative, dull colors, black and white, photograph"
- **Tags:** orphism, abstract, painting, colorful, music
- **Style / Reference:** Orphism, Robert Delaunay, Sonia Delaunay
- **Composition:** Circular, rhythmic
- **Color palette:** Rainbow, contrasting complementary colors
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20281101_orphism.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the "simultaneity" of colors and circular geometry.

### Suggestion: Foggy Victorian Opera
- **Date:** 2028-11-01
- **Prompt:** "A dramatic, atmospheric shot of the stage in a grand Victorian Opera House. The stage is filled with swirling, heavy dry ice fog. A single spotlight cuts through the mist, illuminating a masked figure in a black cape. The ornate gold balconies are faintly visible in the background gloom."
- **Negative prompt:** "bright, daylight, modern, clean, neon, cartoon"
- **Tags:** opera, victorian, fog, atmospheric, dramatic
- **Style / Reference:** Cinematic, Gothic, Phantom of the Opera
- **Composition:** Wide shot from audience
- **Color palette:** Deep Red (curtains), Fog White, Gold, Shadow Black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20281101_opera_fog.jpg`
- **License / Attribution:** CC0
- **Notes:** The density of the dry ice fog is the key texture.

### Suggestion: Pyrite Cube Cluster
- **Date:** 2028-11-01
- **Prompt:** "A high-resolution macro photography shot of a natural cluster of Iron Pyrite (Fool's Gold) crystals. The perfect metallic cubes interlock with each other. The surfaces are brassy-yellow and highly reflective, showing natural striations. The background is a dark slate rock."
- **Negative prompt:** "gold bar, jewelry, processed metal, blurry, low resolution"
- **Tags:** pyrite, crystal, macro, geometry, mineral
- **Style / Reference:** Macro Photography, Mineralogy
- **Composition:** Extreme close-up
- **Color palette:** Metallic Gold/Brass, Slate Grey
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20281101_pyrite.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the perfect cubic geometry which occurs naturally.

### Suggestion: Rayonist Night City
- **Date:** 2028-11-01
- **Prompt:** "An abstract painting of a modern city at night in the style of Rayonism (Mikhail Larionov). Beams of light ('rays') fracture the image, representing the reflection of neon signs and streetlights. The buildings are dissolved into intersecting lines of light and energy."
- **Negative prompt:** "realistic, detailed buildings, smooth, traditional landscape"
- **Tags:** rayonism, abstract, city, night, painting
- **Style / Reference:** Rayonism, Mikhail Larionov, Natalia Goncharova
- **Composition:** Diagonal rays, fragmented
- **Color palette:** Neon Blue, Yellow, Red, Black
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20281101_rayonism.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the "rays" of light rather than the objects themselves.

### Suggestion: Sunrise Balloon Festival
- **Date:** 2028-11-01
- **Prompt:** "An Impressionist style painting of a hot air balloon festival over the rocky landscape of Cappadocia at sunrise. Hundreds of colorful balloons dot the sky. The light is soft and dappled. Loose brushstrokes capture the movement of the air and the texture of the rocks."
- **Negative prompt:** "photograph, sharp, digital art, night, storm"
- **Tags:** impressionism, hot air balloon, landscape, sky, painting
- **Style / Reference:** Impressionism, Claude Monet
- **Composition:** Wide landscape
- **Color palette:** Pastel Pink, Sky Blue, Rock Ochre, Balloon colors
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20281101_balloon_fest.jpg`
- **License / Attribution:** CC0
- **Notes:** The atmosphere should feel airy and light.

### Suggestion: Vaporwave Mall Statue
- **Date:** 2028-11-15
- **Prompt:** "A nostalgic Vaporwave aesthetic scene inside a deserted 1980s shopping mall. A pristine white marble bust of Helios floats above a checkerboard floor. The scene is bathed in neon pink and cyan lighting. Palm trees and a CRT television displaying static are in the background."
- **Negative prompt:** "realistic, dark, gritty, modern, high contrast"
- **Tags:** vaporwave, aesthetic, 80s, surreal, neon
- **Style / Reference:** Vaporwave, Glitch Art
- **Composition:** Centered, surreal
- **Color palette:** Neon Pink, Cyan, Marble White, Palm Green
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20281115_vaporwave.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the dreamy, nostalgic, and slightly glitchy atmosphere.

### Suggestion: Infrared Aerochrome Forest
- **Date:** 2028-11-15
- **Prompt:** "A surreal landscape photograph taken with Kodak Aerochrome infrared film. A dense forest covers rolling hills. The foliage is a vibrant, shocking pink/magenta, contrasting deeply with the teal-blue sky and a dark blue river winding through the trees."
- **Negative prompt:** "green trees, realistic colors, digital filter, low saturation"
- **Tags:** infrared, aerochrome, landscape, surreal, pink
- **Style / Reference:** Infrared Photography, Kodak Aerochrome
- **Composition:** Wide landscape
- **Color palette:** Magenta, Pink, Teal, Dark Blue
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20281115_aerochrome.jpg`
- **License / Attribution:** CC0
- **Notes:** The key is the false-color effect where green becomes pink.

### Suggestion: Urban Double Exposure
- **Date:** 2028-11-15
- **Prompt:** "A striking double exposure photography portrait. The silhouette of a thoughtful woman's profile is filled with a bustling night cityscape (New York). Streetlights and skyscraper windows form the details of her face. The background is pure white."
- **Negative prompt:** "single exposure, messy, colorful background, cartoon"
- **Tags:** double exposure, portrait, city, surreal, monochrome
- **Style / Reference:** Double Exposure Photography
- **Composition:** Profile silhouette
- **Color palette:** Black, White, Amber City Lights
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20281115_double_exposure.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure a clean blend between the silhouette and the city.

### Suggestion: Ferrofluid Magnetism
- **Date:** 2028-11-15
- **Prompt:** "A macro shot of a black ferrofluid sculpture under a strong magnetic field. The liquid forms sharp, rhythmic spikes and alien organic shapes. Reflections of studio softboxes trace the glossy, oil-like surface. The background is a gradient of dark grey."
- **Negative prompt:** "water, solid metal, dry, low resolution, blurry"
- **Tags:** ferrofluid, macro, abstract, science, fluid
- **Style / Reference:** Macro Photography, Abstract
- **Composition:** Centered macro
- **Color palette:** Black, Metallic Grey, White Reflections
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20281115_ferrofluid.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the spiked texture and the liquid gloss.

### Suggestion: Bauhaus Geometric Poster
- **Date:** 2028-11-15
- **Prompt:** "A graphic design poster in the style of the Bauhaus school. Simple geometric shapes (red circle, blue square, yellow triangle) are balanced asymmetrically on a beige paper texture background. Strong diagonal black lines connect the forms. Typography is sans-serif and minimal."
- **Negative prompt:** "realistic, 3D, ornate, cluttered, messy"
- **Tags:** bauhaus, graphic design, geometric, minimal, abstract
- **Style / Reference:** Bauhaus, Constructivism
- **Composition:** Asymmetrical, balanced
- **Color palette:** Primary Red, Blue, Yellow, Black, Beige
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20281115_bauhaus.jpg`
- **License / Attribution:** CC0
- **Notes:** Adhere strictly to primary colors and geometric primitives.

### Suggestion: Bismuth Crystal Hoppers
- **Date:** 2028-12-01
- **Prompt:** "A macro photography shot of a synthetic Bismuth crystal. The geometric 'hopper' structure forms a spiraling, stair-step labyrinth. The surface oxidization creates a vibrant iridescent rainbow of colors: metallic blues, purples, golds, and pinks. The background is a clean dark grey."
- **Negative prompt:** "rock, dirt, organic, dull colors, blurry"
- **Tags:** bismuth, crystal, macro, geometry, iridescent
- **Style / Reference:** Macro Photography, Mineralogy
- **Composition:** Extreme close-up
- **Color palette:** Iridescent Rainbow, Metallic
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20281201_bismuth.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the right angles and the rainbow oxidation.

### Suggestion: Dyson Sphere Construction
- **Date:** 2028-12-01
- **Prompt:** "A colossal sci-fi concept art piece depicting the construction of a Dyson Sphere around a blue giant star. Hexagonal solar panels the size of continents are being assembled by swarms of spacecraft. The star's light bursts through the gaps in the megastructure. The scale is incomprehensible."
- **Negative prompt:** "small planet, moon, cartoon, empty space, asteroid"
- **Tags:** dyson sphere, sci-fi, space, megastructure, epic
- **Style / Reference:** Sci-Fi Concept Art, Space Art
- **Composition:** Wide shot, cosmic scale
- **Color palette:** Star Blue, Panel Black/Silver, Silhouette
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20281201_dyson_sphere.jpg`
- **License / Attribution:** CC0
- **Notes:** Convey the immense scale of the structure against the star.

### Suggestion: Pixel Sorting Portrait
- **Date:** 2028-12-01
- **Prompt:** "A digital glitch art portrait of a cyberpunk hacker. The image is heavily processed with a 'pixel sorting' effect, where rows of pixels are dragged downwards based on luminance. The face is fragmented into cascading vertical lines of neon code and color, dissolving into digital noise."
- **Negative prompt:** "clean, realistic, painting, smooth, normal"
- **Tags:** pixel sorting, glitch art, cyberpunk, portrait, digital
- **Style / Reference:** Glitch Art, Datamoshing
- **Composition:** Portrait, centered
- **Color palette:** Neon Green, Black, Static White, Magenta
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20281201_pixel_sort.jpg`
- **License / Attribution:** CC0
- **Notes:** The vertical streaking effect is the defining feature.

### Suggestion: Bioluminescent Bay
- **Date:** 2028-12-01
- **Prompt:** "A magical night landscape of a tropical bay filled with bioluminescent plankton. A wooden boat cuts through the dark water, leaving a glowing trail of electric blue light. The stars above reflect on the calm surface. Palm trees silhouette against the night sky."
- **Negative prompt:** "daylight, sun, murky, green water, city lights"
- **Tags:** bioluminescence, nature, ocean, night, magical
- **Style / Reference:** Landscape Photography, Travel
- **Composition:** Wide shot
- **Color palette:** Electric Blue, Night Black, Star White
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20281201_bio_bay.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the glow of the water where it is disturbed.

### Suggestion: Damascus Steel Pattern
- **Date:** 2028-12-01
- **Prompt:** "A high-resolution macro texture shot of a hand-forged Damascus steel knife blade. The intricate, wavy water-like pattern of the folded steel layers is clearly visible. The metal is etched to reveal the contrast between the dark and light steel. Studio lighting highlights the grain."
- **Negative prompt:** "stainless steel, smooth, rust, blurry, scratches"
- **Tags:** damascus steel, metal, texture, macro, craft
- **Style / Reference:** Macro Photography, Product Photography
- **Composition:** Flat lay texture
- **Color palette:** Steel Grey, Silver, Black, Charcoal
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20281201_damascus.jpg`
- **License / Attribution:** CC0
- **Notes:** The contrast in the folded metal pattern is key.

## Attribution & legal

- Always record the **License / Attribution** for reference images and any artist references. Confirm you have the rights to store and use included images.
- When using external images, include the URL and the license where possible.

---

## Workflow suggestions

- **Check for duplicates:** Before adding, search existing titles and prompts to ensure distinctness.
- Keep each suggestion self-contained (title + metadata + example prompt). This helps reuse and automation.
- **Diversity Check:** Ensure new suggestions introduce new textures, materials, or lighting scenarios not yet covered.
- **Aspect Ratio Diversity:** Avoid sticking to 16:9 or 1:1. Experiment with 21:9 (Cinematic), 9:16 (Mobile), or 4:5 (Portrait).
- **Select & Remove:** When creating new suggestions, pick from the "Future Suggestion Ideas" list and **remove the utilized items** to keep the list fresh.
- **Update Wishlist:** After adding suggestions, add new gaps you noticed to replenish the list.
- **Review Tags:** Check the 'Tags' of existing entries to ensure diversity and avoid over-representation of certain genres (e.g., Cyberpunk).
- Optionally maintain a simple CSV/JSON data file for programmatic consumption (columns: id, title, prompt, tags, ref_image, license).
- Scheduled task: Add 5 new suggestions weekly to maintain a diverse and growing collection of prompts, ensuring the wishlist is replenished with at least as many new ideas.
- **Verification:** Always check the bottom of the **Prompt examples** section to see what has been recently added. The Wishlist below may not always reflect the absolute latest additions if the previous agent forgot to update it.

### Future Suggestion Ideas (Wishlist)
To keep the collection diverse, consider adding prompts for:
- **Styles:** Matte Painting, Baroque, Gothic, Scanography, Glitch Art, Pointillism, Low Poly, Brutalism, Geometric Abstraction, High-Speed Photography, Trompe-l'œil, Kinetic Art, Brutalist Web Design, Solarpunk, Art Deco, Constructivism, Neoclassicism, Metaphysical Art, Hard Edge Painting, Tachisme, Neo-Geo, Rayograph, Hard Surface Modeling, Crosshatching, Ashcan School, Northern Renaissance, Italian Futurism, Deconstructivism, Spatialism, Op Art, Ukiyo-e, Low Key Photography, Brutalist Architecture, Art Nouveau, Kintsugi.
- **Materials:** Cork, Chainmail, Fur, Marble, Sea Glass, Amber, Rust, Slime, Denim, Paper Marbling, Soap Bubbles, Vantablack, Carbon Fiber, Generative Fluid Simulation, Sand, Mercury, Gallium, Burlap, Obsidian, Titanium, Latex, Basalt, Aerogel, Velcro, Sandpaper, Cellophane, Aluminum Foil, Porcelain, Terracotta, Opal, Chiffon, Tweed, Granite, Topaz, Pewter, Alabaster, Organza, Cracked Clay, Slate, Kevlar.
- **Subjects:** Geode, Supernova, DNA Helix, Fireworks, Volcanic Eruption, Bioluminescent Forest, Diorama, Space Elevator, Microchip City, Nebula, Quasar, Pulsar, Tsunami, Solar Punk City, Coral Reef, Quantum Computer, Space Station, Ancient Ruins, Black Hole, Swamp, Glacier, Canyon, Fjord, Oasis, Ant Farm, Beehive, Termite Mound, Beaver Dam, Bird's Nest, Spider Web, Cocoon, Neutron Star Collision, Volcanic Lightning, Kaleidoscope, Holographic Statue, Bioluminescent Plankton, Tide Pool, Sundog, Hydroelectric Dam, Oil Rig, Bonsai Tree, Wind Tunnel, Supervolcano, Magnetar, Origami, Steampunk Airship, Circuit Board Macro.

---

## Agent suggestions
This section is reserved for short, incremental contributions by agents (automation scripts, bots, or collaborators). Add one suggestion per subsection so entries are easy to track and reference.[...] 

**Agent contribution template (copy & paste):**

```md
### Agent Suggestion: <Title> — @<agent-name> — YYYY-MM-DD
- **Prompt:** "<Detailed prompt — include subject, mood, lighting, style, and camera cues>"
- **Negative prompt:** "<Optional: words to exclude>"
- **Tags:** tag1, tag2
- **Ref image:** `public/images/suggestions/<filename>.jpg` or URL
- **Notes / agent context:** (e.g., generation params, seed, why suggested)
- **Status:** proposed / tested / merged (include PR or commit link if applicable)
```

**Example (agent entry):**

### Agent Suggestion: Lonely Forest Flume — @autogen-bot — 2026-01-12
- **Prompt:** "A photorealistic landscape photograph captures an ancient, collapsing wooden flume extending into a dense, old-growth forest. Moss and thick ivy drape heavily from the decaying trestles."
- **Negative prompt:** "lowres, watermark, overexposed, text, modern structures"
- **Tags:** photorealism, nature, melancholic
- **Ref image:** `public/images/suggestions/20260112_forest-flume.jpg`
- **Notes / agent context:** Suggested as a high-recall prompt for melancholic nature scenes; tested with seed=12345, steps=50.
- **Status:** proposed

### Agent Suggestion: Bioluminescent Cave — @gemini-agent — 2026-01-12
- **Prompt:** "A photorealistic wide shot of a massive underground cavern filled with glowing bioluminescent mushrooms and strange flora. A crystal-clear river flows through the center, reflecting the eerie glow of the cave ceiling."
- **Negative prompt:** "sunlight, daylight, artificial lights, blurry, people"
- **Tags:** fantasy, nature, underground, glowing
- **Ref image:** `public/images/suggestions/20260112_bioluminescent-cave.jpg`
- **Notes / agent context:** Good for testing ethereal and magical visual effects.
- **Status:** proposed

### Agent Suggestion: Retro-Futuristic Android Portrait — @gemini-agent — 2026-01-12
- **Prompt:** "A 1980s-style airbrushed portrait of a female android. Her face is partially translucent, revealing complex chrome mechanics and wiring underneath. She has vibrant neon pink hair and cybernetic eyes."
- **Negative prompt:** "photorealistic, modern, flat, simple"
- **Tags:** cyberpunk, retro, 80s, portrait
- **Ref image:** `public/images/suggestions/20260112_retro-android.jpg`
- **Notes / agent context:** Ideal for testing neon, glitch, and retro shader effects.
- **Status:** proposed

### Agent Suggestion: Crystalline Alien Jungle — @gemini-agent — 2026-01-12
- **Prompt:** "A world where the jungle is made of semi-translucent, glowing crystals instead of wood. The air is filled with floating, sparkling spores. The flora and fauna are alien and geometric, shifting colors as the light changes."
- **Negative prompt:** "trees, wood, leaves, green, people, earth-like"
- **Tags:** sci-fi, alien, fantasy, crystal, jungle
- **Ref image:** `public/images/suggestions/20260112_crystal-jungle.jpg`
- **Notes / agent context:** Excellent for refraction, bloom, and god-ray effects.
- **Status:** proposed

### Agent Suggestion: Quantum Computer Core — @gemini-agent — 2026-01-12
- **Prompt:** "The inside of a futuristic quantum computer core. A central sphere of entangled light particles pulses with energy, connected by threads of light to a complex, fractal-like structure of gold and cooling pipes."
- **Negative prompt:** "people, screens, keyboards, messy wires"
- **Tags:** abstract, tech, sci-fi, quantum, computer
- **Ref image:** `public/images/suggestions/20260112_quantum-core.jpg`
- **Notes / agent context:** Use for testing generative, abstract, and data-moshing shaders.
- **Status:** proposed

### Agent Suggestion: Solar Sail Ship — @gemini-agent — 2026-01-12
- **Prompt:** "A massive, elegant spaceship with vast, shimmering solar sails that look like a captured nebula, cruising silently through a dense starfield. The ship's hull is sleek and pearlescent, reflecting the distant stars."
- **Negative prompt:** "fire, smoke, explosions, cartoon"
- **Tags:** sci-fi, space, ship, nebula, majestic
- **Ref image:** `public/images/suggestions/20260112_solar-sail.jpg`
- **Notes / agent context:** Good for testing galaxy, starfield, and other cosmic background shaders.
- **Status:** proposed

### Agent Suggestion: Clockwork Dragon — @gemini-agent — 2026-01-12
- **Prompt:** "A magnificent and intricate mechanical dragon made of polished brass, copper, and glowing gears, perched atop a gothic cathedral. Steam escapes from vents on its body. The city below is a sprawl of Victorian architecture."
- **Negative prompt:** "flesh, scales, simple, modern"
- **Tags:** steampunk, fantasy, dragon, mechanical, gothic
- **Ref image:** `public/images/suggestions/20260112_clockwork-dragon.jpg`
- **Notes / agent context:** Tests metallic surfaces, fog, and glow effects.
- **Status:** proposed

### Agent Suggestion: Underwater Metropolis — @gemini-agent — 2026-01-12
- **Prompt:** "A bustling futuristic city enclosed in a giant glass dome at the bottom of the ocean. Schools of bioluminescent fish and giant marine creatures swim peacefully outside the dome, while futuristic submarines dock at the ports."
- **Negative prompt:** "land, sky, clouds, empty, ruins"
- **Tags:** futuristic, city, underwater, sci-fi
- **Ref image:** `public/images/suggestions/20260112_underwater-city.jpg`
- **Notes / agent context:** Perfect for caustics, water distortion, and fog effects.
- **Status:** proposed

### Agent Suggestion: Floating Islands Market — @gemini-agent — 2026-01-12
- **Prompt:** "A vibrant and chaotic marketplace set on a series of fantastical floating islands, connected by rickety rope bridges. Strange, colorful alien merchants sell exotic fruits and mysterious artifacts to passing travelers."
- **Negative prompt:** "ground, roads, cars, realistic"
- **Tags:** fantasy, flying, islands, market, whimsical
- **Ref image:** `public/images/suggestions/20260112_floating-market.jpg`
- **Notes / agent context:** A colorful and complex scene to test a wide variety of effects.
- **Status:** proposed

### Agent Suggestion: Desert Planet Oasis — @gemini-agent — 2026-01-12
- **Prompt:** "A hidden oasis on a desert planet with two suns setting in the sky, casting long shadows. The oasis is centered around a shimmering, turquoise pool, surrounded by bizarre, crystalline rock formations."
- **Negative prompt:** "green, Earth-like, trees, people"
- **Tags:** sci-fi, desert, oasis, alien, landscape
- **Ref image:** `public/images/suggestions/20260112_desert-oasis.jpg`
- **Notes / agent context:** Good for testing heat-haze, water ripples, and stark lighting.
- **Status:** proposed

### Agent Suggestion: Ancient Tree of Souls — @gemini-agent — 2026-01-12
- **Prompt:** "A colossal, ancient, glowing tree whose leaves and bark emit a soft, ethereal, spiritual light. Its roots are massive, intertwining with the landscape and appearing to connect to the glowing ley lines of the planet."
- **Negative prompt:** "chopped, burning, daytime, simple"
- **Tags:** fantasy, magic, tree, spiritual, glowing
- **Ref image:** `public/images/suggestions/20260112_soul-tree.jpg`
- **Notes / agent context:** Great for particle effects, glow, and ethereal vibes.
- **Status:** proposed

### Agent Suggestion: Post-Apocalyptic Library — @gemini-agent — 2026-01-12
- **Prompt:** "The grand, dusty interior of a ruined baroque library, reclaimed by nature. Huge shafts of volumetric light pierce through the collapsed, vaulted ceiling, illuminating floating dust motes and the overgrowth covering the shelves."
- **Negative prompt:** "clean, new, people, pristine"
- **Tags:** post-apocalyptic, ruins, library, atmospheric
- **Ref image:** `public/images/suggestions/20260112_ruin-library.jpg`
- **Notes / agent context:** Tests god-rays, dust particles, and detailed textures.
- **Status:** proposed

### Agent Suggestion: Surreal Cloudscape — @gemini-agent — 2026-01-12
- **Prompt:** "A dreamlike, minimalist landscape set high above the clouds at sunset. The clouds are a soft, pink and orange sea. Impossible geometric shapes and minimalist architecture float serenely in the sky."
- **Negative prompt:** "realistic, ground, busy, dark"
- **Tags:** surreal, dreamlike, minimalist, clouds
- **Ref image:** `public/images/suggestions/20260112_cloudscape.jpg`
- **Notes / agent context:** Good for simple, clean shaders and color-blending effects.
- **Status:** proposed

### Agent Suggestion: Overgrown Train Station — @autogen-bot — 2026-01-12
- **Prompt:** "A wide-angle photorealistic scene of an abandoned train station overtaken by nature: platforms cracked and lifted by roots, trains half-buried in moss, glass roofs shattered with vines hanging down."
- **Negative prompt:** "modern signs, people, clean, sunny"
- **Tags:** urban, ruins, nature, atmospheric
- **Ref image:** `public/images/suggestions/20260112_overgrown-station.jpg`
- **Notes / agent context:** Great for testing wet surfaces, moss detail, and depth-of-field. Suggested aspect ratio: 16:9.
- **Status:** proposed

### Agent Suggestion: Neon Rain Alley — @neonbot — 2026-01-12
- **Prompt:** "A dark, rain-soaked alley in a cyberpunk city at night: neon signs in kanji and English flicker, puddles reflect saturated color, steam rises from grates, and a lone figure with a glowing umbrella walks away."
- **Negative prompt:** "daylight, cartoon, bright, cheerful"
- **Tags:** cyberpunk, neon, urban, night
- **Ref image:** `public/images/suggestions/20260112_neon-alley.jpg`
- **Notes / agent context:** Use for testing chromatic aberration, bloom, and wet-reflection shaders. Try seed=67890 for reproducibility.
- **Status:** proposed

### Agent Suggestion: Antique Map Room with Floating Islands — @mapbot — 2026-01-12
- **Prompt:** "An ornately furnished, dimly lit study filled with antique maps and celestial globes; in the center, several miniature floating islands levitate above a polished mahogany table, each with its own tiny weather system."
- **Negative prompt:** "modern electronics, fluorescent light, messy"
- **Tags:** fantasy, interior, steampunk, magic
- **Ref image:** `public/images/suggestions/20260112_map-room.jpg`
- **Notes / agent context:** Ideal for layered compositing, warm lighting, and small-scale detail tests. Aspect ratio: 4:3.
- **Status:** proposed

### Agent Suggestion: Microscopic Coral City — @biology-agent — 2026-01-12
- **Prompt:** "A macro, photorealistic view of a coral reef that resembles an ancient submerged city: arched coral towers, tiny fish like airborne commuters, minuscule windows filled with bioluminescent light."
- **Negative prompt:** "land, buildings, people, murky"
- **Tags:** macro, underwater, coral, photorealism
- **Ref image:** `public/images/suggestions/20260112_coral-city.jpg`
- **Notes / agent context:** Use for caustics, water distortion, and fine-scale texture generation tests. Suggested camera: macro 100mm.
- **Status:** proposed

### Agent Suggestion: Auroral Glacier Cathedral — @aurora-agent — 2026-01-12
- **Prompt:** "A majestic natural cathedral carved of blue ice and glacier, its spires and arches rimed with frost; above, a luminous aurora paints vivid green and purple curtains across the night sky, reflected in the ice below."
- **Negative prompt:** "tropical, sunlight, warm colors, crowds"
- **Tags:** landscape, aurora, ice, epic
- **Ref image:** `public/images/suggestions/20260112_auroral-cathedral.jpg`
- **Notes / agent context:** Excellent for volumetric lighting, ice refraction, and subtle color grading tests.
- **Status:** proposed
