# Image Suggestions 🖼️

## Purpose

This file stores curated image suggestions for text-to-image generation and provides guidance on how to write high-quality prompts.

---

## How to store suggestions

- Recommended directory for actual image files: `public/images/suggestions/` (or reference an external URL).
- File naming convention suggestion: `YYYYMMDD_slug.ext` (e.g., `20260112_sunset-glass-city.jpg`).
- Each suggestion should be a markdown section with a clear title and metadata (see the template below).

---

## Suggestion template (copy & paste)

```md
## Suggestion: <Title>
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
- **Iterate & record variants.** Save alternate prompts and parameter changes (seed, steps, scale) so results can be reproduced.

---

## Prompt examples

### Example 1 — Photorealistic landscape
- **Prompt:** "A photorealistic landscape photograph captures a hyper-realistic sunset over a futuristic glass city. Reflective skyscrapers stretch into the sky, their mirrored facades catching wa[...]"
- **Negative prompt:** "lowres, watermark, extra limbs, text, cartoonish"
- **Notes:** Use wide aspect (16:9), emphasize warm color grading and crisp reflections. Include camera cues (lens, DOF) for photorealism.

### Example 2 — Painterly portrait
- **Prompt:** "A close-up painterly portrait of an elderly woman rendered in Rembrandt-style oil painting; soft directional Rembrandt lighting creates strong chiaroscuro; warm earth tones and laye[...]"
- **Negative prompt:** "blurry, disfigured, text, oversaturated"
- **Notes:** Use 4:5 aspect; request visible brushstrokes and canvas texture; specify the level of detail.

### Example 3 — Ancient collapsing flume in old-growth forest (detailed)
- **Prompt:** "A photorealistic landscape photograph captures an ancient, collapsing wooden flume extending into a dense, old-growth forest. Moss and thick ivy drape heavily from the decaying tres[...]"
- **Negative prompt:** "lowres, watermark, overexposed, text, modern structures"
- **Notes:** Aim for a moody, melancholic atmosphere; emphasize volumetric light shafts, rich texture detail, and film grain. Suggested aspect ratios: 3:2 or 16:10; use shallow depth to slightly s[...] 

### Suggestion: Neon Street Vendor
- **Prompt:** "A cinematic, photorealistic night shot of a futuristic street food stall tucked into a rain-drenched cyberpunk alley. A battered mechanical vendor with glowing blue optics serves st[...]"
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
- **Prompt:** "A majestic steampunk airship docking at a floating Victorian sky-station high above a sea of clouds during golden hour. The ship features polished brass gears, billowing canvas sail[...]"
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
- **Prompt:** "A macro photography shot of an alien flower composed entirely of translucent, iridescent crystals. The faceted petals refract light into spectral rainbows. Inside the flower, a tiny[...]"
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
- **Prompt:** "A classic black and white film noir scene inside a private detective's office. Venetian blinds cast harsh, striped shadows (chiaroscuro) across a cluttered wooden desk featuring a [...]"
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
- **Prompt:** "An isometric 3D render of a cozy, cluttered alchemist's workshop. Wooden shelves are packed with glowing potions in various shapes, ancient rolled scrolls, and leather-bound books.[...]"
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
- **Prompt:** "A photorealistic wide shot inside a massive rotating space station greenhouse. Lush, vibrant tropical vegetation and hanging gardens fill the curved interior structure. Through the[...]"
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
- **Prompt:** "A whimsical landscape entirely constructed from folded paper. Mountains are sharp geometric folds, trees are stylized paper cutouts, and a river is made of layered blue tissue pape[...]"
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
- **Prompt:** "Inside a colossal dwarven forge deep within a volcano. Molten lava flows in channels carved into dark obsidian rock. A massive anvil sits in the center, glowing with heat. Sparks f[...]"
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
- **Prompt:** "A high-angle, directly overhead 'knolling' shot of vintage exploration gear arranged neatly on a weathered wooden table. Items include a brass compass, a rolled parchment map, a le[...]"
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
- **Prompt:** "A artistic double exposure image blending the silhouette of a majestic stag with a foggy pine forest landscape. The stag's body is filled with the forest scene: tall pine trees, mi[...]"
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
- **Prompt:** "A traditional Japanese Sumi-e ink wash painting of towering, jagged mountain peaks shrouded in mist. Stark black brushstrokes define the cliffs against a textured white rice paper [...]"
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
- **Prompt:** "A cozy, whimsical scene of a miniature village entirely made of knitted wool and yarn. Small cottages have fuzzy roof thatching, trees are pom-poms, and the ground is a patchwork o[...]"
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
- **Prompt:** "A retro-futuristic 1950s 'Googie' architecture diner on the moon. Curved chrome fins, large glass bubbles, and starburst motifs. Inside, a robot waitress on a unicycle serves milks[...]"
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
- **Prompt:** "A massive, imposing Brutalist concrete monument rising from a dark, foggy plain. Sharp geometric angles, raw concrete textures with water stains, and repeating modular patterns. Th[...]"
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
- **Prompt:** "A macro photography shot of a computer motherboard, visualized as a futuristic glowing city at night. Capacitors look like skyscrapers, copper traces are highways of light, and the[...]"
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
- **Prompt:** "A terrifying yet beautiful photorealistic deep-sea scene. A colossal, translucent leviathan resembling a jellyfish floats in the crushing darkness of the abyss. Its internal organs[...]"
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
- **Prompt:** "A nostalgic 1980s arcade interior at night, filled with rows of glowing CRT cabinets. The carpet has a vibrant, cosmic pattern glowing under blacklight. A teenager in a denim jacke[...]"
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
- **Prompt:** "A surreal landscape where everything is made of glazed white porcelain with intricate Delft blue patterns. A windmill sits on a hill, and the clouds are painted ceramic shapes susp[...]"
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
- **Prompt:** "A dynamic action shot of a cybernetic samurai drawing a glowing katana in a rain-slicked neo-Tokyo street. Sparks fly from the blade. The samurai has a traditional silhouette but w[...]"
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
- **Prompt:** "A double exposure artistic shot of a dancer formed entirely from swirling, colored smoke and ink in water. The human form is suggested but ephemeral, dissolving into wisps of pink,[..."
- **Negative prompt:** "solid body, flesh, clothes, messy"
- **Tags:** smoke, abstract, dancer, fluid, ethereal
- **Style / Reference:** Abstract Photography, Fluid Art
- **Composition:** Centered, floating
- **Color palette:** Black background, pastel pink, gold, teal
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260124_smoke_spirit.jpg`
- **License / Attribution:** CC0
- **Notes:** The form should be ambiguous but recognizable.

---

## Attribution & legal

- Always record the **License / Attribution** for reference images and any artist references. Confirm you have the rights to store and use included images.
- When using external images, include the URL and the license where possible.

---

## Workflow suggestions ✅

- Keep each suggestion self-contained (title + metadata + example prompt). This helps reuse and automation.
- Optionally maintain a simple CSV/JSON data file for programmatic consumption (columns: id, title, prompt, tags, ref_image, license).
- Scheduled task: Add 5 new suggestions weekly to maintain a diverse and growing collection of prompts.

---

## Agent suggestions ✍️

This section is reserved for short, incremental contributions by agents (automation scripts, bots, or collaborators). Add one suggestion per subsection so entries are easy to track and reference.[...]