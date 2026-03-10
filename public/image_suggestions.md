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

### Suggestion: Bioluminescent Deep Sea Diver
- **Date:** 2026-01-20
- **Prompt:** "A close-up of a futuristic deep-sea diver floating in the pitch-black abyss. The subject is wearing an intricate, heavily armored diving suit that emits a soft, pulsing bioluminescent teal and purple glow. The lighting is low-key, entirely dependent on the glowing suit elements and tiny, alien luminescent jellyfish floating nearby. The mood is eerie, isolated, and wondrous. Captured with a macro lens, focusing on the textured metal and glowing fluid pipes of the helmet."
- **Negative prompt:** "sunlight, surface, bright, simple, cartoon, blurry"
- **Tags:** sci-fi, underwater, glowing, portrait, futuristic
- **Style / Reference:** photorealistic, dark sci-fi, detailed 3D render
- **Composition:** close-up, centered on the helmet
- **Color palette:** deep blacks, vibrant teal, glowing purple
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260120_deep-sea-diver.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing glowing emissive materials against dark backgrounds and particle effects.

### Suggestion: Overgrown Solarpunk Skyscraper
- **Date:** 2026-01-20
- **Prompt:** "A majestic, wide-angle shot of a towering solarpunk skyscraper made of gleaming white composite materials and sweeping glass curves, heavily overgrown with lush, vibrant green vertical gardens and cascading waterfalls. The subject is bathed in warm, golden-hour sunlight casting long, dramatic shadows. The mood is optimistic, peaceful, and harmonious. Captured with a wide-angle 16mm lens to emphasize the colossal scale against a clear blue sky."
- **Negative prompt:** "pollution, dystopian, dark, gray, gloomy, low-res"
- **Tags:** solarpunk, architecture, nature, city, bright
- **Style / Reference:** architectural visualization, utopia, photorealistic
- **Composition:** wide angle, low angle looking up
- **Color palette:** bright whites, vibrant greens, golden hour oranges, sky blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260120_solarpunk-skyscraper.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing lush foliage generation, bright daylight global illumination, and water features.

### Suggestion: Cybernetic Geisha in a Neon Garden
- **Date:** 2026-01-20
- **Prompt:** "A portrait of an elegant cybernetic geisha with porcelain skin that features delicate, glowing golden seam lines revealing mechanical joints. She is holding a translucent, holographic parasol. The subject is illuminated by the harsh, vibrant neon lights of a futuristic Tokyo alleyway, contrasted by the soft glow of artificial cherry blossoms. The mood is melancholic yet beautiful. Captured with a 50mm portrait lens, shallow depth of field, sharp focus on the eye mechanics."
- **Negative prompt:** "traditional, historical, messy, poorly drawn, out of focus"
- **Tags:** cyberpunk, portrait, geisha, neon, robot
- **Style / Reference:** futuristic portrait, highly detailed, cinematic lighting
- **Composition:** medium portrait, rule of thirds, shallow depth of field
- **Color palette:** neon pinks, electric blues, gold, stark white
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260120_cyber-geisha.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing high-contrast neon lighting on shiny porcelain and metallic surfaces.

### Suggestion: Abandoned Spaceship Cargo Hold
- **Date:** 2026-01-20
- **Prompt:** "An expansive, cavernous interior of an abandoned spaceship cargo hold. The vast subject is filled with rusted, monolithic cargo containers stacked haphazardly. The lighting is dramatic and moody, with harsh, cold, volumetric blue light streaming in through a hull breach, cutting through thick atmospheric dust and fog. Emergency red strobe lights cast long, ominous shadows. The mood is tense, claustrophobic, and suspenseful. Captured with a 24mm lens to emphasize depth and scale."
- **Negative prompt:** "clean, new, bright, daylight, people, aliens, cozy"
- **Tags:** sci-fi, interior, abandoned, spaceship, atmospheric
- **Style / Reference:** cinematic sci-fi concept art, dark and gritty
- **Composition:** deep perspective, vanishing point, high contrast
- **Color palette:** rusted browns, cold steel greys, vibrant emergency reds, piercing blue light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260120_abandoned-cargo.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing volumetric fog, light shafts, rust textures, and atmospheric depth.

