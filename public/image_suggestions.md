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

### Suggestion: Neon Street Vendor
- **Prompt:** "A cinematic, photorealistic night shot of a futuristic street food stall tucked into a rain-drenched cyberpunk alley. A battered mechanical vendor with glowing blue optics serves steaming noodles to a hooded figure."
- **Negative prompt:** "daylight, sunshine, blurry, low resolution, cartoon, illustration"
- **Tags:** cyberpunk, robot, night, neon, food
- **Style / Reference:** Photorealistic, Cinematic
- **Composition:** Medium shot, eye level, focus on interaction
- **Color palette:** Cyan, Magenta, dark shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260112_neon_vendor.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the texture of the wet ground and the glow of the neon.

### Suggestion: Steampunk Airship Dock
- **Prompt:** "A majestic steampunk airship docking at a floating Victorian sky-station high above a sea of clouds during golden hour. The ship features polished brass gears, billowing canvas sails, and intricate rigging."
- **Negative prompt:** "modern technology, airplanes, plastic, low detail"
- **Tags:** steampunk, airship, clouds, golden hour, victorian
- **Style / Reference:** Digital Painting, Concept Art
- **Composition:** Wide angle, looking up slightly
- **Color palette:** Gold, Brass, Sky Blue, White
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260112_airship_dock.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the scale of the ship versus the people.

### Suggestion: Crystalline Flora
- **Prompt:** "A macro photography shot of an alien flower composed entirely of translucent, iridescent crystals. The faceted petals refract light into spectral rainbows. Inside the flower, a tiny glowing orb pulses with soft light."
- **Negative prompt:** "blurry, organic textures, dull colors"
- **Tags:** macro, crystal, alien, nature, abstract
- **Style / Reference:** Macro Photography, 3D Render
- **Composition:** Extreme close-up, center focus
- **Color palette:** Iridescent, pastel rainbow, dark background
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260112_crystal_flower.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the refraction looks realistic.

### Suggestion: Shadows of the City
- **Prompt:** "A classic black and white film noir scene inside a private detective's office. Venetian blinds cast harsh, striped shadows (chiaroscuro) across a cluttered wooden desk featuring a rotary phone, a half-empty glass of whiskey, and a smoking cigarette."
- **Negative prompt:** "color, bright, happy, modern"
- **Tags:** noir, black and white, detective, moody, interior
- **Style / Reference:** Film Noir, B&W Photography
- **Composition:** Dutch angle, rule of thirds
- **Color palette:** Grayscale, high contrast
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260112_noir_office.jpg`
- **License / Attribution:** CC0
- **Notes:** The play of light and shadow is crucial.

### Suggestion: The Alchemist's Corner
- **Prompt:** "An isometric 3D render of a cozy, cluttered alchemist's workshop. Wooden shelves are packed with glowing potions in various shapes, ancient rolled scrolls, and leather-bound books. A bubbling cauldron sits on a small burner."
- **Negative prompt:** "realistic, dark, scary, messy geometry"
- **Tags:** isometric, 3D, magic, cute, interior
- **Style / Reference:** Stylized 3D, Isometric Art
- **Composition:** Isometric view
- **Color palette:** Warm woods, purple and green magic glows
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260112_magic_shop.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing consistent isometric perspective.

### Suggestion: Orbital Greenhouse
- **Prompt:** "A photorealistic wide shot inside a massive rotating space station greenhouse. Lush, vibrant tropical vegetation and hanging gardens fill the curved interior structure. Through the massive glass panels, the curvature of the Earth is visible against the blackness of space."
- **Negative prompt:** "blurry, low resolution, painting, illustration, distortion"
- **Tags:** sci-fi, space, nature, greenhouse, earth
- **Style / Reference:** Photorealistic, Sci-Fi Concept Art
- **Composition:** Wide angle, curved perspective
- **Color palette:** Lush greens, metallic greys, deep space blues, bright white sunlight
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260124_orbital_greenhouse.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the contrast between the organic plants and the cold tech/space background.

### Suggestion: Origami Paper Kingdom
- **Prompt:** "A whimsical landscape entirely constructed from folded paper. Mountains are sharp geometric folds, trees are stylized paper cutouts, and a river is made of layered blue tissue paper. Small paper cranes fly in the sky."
- **Negative prompt:** "realistic textures, water, photorealistic, dark, gritty"
- **Tags:** origami, papercraft, miniature, whimsical, landscape
- **Style / Reference:** Papercraft, Macro Photography
- **Composition:** Tilt-shift, isometric-like
- **Color palette:** Pastel blues, greens, and creams
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260124_origami_kingdom.jpg`
- **License / Attribution:** CC0
- **Notes:** Essential to emphasize the *paper texture* and physical folds.

### Suggestion: Magma Forge
- **Prompt:** "Inside a colossal dwarven forge deep within a volcano. Molten lava flows in channels carved into dark obsidian rock. A massive anvil sits in the center, glowing with heat. Sparks fly as a heavy hammer strikes glowing metal."
- **Negative prompt:** "cool colors, blue, daylight, clean, modern"
- **Tags:** fantasy, forge, lava, fire, interior
- **Style / Reference:** Fantasy Concept Art, Cinematic
- **Composition:** Eye level, framing the anvil
- **Color palette:** Burning oranges, reds, deep blacks, charcoal greys
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260124_magma_forge.jpg`
- **License / Attribution:** CC0
- **Notes:** Use heavy contrast and saturation for the lava glow.

### Suggestion: Vintage Explorer's Flatlay
- **Prompt:** "A high-angle, directly overhead 'knolling' shot of vintage exploration gear arranged neatly on a weathered wooden table. Items include a brass compass, a rolled parchment map, a leather journal, and an old brass telescope."
- **Negative prompt:** "messy, angled, perspective, digital, plastic"
- **Tags:** knolling, vintage, explorer, still life, flatlay
- **Style / Reference:** Product Photography, Still Life
- **Composition:** Top-down (flatlay), organized
- **Color palette:** Browns, golds, warm wood tones
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260124_explorer_flatlay.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the items are arranged in a grid or organized pattern (knolling).

### Suggestion: Double Exposure Stag
- **Prompt:** "A artistic double exposure image blending the silhouette of a majestic stag with a foggy pine forest landscape. The stag's body is filled with the forest scene: tall pine trees, mist, and birds flying in the distance."
- **Negative prompt:** "color, messy background, realistic fur, low contrast"
- **Tags:** double exposure, abstract, nature, stag, minimalist
- **Style / Reference:** Double Exposure, Digital Art
- **Composition:** Centered subject, silhouette
- **Color palette:** Black, white, grey, cool pine greens (desaturated)
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260124_double_exposure_stag.jpg`
- **License / Attribution:** CC0
- **Notes:** Needs a clear silhouette for the effect to work.

### Suggestion: Sumi-e Ink Mountains
- **Prompt:** "A traditional Japanese Sumi-e ink wash painting of towering, jagged mountain peaks shrouded in mist. Stark black brushstrokes define the cliffs against a textured white rice paper. A solitary bird flies near the peak."
- **Negative prompt:** "color, photograph, realistic, 3D, modern, vibrant"
- **Tags:** sumi-e, ink wash, japanese, landscape, minimalist
- **Style / Reference:** Traditional Ink Painting, Sesshu Toyo
- **Composition:** Vertical, lots of negative space
- **Color palette:** Black, Grayscale, White
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20260124_sumi_e_mountains.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the texture of the paper and the fluidity of the ink.

### Suggestion: Knitted Wool Village
- **Prompt:** "A cozy, whimsical scene of a miniature village entirely made of knitted wool and yarn. Small cottages have fuzzy roof thatching, trees are pom-poms, and the ground is a patchwork of green knitted squares."
- **Negative prompt:** "plastic, realistic materials, metal, sharp edges, smooth"
- **Tags:** knitted, wool, craft, miniature, cute
- **Style / Reference:** Stop Motion, Handicraft
- **Composition:** High angle, tilt-shift
- **Color palette:** Warm pastels, soft creams, cozy greens
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260124_knitted_village.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the stray fibers and the tactile nature of the wool.

### Suggestion: Atomic Age Diner
- **Prompt:** "A retro-futuristic 1950s 'Googie' architecture diner on the moon. Curved chrome fins, large glass bubbles, and starburst motifs. Inside, a robot waitress on a unicycle serves milkshakes to a space-suited couple."
- **Negative prompt:** "gritty, dark, dystopian, cyberpunk, rusty"
- **Tags:** retro-futurism, 1950s, sci-fi, space, diner
- **Style / Reference:** Mid-Century Modern, Googie, Technicolor
- **Composition:** Wide shot showing interior and view outside
- **Color palette:** Teal, chrome, cherry red, bright white
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260124_atomic_diner.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the optimism of the space age.

### Suggestion: Brutalist Fog Monument
- **Prompt:** "A massive, imposing Brutalist concrete monument rising from a dark, foggy plain. Sharp geometric angles, raw concrete textures with water stains, and repeating modular patterns. The structure dominates the landscape, evoking a sense of awe and dread."
- **Negative prompt:** "ornate, colorful, happy, nature, wood"
- **Tags:** brutalism, concrete, fog, dystopian, architecture
- **Style / Reference:** Brutalist Architecture, Dystopian Sci-Fi
- **Composition:** Low angle, looking up to emphasize scale
- **Color palette:** Monochromatic greys, cold blue fog, harsh white light
- **Aspect ratio:** 9:16
- **Reference images:** `public/images/suggestions/20260124_brutalist_fog.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the scale and the texture of the raw concrete.

### Suggestion: Microchip Metropolis
- **Prompt:** "A macro photography shot of a computer motherboard, visualized as a futuristic glowing city at night. Capacitors look like skyscrapers, copper traces are highways of light, and the CPU cooler resembles a futuristic stadium."
- **Negative prompt:** "organic, dirt, rust, full size city"
- **Tags:** macro, technology, circuit, cyberpunk, abstract
- **Style / Reference:** Macro Photography, Tech Noir
- **Composition:** Isometric or close-up macro
- **Color palette:** Electric blue, neon green, gold, black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260124_microchip_city.jpg`
- **License / Attribution:** CC0
- **Notes:** Blur the line between hardware and architecture.

### Suggestion: Bioluminescent Abyss
- **Prompt:** "A terrifying yet beautiful photorealistic deep-sea scene. A colossal, translucent leviathan resembling a jellyfish floats in the crushing darkness of the abyss. Its internal organs glow with a faint, rhythmic pulse."
- **Negative prompt:** "surface, boat, bright, cartoon, blurry"
- **Tags:** underwater, bioluminescence, creature, horror, nature
- **Style / Reference:** Photorealistic, Nature Documentary
- **Composition:** Wide shot, low angle
- **Color palette:** Black, electric blue, violet
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260124_bioluminescent_abyss.jpg`
- **License / Attribution:** CC0
- **Notes:** High contrast is key to emphasize the bioluminescence against the dark water.

### Suggestion: Midnight Arcade
- **Prompt:** "A nostalgic 1980s arcade interior at night, filled with rows of glowing CRT cabinets. The carpet has a vibrant, cosmic pattern glowing under blacklight. A teenager in a denim jacket plays an intense game."
- **Negative prompt:** "LCD screens, modern clothes, daylight, clean"
- **Tags:** arcade, 80s, retro, neon, interior
- **Style / Reference:** Retro Photography, Cinematic
- **Composition:** Eye level, depth of field
- **Color palette:** Neon pink, cyan, deep purple, black
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260124_midnight_arcade.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the screen glow and the carpet texture for authenticity.

### Suggestion: Delftware Diorama
- **Prompt:** "A surreal landscape where everything is made of glazed white porcelain with intricate Delft blue patterns. A windmill sits on a hill, and the clouds are painted ceramic shapes suspended in the sky."
- **Negative prompt:** "rough texture, dirt, realistic grass, matte"
- **Tags:** porcelain, delftware, blue and white, surreal, miniature
- **Style / Reference:** 3D Render, Ceramic Art
- **Composition:** Isometric or tilt-shift
- **Color palette:** White, Cobalt Blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260124_delftware_diorama.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the glossiness of the ceramic to sell the material.

### Suggestion: Cyber Samurai Duel
- **Prompt:** "A dynamic action shot of a cybernetic samurai drawing a glowing katana in a rain-slicked neo-Tokyo street. Sparks fly from the blade. The samurai has a traditional silhouette but with mechanical limbs and glowing eyes."
- **Negative prompt:** "static, boring, peaceful, historical accuracy"
- **Tags:** cyberpunk, samurai, action, rain, neon
- **Style / Reference:** Action Movie Still, Concept Art
- **Composition:** Low angle, dynamic action
- **Color palette:** Steel grey, blood red, neon blue
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260124_cyber_samurai.jpg`
- **License / Attribution:** CC0
- **Notes:** Use motion blur to convey speed and impact.

### Suggestion: Smoke Spirit
- **Prompt:** "A double exposure artistic shot of a dancer formed entirely from swirling, colored smoke and ink in water. The human form is suggested but ephemeral, dissolving into wisps of pink, blue, and violet."
- **Negative prompt:** "solid body, flesh, clothes, messy"
- **Tags:** smoke, abstract, dancer, fluid, ethereal
- **Style / Reference:** Abstract Photography, Fluid Art
- **Composition:** Centered, floating
- **Color palette:** Black background, pastel pink, gold, teal
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260124_smoke_spirit.jpg`
- **License / Attribution:** CC0
- **Notes:** The form should be ambiguous but recognizable.

### Suggestion: Crystal Knowledge Cavern
- **Prompt:** "A mystical underground library carved into a geode. Instead of books, shelves hold glowing, color-coded crystal shards. A scholar in robes inspects a shard, illuminating their face. The walls sparkle with amethyst and quartz structures..."
- **Negative prompt:** "books, paper, wooden shelves, daylight, modern"
- **Tags:** fantasy, library, crystal, magical, interior
- **Style / Reference:** Fantasy Concept Art, 3D Render
- **Composition:** Wide shot, atmospheric perspective
- **Color palette:** Purple, blue, glowing cyan, dark rock
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260115_crystal_library.jpg`
- **License / Attribution:** CC0
- **Notes:** The lighting should come primarily from the crystals.

### Suggestion: Solarpunk City Heights
- **Prompt:** "A bright, optimistic view of a Solarpunk city. Skyscrapers are covered in lush vertical gardens and cascading waterfalls. Solar panels resemble glass leaves. People travel in transparent pneumatic tubes. The lighting is warm morning sun..."
- **Negative prompt:** "smog, dark, dirty, concrete, dystopian, cars"
- **Tags:** solarpunk, eco-friendly, futuristic, city, bright
- **Style / Reference:** Solarpunk, Architectural Rendering
- **Composition:** High angle, overlooking the city
- **Color palette:** Bright greens, sky blue, warm sunlight, white
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260115_solarpunk_city.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the harmony between technology and nature.

### Suggestion: Haunted Carnival Pier
- **Prompt:** "A foggy, atmospheric shot of an abandoned seaside amusement park at twilight. A rusted Ferris wheel looms in the mist. The wooden pier is rotting. Faint, ghostly lights flicker on a carousel. The mood is eerie and silent..."
- **Negative prompt:** "bright, happy, people, clean, day"
- **Tags:** horror, carnival, abandoned, moody, fog
- **Style / Reference:** Horror Photography, Cinematic
- **Composition:** Eye level, leading lines along the pier
- **Color palette:** Desaturated blues, greys, rust orange, faint yellow
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260115_haunted_pier.jpg`
- **License / Attribution:** CC0
- **Notes:** Use fog to hide details and create mystery.

### Suggestion: Liquid Chrome Symphony
- **Prompt:** "An abstract macro shot of liquid metal (mercury or chrome) splashing and morphing. The surface is perfectly reflective, mirroring a distorted studio light setup. Ripples and droplets are frozen in time. High contrast, monochromatic with metallic sheen..."
- **Negative prompt:** "matte, color, water, plastic, rough"
- **Tags:** abstract, liquid, chrome, 3D, macro
- **Style / Reference:** 3D Simulation, Abstract Photography
- **Composition:** Macro, centered splash
- **Color palette:** Silver, black, white (monochrome)
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260115_liquid_chrome.jpg`
- **License / Attribution:** CC0
- **Notes:** Reflections are the most important part of this look.

### Suggestion: Voxel Valley Sunset
- **Prompt:** "A landscape made entirely of photorealistic voxels (cubes). A blocky sun sets over a blocky ocean, casting realistic ray-traced reflections. Trees are cube clusters. It looks like a high-end render of a video game world, distinct and geometric..."
- **Negative prompt:** "smooth, curves, round sun, lowres"
- **Tags:** voxel, 8-bit, landscape, 3D, geometric
- **Style / Reference:** Voxel Art, Ray-Tracing
- **Composition:** Wide landscape view
- **Color palette:** Sunset oranges, purples, deep blue ocean
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260115_voxel_valley.jpg`
- **License / Attribution:** CC0
- **Notes:** The key is the contrast between the blocky shapes and the realistic lighting.

### Suggestion: Stained Glass Forest
- **Prompt:** "A breathtaking view inside a cathedral made entirely of living trees, where the leaves form a natural stained glass canopy. Sunlight streams through the translucent, multi-colored leaves (autumnal reds, golds, and greens), casting kaleidoscope patterns on the mossy floor. The atmosphere is holy and serene."
- **Negative prompt:** "man-made structure, stone, dark, gloomy"
- **Tags:** fantasy, forest, stained glass, light, ethereal
- **Style / Reference:** Fantasy Concept Art, Ethereal
- **Composition:** Low angle, looking up at the canopy
- **Color palette:** Jewel tones, gold, green, ruby red
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260215_stained_glass_forest.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the translucency of the leaves.

### Suggestion: Graffiti Alleyway Mural
- **Prompt:** "A wide shot of a gritty urban alleyway featuring a massive, vibrant graffiti mural of a roaring tiger breaking through a brick wall. The spray paint texture is visible, with drips and layers. Puddles on the ground reflect the colorful art. The lighting is overcast, making the colors pop."
- **Negative prompt:** "clean, vector, cartoon, 3D render, luxury"
- **Tags:** street art, graffiti, urban, tiger, grunge
- **Style / Reference:** Urban Photography, Street Art
- **Composition:** Wide shot, slightly off-center
- **Color palette:** Concrete grey, vibrant orange, electric blue, black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260215_graffiti_mural.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the texture of the brick and paint.

### Suggestion: X-Ray Floral Composition
- **Prompt:** "An artistic X-ray photography composition of a bouquet of lilies and tulips. The petals are ghost-like and translucent, revealing the delicate internal veins and structures. The background is deep black, highlighting the skeletal beauty of the flowers. High contrast and fine detail."
- **Negative prompt:** "color, opaque, painting, illustration, blurry"
- **Tags:** x-ray, flowers, abstract, botanical, monochrome
- **Style / Reference:** X-Ray Photography, Fine Art
- **Composition:** Centered, flat lay
- **Color palette:** Grayscale, inverted white on black
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260215_xray_flowers.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the image looks like a medical X-ray or fine art radiograph.

### Suggestion: Retro Travel Poster: Mars
- **Prompt:** "A vintage 1930s style travel poster advertising 'Visit Mars'. Flat vector illustration style with bold shapes and limited color palette. A sleek art-deco rocket stands on red dunes, with two moons in the teal sky. Typography at the bottom says 'MARS' in a retro font."
- **Negative prompt:** "photorealistic, 3D, noise, gradient, messy"
- **Tags:** retro, vintage, poster, mars, vector
- **Style / Reference:** WPA Poster, Art Deco, Vector Art
- **Composition:** Vertical poster layout
- **Color palette:** Rust red, teal, cream, mustard yellow
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20260215_mars_poster.jpg`
- **License / Attribution:** CC0
- **Notes:** Needs to look like a printed lithograph.

