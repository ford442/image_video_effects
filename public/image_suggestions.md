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
- **Prompt:** "A photorealistic landscape photograph captures a hyper-realistic sunset over a futuristic glass city. Reflective skyscrapers stretch into the sky, their mirrored facades catching warm orange and magenta highlights; flying vehicles streak between towers; cinematic rim lighting and volumetric haze create dramatic depth; ultra-detailed textures, realistic reflections, atmospheric perspective, shot with a 35mm lens and shallow depth of field, filmic color grading, 8k."
- **Negative prompt:** "lowres, watermark, extra limbs, text, cartoonish"
- **Notes:** Use wide aspect (16:9), emphasize warm color grading and crisp reflections. Include camera cues (lens, DOF) for photorealism.

### Example 2 — Painterly portrait
- **Prompt:** "A close-up painterly portrait of an elderly woman rendered in Rembrandt-style oil painting; soft directional Rembrandt lighting creates strong chiaroscuro; warm earth tones and layered brushstrokes give tactile texture; subtle imperfections and emotional expression; ultra-detailed skin pores and hair strands; medium-format lens feel; high-resolution canvas detail."
- **Negative prompt:** "blurry, disfigured, text, oversaturated"
- **Notes:** Use 4:5 aspect; request visible brushstrokes and canvas texture; specify the level of detail.

### Example 3 — Ancient collapsing flume in old-growth forest (detailed)
- **Prompt:** "A photorealistic landscape photograph captures an ancient, collapsing wooden flume extending into a dense, old-growth forest. Moss and thick ivy drape heavily from the decaying trestle structure, casting long, intricate shadows through shafts of dramatic sunlight piercing the forest canopy. The wooden beams are rotted and broken, with sections of the flume sagging and fallen. Below, a fern-covered forest floor and a rushing creek are partially visible. The atmosphere is melancholic and overgrown. Film grain."
- **Negative prompt:** "lowres, watermark, overexposed, text, modern structures"
- **Notes:** Aim for a moody, melancholic atmosphere; emphasize volumetric light shafts, rich texture detail, and film grain. Suggested aspect ratios: 3:2 or 16:10; use shallow depth to slightly soften distant canopy.

