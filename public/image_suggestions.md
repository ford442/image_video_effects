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
- **Style Blending.** Combine two distinct styles for unique results (e.g., "Art Nouveau architecture in a Cyberpunk setting").
- **Iterate & record variants.** Save alternate prompts and parameter changes (seed, steps, scale) so results can be reproduced.

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


---

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

---

## Attribution & legal

- Always record the **License / Attribution** for reference images and any artist references. Confirm you have the rights to store and use included images.
- When using external images, include the URL and the license where possible.

---

## Workflow suggestions

- **Check for duplicates:** Before adding, search existing titles and prompts to ensure distinctness.
- Keep each suggestion self-contained (title + metadata + example prompt). This helps reuse and automation.
- Optionally maintain a simple CSV/JSON data file for programmatic consumption (columns: id, title, prompt, tags, ref_image, license).
- Scheduled task: Add 5 new suggestions weekly to maintain a diverse and growing collection of prompts.

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