### Suggestion: Baroque Cyborg Portrait
- **Prompt:** "A hyper-realistic portrait of a cyborg noblewoman in the style of the late Baroque period. Her face is porcelain white, but portions reveal intricate gold clockwork and filigree gears underneath. She wears a powdered wig and a dress made of fiber-optic lace. Soft, dramatic lighting."
- **Negative prompt:** "low quality, anime, cartoon, sketch"
- **Tags:** steampunk, baroque, cyborg, portrait, gold
- **Style / Reference:** Oil Painting, Sci-Fi Baroque
- **Composition:** Medium shot, portrait
- **Color palette:** Gold, white, deep velvet red, bronze
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20260215_baroque_cyborg.jpg`
- **License / Attribution:** CC0
- **Notes:** Blend the mechanical and organic seamlessly.

### Suggestion: Phoenix Ascending
- **Prompt:** "A dramatic fantasy scene of a massive phoenix rising from a pile of white ash. The bird is composed of living fire and molten gold feathers. Embers and sparks fill the air. The background is a dark, charred landscape, contrasting with the intense brightness of the bird."
- **Negative prompt:** "water, ice, dull colors, bird skeleton, cartoon"
- **Tags:** fantasy, fire, phoenix, mythical, epic
- **Style / Reference:** Fantasy Art, Digital Painting
- **Composition:** Centered, dynamic upward motion
- **Color palette:** Blazing orange, yellow, gold, charcoal black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260215_phoenix_ascending.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the particle effects of the sparks and fire.

### Suggestion: Clockwork Heart
- **Prompt:** "A surreal, hyper-realistic close-up of a human heart mechanically constructed from intricate brass watch gears, springs, and ticking escapements. It is suspended in a glass jar filled with amber fluid. Light refracts through the glass and metal."
- **Negative prompt:** "blood, gore, organic tissue, plastic, simple"
- **Tags:** surreal, steampunk, mechanical, heart, macro
- **Style / Reference:** Surrealism, Macro Photography
- **Composition:** Extreme close-up, center focus
- **Color palette:** Brass, gold, amber, dark vignette
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260215_clockwork_heart.jpg`
- **License / Attribution:** CC0
- **Notes:** The metal textures should look oiled and functional.

### Suggestion: Art Deco Atlantis
- **Prompt:** "A majestic underwater city built in the Art Deco style. Gold-plated geometric skyscrapers rise from the ocean floor, covered in barnacles and glowing corals. Schools of fish swim through the arched windows. God rays filter down from the surface."
- **Negative prompt:** "modern, ugly, ruins, rubble, murky"
- **Tags:** underwater, art deco, architecture, city, fantasy
- **Style / Reference:** BioShock-esque, Architectural Visualization
- **Composition:** Wide angle, looking up
- **Color palette:** Turquoise, gold, deep blue, seafoam green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260215_art_deco_atlantis.jpg`
- **License / Attribution:** CC0
- **Notes:** Combine the clean lines of Art Deco with the organic chaos of the ocean.

### Suggestion: Galactic Patisserie
- **Prompt:** "A mouth-watering macro shot of a glazed donut that looks like a miniature galaxy. The glaze is a swirling nebula of purple and blue with edible star sprinkles. It sits on a silver plate. The lighting is soft and cinematic."
- **Negative prompt:** "messy, dry, realistic dough, boring"
- **Tags:** food, space, abstract, macro, whimsical
- **Style / Reference:** Food Photography, Abstract Art
- **Composition:** 45-degree angle, macro
- **Color palette:** Galaxy purple, blue, silver, pastry golden brown
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260215_galactic_patisserie.jpg`
- **License / Attribution:** CC0
- **Notes:** The glaze should look glossy and wet.

### Suggestion: Bioluminescent High Fashion
- **Prompt:** "A fashion editorial shot of a model wearing an avant-garde dress made of living bioluminescent jellyfish tissue. The dress glows with a soft blue light. The model poses on a reflective black runway. The background is dark to let the dress shine."
- **Negative prompt:** "casual clothes, daylight, ugly face, low fashion"
- **Tags:** fashion, bioluminescence, sci-fi, portrait, avant-garde
- **Style / Reference:** High Fashion Photography, Sci-Fi
- **Composition:** Full body shot, low angle
- **Color palette:** Electric blue, black, skin tones
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20260215_bioluminescent_fashion.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the fabric looks organic and translucent.

### Suggestion: Miniature Railway Chase
- **Prompt:** "A macro tilt-shift photography shot of a miniature steam train chase scene on a model railway. The trains are tiny but incredibly detailed, puffing cotton smoke. They race through a miniature pine forest made of bottle brushes. The lighting mimics a sunny afternoon with shallow depth of field."
- **Negative prompt:** "full size train, real forest, dark, blurry"
- **Tags:** retro, macro, still life, whimsical, bright
- **Style / Reference:** Tilt-shift Photography, Miniature Faking
- **Composition:** High angle, macro focus
- **Color palette:** Bright greens, train engine black/red, sunny yellow
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260223_miniature_railway.jpg`
- **License / Attribution:** CC0
- **Notes:** Use tilt-shift blur to emphasize the scale.

### Suggestion: The Eye in the Storm
- **Prompt:** "A terrifying, hyper-realistic wide shot of a massive hurricane viewed from a ship at sea. In the center of the storm's eye, a colossal, non-Euclidean glowing eye gazes down from the heavens. The water is rough and dark, with jagged lightning illuminating the roiling clouds."
- **Negative prompt:** "calm, sunny, land, cartoon, low resolution"
- **Tags:** horror, fantasy, landscape, nature, dark, moody
- **Style / Reference:** Lovecraftian Horror, Cinematic
- **Composition:** Wide shot, low angle from water surface
- **Color palette:** Dark blues, greys, electric purple/white lightning
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260223_eye_in_storm.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the scale of the eye against the storm.

### Suggestion: Layered Paper Forest
- **Prompt:** "A digital art illustration mimicking a backlit paper-cut light box. Layers of white paper are cut into silhouettes of a dense forest and distant mountains. Warm golden light shines from behind, creating depth through shadows and varying opacity of the paper layers."
- **Negative prompt:** "realistic, 3D render, photo, flat, cold colors"
- **Tags:** fantasy, landscape, nature, ethereal, cinematic
- **Style / Reference:** Paper Art, Silhouette, Lightbox
- **Composition:** Centered, layered depth
- **Color palette:** Gold, orange, deep brown shadows, warm white
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260223_paper_forest.jpg`
- **License / Attribution:** CC0
- **Notes:** The lighting needs to look like it's coming from behind the paper.

### Suggestion: Digital Fragmentation
- **Prompt:** "A stylized portrait of a hacker where their face is partially dissolving into digital pixels and data streams (datamoshing). The left side is a realistic human face, while the right side fragments into colorful glitch artifacts, compression blocks, and cascading code."
- **Negative prompt:** "perfect face, clean, painting, black and white"
- **Tags:** cyberpunk, sci-fi, portrait, abstract, dark
- **Style / Reference:** Glitch Art, Datamoshing, Cyberpunk
- **Composition:** Close-up portrait
- **Color palette:** Skin tones, neon green, magenta, digital noise
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260223_digital_fragmentation.jpg`
- **License / Attribution:** CC0
- **Notes:** Balance the realism with the glitch effect.

### Suggestion: Gummy Bear Canyon
- **Prompt:** "A surreal landscape composed entirely of translucent gummy candy. The river is flowing soda, the rocks are rock candy, and the trees are giant lollipops. Sunlight passes through the translucent gummy mountains, casting colorful caustics on the sugary ground."
- **Negative prompt:** "realistic rock, water, dirt, dark, scary"
- **Tags:** fantasy, landscape, surreal, whimsical, bright
- **Style / Reference:** 3D Render, Surrealism
- **Composition:** Wide angle landscape
- **Color palette:** Translucent red, green, orange, bright blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260223_gummy_canyon.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the subsurface scattering and translucency of the materials.

### Suggestion: Infrared Dreamscape
- **Prompt:** "A surreal landscape shot on Kodak Aerochrome infrared film. The dense forest foliage is a vibrant, shocking pink and magenta, contrasting deeply with a turquoise blue river and sky. A solitary wooden cabin sits on the riverbank."
- **Negative prompt:** "green trees, realistic colors, digital, low contrast"
- **Tags:** infrared, aerochrome, surreal, landscape, pink
- **Style / Reference:** Analog Photography, Kodak Aerochrome
- **Composition:** Wide shot, rule of thirds
- **Color palette:** Hot pink, Magenta, Turquoise, White
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260301_infrared_dream.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the grain and the specific color shift of infrared film.

### Suggestion: Vaporwave Classical
- **Prompt:** "A Vaporwave aesthetic composition featuring a classical white marble bust of Helios wearing pixelated black sunglasses. The statue is blowing a pink bubblegum bubble. The background is a retro neon grid fading into a purple and cyan gradient sunset."
- **Negative prompt:** "realistic, historical, boring, sepia, warm colors"
- **Tags:** vaporwave, aesthetic, statue, surreal, retro
- **Style / Reference:** Vaporwave, Glitch Art, Pop Art
- **Composition:** Centered portrait
- **Color palette:** Cyan, Magenta, Pink, Marble White
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260301_vaporwave_statue.jpg`
- **License / Attribution:** CC0
- **Notes:** Combine the high art of the statue with the low-fi digital aesthetic.

### Suggestion: Layered Paper Lightbox
- **Prompt:** "A backlit paper-cut light box art piece depicting a deep forest scene. Multiple layers of white paper silhouettes create depth. In the distance, a deer stands between the trees. The backlight is a warm golden glow that fades to deep orange at the edges."
- **Negative prompt:** "flat, drawing, painting, 3D render, realistic trees"
- **Tags:** papercut, lightbox, silhouette, craft, layered
- **Style / Reference:** Paper Art, Shadow Box
- **Composition:** Layered depth, centered subject
- **Color palette:** White (paper), Orange/Gold (light), Black (shadows)
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260301_paper_lightbox.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the shadows cast by the paper layers to show thickness.

### Suggestion: Glitch Art Portrait
- **Prompt:** "A digital glitch art portrait of a cyberpunk hacker. Half of their face is photorealistic, while the other half is heavily datamoshed, pixelated, and smeared into digital noise. CRT scanlines and chromatic aberration overlay the image."
- **Negative prompt:** "clean, smooth, perfect, painting, lowres"
- **Tags:** glitch, datamoshing, cyberpunk, portrait, abstract
- **Style / Reference:** Glitch Art, Datamoshing
- **Composition:** Close-up portrait
- **Color palette:** Neon green, static grey, skin tones, electric blue
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20260301_glitch_portrait.jpg`
- **License / Attribution:** CC0
- **Notes:** The transition between real and glitch should be jagged and digital.

### Suggestion: Retro Terminal Room
- **Prompt:** "A dimly lit, claustrophobic server room from the late 1970s (Cassette Futurism). Walls are lined with bulky mainframe computers featuring reeling tape drives and flashing incandescent bulbs. Green phosphor monochrome monitors display scrolling code. Cables hang messily from the ceiling."
- **Negative prompt:** "modern, LCD, blue LEDs, clean, white"
- **Tags:** cassette futurism, retro, technology, 70s, sci-fi
- **Style / Reference:** Sci-Fi Movie Set, Analog Tech
- **Composition:** One-point perspective down the aisle
- **Color palette:** Phosphor green, beige, dark grey, amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260301_retro_terminal.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the tactility of the buttons and the glow of the CRTs.

### Suggestion: Ceramic Tea Party
- **Prompt:** "A surreal tea party scene where the characters (rabbits and hatters) and the setting are made entirely of polished, painted porcelain. Fine cracks in the material are filled with gold (kintsugi). The table is set in a garden of ceramic flowers."
- **Negative prompt:** "flesh, fur, realistic skin, dull, broken"
- **Tags:** surreal, porcelain, kintsugi, tea party, fantasy
- **Style / Reference:** 3D Render, Ceramic Art, Alice in Wonderland
- **Composition:** Eye level, table setting
- **Color palette:** White, cobalt blue, gold, pastel pink
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260401_ceramic_tea.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the glossiness of the porcelain and the gold cracks.

### Suggestion: Bioluminescent Desert
- **Prompt:** "A majestic night landscape of a vast desert. The sand dunes ripple with faint blue bioluminescence. Giant alien cacti glow with internal neon green light. A massive, ringed planet dominates the starry sky."
- **Negative prompt:** "daylight, sun, water, forest, city"
- **Tags:** sci-fi, desert, bioluminescence, night, alien
- **Style / Reference:** Sci-Fi Concept Art, National Geographic (Alien)
- **Composition:** Wide shot, low angle
- **Color palette:** Deep blue, neon green, sand beige, black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260401_bio_desert.jpg`
- **License / Attribution:** CC0
- **Notes:** Contrast the dark sky with the glowing terrestrial elements.

### Suggestion: Isometric Pixel Gamer Room
- **Prompt:** "A cozy, high-fidelity isometric pixel art view of a gamer's bedroom. A desk with a dual-monitor setup glows. Posters cover the walls. A cat sleeps on a beanbag. Rain falls outside the window."
- **Negative prompt:** "blurry, vector, 3D render, realistic, messy"
- **Tags:** pixel art, isometric, interior, cozy, retro
- **Style / Reference:** Pixel Art, 16-bit, Cozy Games
- **Composition:** Isometric view (45 degrees)
- **Color palette:** Warm indoors, cool blue outdoors, neon accents
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260401_pixel_room.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure clear pixel definition and grid alignment.

### Suggestion: Miniature Food Kingdom
- **Prompt:** "A whimsical landscape photography shot where giant food items form the terrain. Steamed broccoli florets are towering trees. Mashed potato mountains rise in the distance. A river of brown gravy flows through a valley of peas."
- **Negative prompt:** "rotten food, messy, plastic, realistic size"
- **Tags:** whimsical, food, miniature, landscape, fun
- **Style / Reference:** Macro Photography, Cloudy with a Chance of Meatballs
- **Composition:** Tilt-shift, bird's eye view
- **Color palette:** Vibrant green, creamy white, rich brown
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260401_food_kingdom.jpg`
- **License / Attribution:** CC0
- **Notes:** Use depth of field to sell the miniature scale.

### Suggestion: Glass Blower's Workshop
- **Prompt:** "A warm, atmospheric interior shot of a traditional glass blower's workshop. A master craftsman shapes a glowing orange molten glass bubble on a blowpipe. Shelves in the background are lined with colorful, delicate glass vases catching the light."
- **Negative prompt:** "modern factory, cold light, plastic, broken glass"
- **Tags:** craft, glass, interior, warm, portrait
- **Style / Reference:** Cinematic Documentary, Artisan
- **Composition:** Medium shot, focus on the molten glass
- **Color palette:** Glowing orange, amber, dark shadows, prismatic reflections
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20260401_glass_workshop.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the intense heat and light of the molten glass.

### Suggestion: Cinematic Claymation
- **Date:** 2026-05-01
- **Prompt:** "A whimsical, stop-motion style claymation character resembling a clumsy robot with fingerprints visible on the plasticine surface. It stands in a miniature cardboard city studio set. Dramatic cinematic lighting creates strong shadows."
- **Negative prompt:** "3D render, smooth, digital, cartoon, drawing"
- **Tags:** claymation, stop-motion, whimsical, miniature, robot
- **Style / Reference:** Aardman, Laika
- **Composition:** Medium shot, studio lighting
- **Color palette:** Primary colors, cardboard browns, warm tungsten light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260501_claymation_robot.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the texture of the clay and the fingerprints.

### Suggestion: Thermal Vision Hunt
- **Date:** 2026-05-01
- **Prompt:** "A simulated thermal imaging camera shot of a wolf howling at the moon. The wolf is a glowing spectrum of heat (reds, oranges, yellows) against a cool, dark blue background. The heat signature reveals the texture of the fur."
- **Negative prompt:** "realistic colors, black and white, standard photo"
- **Tags:** thermal, heat map, infrared, predator, abstract
- **Style / Reference:** Thermal Imaging, Scientific Visualization
- **Composition:** Silhouette, high contrast
- **Color palette:** Thermal spectrum (Red, Orange, Yellow, Blue, Black)
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260501_thermal_wolf.jpg`
- **License / Attribution:** CC0
- **Notes:** The contrast between the hot subject and cold background is key.

### Suggestion: Blueprint Schematic
- **Date:** 2026-05-01
- **Prompt:** "A detailed cyanotype blueprint schematic of a fictional steampunk flying machine. White technical lines, measurements, and annotations are drawn on a textured dark blue paper background. The design includes gears, propellers, and balloons."
- **Negative prompt:** "photo, 3D, color, realistic, render"
- **Tags:** blueprint, schematic, cyanotype, steampunk, technical
- **Style / Reference:** Architectural Drawing, Cyanotype
- **Composition:** Flat lay, technical diagram
- **Color palette:** Cyan blue, white
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20260501_blueprint_machine.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the lines are clean and the paper texture is visible.

### Suggestion: Trash Polka Portrait
- **Date:** 2026-05-01
- **Prompt:** "A striking Trash Polka style tattoo art portrait of a woman's face. Realistic black and grey shading is juxtaposed with chaotic red smears, geometric shapes, and bold typography. The background is a distressed paper texture."
- **Negative prompt:** "clean, simple, traditional tattoo, color photo"
- **Tags:** trash polka, tattoo, abstract, portrait, collage
- **Style / Reference:** Tattoo Art, Mixed Media
- **Composition:** Portrait, centered
- **Color palette:** Black, Grey, Red, White
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20260501_trash_polka.jpg`
- **License / Attribution:** CC0
- **Notes:** The red elements should look like paint or ink splatters.

### Suggestion: Psychedelic Fractal Tunnel
- **Date:** 2026-05-01
- **Prompt:** "An infinite, mind-bending 3D fractal tunnel. Intricate geometric patterns in neon colors (electric blue, magenta, lime green) spiral towards a bright white center. The walls of the tunnel are reflective, creating a kaleidoscope effect."
- **Negative prompt:** "flat, 2D, simple, blurry, natural"
- **Tags:** fractal, psychedelic, abstract, 3D, neon
- **Style / Reference:** Mathematical Art, Psychedelic
- **Composition:** Centered perspective (infinite zoom)
- **Color palette:** Neon rainbow, black void
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260501_fractal_tunnel.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the depth and the infinite nature of the pattern.

### Suggestion: Unfinished Cathedral Sketch
- **Date:** 2026-01-19
- **Prompt:** "A rough graphite pencil sketch of a gothic cathedral on textured white paper. Construction lines, perspective grids, and eraser marks are visible. The bottom half is highly detailed and shaded with hatching, fading into loose gesture lines at the top."
- **Negative prompt:** "photorealistic, color, 3D render, smooth, ink"
- **Tags:** sketch, pencil, architecture, drawing, unfinished
- **Style / Reference:** Architectural Sketch, Graphite
- **Composition:** Low angle perspective
- **Color palette:** Grayscale, graphite grey, paper white
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20260119_cathedral_sketch.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the paper texture and the difference in finish between bottom and top.

### Suggestion: Byzantine Gold Mosaic
- **Date:** 2026-01-19
- **Prompt:** "A close-up of an ancient Byzantine gold leaf mosaic on a cracked church wall. Uneven tesserae tiles form the image of a celestial angel with multi-colored wings. Some tiles are missing, revealing the rough plaster underneath. The gold reflects light unevenly."
- **Negative prompt:** "painting, smooth, digital art, modern, flat"
- **Tags:** mosaic, gold, byzantine, texture, angel
- **Style / Reference:** Byzantine Art, Mosaic
- **Composition:** Close-up face and wings
- **Color palette:** Gold, Lapis Lazuli Blue, Deep Red
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260119_byzantine_mosaic.jpg`
- **License / Attribution:** CC0
- **Notes:** The grout lines and tile unevenness are crucial for realism.