### Suggestion: Neon Street Vendor
- **Prompt:** "A cinematic, photorealistic night shot of a futuristic street food stall tucked into a rain-drenched cyberpunk alley. A battered mechanical vendor with glowing blue optics serves steaming noodles to a hooded figure. Neon signs in electric pink and cyan reflect vividly off the wet pavement and the metallic surfaces of the stall. Volumetric steam rises from the cooking station, blending with the atmospheric city fog. High contrast, sharp focus on the interaction, creamy bokeh background showing distant city lights. Shot on 35mm lens, f/1.8, 8k resolution, Unreal Engine 5 render style."
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
- **Prompt:** "A majestic steampunk airship docking at a floating Victorian sky-station high above a sea of clouds during golden hour. The ship features polished brass gears, billowing canvas sails, and a rich mahogany hull. The station is an intricate lattice of ironwork and steam vents. Crew members in period goggles and leather aviation gear are securing mooring ropes. Warm, low-angle sunlight bathes the scene, casting long, dramatic shadows and creating lens flares. Volumetric clouds, hyper-detailed mechanical parts, cinematic lighting, wide-angle shot."
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
- **Prompt:** "A macro photography shot of an alien flower composed entirely of translucent, iridescent crystals. The faceted petals refract light into spectral rainbows. Inside the flower, a tiny, bioluminescent insect rests on a stamen. The background is a soft, dreamy wash of other crystal flora. Extremely sharp focus on the subject, shallow depth of field, caustic lighting effects, vibrant jewel tones. 100mm macro lens, photorealistic, 8k."
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
- **Prompt:** "A classic black and white film noir scene inside a private detective's office. Venetian blinds cast harsh, striped shadows (chiaroscuro) across a cluttered wooden desk featuring a smoking ashtray, a half-empty glass of whiskey, and a revolver. Rain streaks the glass of the window. A silhouette of a fedora-wearing figure stands by the window, gazing out at the rainy city lights. High contrast, film grain, dramatic moody lighting, atmospheric perspective. 50mm lens, cinematic composition."
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
- **Prompt:** "An isometric 3D render of a cozy, cluttered alchemist's workshop. Wooden shelves are packed with glowing potions in various shapes, ancient rolled scrolls, and leather-bound books. A cauldron bubbles in the center emitting green steam. A sleeping cat rests on a rug near a fireplace. Warm, inviting lighting from candles and magical artifacts. Stylized, low poly but with detailed textures, diorama aesthetic, soft ambient occlusion, vibrant colors. 4k resolution."
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
- **Prompt:** "A photorealistic wide shot inside a massive rotating space station greenhouse. Lush, vibrant tropical vegetation and hanging gardens fill the curved interior structure. Through the large reinforced glass panels above, the curvature of the Earth and the starry void of space are visible. Sunlight streams in, creating dappled shadows on the metallic floor grates. High-tech hydroponic systems mix with organic nature. 8k, cinematic lighting, highly detailed."
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
- **Prompt:** "A whimsical landscape entirely constructed from folded paper. Mountains are sharp geometric folds, trees are stylized paper cutouts, and a river is made of layered blue tissue paper. Soft, warm studio lighting casts gentle shadows, enhancing the texture of the paper grain. A small paper boat floats on the river. Depth of field emphasizes the miniature scale. Tilt-shift effect, macro photography style, 8k."
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
- **Prompt:** "Inside a colossal dwarven forge deep within a volcano. Molten lava flows in channels carved into dark obsidian rock. A massive anvil sits in the center, glowing with heat. Sparks fly as a giant mechanical hammer strikes glowing metal. The lighting is dominated by the intense orange and red glow of the lava, contrasting with deep shadows. Heat haze distortion, sparks, smoke, volumetric lighting. Epic fantasy style, detailed textures."
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
- **Prompt:** "A high-angle, directly overhead 'knolling' shot of vintage exploration gear arranged neatly on a weathered wooden table. Items include a brass compass, a rolled parchment map, a leather-bound journal, an old brass telescope, a fountain pen, and a flickering candle. The lighting is warm and diffuse. Ultra-detailed textures of leather, brass, and paper. Photorealistic, commercial product photography style."
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
- **Prompt:** "A artistic double exposure image blending the silhouette of a majestic stag with a foggy pine forest landscape. The stag's body is filled with the forest scene: tall pine trees, mist, and a flock of birds flying into the pale sky. The background is a clean, solid off-white to isolate the shape. Minimalist, moody, ethereal. High contrast between the dark trees and the light mist. Vector art inspiration but with photographic textures."
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
- **Prompt:** "A traditional Japanese Sumi-e ink wash painting of towering, jagged mountain peaks shrouded in mist. Stark black brushstrokes define the cliffs against a textured white rice paper background. A solitary, gnarled pine tree clings to a precipice in the foreground. Minimalist composition, emphasizing negative space (ma). High contrast, fluid ink bleeding effects, visible paper grain."
- **Negative prompt:** "color, photograph, realistic, 3D, modern, vibrant"
- **Tags:** sumi-e, ink wash, japanese, landscape, minimalist
- **Style / Reference:** Traditional Ink Painting, Sesshu Toyo
- **Composition:** Vertical, lots of negative space
- **Color palette:** Black, Grayscale, White
- **Aspect ratio:** 2:3
- **Reference images:** `public/images/suggestions/20260210_sumi_e_mountains.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the texture of the paper and the fluidity of the ink.

### Suggestion: Knitted Wool Village
- **Prompt:** "A cozy, whimsical scene of a miniature village entirely made of knitted wool and yarn. Small cottages have fuzzy roof thatching, trees are pom-poms, and the ground is a patchwork of green crochet patterns. Soft, warm studio lighting highlights the fuzzy texture and stray fibers. Macro photography style, shallow depth of field, tilt-shift effect to enhance the miniature look."
- **Negative prompt:** "plastic, realistic materials, metal, sharp edges, smooth"
- **Tags:** knitted, wool, craft, miniature, cute
- **Style / Reference:** Stop Motion, Handicraft
- **Composition:** High angle, tilt-shift
- **Color palette:** Warm pastels, soft creams, cozy greens
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260210_knitted_village.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the stray fibers and the tactile nature of the wool.

### Suggestion: Atomic Age Diner
- **Prompt:** "A retro-futuristic 1950s 'Googie' architecture diner on the moon. Curved chrome fins, large glass bubbles, and starburst motifs. Inside, a robot waitress on a unicycle serves milkshakes to astronauts in bubble helmets. Outside the window, the Earth rises over the cratered lunar landscape. Bright, cheerful optimistic lighting. Technicolor aesthetic, Norman Rockwell meets The Jetsons."
- **Negative prompt:** "gritty, dark, dystopian, cyberpunk, rusty"
- **Tags:** retro-futurism, 1950s, sci-fi, space, diner
- **Style / Reference:** Mid-Century Modern, Googie, Technicolor
- **Composition:** Wide shot showing interior and view outside
- **Color palette:** Teal, chrome, cherry red, bright white
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260210_atomic_diner.jpg`
- **License / Attribution:** CC0
- **Notes:** Capture the optimism of the space age.