### Suggestion: Ethereal Floating Crystal Shards
- **Date:** 2026-01-20
- **Prompt:** "A mesmerizing arrangement of gigantic, semi-translucent, iridescent crystal shards floating effortlessly above a tranquil, mirror-like liquid surface. The crystalline subjects refract and split the soft, diffuse ambient light into a spectrum of pearlescent colors. The lighting is completely soft and omnidirectional, creating a dreamlike, serene, and magical mood. Captured with a standard 35mm lens, perfectly balanced symmetry, and a serene, still atmosphere."
- **Negative prompt:** "harsh shadows, rough textures, messy, cluttered, dark, gloomy"
- **Tags:** abstract, magical, crystals, serene, floating
- **Style / Reference:** surreal 3D render, minimalist, ethereal
- **Composition:** perfectly symmetrical, calm horizon line
- **Color palette:** pearlescent whites, soft pastels, iridescent pinks and blues
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260120_floating-crystals.jpg`
- **License / Attribution:** CC0
- **Notes:** Highly recommended for testing advanced refraction, iridescence, and sub-surface scattering materials.


### Suggestion: Luminescent Amethyst Geode
- **Date:** 2026-02-24
- **Prompt:** "A macro, photorealistic cross-section of a massive, cracked geode. Inside, thousands of jagged amethyst crystals emit a pulsating, bioluminescent purple and pink glow. The lighting is low-key, strictly internal from the glowing crystals, creating stark contrasts and deep shadows within the rocky exterior crust. The mood is mysterious and magical. Captured with a 100mm macro lens, ultra-detailed focus on the sharp edges and light refraction."
- **Negative prompt:** "flat, cartoon, brightly lit, blurry, low resolution"
- **Tags:** macro, nature, crystals, glowing, magical
- **Style / Reference:** photorealistic, macro photography, geological marvel
- **Composition:** close-up, rule of thirds, sharp center focus
- **Color palette:** deep purples, neon pinks, dark rocky greys
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260224_luminescent-geode.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing sub-surface scattering, refraction, and emissive materials on sharp geometric shapes.

### Suggestion: Cataclysmic Supernova Remnant
- **Date:** 2026-02-24
- **Prompt:** "A breathtaking, wide-angle shot of a cataclysmic supernova remnant expanding through deep space. The subject is a chaotic, swirling cloud of superheated plasma, glowing stellar dust, and intricate magnetic filaments. The lighting is extremely bright and dynamic, emanating from a blindingly white dwarf star at the center, casting dramatic light through the gaseous nebula. The mood is awe-inspiring and destructive. Captured as if by the James Webb Space Telescope, high dynamic range, cosmic scale."
- **Negative prompt:** "earth, planets, spaceships, cartoon, simple colors"
- **Tags:** sci-fi, space, nebula, cosmic, epic
- **Style / Reference:** astrophotography, hyper-detailed, Hubble/JWST style
- **Composition:** wide angle, expansive, centered explosion
- **Color palette:** fiery oranges, blinding whites, deep cosmic blues, vibrant magenta
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260224_cataclysmic-supernova.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex volumetric lighting, particle dispersion, and vibrant cosmic color palettes.

### Suggestion: Futuristic Neon Fireworks Festival
- **Date:** 2026-02-24
- **Prompt:** "A vibrant, long-exposure photograph of a massive fireworks display over a futuristic cyberpunk metropolis. The exploding fireworks are not traditional, but form intricate geometric patterns, glowing mandalas, and cascading digital glitches in the night sky. The city below is lit by millions of neon signs and flying vehicles. The mood is celebratory, energetic, and technologically advanced. Captured from a high vantage point overlooking the skyline, showcasing the scale of the explosions."
- **Negative prompt:** "daylight, ancient, traditional, quiet, blurry"
- **Tags:** cyberpunk, city, fireworks, night, energetic
- **Style / Reference:** long-exposure photography, cyberpunk aesthetic, digital art
- **Composition:** high angle, wide skyline view
- **Color palette:** electric cyan, neon magenta, bright yellow, dark night sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260224_neon-fireworks.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing bloom effects, light trails, and complex, glowing particle simulations over urban environments.

### Suggestion: Apocalyptic Volcanic Eruption
- **Date:** 2026-02-24
- **Prompt:** "An apocalyptic, highly detailed scene of a massive volcanic eruption tearing through a mountainous landscape at night. Rivers of glowing, viscous orange magma carve through the dark, jagged rocks, while a towering plume of thick black ash and blinding volcanic lightning dominates the sky. The lighting is harsh, chaotic, and completely dominated by the intense heat of the lava and sudden flashes of lightning. The mood is terrifying, raw, and powerful. Captured with a wide 24mm lens to show the sheer scale of the destruction."
- **Negative prompt:** "peaceful, daylight, green grass, calm, low detail"
- **Tags:** landscape, disaster, volcano, epic, dark
- **Style / Reference:** cinematic disaster concept art, highly dramatic, photorealistic
- **Composition:** wide angle, low angle looking up at the ash plume
- **Color palette:** intense magma orange, pitch black ash, blinding white lightning
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260224_volcanic-eruption.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing emissive fluid dynamics (lava), thick volumetric smoke, and dramatic contrast lighting.

### Suggestion: Enchanted Bioluminescent Forest
- **Date:** 2026-02-24
- **Prompt:** "A serene, mystical shot deep within an ancient, enchanted forest at night. The dense canopy blocks out all moonlight, but the forest floor is entirely illuminated by thousands of glowing, bioluminescent mushrooms, ferns, and floating ethereal spores. The lighting is soft, magical, and varied in color, with gentle cyan, green, and purple hues emanating from the flora. The mood is peaceful, magical, and untouched by humans. Captured with a 35mm lens, soft focus background, emphasizing the glowing details in the foreground."
- **Negative prompt:** "sunlight, harsh shadows, scary, modern, people, animals"
- **Tags:** fantasy, nature, forest, glowing, magical
- **Style / Reference:** fantasy concept art, ethereal, highly detailed nature
- **Composition:** ground-level perspective, shallow depth of field
- **Color palette:** glowing cyans, soft greens, bioluminescent purples, dark forest greens
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260224_bioluminescent-forest.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing soft, multi-colored ambient occlusion, particle systems (spores), and lush, glowing vegetation.

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
- **Styles:** Geometric Abstraction, Brutalist Web Design, Neoclassicism, Metaphysical Art, Hard Edge Painting, Tachisme, Neo-Geo, Rayograph, Hard Surface Modeling, Crosshatching, Ashcan School, Northern Renaissance, Italian Futurism, Deconstructivism, Tonalism, Op Art, Low Key Photography, Art Nouveau, Memphis Design, Suprematism, Fauvism, Vorticism, Dadaism, Tenebrism, Pixel Art, Risograph, Synthwave, Ukiyo-e, Biopunk, Gothcore, Retrowave, Cyberprep, Digital Cubism. Afrofuturism.
- **Materials:** Cork, Chainmail, Fur, Amber, Slime, Brass, Carbon Fiber, Generative Fluid Simulation, Sand, Silicone, Burlap, Titanium, Latex, Basalt, Velcro, Sandpaper, Cellophane, Aluminum Foil, Porcelain, Terracotta, Chiffon, Tweed, Granite, Topaz, Organza, Cracked Clay, Slate, Kevlar, Perovskite, Velvet, Aerogel, Bismuth, Nacre, Damascus Steel, Onyx, Liquid Metal. Graphene.
- **Subjects:** Diorama, Nebula, Quasar, Pulsar, Tsunami, Solar Punk City, Quantum Computer, Space Station, Ancient Ruins, Meteor Crater, Swamp, Glacier, Canyon, Fjord, Oasis, Ant Farm, Beehive, Termite Mound, Beaver Dam, Bird's Nest, Spider Web, Cocoon, Neutron Star Collision, Kaleidoscope, Holographic Statue, Tide Pool, Sundog, Hydroelectric Dam, Oil Rig, Wind Tunnel, Supervolcano, Magnetar, Origami, Circuit Board Macro, Rogue Wave, Skyhook, Orbital Ring, Cybernetic Implant, Crystal Cave, Bioluminescent Fungi, Coral Reef Megastructure, Dyson Swarm, Bioluminescent Cavern. Subterranean Garden, Clockwork Universe, Time Machine.

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