### Suggestion: Floating City Bubble
- **Date:** 2026-01-19
- **Prompt:** "A macro photograph of a giant iridescent soap bubble floating down a busy New York street. The thin, oily surface of the bubble reflects a distorted, fish-eye view of the surrounding skyscrapers, traffic, and pedestrians. The background is softly blurred (bokeh)."
- **Negative prompt:** "illustration, drawing, fake, matte, solid"
- **Tags:** macro, bubble, reflection, urban, photorealistic
- **Style / Reference:** Macro Photography, Street Photography
- **Composition:** Centered bubble, shallow depth of field
- **Color palette:** Rainbow iridescence, urban greys and yellows
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260119_city_bubble.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the refraction and reflection on the bubble surface.

### Suggestion: Linocut Forest Stag
- **Date:** 2026-01-19
- **Prompt:** "A high-contrast black and white linocut print of a majestic stag standing in a stylized pine forest. The image features bold, carved lines and ink textures. The white areas show the paper grain where the ink didn't touch. No greyscale, only black and white."
- **Negative prompt:** "color, grey, shading, smooth, photo"
- **Tags:** linocut, printmaking, black and white, stag, forest
- **Style / Reference:** Linocut, Woodblock Print
- **Composition:** Centered subject
- **Color palette:** Black Ink, Cream Paper
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20260119_linocut_stag.jpg`
- **License / Attribution:** CC0
- **Notes:** The look should simulate the physical carving of the block.

### Suggestion: Felt Puppet Adventurer
- **Date:** 2026-01-19
- **Prompt:** "A cinematic shot of a fuzzy felt puppet character resembling a brave explorer, wearing a tiny stitched leather hat and jacket. He stands in a realistic, mossy forest environment. Dramatic lighting treats the puppet like a serious actor, highlighting the fuzz texture."
- **Negative prompt:** "human, skin, cartoon drawing, 3D render, smooth"
- **Tags:** puppet, felt, whimsical, cinematic, forest
- **Style / Reference:** Jim Henson style, Felt Art
- **Composition:** Eye level (puppet scale), depth of field
- **Color palette:** Earth tones, moss green, felt texture
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260119_felt_puppet.jpg`
- **License / Attribution:** CC0
- **Notes:** The contrast between the toy-like material and realistic lighting makes this work.

### Suggestion: Anamorphic Chalk Illusion
- **Date:** 2026-06-01
- **Prompt:** "A high-angle photograph of 3D anamorphic street art drawn in chalk on pavement. From this specific angle, the drawing creates a convincing illusion of a gaping abyss opening up in the middle of the sidewalk, revealing a subterranean fantasy world with glowing mushrooms and waterfalls. Passersby look at it in amazement."
- **Negative prompt:** "flat, bad perspective, 2D, mural on wall, graffiti, messy"
- **Tags:** street art, illusion, 3D, chalk, fantasy
- **Style / Reference:** Anamorphic Art, Street Photography
- **Composition:** High angle (forced perspective)
- **Color palette:** Dusty chalk pastels, grey pavement, vibrant underground colors
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260601_chalk_illusion.jpg`
- **License / Attribution:** CC0
- **Notes:** The angle is critical to sell the 3D illusion effect.

### Suggestion: Bismuth Crystal Fortress
- **Date:** 2026-06-01
- **Prompt:** "A surreal architectural concept art of a fortress grown entirely from bismuth crystals. The walls feature the characteristic geometric, staircase-like hopper crystal structure. The surface is iridescent, shifting between rainbow colors (metallic pink, gold, blue) under a bright white sky."
- **Negative prompt:** "organic, round, brick, stone, dull colors, realistic castle"
- **Tags:** bismuth, crystal, architecture, surreal, iridescent
- **Style / Reference:** 3D Render, Surrealism
- **Composition:** Wide shot, low angle
- **Color palette:** Metallic rainbow, iridescent, white background
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260601_bismuth_fortress.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the 'hopper' geometric structure of the crystals.

### Suggestion: Kirlian Aura Photography
- **Date:** 2026-06-01
- **Prompt:** "A Kirlian photography shot of a maple leaf against a pitch-black background. The leaf is silhouetted, surrounded by a coronal discharge of glowing, electrified plasma filaments in violet and electric blue. The veins of the leaf faintly glow with energy."
- **Negative prompt:** "daylight, normal photo, green leaf, flat, blurry"
- **Tags:** kirlian, photography, aura, electric, abstract
- **Style / Reference:** Scientific Photography, Abstract
- **Composition:** Centered, flat lay
- **Color palette:** Black, Violet, Electric Blue, White
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260601_kirlian_leaf.jpg`
- **License / Attribution:** CC0
- **Notes:** The glowing edge effect (corona) is the defining feature.

### Suggestion: Cross-Stitch Pixel Art
- **Date:** 2026-06-01
- **Prompt:** "A close-up macro shot of a framed cross-stitch embroidery piece. The embroidery depicts a retro 8-bit video game landscape (green hills, blue sky). The image focuses on the texture of the fabric (aida cloth) and the individual X-shaped thread stitches that form the pixels."
- **Negative prompt:** "digital pixel art, screen, smooth, drawing, vector"
- **Tags:** embroidery, cross-stitch, craft, pixel art, texture
- **Style / Reference:** Macro Photography, Handicraft
- **Composition:** Close-up, texture focus
- **Color palette:** Cotton thread colors, white fabric
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260601_cross_stitch.jpg`
- **License / Attribution:** CC0
- **Notes:** Must look like physical thread and fabric, not a digital image.

### Suggestion: Ferrofluid Magnetic Sculpture
- **Date:** 2026-06-01
- **Prompt:** "A studio macro shot of a ferrofluid sculpture under a magnetic field. The black magnetic liquid forms sharp, rhythmic spikes and organic alien shapes. The surface is highly reflective, mirroring the studio softbox lighting. A splash of gold ink mixes with the black fluid."
- **Negative prompt:** "water, matte, flat, blurry, messy, rust"
- **Tags:** ferrofluid, macro, abstract, physics, liquid
- **Style / Reference:** Scientific Photography, Abstract Art
- **Composition:** Macro, centered
- **Color palette:** Glossy Black, Gold, White reflections
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260601_ferrofluid.jpg`
- **License / Attribution:** CC0
- **Notes:** The sharp spikes are the key visual element.

### Suggestion: Misty Prehistoric Swamp
- **Date:** 2026-06-15
- **Prompt:** "A photorealistic, atmospheric shot of a misty prehistoric swamp at dawn. A massive Triceratops wades through the murky water, surrounded by giant ferns and ancient cycads. Soft morning light filters through the fog, creating god rays."
- **Negative prompt:** "cartoon, drawing, lowres, modern plants, blur"
- **Tags:** prehistoric, dinosaur, nature, fog, cinematic
- **Style / Reference:** Paleoart, National Geographic
- **Composition:** Eye level, environmental portrait
- **Color palette:** Muted greens, grey fog, soft morning gold
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260615_prehistoric_swamp.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the atmosphere and scale of the dinosaur.

### Suggestion: Watercolor Rainy Paris
- **Date:** 2026-06-15
- **Prompt:** "A soft, impressionistic watercolor painting of a rainy street in Paris. Reflections of street lamps shimmer on the wet cobblestones. The Eiffel Tower fades into the grey mist in the background. Loose brushstrokes define the umbrellas of pedestrians."
- **Negative prompt:** "photograph, sharp, digital art, acrylic, oil"
- **Tags:** watercolor, paris, rain, impressionism, art
- **Style / Reference:** Watercolor, Impressionism
- **Composition:** Street view, leading lines
- **Color palette:** Pastel blues, greys, soft yellows
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260615_watercolor_paris.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the bleeding colors and paper texture.

### Suggestion: Pop Art Explosion
- **Date:** 2026-06-15
- **Prompt:** "A vibrant Pop Art style comic book panel inspired by Roy Lichtenstein. A dramatic explosion with a bold 'BOOM!' sound effect in a jagged yellow speech bubble. Thick black outlines, Ben-Day dots for shading, and flat primary colors."
- **Negative prompt:** "photorealistic, 3D, shading, gradients, noise"
- **Tags:** pop art, comic, retro, explosion, vector
- **Style / Reference:** Pop Art, Comic Book
- **Composition:** Dynamic, centered text
- **Color palette:** Primary Red, Blue, Yellow, Black, White
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260615_pop_art_boom.jpg`
- **License / Attribution:** CC0
- **Notes:** The Ben-Day dots are the signature texture to capture.

### Suggestion: Bauhaus Geometric Poster
- **Date:** 2026-06-15
- **Prompt:** "A minimalist geometric poster design inspired by the Bauhaus movement. A balanced composition of simple shapes (circles, triangles, rectangles) arranged on a beige paper background. Clean typography."
- **Negative prompt:** "busy, textured, 3D, messy, realistic"
- **Tags:** bauhaus, abstract, geometric, design, minimalist
- **Style / Reference:** Bauhaus, Graphic Design
- **Composition:** Flat, graphic
- **Color palette:** Red, Blue, Yellow, Black, Beige
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20260615_bauhaus_poster.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on balance and negative space.

### Suggestion: Wild West Ghost Town
- **Date:** 2026-06-15
- **Prompt:** "A dusty, desolate street of an abandoned Wild West ghost town at high noon. Tumbleweeds roll past wooden saloon doors hanging off their hinges. The sun is harsh and unforgiving, casting deep shadows. Heat haze ripples the air."
- **Negative prompt:** "modern, cars, people, green grass, rain"
- **Tags:** western, cowboy, ghost town, abandoned, cinematic
- **Style / Reference:** Western Movie, Cinematic
- **Composition:** One-point perspective down the street
- **Color palette:** Sepia, dusty brown, faded wood, bleached sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260615_ghost_town.jpg`
- **License / Attribution:** CC0
- **Notes:** The lighting should be hard and direct to mimic the midday sun.

### Suggestion: Surreal Chessboard Desert
- **Date:** 2026-10-25
- **Prompt:** "A surreal, dreamlike landscape painting in the style of Salvador Dali. The desert floor is a warping, melting black and white chessboard grid that stretches to infinity. Giant chess pieces (knights and rooks) float weightlessly in the sky among melting pocket watches. Long, dramatic shadows cast by invisible objects."
- **Negative prompt:** "realistic, logical, modern, photo, noise"
- **Tags:** surreal, dali, chess, dream, melting
- **Style / Reference:** Surrealism, Salvador Dali
- **Composition:** Wide angle, deep depth of field
- **Color palette:** Desert orange, sky blue, black, white, gold
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261025_chess_desert.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the "melting" and "warping" aspect.

### Suggestion: 1960s Spaceport Lounge
- **Date:** 2026-10-25
- **Prompt:** "A cinematic wide shot of a retro-futuristic spaceport departure lounge, designed in the 1960s Jet Age style (Eero Saarinen). Huge curved glass windows overlook a launchpad where sleek silver retro-rockets are taking off. Passengers in mod fashion and bubble helmets wait in ball chairs. The floor is polished terrazzo."
- **Negative prompt:** "modern technology, flat screens, messy, dark, dystopian"
- **Tags:** retro-futurism, 60s, spaceport, mid-century modern, travel
- **Style / Reference:** Mid-Century Modern, Cinematic, TWA Flight Center
- **Composition:** Wide interior shot, symmetrical
- **Color palette:** Burnt orange, teal, crisp white, silver
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261025_spaceport.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the optimism of the early space age.

### Suggestion: Mechanical Bee on Circuit Flower
- **Date:** 2026-10-25
- **Prompt:** "A hyper-realistic macro photography shot of a tiny mechanical bee collecting data from a flower made of flexible printed circuit boards and fiber optics. The bee has translucent glass wings with gold veins and a copper abdomen. The flower's pistils are glowing LED filaments. Shallow depth of field."
- **Negative prompt:** "real insect, organic flower, blurry, lowres, drawing"
- **Tags:** macro, cyberpunk, insect, technology, nature
- **Style / Reference:** Macro Photography, Sci-Fi
- **Composition:** Extreme close-up, macro focus
- **Color palette:** Gold, copper, circuit board green, electric blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261025_mech_bee.jpg`
- **License / Attribution:** CC0
- **Notes:** The textures of metal and glass are crucial.

### Suggestion: Rooftop Oasis in Ruined City
- **Date:** 2026-10-25
- **Prompt:** "A serene, golden-hour shot of a lush vegetable garden thriving on the roof of a crumbling skyscraper in a reclaimed post-apocalyptic city. Vines drape over the edge. In the background, other ruined skyscrapers are covered in greenery. A survivor reads a book in a hammock, suggesting peace amidst ruins."
- **Negative prompt:** "zombies, monsters, scary, dark, fire, destruction"
- **Tags:** post-apocalyptic, solarpunk, nature, peace, city
- **Style / Reference:** Concept Art, The Last of Us, Solarpunk
- **Composition:** Medium-wide shot, environmental
- **Color palette:** Sunset gold, lush green, concrete grey, soft blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261025_rooftop_oasis.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the beauty of nature taking back the city.

### Suggestion: Memphis Group Playground
- **Date:** 2026-10-25
- **Prompt:** "A surreal, abstract architectural space designed in the style of the 80s Memphis Group. The room is filled with giant geometric shapes: squiggly lines, cones, and spheres. Patterns include terrazzo and black-and-white stripes. The lighting is flat and bright, making it look like a 3D render."
- **Negative prompt:** "realistic, dirt, shadows, moody, organic"
- **Tags:** memphis design, 80s, abstract, geometric, pattern
- **Style / Reference:** Memphis Group, Postmodernism, 3D Render
- **Composition:** Eye level, chaotic but balanced
- **Color palette:** Pastel pink, mint green, electric blue, yellow, black/white
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20261025_memphis_playground.jpg`
- **License / Attribution:** CC0
- **Notes:** It should feel playful and artificial.

### Suggestion: Rococo Ballroom Dancers
- **Date:** 2026-11-01
- **Prompt:** "A lavish, pastel-colored Rococo ballroom filled with dancers in powdered wigs and wide silk gowns. Crystal chandeliers drip with diamonds. The walls are adorned with gold filigree and mirrors. Soft, airy lighting captures the frivolity and elegance of the era."
- **Negative prompt:** "dark, gritty, modern, plain, high contrast"
- **Tags:** rococo, historical, dance, interior, pastel
- **Style / Reference:** Rococo, Oil Painting, Fragonard
- **Composition:** Wide shot, slightly high angle
- **Color palette:** Pastel pink, baby blue, gold, cream
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261101_rococo_ballroom.jpg`
- **License / Attribution:** CC0
- **Notes:** The key is the 'airiness' and the abundance of pastel colors.

### Suggestion: Obsidian Volcanic Temple
- **Date:** 2026-11-01
- **Prompt:** "A sharp, angular temple carved entirely from glossy black obsidian volcanic glass. It sits at the edge of a bubbling lava lake. The black stone reflects the intense red glow of the lava, creating high-contrast highlights. Smoke rises from vents in the ground."
- **Negative prompt:** "matte stone, grey rock, daylight, blue sky, trees"
- **Tags:** obsidian, volcano, temple, fantasy, dark
- **Style / Reference:** Fantasy Landscape, 3D Render
- **Composition:** Low angle, looking up at the temple
- **Color palette:** Black, lava red, orange, smoke grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261101_obsidian_temple.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the glass-like reflectivity of the obsidian.

### Suggestion: Holographic Data Map
- **Date:** 2026-11-01
- **Prompt:** "A 3D holographic topographic map floating in the center of a dark, high-tech command center. The terrain is rendered in translucent blue and orange wireframe grids. A hand reaches into the frame to manipulate the hologram, causing digital ripples."
- **Negative prompt:** "paper map, physical screen, messy, bright room"
- **Tags:** hologram, map, sci-fi, technology, ui
- **Style / Reference:** Sci-Fi UI Design, Cyberpunk
- **Composition:** Close-up on the hologram
- **Color palette:** Electric blue, safety orange, black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261101_holographic_map.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the hologram looks translucent and emits light.

### Suggestion: Futuristic Zero-G Sports
- **Date:** 2026-11-01
- **Prompt:** "A dynamic action shot of a futuristic zero-gravity sport played inside a massive transparent sphere arena. Athletes in sleek, neon-trimmed armored suits propel themselves off floating platforms to catch a glowing orb. The background shows a cheering crowd and a futuristic cityscape."
- **Negative prompt:** "gravity, ground, grass, stadium, static"
- **Tags:** sports, sci-fi, zero-g, action, futuristic
- **Style / Reference:** Sci-Fi Concept Art, Sports Photography
- **Composition:** Dynamic, tilted angle, motion blur
- **Color palette:** Neon team colors (cyan vs magenta), stadium lights
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261101_zero_g_sports.jpg`
- **License / Attribution:** CC0
- **Notes:** Use motion blur to convey the speed and chaos.

### Suggestion: Ukiyo-e Cat Spirit
- **Date:** 2026-11-01
- **Prompt:** "A traditional Japanese woodblock print (Ukiyo-e) depicting a giant, spectral cat (Bakeneko) looming over a snow-covered village at night. The colors are flat and vibrant—indigo sky, salmon pink glowing eyes, and matcha green kimono patterns. The texture of the paper is visible."
- **Negative prompt:** "3D, realistic, photograph, shading, gradient"
- **Tags:** ukiyo-e, woodblock, cat, yokai, japanese
- **Style / Reference:** Ukiyo-e, Hokusai, Kuniyoshi
- **Composition:** Vertical, dramatic scale difference
- **Color palette:** Indigo, Salmon Pink, White, Black
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20261101_ukiyo_e_cat.jpg`
- **License / Attribution:** CC0
- **Notes:** Adhere strictly to the flat color and line work style of woodblock prints.

### Suggestion: Constructivist Revolution
- **Date:** 2026-11-15
- **Prompt:** "A bold, geometric Soviet Constructivist style poster design. Sharp diagonal red and black shapes slice through a cream background. Industrial imagery (gears, factories) is abstracted into pure form. Cyrillic-style typography integrates with the architecture of the composition."
- **Negative prompt:** "photorealistic, messy, organic, 3D render, gradient"
- **Tags:** constructivism, geometric, poster, abstract, retro
- **Style / Reference:** Constructivism, El Lissitzky, Rodchenko
- **Composition:** Diagonal dynamic, graphic design
- **Color palette:** Red, Black, Cream, Grey
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20261115_constructivist_poster.jpg`
- **License / Attribution:** CC0
- **Notes:** Keep the shapes flat and the lines sharp.

### Suggestion: Iridescent Slime Mold
- **Date:** 2026-11-15
- **Prompt:** "A macro photography shot of a vibrant, iridescent slime mold growing on rotting dark wood. The mold forms intricate, vein-like networks that pulse with a yellow and neon green glow. Water droplets cling to the surface, reflecting the forest canopy."
- **Negative prompt:** "blurry, low contrast, dry, artificial, plastic"
- **Tags:** macro, slime, nature, bioluminescence, abstract
- **Style / Reference:** Macro Nature Photography, Scientific
- **Composition:** Extreme close-up
- **Color palette:** Neon Yellow, Lime Green, Dark Brown, Wet Black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261115_slime_mold.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the vein structure and the wet, biological texture.