### Suggestion: Brutalist Fog Monument
- **Prompt:** "A massive, imposing Brutalist concrete monument rising from a dark, foggy plain. Sharp geometric angles, raw concrete textures with water stains, and repeating modular patterns. The structure is illuminated by a single, harsh searchlight cutting through the thick fog. Atmosphere of oppression and mystery. Cinematic, dystopian, Villeneuve-style sci-fi."
- **Negative prompt:** "ornate, colorful, happy, nature, wood"
- **Tags:** brutalism, concrete, fog, dystopian, architecture
- **Style / Reference:** Brutalist Architecture, Dystopian Sci-Fi
- **Composition:** Low angle, looking up to emphasize scale
- **Color palette:** Monochromatic greys, cold blue fog, harsh white light
- **Aspect ratio:** 9:16
- **Reference images:** `public/images/suggestions/20260210_brutalist_fog.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the scale and the texture of the raw concrete.

### Suggestion: Microchip Metropolis
- **Prompt:** "A macro photography shot of a computer motherboard, visualized as a futuristic glowing city at night. Capacitors look like skyscrapers, copper traces are highways of light, and the CPU is a central citadel. Neon green and blue energy pulses through the circuits. Extremely shallow depth of field, bokeh from distant LEDs. High-tech, intricate detail, cyberpunk aesthetic on a micro scale."
- **Negative prompt:** "organic, dirt, rust, full size city"
- **Tags:** macro, technology, circuit, cyberpunk, abstract
- **Style / Reference:** Macro Photography, Tech Noir
- **Composition:** Isometric or close-up macro
- **Color palette:** Electric blue, neon green, gold, black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260210_microchip_city.jpg`
- **License / Attribution:** CC0
- **Notes:** Blur the line between hardware and architecture.

### Suggestion: Bioluminescent Abyss
- **Prompt:** "A terrifying yet beautiful photorealistic deep-sea scene. A colossal, translucent leviathan resembling a jellyfish floats in the crushing darkness of the abyss. Its internal organs glow with a pulsating bioluminescent blue and violet light, illuminating the surrounding marine snow and tiny swarming crustaceans. 8k, national geographic style, high contrast."
- **Negative prompt:** "surface, boat, bright, cartoon, blurry"
- **Tags:** underwater, bioluminescence, creature, horror, nature
- **Style / Reference:** Photorealistic, Nature Documentary
- **Composition:** Wide shot, low angle
- **Color palette:** Black, electric blue, violet
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260211_bioluminescent_abyss.jpg`
- **License / Attribution:** CC0
- **Notes:** High contrast is key to emphasize the bioluminescence against the dark water.

### Suggestion: Midnight Arcade
- **Prompt:** "A nostalgic 1980s arcade interior at night, filled with rows of glowing CRT cabinets. The carpet has a vibrant, cosmic pattern glowing under blacklight. A teenager in a denim jacket plays a cabinet in the foreground, illuminated by the screen's glow. Synthwave atmosphere, neon pink and blue lighting, haze, shallow depth of field. Cinematic, detailed textures."
- **Negative prompt:** "LCD screens, modern clothes, daylight, clean"
- **Tags:** arcade, 80s, retro, neon, interior
- **Style / Reference:** Retro Photography, Cinematic
- **Composition:** Eye level, depth of field
- **Color palette:** Neon pink, cyan, deep purple, black
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260211_midnight_arcade.jpg`
- **License / Attribution:** CC0
- **Notes:** Focus on the screen glow and the carpet texture for authenticity.