### Suggestion: Velvet Jazz Lounge
- **Date:** 2026-11-15
- **Prompt:** "An interior shot of a moody, upscale jazz lounge. The furniture is upholstered in crushed red velvet. Dim, warm lighting reflects off brass instruments and crystal glasses. Smoke hangs low in the air. The atmosphere is intimate and luxurious."
- **Negative prompt:** "bright, daylight, modern, clean, neon"
- **Tags:** interior, noir, velvet, luxury, jazz
- **Style / Reference:** Cinematic, Interior Design
- **Composition:** Eye level, cozy
- **Color palette:** Deep Red, Gold, Shadowy Black, Warm Amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261115_velvet_lounge.jpg`
- **License / Attribution:** CC0
- **Notes:** The texture of the velvet and the haziness of the smoke are key.

### Suggestion: 3D Topographic Fantasy Map
- **Date:** 2026-11-15
- **Prompt:** "A high-angle, photorealistic view of a physical relief map of a fantasy kingdom. The terrain is built from layers of wood and painted plaster. Mountains are raised, rivers are carved deep blue channels. Tiny miniature castles and forests dot the landscape. Side lighting reveals the texture of the elevation."
- **Negative prompt:** "paper map, flat, drawing, digital map, satellite"
- **Tags:** map, topographic, fantasy, miniature, craft
- **Style / Reference:** Physical Model, Diorama
- **Composition:** High angle (top-down or 45 degrees)
- **Color palette:** Earth tones, wood, plaster white, river blue
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20261115_topographic_map.jpg`
- **License / Attribution:** CC0
- **Notes:** It must look like a physical object, not a digital drawing.

### Suggestion: Cybernetic Sprinter
- **Date:** 2026-11-15
- **Prompt:** "A frozen-in-time action shot of a Paralympic-style cybernetic sprinter launching from the starting blocks. Their legs are advanced carbon-fiber blades with glowing hydraulics. The stadium background is a blur of motion and neon lights. Raindrops are suspended in the air around them."
- **Negative prompt:** "static, standing still, normal legs, daylight, calm"
- **Tags:** sports, cyberpunk, action, cyborg, futuristic
- **Style / Reference:** Sports Photography, Cyberpunk Concept Art
- **Composition:** Low angle, dynamic action
- **Color palette:** Neon Blue, Carbon Black, Silver, Stadium lights
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261115_cyber_sprinter.jpg`
- **License / Attribution:** CC0
- **Notes:** Use motion blur on the background to emphasize the speed.

### Suggestion: Brutalist Library Atrium
- **Date:** 2026-12-01
- **Prompt:** "A monumental Brutalist library atrium. Massive, raw concrete pillars rise to a grid-patterned skylight. Geometric staircases crisscross the void in a complex, Escher-like arrangement. The atmosphere is quiet and imposing, with soft diffused light highlighting the rough texture of the concrete."
- **Negative prompt:** "ornate, colorful, wood, cozy, noisy, modern furniture"
- **Tags:** brutalism, architecture, interior, concrete, monolithic
- **Style / Reference:** Brutalist Architecture, Louis Kahn
- **Composition:** Wide angle, looking up, symmetry
- **Color palette:** Concrete Grey, Shadow Black, Soft White
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20261201_brutalist_atrium.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the weight and texture of the concrete.

### Suggestion: Microscopic Tardigrade
- **Date:** 2026-12-01
- **Prompt:** "A scanning electron microscope (SEM) style image of a tardigrade (water bear) clinging to a piece of moss. The image is falsely colored in neon blues and magentas to highlight the wrinkled texture of its skin and its tiny claws. The background is a dark void."
- **Negative prompt:** "optical photo, blurry, realistic colors, low detail, cartoon"
- **Tags:** microscopic, nature, science, abstract, neon
- **Style / Reference:** SEM Photography, Scientific Visualization
- **Composition:** Macro, centered subject
- **Color palette:** Neon Blue, Magenta, Black
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20261201_tardigrade.jpg`
- **License / Attribution:** CC0
- **Notes:** The 'false color' SEM look is distinct from standard macro photography.

### Suggestion: Damascus Steel Blade
- **Date:** 2026-12-01
- **Prompt:** "A high-resolution macro studio shot of a hand-forged Damascus steel knife blade. The intricate, swirling 'raindrop' pattern of the folded steel is clearly visible, contrasting with the mirror-polished cutting edge. Warm studio lighting reflects off the oil on the blade."
- **Negative prompt:** "stainless steel, smooth, scratches, rust, dull"
- **Tags:** craft, metal, texture, macro, damascus
- **Style / Reference:** Product Photography, Macro
- **Composition:** Close-up on the pattern
- **Color palette:** Steel Grey, Silver, Warm Gold (reflections)
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261201_damascus_steel.jpg`
- **License / Attribution:** CC0
- **Notes:** The contrast between the dark etched layers and bright polished layers is key.

### Suggestion: Tokyo Night Market
- **Date:** 2026-12-01
- **Prompt:** "A vibrant, crowded night market scene in a Tokyo alleyway. Clouds of steam rise from yakitori grills. Red and white paper lanterns glow overhead. In the foreground, a chef hands a skewer to a customer. The background is a beautiful bokeh blur of moving crowds and neon signs."
- **Negative prompt:** "empty, daylight, clean, quiet, western"
- **Tags:** street food, night, crowd, japan, atmospheric
- **Style / Reference:** Street Photography, Cinematic
- **Composition:** Eye level, depth of field
- **Color palette:** Lantern Red, Neon Blue, Smoke Grey, Warm Orange
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261201_tokyo_market.jpg`
- **License / Attribution:** CC0
- **Notes:** Balance the chaos of the crowd with a clear focal point.

### Suggestion: Art Nouveau Conservatory
- **Date:** 2026-12-01
- **Prompt:** "A romantic Art Nouveau conservatory at sunset. Curving, organic ironwork frames the tall glass walls, shaped like vines and flowers. Inside, exotic orchids and giant ferns grow wildly. The golden hour light casts complex, organic shadows on the intricate mosaic tile floor."
- **Negative prompt:** "modern, straight lines, industrial, dead plants, bright noon"
- **Tags:** art nouveau, architecture, nature, greenhouse, romantic
- **Style / Reference:** Art Nouveau, Alphonse Mucha (architecture)
- **Composition:** Wide shot, interior
- **Color palette:** Sage Green, Gold, Sunset Orange, Iron Black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261201_art_nouveau.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the 'whiplash' curves of the ironwork.
### Suggestion: Art Nouveau Greenhouse
- **Date:** 2026-12-01
- **Prompt:** "A breathtaking interior shot of an Art Nouveau style greenhouse. Curving ironwork beams in organic shapes support a glass roof. Lush exotic plants and hanging ferns fill the space. Stained glass panels with floral motifs filter the sunlight, casting colorful patterns on the mosaic floor."
- **Negative prompt:** "modern, straight lines, brutalist, dead plants, dark"
- **Tags:** art nouveau, greenhouse, architecture, nature, interior
- **Style / Reference:** Art Nouveau, Alphonse Mucha (architecture)
- **Composition:** Wide angle, looking up
- **Color palette:** Sage green, gold, stained glass colors
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261201_art_nouveau.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the organic curves of the ironwork.

### Suggestion: Damascus Steel Dagger
- **Date:** 2026-12-01
- **Prompt:** "A macro studio shot of an ornate dagger with a blade made of high-contrast Damascus steel. The watery, rippled pattern of the steel is clearly visible. The handle is carved from dark ebony wood with gold inlay. It rests on piece of red velvet."
- **Negative prompt:** "rust, plain steel, lowres, blurry, sword"
- **Tags:** damascus steel, weapon, macro, craft, still life
- **Style / Reference:** Product Photography, Macro
- **Composition:** Macro, 45-degree angle
- **Color palette:** Silver, black, gold, deep red
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261201_damascus_dagger.jpg`
- **License / Attribution:** CC0
- **Notes:** The texture of the Damascus steel is the hero of the shot.

### Suggestion: Steampunk Cello Performance
- **Date:** 2026-12-01
- **Prompt:** "A cinematic portrait of a musician playing a mechanical Steampunk cello. The instrument is a complex assembly of brass pipes, gears, and steam vents. The musician wears Victorian attire with leather goggles. The setting is a smoky, dimly lit Victorian theater stage."
- **Negative prompt:** "electric guitar, modern clothes, daylight, simple"
- **Tags:** steampunk, music, cello, portrait, cinematic
- **Style / Reference:** Steampunk, Cinematic Portrait
- **Composition:** Medium shot
- **Color palette:** Brass, copper, leather brown, stage smoke blue
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20261201_steampunk_cello.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the intricate details of the mechanical instrument.

### Suggestion: Fauvist City Street
- **Date:** 2026-12-01
- **Prompt:** "A vibrant, expressive painting of a busy city street in the style of Fauvism (Henri Matisse). Colors are unnatural and wild: trees are red, the sky is green, and the road is yellow. Bold, thick brushstrokes define the buildings and people. The mood is energetic and joyful."
- **Negative prompt:** "photorealistic, dull colors, black and white, precise"
- **Tags:** fauvism, painting, abstract, city, colorful
- **Style / Reference:** Fauvism, Henri Matisse, André Derain
- **Composition:** Street view
- **Color palette:** Bright red, emerald green, cadmium yellow, cobalt blue
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20261201_fauvist_street.jpg`
- **License / Attribution:** CC0
- **Notes:** Don't be afraid of clashing colors; that's the point of the style.

### Suggestion: Microscopic Water Bear
- **Date:** 2026-12-01
- **Prompt:** "A scanning electron microscope (SEM) style image of a tardigrade (water bear) in extreme detail. It clings to a piece of moss. The image is false-colored to highlight the texture of its chubby body and tiny claws. The background is a blurred void."
- **Negative prompt:** "cartoon, drawing, low detail, blurry"
- **Tags:** microscopic, tardigrade, science, macro, nature
- **Style / Reference:** Scientific Visualization, SEM Photography
- **Composition:** Extreme close-up
- **Color palette:** False color (electric blue, purple, or gold), black background
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261201_micro_tardigrade.jpg`
- **License / Attribution:** CC0
- **Notes:** The texture should look bumpy and organic, like an SEM scan.

### Suggestion: Kinetic Beach Beast
- **Date:** 2026-12-15
- **Prompt:** "A photorealistic wide shot of a massive, intricate kinetic sculpture walking on a windy beach. The structure is made of yellow PVC pipes and white sails, resembling a Theo Jansen Strandbeest. Sand blows across the dunes. The sky is overcast and dramatic."
- **Negative prompt:** "static, metal, robot, engine, calm"
- **Tags:** kinetic sculpture, beach, strandbeest, engineering, wind
- **Style / Reference:** Photorealistic, Kinetic Art, Theo Jansen
- **Composition:** Wide shot, low angle
- **Color palette:** Sand beige, PVC yellow, white, storm grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261215_kinetic_beast.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the sense of motion and the mechanical complexity.

### Suggestion: Pointillist Riverbank
- **Date:** 2026-12-15
- **Prompt:** "A vibrant landscape painting in the style of Pointillism (Neo-Impressionism). Thousands of tiny distinct dots of pure color blend to form a scene of a peaceful riverbank in summer. Willows drape over the water. People in Victorian dress picnic on the grass."
- **Negative prompt:** "smooth brushstrokes, blended colors, digital art, photo"
- **Tags:** pointillism, painting, river, dots, art
- **Style / Reference:** Pointillism, Georges Seurat, Signac
- **Composition:** Landscape view
- **Color palette:** Vibrant green, blue, yellow, touches of red
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20261215_pointillist_river.jpg`
- **License / Attribution:** CC0
- **Notes:** The 'dots' texture is essential for this style.

### Suggestion: Iridescent Dragon Scale
- **Date:** 2026-12-15
- **Prompt:** "A stunning macro photography shot of dragon scales. The scales shift color from emerald green to deep violet (iridescence) as they curve. The texture is hard and armor-like, but with organic ridges and scratches. Drops of water rest on the surface."
- **Negative prompt:** "blurry, lizard skin, soft, matte, flat color"
- **Tags:** macro, dragon, scales, iridescent, fantasy
- **Style / Reference:** Macro Photography, Fantasy Concept Art
- **Composition:** Extreme close-up, abstract texture
- **Color palette:** Iridescent Green, Purple, Blue, Black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261215_dragon_scale.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the light refraction and surface detail.

### Suggestion: Aerogel Flower Holder
- **Date:** 2026-12-15
- **Prompt:** "A studio product shot of a block of blue aerogel ('frozen smoke') holding a vibrant red rose. The aerogel is translucent and ghost-like, barely visible against the dark background, yet it physically supports the flower. The lighting highlights the ethereal, smoky quality of the material."
- **Negative prompt:** "glass, plastic, opaque, ice, messy"
- **Tags:** aerogel, science, flower, translucent, studio
- **Style / Reference:** Scientific Photography, Minimalist
- **Composition:** Centered, studio lighting
- **Color palette:** Pale ghostly blue, vibrant red, black background
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20261215_aerogel_flower.jpg`
- **License / Attribution:** CC0
- **Notes:** Aerogel has a very specific blue-haze look; avoid making it look like clear glass.

### Suggestion: Low Poly Winter Retreat
- **Date:** 2026-12-15
- **Prompt:** "A charming low poly 3D render of a winter mountain cabin at night. The scene is composed of sharp geometric triangles. Smoke puffs from the chimney are low-poly spheres. Snow-covered pine trees surround the cabin. The lighting is soft blue moonlight with warm yellow windows."
- **Negative prompt:** "high poly, smooth, realistic, detailed textures, noise"
- **Tags:** low poly, winter, 3D, geometric, cozy
- **Style / Reference:** Low Poly Art, 3D Render
- **Composition:** Isometric or high angle
- **Color palette:** Moonlight blue, snow white, warm yellow/orange
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261215_low_poly_winter.jpg`
- **License / Attribution:** CC0
- **Notes:** The geometry should be faceted and sharp.

### Suggestion: Vantablack Geometric Abstract
- **Date:** 2027-01-01
- **Prompt:** "A minimalist abstract composition featuring a perfect cube and sphere coated in Vantablack (absorbing 99.9% of light). They float in a blindingly white, featureless void. The objects appear as 2D flat black holes, void of any texture or reflection, creating a stark contrast."
- **Negative prompt:** "reflections, shadows on object, grey, texture, noise"
- **Tags:** vantablack, abstract, minimalist, surreal, contrast
- **Style / Reference:** Minimalist Photography, Surrealism
- **Composition:** Centered, floating
- **Color palette:** Pure Black, Pure White
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270101_vantablack.jpg`
- **License / Attribution:** CC0
- **Notes:** The key is the absolute lack of shading on the black objects.

### Suggestion: Liquid Satin Waves
- **Date:** 2027-01-01
- **Prompt:** "An abstract background texture of flowing, rippled silk satin fabric in a rich emerald green. The lighting is soft and luxurious, creating deep shadows in the folds and bright, glossy highlights on the peaks. The fabric looks like liquid metal."
- **Negative prompt:** "flat, cotton, rough, noisy, dull"
- **Tags:** satin, silk, fabric, abstract, texture
- **Style / Reference:** Product Photography, Cloth Simulation
- **Composition:** Full frame texture
- **Color palette:** Emerald Green, White highlights, Black shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270101_liquid_satin.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the sheen and the fluidity of the folds.

### Suggestion: Lantern Festival on the Lake
- **Date:** 2027-01-01
- **Prompt:** "A breathtaking wide shot of a traditional lantern festival at night. Thousands of glowing paper lanterns float on a calm, misty lake, reflecting in the water. In the background, silhouetted mountains rise against a starry sky. A small wooden boat drifts nearby."
- **Negative prompt:** "daylight, modern buildings, neon, electric lights, chaotic"
- **Tags:** festival, lanterns, lake, night, atmospheric
- **Style / Reference:** Travel Photography, Cinematic
- **Composition:** Wide landscape, low angle
- **Color palette:** Warm orange (lanterns), cool blue (night), black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270101_lantern_festival.jpg`
- **License / Attribution:** CC0
- **Notes:** The reflection in the water is as important as the sky.

### Suggestion: Exploded Mechanical Watch
- **Date:** 2027-01-01
- **Prompt:** "A highly detailed 3D technical illustration of a luxury mechanical watch in an 'exploded view'. Gears, springs, screws, and the watch face float in an expanded arrangement, showing how the parts fit together. Clean studio lighting highlights the brass and steel textures."
- **Negative prompt:** "flat, 2D, sketch, drawing, blurry"
- **Tags:** exploded view, watch, mechanical, technical, 3D
- **Style / Reference:** Technical Illustration, Product Render
- **Composition:** Centered, exploded diagram
- **Color palette:** Silver, gold, brass, white background
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270101_exploded_watch.jpg`
- **License / Attribution:** CC0
- **Notes:** Every tiny screw and gear should be sharp and metallic.

### Suggestion: Paper Quilling Peacock
- **Date:** 2027-01-01
- **Prompt:** "A vibrant artistic depiction of a peacock made entirely of intricate paper quilling (coiled strips of paper). The tail feathers are detailed swirls of blue, teal, and gold paper strips standing on edge. The background is a simple textured white cardstock."
- **Negative prompt:** "drawing, painting, real bird, feathers, flat"
- **Tags:** paper quilling, craft, peacock, art, colorful
- **Style / Reference:** Paper Quilling, Handicraft
- **Composition:** Centered subject
- **Color palette:** Royal blue, teal, gold, white
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270101_quilling_peacock.jpg`
- **License / Attribution:** CC0
- **Notes:** The depth and shadows of the paper coils are essential.

### Suggestion: Risograph Retro Kitchen
- **Date:** 2027-02-01
- **Prompt:** "A nostalgic 3-color Risograph print of a cluttered 1970s kitchen. The image features grainy texture, halftone patterns, and slight misregistration of layers. A vintage orange refrigerator and a patterned linoleum floor are visible. A black cat sits on a yellow chair. The ink colors are Fluorescent Orange, Teal, and Black."
- **Negative prompt:** "photorealistic, smooth, perfect alignment, digital painting, 3D"
- **Tags:** risograph, retro, kitchen, 70s, printmaking
- **Style / Reference:** Risograph, Vintage Print
- **Composition:** Interior room view
- **Color palette:** Fluorescent Orange, Teal, Black, White paper
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270201_risograph_kitchen.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the grain and the specific ink color limitations.

### Suggestion: Liminal Indoor Pool
- **Date:** 2027-02-01
- **Prompt:** "A hyper-realistic, unsettling photo of a 'Liminal Space': a vast, tiled indoor swimming pool complex with no windows. The architecture is nonsensical, with pillars rising from the water and doorways leading nowhere. The water is glassy and still. The lighting is an artificial, buzzing fluorescent white. No people are present."
- **Negative prompt:** "people, sunlight, outdoors, messy, dirt"
- **Tags:** liminal space, pool, eerie, architecture, dreamcore
- **Style / Reference:** Liminal Space Photography, Dreamcore
- **Composition:** Wide angle, symmetrical
- **Color palette:** Sterile White, Aqua Blue, Pale Tiles
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270201_liminal_pool.jpg`
- **License / Attribution:** CC0
- **Notes:** The feeling of emptiness and artificiality is key.

### Suggestion: Carbon Fiber Racer
- **Date:** 2027-02-01
- **Prompt:** "A cinematic, low-angle action shot of a futuristic Formula 1 race car speeding on a wet track at night. The car's body is unpainted, revealing the raw, woven texture of the Carbon Fiber material. Raindrops streak across the surface. Neon advertisements reflect on the wet asphalt and the glossy car body."
- **Negative prompt:** "painted car, plastic, daylight, dry, static"
- **Tags:** carbon fiber, f1, racing, automotive, night
- **Style / Reference:** Automotive Photography, Cinematic
- **Composition:** Low angle, panning shot (motion blur)
- **Color palette:** Black (carbon), Neon Red/Blue reflections, Wet Grey
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270201_carbon_racer.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the woven texture of the carbon fiber.

### Suggestion: Charcoal Thunderstorm
- **Date:** 2027-02-01
- **Prompt:** "A dramatic, expressive charcoal drawing of a violent thunderstorm rolling over a jagged coastline. Deep, smudged black charcoal creates heavy storm clouds. Eraser marks are used to create stark white lightning bolts tearing through the sky. The rough texture of the paper is visible."
- **Negative prompt:** "color, paint, smooth, digital, photo"
- **Tags:** charcoal, drawing, storm, landscape, moody
- **Style / Reference:** Charcoal Sketch, Fine Art
- **Composition:** Wide landscape
- **Color palette:** Black, Grey, White
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20270201_charcoal_storm.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the smudge texture and the contrast between black charcoal and white paper.

### Suggestion: Surreal Dada Collage
- **Date:** 2027-02-01
- **Prompt:** "A surreal analog collage in the style of Dadaism. Cut-out black-and-white vintage magazine photos are layered to create a bizarre scene. A giant human eye replaces the sun. A hand reaches out from a chimney holding a bouquet of colorful flowers (the only color element). Ripped paper edges and glue marks are visible."
- **Negative prompt:** "digital blending, smooth, photoshop, realistic, painting"
- **Tags:** collage, dada, surreal, vintage, mixed media
- **Style / Reference:** Dada, Analog Collage
- **Composition:** Centered composition
- **Color palette:** Black and White, Splash of vintage color
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270201_dada_collage.jpg`
- **License / Attribution:** CC0
- **Notes:** It should look like it was physically cut and pasted with scissors and glue.

### Suggestion: Risograph Retro Space Poster
- **Date:** 2027-02-15
- **Prompt:** "A retro-futuristic Risograph print of a 1950s style rocket ship launching into a starry void. Grainy texture, misaligned color layers, and a limited color palette of bright fluorescent pink, teal, and yellow on off-white paper."
- **Negative prompt:** "digital, smooth, 3d render, perfect registration, cgi"
- **Tags:** risograph, retro, sci-fi, print
- **Style / Reference:** Risograph, Vintage Print
- **Composition:** Minimalist, centered
- **Color palette:** Fluorescent Pink, Teal, Yellow, Off-white
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20270215_risograph_rocket.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the texture of the paper and the imperfections of the printing process (misaligned layers).

### Suggestion: F1 Race Car in Rain
- **Date:** 2027-02-15
- **Prompt:** "A high-octane photorealistic shot of a Formula 1 race car speeding down a wet track at night. The carbon fiber body reflects the stadium floodlights. Spray kicks up from the tires, blurring the background. Motion blur emphasizes speed."
- **Negative prompt:** "stationary, parked, sunny, cartoon, drawing"
- **Tags:** f1, racing, automotive, carbon fiber, photorealistic
- **Style / Reference:** Sports Photography, Photorealism
- **Composition:** Low angle, tracking shot, motion blur
- **Color palette:** Dark asphalt, bright neon highlights, silver reflections
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270215_f1_rain.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the texture of the carbon fiber and the interaction of light with the water spray.

### Suggestion: Holographic Cyberpunk Map
- **Date:** 2027-02-15
- **Prompt:** "A close-up of a 3D holographic city map projecting from a wrist-mounted device. The hologram is made of translucent blue and cyan light particles, showing wireframe buildings and data streams. Shallow depth of field focuses on the hologram, blurring the rainy street background."
- **Negative prompt:** "solid, opaque, plastic, daylight, low contrast"
- **Tags:** hologram, cyberpunk, sci-fi, technology
- **Style / Reference:** Cyberpunk, Macro Photography
- **Composition:** Close-up, shallow depth of field
- **Color palette:** Cyan, Blue, Black, Neon
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270215_hologram_map.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the hologram looks volumetric and light-emitting, not just a flat screen.

### Suggestion: Liminal Indoor Pool
- **Date:** 2027-02-15
- **Prompt:** "A surreal, unsettling photo of a vast, empty indoor tiled pool room. The water is still and turquoise. The walls are tiled in white and mint green. No windows, just artificial fluorescent lighting humming overhead. An endless series of archways leads into darkness."
- **Negative prompt:** "people, dirt, furniture, sunlight, outdoor"
- **Tags:** liminal space, poolrooms, surreal, unsettling
- **Style / Reference:** Liminal Space, Dreamcore
- **Composition:** Wide angle, symmetrical, vanishing point
- **Color palette:** White, Mint Green, Turquoise, Sterile
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270215_liminal_pool.jpg`
- **License / Attribution:** CC0
- **Notes:** The lighting should be flat and artificial. The atmosphere should feel eerily quiet.

### Suggestion: Charcoal Portrait of a Miner
- **Date:** 2027-02-15
- **Prompt:** "A rough, expressive charcoal drawing of an old miner's face. Heavy, dark strokes define the deep wrinkles and grit. Smudges and eraser marks add texture. High contrast between the dark coal dust on the face and the white of the eyes."
- **Negative prompt:** "color, digital painting, smooth, airbrushed, photo"
- **Tags:** charcoal, drawing, portrait, expressive, monochrome
- **Style / Reference:** Charcoal Drawing, Expressive Realism
- **Composition:** Extreme close-up, front facing
- **Color palette:** Black, White, Grey
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270215_charcoal_miner.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the materiality of the charcoal—dust, smudges, and the texture of the paper.

### Suggestion: Voxel Coral Reef
- **Date:** 2027-03-01
- **Prompt:** "A vibrant, isometric 3D voxel art scene of a teeming coral reef. Blocky clownfish swim among cube-shaped anemones and pixelated brain coral. Shafts of light penetrate the water, illuminating the geometric textures. The water is a gradient of voxel blues."
- **Negative prompt:** "smooth, curves, round, high poly, realistic"
- **Tags:** voxel, coral reef, underwater, 3D, isometric
- **Style / Reference:** Voxel Art, Minecraft-esque, 3D Render
- **Composition:** Isometric view
- **Color palette:** Bright Orange, Cyan, Pink, Deep Blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270301_voxel_reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the 'blocky' look is consistent.

### Suggestion: Stained Glass Space Station
- **Date:** 2027-03-01
- **Prompt:** "A majestic interior shot of a futuristic space station built in the style of a Gothic cathedral. Huge stained glass windows depict cosmic events (supernovas, nebulae) in vibrant colored glass. Sunlight from a nearby star streams through, casting multi-colored patterns on the high-tech metal floor."
- **Negative prompt:** "simple glass, clear windows, dark, gloomy, low detail"
- **Tags:** stained glass, sci-fi, space station, gothic, interior
- **Style / Reference:** Gothic Sci-Fi, Concept Art
- **Composition:** Wide angle, looking up at the windows
- **Color palette:** Jewel tones (Ruby, Sapphire, Emerald), Metallic Grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270301_stained_glass_station.jpg`
- **License / Attribution:** CC0
- **Notes:** The contrast between the ancient art form and futuristic setting is key.

### Suggestion: Liquid Metal Cybernetics
- **Date:** 2027-03-01
- **Prompt:** "A close-up portrait of a cyborg with liquid metal skin (like mercury or gallium) flowing over their face. The metal ripples and reflects the neon city lights around them. Where the metal pulls back, complex circuitry is visible underneath. The eyes are glowing red optical sensors."
- **Negative prompt:** "flesh, skin, matte, rust, static"
- **Tags:** liquid metal, cyborg, cyberpunk, portrait, reflective
- **Style / Reference:** Sci-Fi, 3D Render, Terminator 2 style
- **Composition:** Portrait, close-up
- **Color palette:** Chrome Silver, Neon Red, Night City Blue
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270301_liquid_metal.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the fluid simulation and reflections.

### Suggestion: Drone Swarm Blueprint
- **Date:** 2027-03-01
- **Prompt:** "A detailed technical blueprint (cyanotype) of a hive-mind drone swarm. White technical lines on a dark blue background show the schematic of individual drones and their formation patterns. Annotation text describes connection nodes and sensor arrays."
- **Negative prompt:** "photo, 3D, color, realistic, drawing"
- **Tags:** blueprint, schematic, drone, sci-fi, technical
- **Style / Reference:** Blueprint, Technical Drawing
- **Composition:** Flat lay, technical diagram
- **Color palette:** Blueprint Blue, White
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270301_drone_blueprint.jpg`
- **License / Attribution:** CC0
- **Notes:** Must look like a technical document.

### Suggestion: Frozen Desert Oasis
- **Date:** 2027-03-01
- **Prompt:** "A surreal landscape of a desert oasis that has been instantly flash-frozen. Palm trees are encased in clear ice, glistening in the harsh desert sun. The sand dunes are dusted with frost. The water hole is a solid mirror of ice. The sky is a piercing cloudless blue."
- **Negative prompt:** "green leaves, flowing water, heat haze, melting"
- **Tags:** surreal, ice, desert, frozen, landscape
- **Style / Reference:** Surrealism, National Geographic (if it were real)
- **Composition:** Wide landscape
- **Color palette:** Ice Blue, Sand Gold, Sky Blue, White
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270301_frozen_oasis.jpg`
- **License / Attribution:** CC0
- **Notes:** The juxtaposition of hot desert elements and ice is the main theme.

### Suggestion: ASCII Terminal Portrait
- **Date:** 2027-03-15
- **Prompt:** "A portrait of a cyberpunk hacker generated entirely from glowing green ASCII characters on an old curved CRT monitor. The characters (letters, numbers, symbols) vary in density to create shading and form the facial features. Scanlines and phosphor bloom are visible."
- **Negative prompt:** "drawing, photo, smooth, solid lines, vector"
- **Tags:** ascii art, typography, cyberpunk, retro, crt
- **Style / Reference:** ASCII Art, Retro Computing
- **Composition:** Close-up portrait
- **Color palette:** Phosphor Green, Black
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270315_ascii_portrait.jpg`
- **License / Attribution:** CC0
- **Notes:** The bloom effect is critical to make it look like a screen.

### Suggestion: Denim Patchwork Plains
- **Date:** 2027-03-15
- **Prompt:** "A creative landscape where rolling hills are made of layered blue denim fabric. The texture of the weave is visible. Rivers are silver zippers. Trees are made of frayed indigo cotton. The sky is a bleached acid-wash blue."
- **Negative prompt:** "realistic grass, water, dirt, smooth, painting"
- **Tags:** denim, fabric, landscape, surreal, texture
- **Style / Reference:** Textile Art, Surrealism
- **Composition:** Wide landscape
- **Color palette:** Indigo, Blue, Silver, White
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270315_denim_plains.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the different washes of denim creating depth.

### Suggestion: Latex Cyber-Assassin
- **Date:** 2027-03-15
- **Prompt:** "A cinematic shot of a futuristic assassin wearing a form-fitting, high-gloss black latex suit. The material stretches and reflects the neon city lights (pink and blue) surrounding them. They wear a sleek helmet. Rain beads on the hydrophobic surface."
- **Negative prompt:** "matte, cloth, cotton, dull, low resolution"
- **Tags:** latex, cyberpunk, sci-fi, character, glossy
- **Style / Reference:** Cyberpunk Concept Art, Fetish Fashion (aesthetic)
- **Composition:** Medium shot, dynamic
- **Color palette:** Glossy Black, Neon Pink, Cyan
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270315_latex_assassin.jpg`
- **License / Attribution:** CC0
- **Notes:** The reflections on the black latex define the form.

### Suggestion: Alebrijes Spirit Guide
- **Date:** 2027-03-15
- **Prompt:** "A vibrant, fantastical Alebrije spirit animal in a dreamscape. It is a hybrid of a jaguar, eagle, and lizard, carved from wood and painted with intricate, colorful Zapotec patterns (dots, lines, geometric shapes). The colors are neon bright against a dark jungle background."
- **Negative prompt:** "realistic animal, fur, plain, dull colors, plastic"
- **Tags:** alebrije, folk art, mexican, fantasy, colorful
- **Style / Reference:** Mexican Folk Art, Wood Carving
- **Composition:** Full body, centered
- **Color palette:** Neon Pink, Orange, Green, Purple, Black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270315_alebrije_spirit.jpg`
- **License / Attribution:** CC0
- **Notes:** The wood texture should be faintly visible under the paint.

### Suggestion: Cardboard Box Metropolis
- **Date:** 2027-03-15
- **Prompt:** "A sprawling city skyline constructed entirely from brown corrugated cardboard boxes and masking tape. Windows are drawn on with black marker. The lighting is warm and dramatic, making the cardboard look like grand architecture. Tearing and corrugation details are visible."
- **Negative prompt:** "realistic buildings, glass, concrete, metal, clean"
- **Tags:** cardboard, craft, miniature, city, texture
- **Style / Reference:** Miniature Art, Recycled Art
- **Composition:** High angle city view
- **Color palette:** Cardboard Brown, Black Marker, Warm Yellow Light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270315_cardboard_city.jpg`
- **License / Attribution:** CC0
- **Notes:** Lighting is key to transforming the trash into treasure.

### Suggestion: Scratchboard Lion
- **Date:** 2027-04-01
- **Prompt:** "A highly detailed scratchboard art illustration of a roaring lion. The image is created by scratching away black ink to reveal the white board underneath. Thousands of fine white lines define the texture of the lion's mane and fur. High contrast, dramatic lighting."
- **Negative prompt:** "color, grey, painting, smooth, graphite"
- **Tags:** scratchboard, illustration, lion, black and white, texture
- **Style / Reference:** Scratchboard, Engraving
- **Composition:** Close-up portrait
- **Color palette:** Black, White
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270401_scratchboard_lion.jpg`
- **License / Attribution:** CC0
- **Notes:** The texture is defined by the negative space (removing black).

### Suggestion: Storm in a Bottle
- **Date:** 2027-04-01
- **Prompt:** "A photorealistic close-up of an antique glass bottle sitting on a wooden desk. Inside the bottle, a raging storm is contained: dark thunderclouds, jagged lightning, and a tiny 18th-century galleon tossing on turbulent waves. The glass distorts the view slightly."
- **Negative prompt:** "calm water, toy boat, plastic, cartoon, blurry"
- **Tags:** ship in a bottle, storm, fantasy, surreal, still life
- **Style / Reference:** Photorealism, Surrealism
- **Composition:** Centered, shallow depth of field
- **Color palette:** Glass green, stormy grey, wood brown, electric blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270401_storm_bottle.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the refraction of the glass and the scale difference.

### Suggestion: Holographic Foil Fashion
- **Date:** 2027-04-01
- **Prompt:** "A futuristic fashion editorial shot. A model wears a structured jacket made entirely of crinkled silver holographic foil. The material reflects a spectrum of rainbow colors (cyan, magenta, yellow) as light hits the folds. The background is stark white."
- **Negative prompt:** "matte, cloth, cotton, dull, dark background"
- **Tags:** holographic, foil, fashion, iridescent, texture
- **Style / Reference:** Fashion Photography, Editorial
- **Composition:** Medium shot
- **Color palette:** Silver, Rainbow iridescence, White
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270401_holographic_foil.jpg`
- **License / Attribution:** CC0
- **Notes:** The rainbow reflections are the key visual element.

### Suggestion: Ant Colony Cross-Section
- **Date:** 2027-04-01
- **Prompt:** "A macro cross-section view of an underground ant colony. Tunnels and chambers are carved into the dark earth. Queen ants, workers, and larvae are visible in high detail. Roots from plants above dangle into the chambers. The soil texture is rich and granular."
- **Negative prompt:** "cartoon, drawing, surface view, messy, blurry"
- **Tags:** ant colony, macro, nature, underground, cross-section
- **Style / Reference:** Scientific Illustration, Macro Photography
- **Composition:** Cutaway view
- **Color palette:** Earth tones, dark brown, black, white (larvae)
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270401_ant_colony.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the intricate network of tunnels.

### Suggestion: Pixel Sorted Tokyo
- **Date:** 2027-04-01
- **Prompt:** "A glitch art cityscape of Tokyo at night. The bright neon lights of Shibuya Crossing are 'pixel sorted', dragging vertically in long streaks of color (pink, blue, green) that melt into the street. The buildings remain partially recognizable but heavily distorted by the digital effect."
- **Negative prompt:** "clean, sharp, normal photo, painting, blur"
- **Tags:** pixel sorting, glitch art, cyberpunk, tokyo, abstract
- **Style / Reference:** Glitch Art, Datamoshing
- **Composition:** Wide city shot
- **Color palette:** Neon Pink, Electric Blue, Acid Green, Black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270401_pixel_sort.jpg`
- **License / Attribution:** CC0
- **Notes:** The vertical streaking is the defining characteristic of pixel sorting.

### Suggestion: Op Art Portrait
- **Date:** 2027-04-15
- **Prompt:** "A striking black and white Op Art portrait. The subject's face is formed by undulating, warping checkerboard patterns that create a dizzying optical illusion of depth and movement. The background is a spiraling geometric vortex."
- **Negative prompt:** "color, grey, shading, realistic skin, messy lines"
- **Tags:** op art, optical illusion, black and white, abstract, portrait
- **Style / Reference:** Op Art, Bridget Riley, Victor Vasarely
- **Composition:** Centered portrait
- **Color palette:** Black, White
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20270415_op_art_portrait.jpg`
- **License / Attribution:** CC0
- **Notes:** The illusion of depth should come purely from the distortion of the pattern.