### Suggestion: Delftware Diorama
- **Prompt:** "A surreal landscape where everything is made of glazed white porcelain with intricate Delft blue patterns. A windmill sits on a hill, and the clouds are painted ceramic shapes suspended by strings. Glossy reflections, studio lighting, smooth textures. The scene looks like a precious antique plate come to life. Macro photography style."
- **Negative prompt:** "rough texture, dirt, realistic grass, matte"
- **Tags:** porcelain, delftware, blue and white, surreal, miniature
- **Style / Reference:** 3D Render, Ceramic Art
- **Composition:** Isometric or tilt-shift
- **Color palette:** White, Cobalt Blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260211_delftware_diorama.jpg`
- **License / Attribution:** CC0
- **Notes:** Emphasize the glossiness of the ceramic to sell the material.

### Suggestion: Cyber Samurai Duel
- **Prompt:** "A dynamic action shot of a cybernetic samurai drawing a glowing katana in a rain-slicked neo-Tokyo street. Sparks fly from the blade. The samurai has a traditional silhouette but with mechanical armor parts and a holographic mask. Motion blur, rain droplets frozen in mid-air, intense lens flare. Cinematic lighting, dramatic angle."
- **Negative prompt:** "static, boring, peaceful, historical accuracy"
- **Tags:** cyberpunk, samurai, action, rain, neon
- **Style / Reference:** Action Movie Still, Concept Art
- **Composition:** Low angle, dynamic action
- **Color palette:** Steel grey, blood red, neon blue
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260211_cyber_samurai.jpg`
- **License / Attribution:** CC0
- **Notes:** Use motion blur to convey speed and impact.