### Suggestion: Ancient Amber Fossil
- **Date:** 2027-04-15
- **Prompt:** "A backlit macro photography shot of a piece of polished, glowing orange amber. Inside, a prehistoric mosquito is perfectly preserved, its delicate wings and legs visible in high detail. Air bubbles are trapped around it."
- **Negative prompt:** "opaque, rock, blurry, modern insect, plastic"
- **Tags:** amber, fossil, macro, nature, prehistoric
- **Style / Reference:** Macro Photography, Scientific
- **Composition:** Extreme close-up, backlit
- **Color palette:** Golden Orange, Honey Yellow, Dark Brown
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270415_amber_fossil.jpg`
- **License / Attribution:** CC0
- **Notes:** Backlighting is crucial to make the amber glow.

### Suggestion: Lighthouse at Cape Wrath
- **Date:** 2027-04-15
- **Prompt:** "A dramatic, moody matte painting of a solitary lighthouse clinging to a jagged black cliff edge during a violent ocean storm. Massive waves crash against the rocks, sending spray high into the air. The lighthouse beam cuts through the dark rain."
- **Negative prompt:** "sunny, calm, blue sky, photo, low detail"
- **Tags:** lighthouse, storm, matte painting, seascape, dramatic
- **Style / Reference:** Matte Painting, Romanticism
- **Composition:** Wide shot, vertical emphasis
- **Color palette:** Stormy Grey, Deep Blue, White Foam, Yellow Light
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270415_lighthouse_storm.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the power of the ocean and the isolation of the lighthouse.

### Suggestion: Mughal Garden Pavilion
- **Date:** 2027-04-15
- **Prompt:** "A highly detailed traditional Mughal Miniature painting. A royal couple sits in an ornate marble pavilion in a lush Persian garden. The scene features flattened perspective, intricate floral borders, and gold leaf accents. Peacocks roam the garden."
- **Negative prompt:** "3D, realistic, perspective, shadows, western style"
- **Tags:** mughal, miniature, painting, india, traditional
- **Style / Reference:** Mughal Miniature, Indian Art
- **Composition:** Flat, decorative
- **Color palette:** Gold, Lapis Blue, Emerald Green, Vermilion
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270415_mughal_garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the intricate patterns and the specific flat style.

### Suggestion: Bubble Wrap Haute Couture
- **Date:** 2027-04-15
- **Prompt:** "A high-fashion editorial studio shot of a model wearing an avant-garde voluminous gown made entirely of clear plastic bubble wrap. Studio lighting creates sparkling highlights on the air bubbles. The model strikes a dramatic pose."
- **Negative prompt:** "fabric, cloth, blurry, casual, dark"
- **Tags:** fashion, bubble wrap, plastic, avant-garde, studio
- **Style / Reference:** High Fashion Photography, Conceptual
- **Composition:** Full body, studio backdrop
- **Color palette:** Clear/White (plastic), Skin tones, Grey background
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270415_bubble_wrap_fashion.jpg`
- **License / Attribution:** CC0
- **Notes:** The texture of the bubble wrap needs to be clearly defined by the lighting.
### Suggestion: Op Art Spiral
- **Date:** 2027-04-15
- **Prompt:** "A black and white Optical Art (Op Art) composition. Concentric circles of alternating black and white bands create a dizzying, vibrating illusion of depth, pulling the viewer into the center. The lines are sharp and vector-like."
- **Negative prompt:** "blur, color, grey, 3D render, noise"
- **Tags:** op art, abstract, illusion, black and white, geometric
- **Style / Reference:** Op Art, Bridget Riley
- **Composition:** Centered, geometric
- **Color palette:** Black, White
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270415_op_art.jpg`
- **License / Attribution:** CC0
- **Notes:** The contrast must be maximum (pure black and white).

### Suggestion: Impasto Sunflower Field
- **Date:** 2027-04-15
- **Prompt:** "A thick impasto oil painting of a vibrant sunflower field under a bright blue sky. The paint is applied in heavy, three-dimensional globs, creating a tactile texture. The yellow petals stand out in relief against the canvas."
- **Negative prompt:** "smooth, digital art, flat, watercolor, photo"
- **Tags:** impasto, painting, texture, sunflowers, art
- **Style / Reference:** Impasto, Van Gogh (style)
- **Composition:** Landscape view
- **Color palette:** Vibrant Yellow, Sky Blue, Green
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270415_impasto_sunflowers.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the height and shadow of the paint strokes.

### Suggestion: Lighthouse in a Gale
- **Date:** 2027-04-15
- **Prompt:** "A dramatic, moody photorealistic shot of an isolated lighthouse on a rocky cliff during a violent storm. Massive waves crash against the rocks, spraying white foam. The lighthouse beam cuts through the dark rain and fog."
- **Negative prompt:** "sunny, calm, blue sky, cartoon, painting"
- **Tags:** lighthouse, storm, ocean, moody, cinematic
- **Style / Reference:** Cinematic, Landscape Photography
- **Composition:** Wide shot, rule of thirds
- **Color palette:** Storm Grey, Dark Blue, White Foam, Yellow Beam
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270415_lighthouse_storm.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the power of the waves and the isolation.

### Suggestion: Fantasy Floating Castle
- **Date:** 2027-04-15
- **Prompt:** "A grand, cinematic digital matte painting of a fantasy castle floating on a rock in the sky. Waterfalls cascade from the rock edge into the clouds below. The lighting is ethereal and soft, blending 2D painting techniques with photorealistic textures."
- **Negative prompt:** "3D render, sharp edges, lowres, sketch"
- **Tags:** matte painting, fantasy, castle, landscape, cinematic
- **Style / Reference:** Matte Painting, Concept Art
- **Composition:** Wide angle, atmospheric perspective
- **Color palette:** Pastel Blue, White, Stone Grey, Soft Gold
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270415_matte_castle.jpg`
- **License / Attribution:** CC0
- **Notes:** Use atmospheric perspective to create scale.

### Suggestion: Bubble Wrap Fashion
- **Date:** 2027-04-15
- **Prompt:** "A high-fashion editorial portrait of a model wearing an avant-garde dress made entirely of clear bubble wrap. The plastic bubbles catch the studio light, creating interesting specular highlights and distortions. The background is a solid hot pink."
- **Negative prompt:** "fabric, cotton, silk, dull, dark"
- **Tags:** bubble wrap, fashion, plastic, texture, pop
- **Style / Reference:** Fashion Photography, Avant-Garde
- **Composition:** Medium shot, studio lighting
- **Color palette:** Clear plastic, Hot Pink background, Skin tones
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270415_bubble_wrap.jpg`
- **License / Attribution:** CC0
- **Notes:** The highlights on the plastic are essential.

### Suggestion: Cubist Jazz Quartet
- **Date:** 2027-05-01
- **Prompt:** "A Cubist painting of a jazz quartet performing in a smoky club. The musicians and instruments (saxophone, double bass, piano, drums) are fragmented into geometric planes and interlocking shapes. Perspectives are simultaneous, showing profiles and front views at once. The colors are muted browns, blues, and greys."
- **Negative prompt:** "realistic, photograph, smooth, 3D render, highly detailed"
- **Tags:** cubism, abstract, jazz, painting, music
- **Style / Reference:** Cubism, Picasso, Braque
- **Composition:** Fragmented, geometric
- **Color palette:** Earth tones, Slate Blue, Charcoal
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270501_cubist_jazz.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the geometric deconstruction of the forms.

### Suggestion: Tinfoil Astronaut
- **Date:** 2027-05-01
- **Prompt:** "A hyper-realistic studio photography shot of an astronaut suit made entirely of crinkled kitchen tinfoil. The foil reflects the studio lighting with sharp, metallic highlights. The astronaut stands on a surface covered in flour (simulating moon dust). The visor is a polished soup ladle."
- **Negative prompt:** "real spacesuit, cloth, fabric, drawing, painting"
- **Tags:** tinfoil, craft, astronaut, whimsical, hyper-realistic
- **Style / Reference:** Product Photography, DIY aesthetic
- **Composition:** Full body, low angle
- **Color palette:** Silver, White, Black background
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270501_tinfoil_astronaut.jpg`
- **License / Attribution:** CC0
- **Notes:** The texture of the wrinkled foil is the most important element.

### Suggestion: Ultimate Treehouse
- **Date:** 2027-05-01
- **Prompt:** "A magical, sprawling treehouse complex built into a massive ancient banyan tree. Wooden walkways connect different levels. Lanterns glow warm orange in the twilight. There are rope swings, a telescope platform, and a slide. The leaves are lush and vibrant green."
- **Negative prompt:** "modern house, concrete, scary, dark, winter"
- **Tags:** treehouse, fantasy, architecture, nature, cozy
- **Style / Reference:** Fantasy Concept Art, Adventure
- **Composition:** Wide shot, looking up
- **Color palette:** Forest Green, Wood Brown, Warm Orange, Twilight Blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270501_ultimate_treehouse.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the sense of childhood wonder and adventure.

### Suggestion: Solarized Surrealist Portrait
- **Date:** 2027-05-15
- **Prompt:** "A black and white surrealist portrait using the Solarisation effect (Sabattier effect). A woman's face is partially inverted in tone, creating glowing dark lines around the edges of her profile. She holds a glass sphere. The lighting is mysterious and dreamlike."
- **Negative prompt:** "color, normal photo, low contrast, digital filter"
- **Tags:** solarisation, surrealism, man ray, black and white, portrait
- **Style / Reference:** Man Ray, Surrealist Photography
- **Composition:** Close-up portrait
- **Color palette:** Black, White, Grey (Solarized)
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20270515_solarized_portrait.jpg`
- **License / Attribution:** CC0
- **Notes:** The tone inversion is specific to the solarisation process.

### Suggestion: Dyson Sphere Construction
- **Date:** 2027-05-15
- **Prompt:** "An epic sci-fi wide shot of a Dyson Sphere under construction around a blazing blue star. Hexagonal megastructures are being assembled by swarm drones, blocking out parts of the star's light. The scale is immense, with planets looking tiny in the foreground."
- **Negative prompt:** "small scale, atmospheric, ground view, blurry"
- **Tags:** dyson sphere, sci-fi, space, megastructure, epic
- **Style / Reference:** Sci-Fi Concept Art, Space Art
- **Composition:** Wide cosmic scale
- **Color palette:** Star Blue, Silhouette Black, Construction Yellow lights
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270515_dyson_sphere.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the sheer scale of the engineering project.

### Suggestion: Retro Anaglyph Dino
- **Date:** 2027-06-01
- **Prompt:** "A vintage-style stereoscopic 3D (anaglyph) image of a roaring T-Rex in a prehistoric jungle. The image is composed of offset red and cyan layers, creating a 3D effect when viewed with glasses. The aesthetic mimics a 1950s comic book or movie poster, with halftone dots and slightly misaligned colors."
- **Negative prompt:** "modern 3D render, clean, digital, perfect alignment"
- **Tags:** anaglyph, 3D, retro, dinosaur, vintage
- **Style / Reference:** Vintage Comic, Anaglyph
- **Composition:** Dynamic action shot
- **Color palette:** Red, Cyan, Black, White
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270601_anaglyph_dino.jpg`
- **License / Attribution:** CC0
- **Notes:** The red/cyan split is the defining feature.

### Suggestion: Sea Glass Mosaic
- **Date:** 2027-06-01
- **Prompt:** "A close-up macro shot of a beach mosaic made entirely of frosted sea glass. Pieces of tumbled glass in shades of bottle green, cobalt blue, and frosted white are arranged in sand. Sunlight shines through the glass, creating soft, caustic shadows on the sand."
- **Negative prompt:** "sharp glass, clear glass, plastic, artificial, broken bottle"
- **Tags:** sea glass, mosaic, beach, macro, texture
- **Style / Reference:** Macro Photography, Nature Art
- **Composition:** Top-down or close-up
- **Color palette:** Seafoam Green, Cobalt Blue, White, Sand Beige
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270601_sea_glass.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the frosted, tumbled texture of the glass.

### Suggestion: Mecha Graveyard
- **Date:** 2027-06-01
- **Prompt:** "A melancholic, atmospheric wide shot of a graveyard for giant battle mechs. Colossal, rusted robot limbs and heads jut out of a foggy swamp. Moss and vines cover the metal. A small human figure stands in the foreground for scale, looking up at a decaying mechanical eye."
- **Negative prompt:** "clean, new robots, action, battle, bright"
- **Tags:** sci-fi, ruins, mecha, atmospheric, dystopian
- **Style / Reference:** Concept Art, Simon Stålenhag
- **Composition:** Wide shot, low angle
- **Color palette:** Rust Orange, Swamp Green, Fog Grey, Muted Blue
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270601_mecha_graveyard.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the scale and the decay.

### Suggestion: Bestiary Dragon
- **Date:** 2027-06-15
- **Prompt:** "A highly detailed page from a medieval illuminated manuscript. A hand-painted illustration depicts a knight fighting a dragon. The borders are filled with intricate gold leaf filigree and latin text in gothic calligraphy. The parchment looks aged and textured."
- **Negative prompt:** "modern drawing, 3D, digital art, clean white paper"
- **Tags:** medieval, manuscript, illustration, dragon, gold leaf
- **Style / Reference:** Medieval Art, Illuminated Manuscript
- **Composition:** Flat page layout
- **Color palette:** Gold, Lapis Blue, Crimson, Parchment Beige
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20270615_illuminated_dragon.jpg`
- **License / Attribution:** CC0
- **Notes:** The gold leaf texture and parchment aging are key.

### Suggestion: Oil Slick Abstract
- **Date:** 2027-06-15
- **Prompt:** "An abstract macro photograph of oil spilled on wet asphalt. The thin film of oil creates swirling, psychedelic interference patterns in rainbow colors (purple, green, pink). The texture of the rough black asphalt is visible underneath the colorful sheen."
- **Negative prompt:** "clean water, solid color, painting, lowres"
- **Tags:** abstract, oil slick, texture, macro, rainbow
- **Style / Reference:** Abstract Photography, Urban Texture
- **Composition:** Top-down macro
- **Color palette:** Asphalt Black, Iridescent Rainbow
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270615_oil_slick.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the iridescence and the contrast with the dark road.

### Suggestion: Encaustic Wax Seascape
- **Date:** 2027-07-01
- **Prompt:** "A textured encaustic painting (hot wax) of a stormy ocean. Thick, translucent layers of beeswax mixed with pigments create a sense of depth and movement. The waves are deep teal and frothy white. The surface has a visible, heat-fused, bumpy texture."
- **Negative prompt:** "flat, oil painting, acrylic, digital, smooth"
- **Tags:** encaustic, wax, painting, ocean, texture
- **Style / Reference:** Encaustic Painting, Textured Art
- **Composition:** Landscape view
- **Color palette:** Deep Teal, White, Beeswax Yellow, Navy
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270701_encaustic_sea.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the translucency and thickness of the wax.

### Suggestion: Trompe-l'œil Archway
- **Date:** 2027-07-01
- **Prompt:** "A hyper-realistic Trompe-l'œil mural painted on a weathered brick wall. The painting depicts a crumbling stone archway that seemingly opens into a lush, sunlit Italian garden with a fountain. Shadows are painted to match the real-world light source, creating a perfect optical illusion of depth."
- **Negative prompt:** "real garden, 3D render, cartoon, flat graffiti, bad perspective"
- **Tags:** trompe-l'œil, mural, illusion, street art, realistic
- **Style / Reference:** Trompe-l'œil, Street Art
- **Composition:** Eye level, straight on
- **Color palette:** Brick Red (wall), Green, Stone Grey, Sky Blue
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270701_trompe_l_oeil.jpg`
- **License / Attribution:** CC0
- **Notes:** The illusion depends on the painted shadows and perspective.

### Suggestion: Cybernetic Vitruvian Study
- **Date:** 2027-07-15
- **Prompt:** "A Leonardo da Vinci style sepia ink sketch on aged parchment, depicting a 'Vitruvian Man' figure. However, the anatomy is half-human, half-machine. Detailed schematics of gears, pulleys, and hydraulic pistons replace muscles and bones on one side. Handwritten mirror-writing annotations surround the figure."
- **Negative prompt:** "photograph, color, modern, 3D render, clean paper"
- **Tags:** sketch, da vinci, steampunk, anatomy, cybernetic
- **Style / Reference:** Renaissance Sketch, Technical Drawing
- **Composition:** Centered, diagrammatic
- **Color palette:** Sepia, Parchment Beige, Black Ink
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270715_vitruvian_cyborg.jpg`
- **License / Attribution:** CC0
- **Notes:** Must look like an authentic 15th-century manuscript page.

### Suggestion: Hessian and Lace
- **Date:** 2027-07-15
- **Prompt:** "A rustic macro still life composition. A piece of rough, brown hessian (burlap) fabric serves as the background. Overlaying it is a delicate, handmade white lace doily. A single dried lavender sprig rests on top. The lighting highlights the contrast between the coarse jute fibers and the fine cotton thread."
- **Negative prompt:** "smooth, plastic, digital, bright colors, complex"
- **Tags:** texture, hessian, burlap, lace, rustic
- **Style / Reference:** Rustic Still Life, Macro Photography
- **Composition:** Flat lay, texture focus
- **Color palette:** Burlap Brown, White, Lavender Purple
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270715_hessian_lace.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the tactile difference between the materials.

### Suggestion: Veiled Marble Mystery
- **Date:** 2027-08-01
- **Prompt:** "A hyper-realistic close-up of a classical marble bust in the style of Giovanni Strazza (The Veiled Virgin). The white Carrara marble is carved to look like a transparent silk veil draped over a woman's face. The facial features are softly visible through the 'stone fabric'. Soft, directional museum lighting."
- **Negative prompt:** "real fabric, skin, painting, low detail, grain"
- **Tags:** sculpture, marble, veil, art, realistic
- **Style / Reference:** Classical Sculpture, Hyper-realism
- **Composition:** Close-up portrait
- **Color palette:** Marble White, Grey Shadows
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20270801_veiled_marble.jpg`
- **License / Attribution:** CC0
- **Notes:** The challenge is to make hard stone look like soft, transparent cloth.
### Agent Suggestion: Volumetric God Rays — @Jules — 2027-10-25
- **Prompt:** "A dense forest canopy with sunlight streaming through the leaves, creating intense volumetric god rays that follow the mouse."

### Agent Suggestion: Origami Fold — @Jules — 2027-10-25
- **Prompt:** "A vintage map of the world being folded like origami, with creases and shadows appearing where the paper bends."
### Agent Suggestion: Steampunk Alchemist's Lab — @jules — 2027-07-01
- **Prompt:** "A cluttered, dimly lit steampunk laboratory filled with bubbling glass retorts, brass pressure gauges, and Tesla coils. Steam fills the air. A mechanical owl sits on a pile of leather-bound books. Warm amber light glows from vacuum tubes."
- **Negative prompt:** "modern, clean, digital, plastic, bright"
- **Tags:** steampunk, interior, laboratory, detailed, brass
- **Ref image:** `public/images/suggestions/20270701_steampunk_lab.jpg`
- **Notes / agent context:** Subject from wishlist.
- **Status:** proposed

### Agent Suggestion: Cold War Bunker — @jules — 2027-07-02
- **Prompt:** "A wide cinematic shot of an abandoned Cold War era nuclear bunker. Rows of dusty metal bunks line the curved concrete walls. Green flickering fluorescent lights illuminate the peeling paint and rusted control panels. The atmosphere is claustrophobic and silent."
- **Negative prompt:** "sunlight, exterior, modern, cozy, warm"
- **Tags:** bunker, post-apocalyptic, interior, cold war, atmospheric
- **Ref image:** `public/images/suggestions/20270702_bunker.jpg`
- **Notes / agent context:** Subject from wishlist.
- **Status:** proposed

### Agent Suggestion: Encaustic Abstract Seascape — @jules — 2027-07-03
- **Prompt:** "A textured encaustic painting (hot wax) of a stormy seascape. Thick, translucent layers of beeswax mixed with pigments create a sense of depth and motion in the waves. The surface is uneven, with visible scraped textures and embedded colored resin."
- **Negative prompt:** "flat, digital, smooth, glossy, photo"
- **Tags:** encaustic, painting, abstract, wax, seascape
- **Ref image:** `public/images/suggestions/20270703_encaustic_sea.jpg`
- **Notes / agent context:** Style from wishlist.
- **Status:** proposed

### Agent Suggestion: Circuit Board Metropolis — @jules — 2027-07-04
- **Prompt:** "A macro photography shot of a computer motherboard, reimagined as a futuristic sprawling city at night. The capacitors are skyscrapers, the copper traces are glowing highways, and the CPU is the central citadel. Depth of field focuses on the 'downtown' area."
- **Negative prompt:** "illustration, cartoon, blurry, messy"
- **Tags:** macro, sci-fi, cyberpunk, tech, miniature
- **Ref image:** `public/images/suggestions/20270704_circuit_city.jpg`
- **Notes / agent context:** Subject from wishlist.
- **Status:** proposed

### Agent Suggestion: Clockwork Macro — @jules — 2027-07-05
- **Prompt:** "Extreme macro photography inside an antique mechanical watch movement. Golden gears, ruby bearings, and hairsprings are visible in exquisite detail. The lighting highlights the microscopic scratches on the brass and the oil on the pivots."
- **Negative prompt:** "digital watch, blurry, lowres, simple"
- **Tags:** macro, mechanical, watch, steampunk, detail
- **Ref image:** `public/images/suggestions/20270705_clockwork.jpg`
- **Notes / agent context:** Subject 'Inside a Watch' from wishlist.
- **Status:** proposed

### Suggestion: Lichtenberg Figures (Wood Burning)
- **Date:** 2027-07-15
- **Prompt:** "A macro photography shot of Lichtenberg figures being burned into a piece of dark cherry wood. High voltage electricity branches out in fractal patterns, glowing with intense orange heat and leaving charred black trails. Smoke rises from the contact points."
- **Negative prompt:** "drawing, painting, low resolution, blurry, digital art"
- **Tags:** lichtenberg, wood, fractal, macro, texture
- **Style / Reference:** Scientific Photography, Macro
- **Composition:** Close-up, top-down
- **Color palette:** Dark Wood Brown, Glowing Orange, Charred Black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270715_lichtenberg.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the contrast between the glowing ember and the dark wood.

### Suggestion: Biomorphic Architecture
- **Date:** 2027-07-15
- **Prompt:** "A futuristic biomorphic skyscraper rising from a green city park. The building is white and organic, shaped like a twisting sea shell or bone structure, with smooth curves and no sharp angles (Zaha Hadid style). It reflects the bright blue sky."
- **Negative prompt:** "brutalist, square, brick, grey, standard building"
- **Tags:** architecture, biomorphic, futuristic, sci-fi, organic
- **Style / Reference:** Zaha Hadid, Biomimicry
- **Composition:** Low angle, looking up
- **Color palette:** White, Sky Blue, lush Green
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270715_biomorphic.jpg`
- **License / Attribution:** CC0
- **Notes:** The building should look grown rather than built.

### Suggestion: Hessian & Gold Embroidery
- **Date:** 2027-07-15
- **Prompt:** "A detailed close-up texture shot of rough, brown hessian (burlap) fabric. Intricate floral patterns are embroidered onto it using metallic gold thread. The contrast between the coarse, frayed fabric and the smooth, shiny gold wire is emphasized."
- **Negative prompt:** "smooth fabric, silk, low detail, blurry"
- **Tags:** texture, fabric, embroidery, gold, craft
- **Style / Reference:** Textile Art, Macro Photography
- **Composition:** Flat lay texture
- **Color palette:** Burlap Brown, Metallic Gold
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270715_hessian_gold.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the tactile difference between the materials.

### Suggestion: Hyperdrive Cockpit
- **Date:** 2027-07-15
- **Prompt:** "A first-person view from the pilot's seat of a sci-fi spaceship cockpit engaging hyperdrive. The stars outside streak into long lines of blue and white light. The dashboard is filled with glowing holographic displays and complex physical switches."
- **Negative prompt:** "third person, exterior view, simple, cartoon"
- **Tags:** sci-fi, cockpit, space, hyperdrive, cinematic
- **Style / Reference:** Sci-Fi Movie, Concept Art
- **Composition:** First-person POV
- **Color palette:** Star White, Deep Space Blue, HUD Cyan/Orange
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270715_hyperdrive.jpg`
- **License / Attribution:** CC0
- **Notes:** The motion blur of the stars should create a sense of speed.

### Suggestion: Neon Forest Light Painting
- **Date:** 2027-07-15
- **Prompt:** "A long-exposure photograph taken in a dark, misty forest at night. Ribbons of glowing neon blue and pink light weave through the trees, creating a magical, floating path. The trees are silhouetted against the light. The ground is covered in ferns."
- **Negative prompt:** "daylight, sun, flash photography, static light"
- **Tags:** light painting, forest, long exposure, neon, abstract
- **Style / Reference:** Long Exposure Photography, Light Art
- **Composition:** Eye level, winding path
- **Color palette:** Black, Neon Blue, Neon Pink, Forest Green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270715_light_painting.jpg`
- **License / Attribution:** CC0
- **Notes:** The light trails must be smooth and continuous.

### Suggestion: Trompe-l'œil Portal
- **Date:** 2026-01-13
- **Prompt:** "A hyper-realistic trompe-l'œil street art mural painted on a crumbling brick wall. The painting depicts a convincing hole in the wall revealing a lush, secret garden bathed in golden sunlight. Vines and ivy from the painting appear to spill out onto the real pavement, blurring the line between art and reality."
- **Negative prompt:** "cartoon, sketch, flat, unrealistic, watermark"
- **Tags:** street art, trompe-l'œil, mural, realistic, optical illusion
- **Style / Reference:** Photorealistic street art, 3D chalk art
- **Composition:** Straight-on view of the wall, centered on the 'hole'
- **Color palette:** Brick red, grey concrete vs. vibrant green and gold
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260113_trompe-l-oeil.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing depth perception and texture blending shaders.

### Suggestion: Bismuth Geometric Sanctum
- **Date:** 2026-01-13
- **Prompt:** "A surreal, alien sanctum constructed entirely from iridescent bismuth crystals. The geometric, stair-step hopper crystals gleam with metallic rainbows of pink, blue, and gold. Soft, ethereal light reflects off the sharp, angular surfaces, creating complex caustics on the floor."
- **Negative prompt:** "organic, round, soft, blurry, dirt"
- **Tags:** abstract, geometric, crystal, iridescent, bismuth
- **Style / Reference:** Macro photography, 3D abstract render
- **Composition:** Low angle, looking up at crystal formations
- **Color palette:** Metallic iridescent (rainbow), silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260113_bismuth.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing iridescence, reflection, and geometric shaders.

### Suggestion: Solar Punk Vertical Garden
- **Date:** 2026-01-13
- **Prompt:** "A vibrant Solar Punk cityscape at noon, where sleek, white futuristic towers are covered in cascading vertical gardens and solar glass. Flying wind turbines drift silently above. The streets are bustling with people and nature living in harmony, bathed in bright, optimistic sunlight."
- **Negative prompt:** "smog, dark, dystopian, cyberpunk, dirt"
- **Tags:** solarpunk, futuristic, city, nature, bright
- **Style / Reference:** Architectural concept art, utopian
- **Composition:** Wide shot, looking down a green canyon of buildings
- **Color palette:** White, lush green, sky blue, golden sunlight
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260113_solarpunk.jpg`
- **License / Attribution:** CC0
- **Notes:** Use to test vegetation shaders and bright, high-key lighting.

### Suggestion: Infrared Dreamscape
- **Date:** 2026-01-13
- **Prompt:** "A surreal infrared landscape photograph of a dense forest. The foliage is a striking, snowy white and vibrant pink, contrasting deeply with a pitch-black sky and dark, mirrored water of a calm lake. The atmosphere is dreamlike, quiet, and otherworldly."
- **Negative prompt:** "green leaves, blue sky, realistic colors, noise"
- **Tags:** infrared, landscape, surreal, dreamlike, nature
- **Style / Reference:** Aerochrome photography, false color
- **Composition:** Landscape orientation, reflection in water
- **Color palette:** Pink, white, black, deep blue
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20260113_infrared.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing color grading and false-color shaders.

### Suggestion: Abstract Fluid Dynamics
- **Date:** 2026-01-13
- **Prompt:** "A macro close-up of a generative fluid simulation. Swirling vortices of metallic gold, deep indigo, and pearlescent white ink mix in a suspension of clear oil. Intricate, fractal-like patterns and bubbles form at the boundaries of the mixing fluids, illuminated by soft studio lighting."
- **Negative prompt:** "blurry, lowres, text, solid colors"
- **Tags:** abstract, fluid, macro, simulation, colorful
- **Style / Reference:** Macro photography, fluid art, 3D simulation
- **Composition:** Macro texture, edge-to-edge detail
- **Color palette:** Gold, indigo, white, transparent
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260113_fluid.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing fluid simulation shaders and sub-surface scattering.
### Suggestion: Scanography Flora
- **Date:** 2027-08-01
- **Prompt:** "A high-resolution scanography art piece of crushed tropical flowers and ferns pressed against a glass scanner bed. The depth of field is extremely shallow, with parts of the petals sharply in focus and others fading into a pitch-black background. Glitch artifacts from the scanner light create a surreal distortion."
- **Negative prompt:** "standard photo, deep depth of field, bright background, perfect flowers"
- **Tags:** scanography, floral, abstract, glitch, texture
- **Style / Reference:** Scanography, Glitch Art
- **Composition:** Flat lay, pressed against glass
- **Color palette:** Vibrant Pink, Green, Pitch Black background
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270801_scanography.jpg`
- **License / Attribution:** CC0
- **Notes:** The 'pressed against glass' look is essential.

### Suggestion: Rusted Chainmail Macro
- **Date:** 2027-08-01
- **Prompt:** "A macro photography shot of antique, rusted iron chainmail armor. Each ring is textured with flaky orange corrosion and battle damage. A single ring is polished silver, standing out against the decay. The lighting emphasizes the rough metal texture."
- **Negative prompt:** "shiny, new, clean, low resolution, blurry, plastic"
- **Tags:** chainmail, texture, macro, rust, medieval
- **Style / Reference:** Macro Photography, Texture Study
- **Composition:** Extreme close-up
- **Color palette:** Rust Orange, Iron Grey, Silver
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270801_chainmail.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the flaking texture of the rust.

### Suggestion: DNA Helix Visualization
- **Date:** 2027-08-15
- **Prompt:** "A cinematic scientific visualization of a double helix DNA strand floating in a deep blue liquid medium. The base pairs are glowing neon blue and magenta. The strand is surrounded by floating proteins and enzymes. The scene has a soft, underwater atmospheric depth."
- **Negative prompt:** "drawing, cartoon, flat, white background, simple model"
- **Tags:** science, dna, biology, 3d, abstract
- **Style / Reference:** Scientific Visualization, 3D Render
- **Composition:** Diagonal composition, shallow depth of field
- **Color palette:** Deep Blue, Neon Blue, Magenta
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270815_dna_helix.jpg`
- **License / Attribution:** CC0
- **Notes:** Use subsurface scattering to make the strand look organic.

### Suggestion: Space Elevator Base
- **Date:** 2027-08-15
- **Prompt:** "A cinematic upward shot from the ocean base of a massive space elevator tether. The thick carbon nanotube cable stretches endlessly up into the clouds and beyond. Futuristic ships and drones dock at the floating platform station. The scale is overwhelming."
- **Negative prompt:** "small scale, messy, lowres, land, mountains"
- **Tags:** sci-fi, space elevator, megastructure, ocean, cinematic
- **Style / Reference:** Sci-Fi Concept Art, Matte Painting
- **Composition:** Low angle, looking straight up (1-point perspective)
- **Color palette:** Ocean Blue, White Clouds, Carbon Grey, Metallic lights
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270815_space_elevator.jpg`
- **License / Attribution:** CC0
- **Notes:** Atmospheric perspective is key to showing the height.

### Suggestion: Suminagashi Paper Marbling
- **Date:** 2027-09-01
- **Prompt:** "A close-up of Suminagashi (Japanese paper marbling) in progress. Concentric rings of black Sumi ink float on the surface of water, distorted by a gentle breeze into organic topographical map shapes. A single drop of red ink creates a focal point. The water surface reflects soft light."
- **Negative prompt:** "dry paper, digital noise, chaotic, muddy colors"
- **Tags:** suminagashi, marbling, ink, water, abstract
- **Style / Reference:** Suminagashi, Abstract Photography
- **Composition:** Top-down, macro
- **Color palette:** Sumi Black, White (water reflection), Red accent
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20270901_suminagashi.jpg`
- **License / Attribution:** CC0
- **Notes:** The fluid nature of the ink on water is distinct from print.
### Suggestion: Trompe-l'œil Facade
- **Date:** 2027-08-01
- **Prompt:** "A photorealistic street photography shot of a brick building with a massive Trompe-l'œil mural. The mural paints a fake tear in the wall revealing a lush, alien jungle inside. Passersby seem to ignore the impossible depth. The lighting matches the real street."
- **Negative prompt:** "bad art, flat, obvious painting, blurry, cartoon"
- **Tags:** trompe-l'œil, mural, street art, illusion, jungle
- **Style / Reference:** Trompe-l'œil, Street Photography
- **Composition:** Street view, wide angle
- **Color palette:** Brick Red, Jungle Green, Concrete Grey
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270801_trompe_l_oeil.jpg`
- **License / Attribution:** CC0
- **Notes:** The key is the seamless blend between the real wall and the painted illusion.

### Suggestion: Cork Miniature World
- **Date:** 2027-08-01
- **Prompt:** "A macro studio shot of a landscape entirely carved from wine corks. Mountains are stacked corks, trees are shaved cork bits. The texture of the cork is porous and detailed. Warm studio lighting creates soft shadows."
- **Negative prompt:** "wood, plastic, realistic mountains, smooth, blurry"
- **Tags:** cork, miniature, craft, carving, macro
- **Style / Reference:** Miniature Art, Macro Photography
- **Composition:** Tilt-shift, high angle
- **Color palette:** Cork Tan, Brown, Warm White
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270801_cork_world.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the porous texture of the cork material.

### Suggestion: Glitched Scanography Portrait
- **Date:** 2027-08-01
- **Prompt:** "A surreal scanography (scanner photography) portrait. A face is pressed against the glass, distorted and smeared by the movement of the scanner bar. The depth of field is non-existent (everything touching the glass is sharp, background is black). High contrast and gritty texture."
- **Negative prompt:** "normal photo, blurry, distance, 3D render, smooth"
- **Tags:** scanography, portrait, surreal, distortion, glitch
- **Style / Reference:** Scanography, Glitch Art
- **Composition:** Close-up face
- **Color palette:** Skin tones, Black background, High Contrast
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20270801_scanography.jpg`
- **License / Attribution:** CC0
- **Notes:** Replicate the specific look of a flatbed scanner light.

### Suggestion: Medical Hologram DNA
- **Date:** 2027-08-01
- **Prompt:** "A clean, high-tech medical visualization of a double helix DNA strand. The DNA is made of floating, glowing blue interface particles. It rotates above a sleek black table in a laboratory. Shallow depth of field focuses on a specific gene segment highlighted in red."
- **Negative prompt:** "cartoon, drawing, messy, organic, biological tissue"
- **Tags:** dna, medical, sci-fi, hologram, interface
- **Style / Reference:** Medical Visualization, Sci-Fi UI
- **Composition:** Centered object, macro
- **Color palette:** Electric Blue, Red highlight, Black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270801_dna_hologram.jpg`
- **License / Attribution:** CC0
- **Notes:** The hologram should look volumetric and light-emitting.

### Suggestion: Suminagashi Ink Swirls
- **Date:** 2027-08-01
- **Prompt:** "A top-down close-up of Suminagashi (Japanese paper marbling) in progress. Black and indigo ink rings float on water, distorted by a single drop of surfactant creating a complex fractal pattern. The texture of the water surface and the ink tension is visible."
- **Negative prompt:** "painting, dry paper, digital art, vector, messy"
- **Tags:** suminagashi, marbling, ink, abstract, water
- **Style / Reference:** Suminagashi, Abstract Photography
- **Composition:** Top-down flat lay
- **Color palette:** Indigo, Black, Water White/Grey
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270801_suminagashi.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the fluid dynamics and the tension on the water surface.
### Suggestion: Floral Scanography
- **Date:** 2027-08-01
- **Prompt:** "A hyper-realistic scanography art piece of crushed vibrant wildflowers (poppies, cornflowers) pressed against a flat scanner glass. The background is pitch black. The lighting is flat and high-contrast, revealing microscopic details of the pollen and petals. Shallow depth of field is non-existent; everything is sharp."
- **Negative prompt:** "blur, depth of field, 3D render, drawing, illustration"
- **Tags:** scanography, floral, macro, abstract, botanical
- **Style / Reference:** Scanography, Botanical Art
- **Composition:** Flat lay, pressed against glass
- **Color palette:** Pitch Black, Vibrant Red, Blue, Green
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270801_scanography.jpg`
- **License / Attribution:** CC0
- **Notes:** The 'pressed against glass' look is the defining feature.

### Suggestion: Gold & Black Fluid Sim
- **Date:** 2027-08-01
- **Prompt:** "A mesmerizing still frame of a 3D generative fluid simulation. Swirling vortices of mixing metallic gold and matte black liquid paints. The fluids look viscous and heavy. Studio lighting creates specular highlights on the gold portions. The composition is abstract and dynamic."
- **Negative prompt:** "water, thin liquid, messy, low resolution, noise"
- **Tags:** abstract, fluid, 3D, gold, liquid
- **Style / Reference:** 3D Simulation, Abstract Art
- **Composition:** Macro, swirling pattern
- **Color palette:** Gold, Matte Black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270801_fluid_sim.jpg`
- **License / Attribution:** CC0
- **Notes:** Contrast between the matte black and shiny gold is key.

### Suggestion: Space Elevator Tether
- **Date:** 2027-08-01
- **Prompt:** "A breathtaking upward-looking wide shot from the base of a futuristic space elevator anchored in the ocean. The carbon-nanotube tether stretches infinitely upwards into the blue sky, piercing the clouds. Climber cars ascend the cable. The ocean is calm with a few maintenance ships."
- **Negative prompt:** "cartoon, drawing, messy, low detail, clouds blocking view"
- **Tags:** sci-fi, space elevator, mega-structure, ocean, futuristic
- **Style / Reference:** Sci-Fi Concept Art, Photorealistic
- **Composition:** Extreme low angle, vanishing point in sky
- **Color palette:** Ocean Blue, Sky Blue, White, Carbon Black
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20270801_space_elevator.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the infinite scale of the tether.

### Suggestion: Suminagashi Paper Marbling
- **Date:** 2027-08-01
- **Prompt:** "A high-resolution texture shot of traditional Japanese Suminagashi (paper marbling). Concentric rings of black ink float on water, distorted by a gentle breeze into organic, topographic map-like patterns. The background is the white of the paper/water."
- **Negative prompt:** "digital noise, 3D, color, messy, blur"
- **Tags:** suminagashi, marbling, abstract, texture, ink
- **Style / Reference:** Suminagashi, Abstract Expressionism
- **Composition:** Top-down texture
- **Color palette:** Black Ink, White Paper
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270801_suminagashi.jpg`
- **License / Attribution:** CC0
- **Notes:** The lines should be organic and fluid, like topography.

### Suggestion: Chainmail Weave Macro
- **Date:** 2027-08-01
- **Prompt:** "A macro photography shot of hand-forged riveting chainmail armor. The interlocking iron rings show signs of wear, rust, and oil. The texture is gritty and metallic. Cold blue cinematic lighting glints off the metal rings. The background is blurred dark leather."
- **Negative prompt:** "perfect rings, machine made, plastic, silver, clean"
- **Tags:** chainmail, armor, macro, texture, medieval
- **Style / Reference:** Macro Photography, Historical
- **Composition:** Extreme close-up
- **Color palette:** Iron Grey, Rust Orange, Cold Blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270801_chainmail.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the imperfections and rust on the rings.

### Suggestion: De Stijl Architecture
- **Date:** 2027-09-15
- **Prompt:** "A minimalist architectural composition inspired by the De Stijl movement. The building facade is composed of precise rectangular planes in primary colors (Red, Blue, Yellow) separated by thick black lines and white stucco. The lighting is flat and graphic, emphasizing the strict geometry."
- **Negative prompt:** "curves, organic shapes, decoration, gradients, messy"
- **Tags:** de stijl, architecture, abstract, geometric, minimalist
- **Style / Reference:** De Stijl, Mondrian, Rietveld
- **Composition:** Flat, graphic, orthogonal
- **Color palette:** Primary Red, Blue, Yellow, Black, White
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270915_destijl.jpg`
- **License / Attribution:** CC0
- **Notes:** Ensure the lines are perfectly straight and colors are flat.

### Suggestion: Iridescent Feathers Macro
- **Date:** 2027-09-15
- **Prompt:** "An extreme macro photography shot of a peacock feather. The barbs are in sharp focus, revealing the microscopic lattice structure that creates the iridescence. Colors shift from emerald green to deep metallic blue and bronze. The background is a soft, dark blur."
- **Negative prompt:** "blurry, whole feather, distant, dull colors"
- **Tags:** macro, feathers, iridescent, texture, nature
- **Style / Reference:** Macro Photography, Nature
- **Composition:** Extreme close-up
- **Color palette:** Emerald Green, Royal Blue, Bronze, Black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270915_feathers.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the metallic sheen and fine detail.

### Suggestion: Wet Plate Portrait
- **Date:** 2027-09-15
- **Prompt:** "A hauntingly beautiful portrait taken using the 19th-century Collodion wet plate process. The subject is a woman in Victorian dress. The image features characteristic chemical swirls, uneven edges, and high contrast. The eyes are piercingly sharp against the slightly blurred periphery."
- **Negative prompt:** "modern photo, color, digital, perfect skin, smooth"
- **Tags:** wet plate, collodion, vintage, portrait, texture
- **Style / Reference:** Wet Plate Photography, Julia Margaret Cameron
- **Composition:** Portrait, shallow depth of field (Petzval lens effect)
- **Color palette:** Sepia, Black, Cream
- **Aspect ratio:** 3:4
- **Reference images:** `public/images/suggestions/20270915_wetplate.jpg`
- **License / Attribution:** CC0
- **Notes:** The chemical imperfections are key to the aesthetic.

### Suggestion: O'Neill Cylinder Interior
- **Date:** 2027-09-15
- **Prompt:** "A breathtaking wide shot inside a massive O'Neill Cylinder space colony. Looking up, the landscape curves upwards until it forms a ceiling of land and rivers overhead. Clouds float in the zero-gravity center. The terrain is a mix of futuristic cities and lush parklands."
- **Negative prompt:** "flat horizon, planet surface, dark, dystopian"
- **Tags:** sci-fi, space colony, o'neill cylinder, landscape, futuristic
- **Style / Reference:** Sci-Fi Concept Art, Syd Mead
- **Composition:** Wide angle, cylindrical perspective
- **Color palette:** Sky Blue, Grass Green, White Clouds, City Lights
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270915_oneill_cylinder.jpg`
- **License / Attribution:** CC0
- **Notes:** Use the curved horizon to sell the scale of the structure.