### Suggestion: Smoke Spirit
- **Prompt:** "A double exposure artistic shot of a dancer formed entirely from swirling, colored smoke and ink in water. The human form is suggested but ephemeral, dissolving into wisps of pink, gold, and teal smoke against a black background. Fluid dynamics, high speed photography, ethereal, dreamlike. 8k, sharp focus on the core."
- **Negative prompt:** "solid body, flesh, clothes, messy"
- **Tags:** smoke, abstract, dancer, fluid, ethereal
- **Style / Reference:** Abstract Photography, Fluid Art
- **Composition:** Centered, floating
- **Color palette:** Black background, pastel pink, gold, teal
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260211_smoke_spirit.jpg`
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

---

## Agent suggestions ✍️

This section is reserved for short, incremental contributions by agents (automation scripts, bots, or collaborators). Add one suggestion per subsection so entries are easy to track and reference. When adding a suggestion, include your agent/author name, date, and a status label (proposed / tested / merged).

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
- **Prompt:** "A photorealistic landscape photograph captures an ancient, collapsing wooden flume extending into a dense, old-growth forest. Moss and thick ivy drape heavily from the decaying trestle structure, casting long, intricate shadows through shafts of dramatic sunlight piercing the forest canopy. The wooden beams are rotted and broken, with sections of the flume sagging and fallen. Below, a fern-covered forest floor and a rushing creek are partially visible. The atmosphere is melancholic and overgrown. Film grain."
- **Negative prompt:** "lowres, watermark, overexposed, text, modern structures"
- **Tags:** photorealism, nature, melancholic
- **Ref image:** `public/images/suggestions/20260112_forest-flume.jpg`
- **Notes / agent context:** Suggested as a high-recall prompt for melancholic nature scenes; tested with seed=12345, steps=50.
- **Status:** proposed

### Agent Suggestion: Bioluminescent Cave — @gemini-agent — 2026-01-12
- **Prompt:** "A photorealistic wide shot of a massive underground cavern filled with glowing bioluminescent mushrooms and strange flora. A crystal-clear river flows through the center, reflecting the ethereal blue and green lights. Intricate rock formations and hanging vines are visible in the soft glow. The atmosphere is magical and mysterious. Ultra-detailed, 8k, cinematic lighting."
- **Negative prompt:** "sunlight, daylight, artificial lights, blurry, people"
- **Tags:** fantasy, nature, underground, glowing
- **Ref image:** `public/images/suggestions/20260112_bioluminescent-cave.jpg`
- **Notes / agent context:** Good for testing ethereal and magical visual effects.
- **Status:** proposed

### Agent Suggestion: Retro-Futuristic Android Portrait — @gemini-agent — 2026-01-12
- **Prompt:** "A 1980s-style airbrushed portrait of a female android. Her face is partially translucent, revealing complex chrome mechanics and wiring underneath. She has vibrant neon pink hair and her eyes glow with a soft blue light. The background is a dark grid with laser beams. High-contrast, sharp details, smooth gradients, iconic 80s chrome and neon aesthetic."
- **Negative prompt:** "photorealistic, modern, flat, simple"
- **Tags:** cyberpunk, retro, 80s, portrait
- **Ref image:** `public/images/suggestions/20260112_retro-android.jpg`
- **Notes / agent context:** Ideal for testing neon, glitch, and retro shader effects.
- **Status:** proposed

### Agent Suggestion: Crystalline Alien Jungle — @gemini-agent — 2026-01-12
- **Prompt:** "A world where the jungle is made of semi-translucent, glowing crystals instead of wood. The air is filled with floating, sparkling spores. The flora and fauna are alien and geometric. A wide-angle shot showing the vast, iridescent landscape under the light of a binary star system. Highly detailed, octane render, 8k."
- **Negative prompt:** "trees, wood, leaves, green, people, earth-like"
- **Tags:** sci-fi, alien, fantasy, crystal, jungle
- **Ref image:** `public/images/suggestions/20260112_crystal-jungle.jpg`
- **Notes / agent context:** Excellent for refraction, bloom, and god-ray effects.
- **Status:** proposed

### Agent Suggestion: Quantum Computer Core — @gemini-agent — 2026-01-12
- **Prompt:** "The inside of a futuristic quantum computer core. A central sphere of entangled light particles pulses with energy, connected by threads of light to a complex, fractal-like structure of superconducting wires and conduits. The scene is dark, illuminated only by the glowing qubits and energy flows. Macro shot, shallow depth of field, abstract, technological."
- **Negative prompt:** "people, screens, keyboards, messy wires"
- **Tags:** abstract, tech, sci-fi, quantum, computer
- **Ref image:** `public/images/suggestions/20260112_quantum-core.jpg`
- **Notes / agent context:** Use for testing generative, abstract, and data-moshing shaders.
- **Status:** proposed

### Agent Suggestion: Solar Sail Ship — @gemini-agent — 2026-01-12
- **Prompt:** "A massive, elegant spaceship with vast, shimmering solar sails that look like a captured nebula, cruising silently through a dense starfield. The ship's hull is sleek and pearlescent. Distant galaxies and planetary rings are visible in the background. Cinematic, epic scale, breathtaking, inspired by EVE Online."
- **Negative prompt:** "fire, smoke, explosions, cartoon"
- **Tags:** sci-fi, space, ship, nebula, majestic
- **Ref image:** `public/images/suggestions/20260112_solar-sail.jpg`
- **Notes / agent context:** Good for testing galaxy, starfield, and other cosmic background shaders.
- **Status:** proposed

### Agent Suggestion: Clockwork Dragon — @gemini-agent — 2026-01-12
- **Prompt:** "A magnificent and intricate mechanical dragon made of polished brass, copper, and glowing gears, perched atop a gothic cathedral. Steam escapes from vents on its body. The city below is shrouded in fog at dusk. The dragon's eyes are glowing red lenses. Detailed steampunk aesthetic."
- **Negative prompt:** "flesh, scales, simple, modern"
- **Tags:** steampunk, fantasy, dragon, mechanical, gothic
- **Ref image:** `public/images/suggestions/20260112_clockwork-dragon.jpg`
- **Notes / agent context:** Tests metallic surfaces, fog, and glow effects.
- **Status:** proposed

### Agent Suggestion: Underwater Metropolis — @gemini-agent — 2026-01-12
- **Prompt:** "A bustling futuristic city enclosed in a giant glass dome at the bottom of the ocean. Schools of bioluminescent fish and giant marine creatures swim peacefully outside the dome, while flying vehicles and pedestrians move within the city. The light from the city illuminates the surrounding deep-sea trench. Photorealistic, detailed, underwater."
- **Negative prompt:** "land, sky, clouds, empty, ruins"
- **Tags:** futuristic, city, underwater, sci-fi
- **Ref image:** `public/images/suggestions/20260112_underwater-city.jpg`
- **Notes / agent context:** Perfect for caustics, water distortion, and fog effects.
- **Status:** proposed

### Agent Suggestion: Floating Islands Market — @gemini-agent — 2026-01-12
- **Prompt:** "A vibrant and chaotic marketplace set on a series of fantastical floating islands, connected by rickety rope bridges. Strange, colorful alien merchants sell exotic fruits and mysterious artifacts. Fantastical flying creatures are used as transport. The sky is filled with colorful clouds and multiple moons. Studio Ghibli inspired, detailed, whimsical."
- **Negative prompt:** "ground, roads, cars, realistic"
- **Tags:** fantasy, flying, islands, market, whimsical
- **Ref image:** `public/images/suggestions/20260112_floating-market.jpg`
- **Notes / agent context:** A colorful and complex scene to test a wide variety of effects.
- **Status:** proposed

### Agent Suggestion: Desert Planet Oasis — @gemini-agent — 2026-01-12
- **Prompt:** "A hidden oasis on a desert planet with two suns setting in the sky, casting long shadows. The oasis is centered around a shimmering, turquoise pool, surrounded by bizarre, crystalline alien plant life and rock formations that defy gravity. The sand is a deep orange. Serene, alien, beautiful landscape."
- **Negative prompt:** "green, Earth-like, trees, people"
- **Tags:** sci-fi, desert, oasis, alien, landscape
- **Ref image:** `public/images/suggestions/20260112_desert-oasis.jpg`
- **Notes / agent context:** Good for testing heat-haze, water ripples, and stark lighting.
- **Status:** proposed

### Agent Suggestion: Ancient Tree of Souls — @gemini-agent — 2026-01-12
- **Prompt:** "A colossal, ancient, glowing tree whose leaves and bark emit a soft, ethereal, spiritual light. Its roots are massive, intertwining with the landscape and appearing to connect to the stars in the night sky above. Wisps of light float around it like fireflies. Mystical, magical, serene, inspired by Avatar."
- **Negative prompt:** "chopped, burning, daytime, simple"
- **Tags:** fantasy, magic, tree, spiritual, glowing
- **Ref image:** `public/images/suggestions/20260112_soul-tree.jpg`
- **Notes / agent context:** Great for particle effects, glow, and ethereal vibes.
- **Status:** proposed

### Agent Suggestion: Post-Apocalyptic Library — @gemini-agent — 2026-01-12
- **Prompt:** "The grand, dusty interior of a ruined baroque library, reclaimed by nature. Huge shafts of volumetric light pierce through the collapsed, vaulted ceiling, illuminating floating dust particles. Books are scattered everywhere, and vines crawl over shelves and statues. A single, tattered armchair sits in a pool of light. Moody, detailed, melancholic, photorealistic."
- **Negative prompt:** "clean, new, people, pristine"
- **Tags:** post-apocalyptic, ruins, library, atmospheric
- **Ref image:** `public/images/suggestions/20260112_ruin-library.jpg`
- **Notes / agent context:** Tests god-rays, dust particles, and detailed textures.
- **Status:** proposed

### Agent Suggestion: Surreal Cloudscape — @gemini-agent — 2026-01-12
- **Prompt:** "A dreamlike, minimalist landscape set high above the clouds at sunset. The clouds are a soft, pink and orange sea. Impossible geometric shapes and minimalist architecture float serenely in the air. A single, stylized tree grows on a small, floating island. Ethereal, surreal, peaceful, vector art style."
- **Negative prompt:** "realistic, ground, busy, dark"
- **Tags:** surreal, dreamlike, minimalist, clouds
- **Ref image:** `public/images/suggestions/20260112_cloudscape.jpg`
- **Notes / agent context:** Good for simple, clean shaders and color-blending effects.
- **Status:** proposed

### Agent Suggestion: Overgrown Train Station — @autogen-bot — 2026-01-12
- **Prompt:** "A wide-angle photorealistic scene of an abandoned train station overtaken by nature: platforms cracked and lifted by roots, trains half-buried in moss, glass roofs shattered with vines spilling through. Shafts of warm afternoon light filter in, highlighting floating dust motes and wet stone surfaces; pigeons and small plants reclaim the tracks. Moody, textured, high-detail, 50mm, subtle film grain."
- **Negative prompt:** "modern signs, people, clean, sunny"
- **Tags:** urban, ruins, nature, atmospheric
- **Ref image:** `public/images/suggestions/20260112_overgrown-station.jpg`
- **Notes / agent context:** Great for testing wet surfaces, moss detail, and depth-of-field. Suggested aspect ratio: 16:9.
- **Status:** proposed

### Agent Suggestion: Neon Rain Alley — @neonbot — 2026-01-12
- **Prompt:** "A dark, rain-soaked alley in a cyberpunk city at night: neon signs in kanji and English flicker, puddles reflect saturated color, steam rises from grates, and a lone figure with a transparent umbrella stands beneath a flickering holo-ad. Wet asphalt, intense reflections, heavy bokeh, cinematic 35mm, ultra-detailed textures, moody atmosphere."
- **Negative prompt:** "daylight, cartoon, bright, cheerful"
- **Tags:** cyberpunk, neon, urban, night
- **Ref image:** `public/images/suggestions/20260112_neon-alley.jpg`
- **Notes / agent context:** Use for testing chromatic aberration, bloom, and wet-reflection shaders. Try seed=67890 for reproducibility.
- **Status:** proposed

### Agent Suggestion: Antique Map Room with Floating Islands — @mapbot — 2026-01-12
- **Prompt:** "An ornately furnished, dimly lit study filled with antique maps and celestial globes; in the center, several miniature floating islands levitate above a polished mahogany table, each with distinct micro-ecosystems. Soft candlelight casts warm highlights and long shadows; dust particles hang in the air. Rich, detailed textures, painterly realism, medium-format lens."
- **Negative prompt:** "modern electronics, fluorescent light, messy"
- **Tags:** fantasy, interior, steampunk, magic
- **Ref image:** `public/images/suggestions/20260112_map-room.jpg`
- **Notes / agent context:** Ideal for layered compositing, warm lighting, and small-scale detail tests. Aspect ratio: 4:3.
- **Status:** proposed

### Agent Suggestion: Microscopic Coral City — @biology-agent — 2026-01-12
- **Prompt:** "A macro, photorealistic view of a coral reef that resembles an ancient submerged city: arched coral towers, tiny fish like airborne commuters, minuscule windows filled with bioluminescent organisms. Light filters through shallow water, producing caustic patterns and a soft haze; ultra-detailed surface textures and micro-ecosystem life."
- **Negative prompt:** "land, buildings, people, murky"
- **Tags:** macro, underwater, coral, photorealism
- **Ref image:** `public/images/suggestions/20260112_coral-city.jpg`
- **Notes / agent context:** Use for caustics, water distortion, and fine-scale texture generation tests. Suggested camera: macro 100mm.
- **Status:** proposed

### Agent Suggestion: Auroral Glacier Cathedral — @aurora-agent — 2026-01-12
- **Prompt:** "A majestic natural cathedral carved of blue ice and glacier, its spires and arches rimed with frost; above, a luminous aurora paints vivid green and purple curtains across the night sky. Soft moonlight catches crystalline details, and a lone traveler in heavy furs stands at the entrance for scale. Epic, melancholic, ultra-detailed landscape, 8k."
- **Negative prompt:** "tropical, sunlight, warm colors, crowds"
- **Tags:** landscape, aurora, ice, epic
- **Ref image:** `public/images/suggestions/20260112_auroral-cathedral.jpg`
- **Notes / agent context:** Excellent for volumetric lighting, ice refraction, and subtle color grading tests.
- **Status:** proposed

**Guidelines for agents:**
- Prefer concise, reproducible entries. Include generation parameters and a seed when possible.
- If a suggestion is tested, attach output samples (in `public/images/suggestions/` or via a PR). Link to PRs or commits in the **Status** field.
- Keep entries focused; avoid adding large binary assets directly into this file—use `public/images/suggestions/` instead.

---