### Suggestion: Zen Garden Morning
- **Date:** 2027-09-15
- **Prompt:** "A peaceful, photorealistic top-down shot of a Japanese Zen garden at sunrise. Raked white gravel forms perfect concentric ripples around moss-covered rocks. A single red maple leaf rests on the stones. The lighting is soft, raking low across the texture of the sand."
- **Negative prompt:** "people, messy, dirt, chaotic, bright noon"
- **Tags:** zen garden, japan, nature, texture, peaceful
- **Style / Reference:** Landscape Photography, Minimalist
- **Composition:** Top-down (flat lay)
- **Color palette:** White/Grey Gravel, Moss Green, Maple Red
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270915_zen_garden.jpg`
- **License / Attribution:** CC0
- **Notes:** The shadows in the raked gravel grooves are essential for depth.

### Suggestion: Cybernetic Renaissance Noble
- **Date:** 2027-10-26
- **Prompt:** "A portrait of a nobleman in the style of the High Renaissance (like Titian or Raphael), but his skin is partially transparent, revealing complex clockwork and gold circuitry underneath. He holds a cybernetic skull. Warm, soft lighting, oil painting texture, cracked varnish details."
- **Negative prompt:** "photograph, modern clothes, flat, vector, 3d render"
- **Tags:** cybernetic, renaissance, portrait, clockwork, oil painting
- **Style / Reference:** Cybernetic Renaissance, High Renaissance
- **Composition:** Half-body portrait, three-quarter view
- **Color palette:** Deep Red, Gold, Vandyke Brown, Skin tones
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20271026_cybernetic_renaissance.jpg`
- **License / Attribution:** CC0
- **Notes:** Combines classical art techniques with sci-fi elements.

### Suggestion: Ferrofluid Event Horizon
- **Date:** 2027-10-26
- **Prompt:** "A macro studio shot of a dynamic ferrofluid sculpture shaped like a black hole's accretion disk. Spiked, glossy black liquid is suspended in a magnetic field, spiraling around a central void. Stark white background to emphasize the fluid's silhouette and specular highlights."
- **Negative prompt:** "color, blurry, messy, low contrast"
- **Tags:** ferrofluid, black hole, physics, macro, abstract
- **Style / Reference:** Scientific Photography, Abstract Sculpture
- **Composition:** Centered, Macro
- **Color palette:** Glossy Black, White, Grey
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20271026_ferrofluid_blackhole.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on surface tension and magnetic spike details.

### Suggestion: Chiaroscuro Spiral Descent
- **Date:** 2027-10-26
- **Prompt:** "A high-angle view looking down a weathered stone spiral staircase into deep darkness. A single lantern halfway down casts dramatic, harsh shadows (chiaroscuro) against the curved walls. Dust motes dance in the beam of light. The texture of the rough stone is palpable."
- **Negative prompt:** "flat lighting, bright, cheerful, modern, metal"
- **Tags:** chiaroscuro, spiral staircase, atmospheric, mystery, architecture
- **Style / Reference:** Baroque, Noir, Tenebrism
- **Composition:** High-angle, Golden Spiral
- **Color palette:** Shadow Black, Warm Lantern Orange, Stone Grey
- **Aspect ratio:** 9:16
- **Reference images:** `public/images/suggestions/20271026_chiaroscuro_staircase.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing dynamic range and contrast.

### Suggestion: Aerogel Lab Sample
- **Date:** 2027-10-26
- **Prompt:** "A translucent, ghostly blue block of aerogel held by precision robotic grippers in a sterile, white laboratory. A red laser beam passes through the material, refracting slightly and scattering light. The aerogel looks like frozen smoke."
- **Negative prompt:** "opaque, heavy, rock, dirty, dark"
- **Tags:** aerogel, science, laboratory, tech, material
- **Style / Reference:** Scientific Visualization, High-Tech
- **Composition:** Close-up, rule of thirds
- **Color palette:** Sterile White, Ethereal Blue, Laser Red, Silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271026_aerogel_sample.jpg`
- **License / Attribution:** CC0
- **Notes:** Captures the unique 'frozen smoke' property of aerogel.

### Suggestion: Bismuth Crystal Metropolis
- **Date:** 2027-10-26
- **Prompt:** "A fantasy cityscape growing organically out of giant, iridescent bismuth crystals. The buildings follow the natural stair-step geometric formations of the crystal. The surfaces oxidize in rainbows of pink, yellow, blue, and purple. The sky is a pale, hazy violet."
- **Negative prompt:** "brick, concrete, normal city, dull colors"
- **Tags:** bismuth, crystal, fantasy city, geometry, iridescent
- **Style / Reference:** Fantasy Landscape, Geometric Abstraction
- **Composition:** Wide landscape, bottom-up perspective
- **Color palette:** Iridescent Rainbow (Pink, Gold, Blue), Violet
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20271026_bismuth_city.jpg`
- **License / Attribution:** CC0
- **Notes:** Explores geometric fractal patterns in architecture.

### Suggestion: Suprematist Void
- **Date:** 2027-11-01
- **Prompt:** "A pure abstract composition in zero gravity inspired by Kazimir Malevich's Suprematism. Floating red squares, black circles, and white crosses drift against a deep void. The forms cast sharp, hard shadows on each other, emphasizing their flatness and geometry."
- **Negative prompt:** "realistic, texture, shading, gradient, messy, 3D"
- **Tags:** suprematism, abstract, geometric, minimalist, art
- **Style / Reference:** Suprematism, Malevich, Abstract Art
- **Composition:** Floating elements, unbalanced but dynamic
- **Color palette:** Red, Black, White, Void Blue
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20271101_suprematist_void.jpg`
- **License / Attribution:** CC0
- **Notes:** The focus is on the "feeling" of weightlessness and pure geometry.

### Suggestion: Glitter Storm Portrait
- **Date:** 2027-11-01
- **Prompt:** "A high-speed macro photography portrait of a woman blowing a handful of gold and silver glitter towards the camera. The focus is on the individual hexagonal particles catching the studio light. The face is visible but slightly obscured by the sparkling bokeh cloud."
- **Negative prompt:** "blurry, messy, dirt, low resolution, dark"
- **Tags:** glitter, portrait, macro, festive, sparkling
- **Style / Reference:** High-Speed Photography, Beauty Editorial
- **Composition:** Close-up, depth of field
- **Color palette:** Gold, Silver, Skin Tones, Bokeh
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20271101_glitter_storm.jpg`
- **License / Attribution:** CC0
- **Notes:** Shallow depth of field is crucial to create the bokeh effect.

### Suggestion: Supercell Sunset
- **Date:** 2027-11-15
- **Prompt:** "A terrifying yet beautiful wide shot of a massive supercell thunderstorm rotating over a golden wheat field in Kansas. The setting sun casts a warm glow on the anvil cloud, contrasting with the bruised purple and green of the storm core. Lightning forks touch the ground."
- **Negative prompt:** "blue sky, sunny, calm, flat clouds, painting"
- **Tags:** tornado, supercell, storm, landscape, weather
- **Style / Reference:** Storm Chasing Photography, National Geographic
- **Composition:** Wide landscape, heavy sky
- **Color palette:** Golden Yellow, Bruised Purple, Storm Green, Grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271115_supercell.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the rotation and structure of the supercell (mesocyclone).

### Suggestion: Terracotta Awakening
- **Date:** 2027-11-15
- **Prompt:** "A cinematic fantasy shot inside the Mausoleum of the First Qin Emperor. The rows of Terracotta Warriors are cracking open, revealing glowing molten magma spirits inside. Dust and clay shards fall from their armor as they begin to move. The atmosphere is ancient and dusty."
- **Negative prompt:** "static, clean, museum, bright lights, normal statue"
- **Tags:** terracotta warriors, fantasy, magic, history, cinematic
- **Style / Reference:** Fantasy Movie Still, Historical Fantasy
- **Composition:** Eye level, looking down the ranks
- **Color palette:** Clay Brown, Magma Orange, Shadowy Blue
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20271115_terracotta_awakening.jpg`
- **License / Attribution:** CC0
- **Notes:** The contrast between the dull clay and bright inner glow is key.

### Suggestion: Chocolate Zoetrope
- **Date:** 2027-11-15
- **Prompt:** "A macro shot of an intricate 3D zoetrope cake made of dark chocolate. The tiers feature rings of tiny chocolate horses in slightly different poses. Under strobe lighting (implied), they appear to be galloping. Cocoa powder dusts the surface."
- **Negative prompt:** "blurry, motion blur, plastic, fake food, painting"
- **Tags:** zoetrope, chocolate, cake, animation, macro
- **Style / Reference:** Food Photography, Kinetic Art
- **Composition:** Close-up, slightly high angle
- **Color palette:** Dark Chocolate Brown, Gold Dust, Cream
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20271115_zoetrope_cake.jpg`
- **License / Attribution:** CC0
- **Notes:** Explain the "strobe" effect visually by having the figures look sharp and sequential.

### Suggestion: Ringworld Horizon
- **Date:** 2027-12-01
- **Prompt:** "A breathtaking wide shot from the inner surface of a massive Ringworld megastructure. The landscape curves upward into the sky, forming a giant arch of terrain (oceans, continents, clouds) that spans the heavens. A distant sun sits at the center point. The foreground features a futuristic city integrated with lush vegetation."
- **Negative prompt:** "flat horizon, planet surface, dark, dystopian, lowres"
- **Tags:** sci-fi, ringworld, megastructure, landscape, futuristic
- **Style / Reference:** Sci-Fi Concept Art, Larry Niven
- **Composition:** Wide angle, upward curve perspective
- **Color palette:** Sky Blue, Lush Green, White Clouds, Sun Gold
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20271201_ringworld.jpg`
- **License / Attribution:** CC0
- **Notes:** The key visual is the horizon curving up into an arch overhead.

### Suggestion: Dieselpunk Garage
- **Date:** 2027-12-01
- **Prompt:** "A gritty, atmospheric interior of a Dieselpunk mech repair garage. A massive, oil-stained walking tank is being welded by mechanics. Thick smoke and steam fill the air. The lighting is dim, industrial orange, with sparks flying. Walls are covered in pipes and gears."
- **Negative prompt:** "clean, modern, sleek, sci-fi, bright"
- **Tags:** dieselpunk, mech, industrial, garage, gritty
- **Style / Reference:** Dieselpunk, Industrial Concept Art
- **Composition:** Eye level, crowded interior
- **Color palette:** Rust Orange, Oil Black, Steel Grey, Spark Yellow
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271201_dieselpunk_garage.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the grease, rust, and smoke textures.

### Suggestion: Tulle Cloudscape
- **Date:** 2027-12-01
- **Prompt:** "A surreal, dreamlike landscape where the clouds are made of layers of gathered pink and peach tulle fabric. The fabric clouds cast soft, diffused shadows on rolling hills made of green velvet. The lighting is soft and romantic, resembling a fashion editorial backdrop."
- **Negative prompt:** "realistic clouds, water, harsh light, digital noise"
- **Tags:** surreal, tulle, fabric, landscape, dreamlike
- **Style / Reference:** Surrealism, Fashion Set Design
- **Composition:** Landscape view
- **Color palette:** Pastel Pink, Peach, Velvet Green, Soft White
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271201_tulle_cloudscape.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the translucency and layering of the tulle material.

### Suggestion: Peridot Crystal Cave
- **Date:** 2027-12-01
- **Prompt:** "A spelunker exploring a massive underground geode cavern lined with giant, translucent green Peridot crystals. The crystals glow with an inner lime-green light, illuminating the dark rocky walls. A subterranean lake reflects the jagged crystal formations."
- **Negative prompt:** "blue crystals, ice, daylight, blurry, low contrast"
- **Tags:** fantasy, cave, crystal, peridot, underground
- **Style / Reference:** Fantasy Landscape, National Geographic
- **Composition:** Wide shot, low angle
- **Color palette:** Lime Green, Peridot Green, Cave Dark Grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271201_peridot_cave.jpg`
- **License / Attribution:** CC0
- **Notes:** The distinctive lime-green color of Peridot is essential.

### Suggestion: Biopunk Laboratory
- **Date:** 2027-12-01
- **Prompt:** "A disturbing yet fascinating Biopunk laboratory. Computers and machinery are fused with organic flesh and pulsing veins. Strange, genetically modified organisms float in bio-luminescent tanks. The aesthetic mixes sterile chrome with visceral organic textures."
- **Negative prompt:** "clean, dry, purely mechanical, cartoon, low detail"
- **Tags:** biopunk, sci-fi, horror, organic, laboratory
- **Style / Reference:** Biopunk, Cronenberg-esque, Sci-Fi Horror
- **Composition:** Interior view
- **Color palette:** Flesh Tones, Sterile White, Bio-Luminescent Green/Blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271201_biopunk_lab.jpg`
- **License / Attribution:** CC0
- **Notes:** Balance the mechanical and biological elements so they look fused.

### Suggestion: Kilonova Explosion
- **Date:** 2027-12-15
- **Prompt:** "A spectacular cosmic visualization of two neutron stars colliding (kilonova). A blinding jet of gamma rays bursts from the center. Shockwaves of gold and platinum dust ripple outwards into space. The surrounding nebula is illuminated in violet and intense white."
- **Negative prompt:** "black hole, dark, painting, cartoon, low resolution"
- **Tags:** space, cosmic, explosion, neutron star, kilonova
- **Style / Reference:** Scientific Visualization, Space Art
- **Composition:** Wide cosmic scale, centered explosion
- **Color palette:** Violet, Intense White, Gold, Platinum
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20271215_kilonova.jpg`
- **License / Attribution:** CC0
- **Notes:** The collision should look incredibly energetic and bright.

### Suggestion: Macro Snowflake Geometry
- **Date:** 2027-12-15
- **Prompt:** "A high-resolution macro photography shot of a single snowflake resting on the fibers of a red wool scarf. The intricate hexagonal ice crystal structure is perfectly sharp. Soft lighting reveals the transparency and prismatic refraction of the ice."
- **Negative prompt:** "melted, blurry, multiple snowflakes, drawing, vector"
- **Tags:** macro, snowflake, winter, ice, texture
- **Style / Reference:** Macro Photography, Winter Nature
- **Composition:** Extreme close-up
- **Color palette:** Ice Blue, White, Wool Red
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20271215_snowflake.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the perfect geometry and the contrast with the fuzzy wool.

### Suggestion: Jade Dragon Seal
- **Date:** 2027-12-15
- **Prompt:** "A studio close-up of an ancient Chinese Imperial seal carved from translucent green jade. The handle is a coiled dragon. The stone glows slightly from backlighting, revealing the cloudy internal texture and fractures. It rests on red silk."
- **Negative prompt:** "plastic, opaque stone, toy, low detail, cartoon"
- **Tags:** jade, artifact, carving, macro, history
- **Style / Reference:** Museum Photography, Artifact
- **Composition:** Close-up, 45-degree angle
- **Color palette:** Jade Green, Silk Red, Gold
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20271215_jade_seal.jpg`
- **License / Attribution:** CC0
- **Notes:** The subsurface scattering of the jade is the key effect.

### Suggestion: Long Exposure Subway
- **Date:** 2027-12-15
- **Prompt:** "A cinematic long-exposure shot inside a tiled subway station. The train is a blur of light streaks rushing past the platform. Commuters standing still are sharp, while moving figures are ghostly blurs. The atmosphere is gritty and urban."
- **Negative prompt:** "static train, sharp people, bright daylight, clean"
- **Tags:** subway, urban, long exposure, motion blur, cinematic
- **Style / Reference:** Urban Photography, Long Exposure
- **Composition:** Perspective down the platform
- **Color palette:** Fluorescent Green, Motion Blur Red/White, Tile Grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271215_subway_blur.jpg`
- **License / Attribution:** CC0
- **Notes:** Balance the sharp static elements with the motion blurred train.

### Suggestion: Mother of Pearl Box
- **Date:** 2027-12-15
- **Prompt:** "A macro detail shot of an antique jewelry box featuring intricate Mother of Pearl (nacre) inlay work. The iridescent shell pieces shift colors (pink, green, silver) in the light. They are set into dark polished ebony wood with geometric precision."
- **Negative prompt:** "plastic, wood only, flat, painting, blurry"
- **Tags:** mother of pearl, inlay, texture, craft, macro
- **Style / Reference:** Macro Photography, Antique
- **Composition:** Top-down detail
- **Color palette:** Iridescent Pearl, Ebony Black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20271215_pearl_inlay.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the iridescence of the shell material.


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
- **Styles:** Matte Painting, Baroque, Gothic, Data Moshing, Scanography, Glitch Art, Pixel Sorting, Pointillism, Low Poly, Brutalism, Tenebrism, Geometric Abstraction, Romanticism, High-Speed Photography, Trompe-l'œil, Infrared Photography, Kinetic Art, Brutalist Web Design, Vaporwave, Solarpunk, Bauhaus, Art Deco, Constructivism, Fresco, Neoclassicism, Color Field Painting, Metaphysical Art, Hard Edge Painting, Tachisme, Synthetism, Rayograph.
- **Materials:** Cork, Chainmail, Fur, Sponges, Marble, Sea Glass, Amber, Rust, Slime, Denim, Paper Marbling, Damascus Steel, Soap Bubbles, Vantablack, Carbon Fiber, Generative Fluid Simulation, Sand, Sequin, Graphene, Mercury, Gallium, Burlap, Liquid Nitrogen, Obsidian, Titanium, Velvet, Latex, Neon Gas, Basalt, Aerogel, Ferrofluid, Velcro, Sandpaper, Cellophane, Aluminum Foil, Porcelain, Terracotta, Opal, Chiffon, Corduroy, Tweed.
- **Subjects:** Geode, Supernova, DNA Helix, Fireworks, Volcanic Eruption, Bioluminescent Forest, Diorama, Dyson Sphere, Space Elevator, Microchip City, Nebula, Quasar, Pulsar, Tsunami, Solar Punk City, Solar Eclipse, Coral Reef, Quantum Computer, Space Station, Ancient Ruins, Bioluminescent Bay, Salt Flats, Crop Circles, Black Hole, Swamp, Glacier, Canyon, Fjord, Oasis, Ant Farm, Beehive, Termite Mound, Beaver Dam, Bird's Nest, Spider Web, Cocoon, Bioluminescent Beach, Volcanic Lightning, Kaleidoscope, Steampunk Locomotive, Holographic Statue.

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
