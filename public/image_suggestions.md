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

### Suggestion: Aerogel Geometric Abstraction Quasar
- **Date:** 2026-03-09
- **Prompt:** "A mesmerizing visualization of a quasar represented through geometric abstraction, constructed entirely of translucent, weightless aerogel blocks and spheres. The central subject, a stylized quasar, emits a blindingly bright, pure white and cyan light that diffuses beautifully through the porous aerogel material. The lighting is extremely high-contrast, with deep, crushing blacks in the void surrounding the luminous core, creating a stark, metaphysical mood. Captured with a sharp, medium format lens, perfectly balanced symmetrical composition."
- **Negative prompt:** "organic shapes, realistic stars, messy, blurry, low contrast, complex textures"
- **Tags:** sci-fi, abstract, space, quasar, geometric
- **Style / Reference:** minimalist 3D render, metaphysical art
- **Composition:** perfectly symmetrical, centered, high contrast
- **Color palette:** deep black void, pure white core, cyan and deep blue refractions
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260309_aerogel-quasar.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the interaction of extreme light sources with highly scattering, low-density translucent materials like aerogel.

### Suggestion: Biopunk Bioluminescent Fungi Swamp
- **Date:** 2026-03-09
- **Prompt:** "A macro, photorealistic shot deep within a murky, overgrown swamp teeming with gigantic, pulsating bioluminescent fungi. The fungi subjects are engineered with complex biopunk aesthetics, featuring semi-translucent, vein-covered caps that drip viscous, glowing green slime. The lighting is exclusively from the fungi's eerie bioluminescence, casting sickly green and vibrant magenta hues onto the wet, dark surroundings. The mood is toxic, alien, and darkly beautiful. Captured with a macro lens, incredibly shallow depth of field, focusing on a single dripping slime droplet."
- **Negative prompt:** "sunlight, daylight, dry, pleasant, clean, low-res"
- **Tags:** biopunk, nature, macro, glowing, alien
- **Style / Reference:** biopunk concept art, photorealistic macro photography
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** toxic greens, vibrant magentas, deep dark browns
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260309_biopunk-fungi.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing sub-surface scattering on organic materials, glowing viscous fluids (slime), and extreme macro depth of field.

### Suggestion: Graphene Dyson Swarm Construction
- **Date:** 2026-03-09
- **Prompt:** "An epic, wide-angle view of a colossal Dyson swarm under construction around a turbulent, young yellow dwarf star. The swarm consists of millions of hexagonal, mirror-like solar collectors made of incredibly thin, shimmering graphene. The central star casts blinding, harsh, unattenuated light, creating deep, sharp shadows on the immense structures. The mood is awe-inspiring, showcasing the sheer scale of a Type II civilization. Captured with an ultra-wide cinematic lens to emphasize vastness and scale."
- **Negative prompt:** "planets, atmosphere, clouds, soft light, small scale, simple"
- **Tags:** sci-fi, space, megastructure, epic
- **Style / Reference:** hard sci-fi concept art, cinematic space visualization
- **Composition:** vast perspective, dynamic angles, dwarfing scale
- **Color palette:** intense solar yellow, pure stark white, deep void black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260309_graphene-dyson-swarm.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing massive arrays of reflective, ultra-thin materials and harsh directional lighting without atmospheric scattering.

### Suggestion: Bismuth Subterranean Garden
- **Date:** 2026-03-09
- **Prompt:** "A breathtaking, wide shot of a hidden subterranean garden where all the flora, instead of organic plants, are massive, naturally forming hopper crystals of iridescent bismuth. The stair-stepped, maze-like bismuth 'trees' and 'bushes' reflect a stunning array of rainbow colors—pinks, greens, golds, and blues. The lighting is provided by a gentle, diffuse, unknown underground source, causing the metallic surfaces to shimmer magically. The mood is serene, hidden, and otherworldly. Captured with a standard wide lens, deep focus to capture the intricate geometric details."
- **Negative prompt:** "green plants, dirt, organic, ugly, rough, dark"
- **Tags:** fantasy, landscape, underground, crystal, geometric
- **Style / Reference:** fantastical landscape, surrealism, hyper-detailed 3D environment
- **Composition:** wide landscape, deep depth of field, meandering path
- **Color palette:** highly iridescent rainbow (metallic pinks, blues, greens, golds)
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260309_bismuth-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** An ultimate test for iridescence, complex metallic reflections, and natural geometric (hopper crystal) generation.

### Suggestion: Damascus Steel Time Machine
- **Date:** 2026-03-09
- **Prompt:** "A detailed, dramatic portrait of an elaborate, intricate time machine mechanism resting in a dark, dusty Victorian laboratory. The central rings and gears of the subject are forged entirely from exquisite, patterned Damascus steel, featuring deep, contrasting waves of dark and light grey metal. The lighting is dramatic tenebrism, with a single, intense beam of warm amber light illuminating the complex patterns of the steel while the rest of the room falls into deep shadow. The mood is mysterious, antique, and powerful. Captured with a 50mm lens, sharp focus on the central temporal core."
- **Negative prompt:** "modern, clean, bright, plastic, futuristic, blurry"
- **Tags:** steampunk, mechanism, still-life, complex
- **Style / Reference:** high-contrast still-life photography, intricate mechanical design
- **Composition:** dramatic lighting, subject centered, dark background
- **Color palette:** dark greys, silver, warm amber light, deep blacks
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260309_damascus-time-machine.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the generation of complex, flowing material patterns (Damascus steel) under highly dramatic, high-contrast lighting (Tenebrism).

### Suggestion: Synthwave Holographic Statue
- **Date:** 2026-03-10
- **Prompt:** "A giant, glowing holographic statue of an ancient deity projected over a sleek, Synthwave-style cyberpunk plaza. The statue appears to be made of rippling, glitchy liquid metal that shifts between neon magenta and cyan. The lighting is extremely vibrant, emanating mostly from the hologram itself and the retro-futuristic grid of the plaza below. The mood is nostalgic yet highly advanced, capturing a retro-futuristic metropolis at midnight. Captured with a low angle using a wide 24mm lens, emphasizing the colossal scale of the projection against a starless night sky."
- **Negative prompt:** "daylight, dull colors, natural, realistic, organic, low contrast"
- **Tags:** synthwave, holographic, statue, neon, cyberpunk
- **Style / Reference:** synthwave digital art, retro-futuristic, 80s aesthetic
- **Composition:** low angle looking up, dramatic scale
- **Color palette:** neon magenta, electric cyan, deep grid purple, stark black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_synthwave-hologram.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of holographic transparency combined with liquid metal reflections and vibrant neon glow.

### Suggestion: Tonalist Rogue Wave
- **Date:** 2026-03-10
- **Prompt:** "An incredibly massive, terrifying rogue wave cresting in the middle of a violently stormy ocean. The water is thick, dark, and churning, with intricate foam patterns and spray caught in the wind. The lighting is heavily subdued and moody, inspired by featuring a limited palette of deep oceanic greens and charcoal greys under a heavy, overcast sky. The mood is ominous, desolate, and entirely focused on the raw power of nature. Captured with a telephoto lens to compress the distance and make the towering wave wall feel claustrophobic and inevitable."
- **Negative prompt:** "sunny, bright sky, tropical, boats, people, vibrant colors"
- **Tags:** ocean, rogue wave, storm, nature, moody
- **Style / Reference:** tonalism painting, moody seascape photography
- **Composition:** tight framing on the wave crest, horizon line low
- **Color palette:** deep sea green, charcoal grey, muted slate blue, stark white foam
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260310_rogue-wave.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing chaotic fluid dynamics, detailed foam generation, and moody, low-contrast atmospheric lighting.

### Suggestion: Cyberprep Carbon Fiber Implant
- **Date:** 2026-03-10
- **Prompt:** "A pristine, ultra-macro shot of a high-end cybernetic implant being seamlessly integrated into human skin. The implant's casing is made of flawless, intricately woven carbon fiber with polished titanium accents. The environment is a sterile, brightly lit Cyberprep medical facility. The lighting is clean, diffused, and surgical, highlighting the micro-textures of the skin and the perfect geometric weave of the carbon fiber. The mood is utopian, precise, and sophisticated. Captured with an extreme macro 100mm lens, razor-thin depth of field focusing exactly on the point of integration."
- **Negative prompt:** "gritty, dirty, blood, cyberpunk, dark, dystopian, rusty"
- **Tags:** cyberprep, macro, cybernetic, medical, futuristic
- **Style / Reference:** photorealistic macro photography, clean futurism
- **Composition:** extreme close-up, rule of thirds, very shallow depth of field
- **Color palette:** sterile white, brushed silver, matte black carbon fiber, natural skin tones
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_cybernetic-implant.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the generation of precise repeating textures (carbon fiber weave) alongside realistic human skin micro-details in bright lighting.

### Suggestion: Op Art Topaz Crystal Cave
- **Date:** 2026-03-10
- **Prompt:** "A mind-bending view deep inside a surreal crystal cave composed entirely of perfectly faceted, giant golden topaz formations. The arrangement of the crystals creates a natural Op Art optical illusion, distorting perspective and depth. The lighting is warm and intensely refractive, bouncing endlessly between the highly polished, geometric facets of the topaz, creating dizzying infinite reflections. The mood is hypnotic, disorienting, and luxurious. Captured with a wide-angle 14mm lens, deep focus to capture the labyrinth of infinite reflections."
- **Negative prompt:** "dull, organic rock, dirt, soft edges, natural cave, dark"
- **Tags:** abstract, crystal, cave, optical illusion, geometric
- **Style / Reference:** op art, surreal geometric 3D render, hyper-detailed
- **Composition:** deep symmetrical perspective, endless tunnel effect
- **Color palette:** intense warm gold, amber, blinding white highlights, deep warm brown
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260310_topaz-crystal-cave.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for pushing multiple bounce refractions, internal crystal light scattering, and sharp geometric optical illusions.

### Suggestion: Art Nouveau Bioluminescent Cavern
- **Date:** 2026-03-10
- **Prompt:** "An exquisite, wide shot of a breathtaking bioluminescent cavern where the glowing flora naturally grows into elegant, sweeping curves and whiplash lines characteristic of Art Nouveau design. The massive glowing vines and lily-like fungi are encased in translucent, fossilized amber, emitting a soft, warm golden and ethereal blue light. The lighting is magical and completely natural, casting intricate, ornate shadows on the smooth cavern walls. The mood is romantic, enchanted, and elegantly organic. Captured with a 35mm lens, balanced lighting with a slight soft-focus bloom on the highlights."
- **Negative prompt:** "straight lines, modern, harsh lighting, daylight, messy, chaotic"
- **Tags:** fantasy, nature, underground, bioluminescent, elegant
- **Style / Reference:** art nouveau illustration, photorealistic fantasy environment
- **Composition:** sweeping curves leading the eye, balanced asymmetry
- **Color palette:** ethereal glowing blue, rich warm amber, deep shadowy greens
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_bioluminescent-cavern.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the AI's ability to naturally form specific architectural styles (Art Nouveau curves) out of organic, glowing plant matter and translucent amber.


### Suggestion: Italian Futurism Metropolis Speed
- **Date:** 2026-03-10
- **Prompt:** "A chaotic, dynamic metropolis depicted in the style of Italian Futurism, emphasizing speed, technology, and violent movement. Abstract, jagged geometric shapes in vibrant reds, yellows, and blacks interlock to form towering skyscrapers and speeding locomotives. The composition is fragmented and kaleidoscopic, capturing the blur of motion. Stark, high-contrast directional lighting highlights the aggressive, mechanical forms. The mood is energetic, overwhelming, and hyper-modern. Shot with a wide-angle perspective to distort scale and enhance the feeling of speed."
- **Negative prompt:** "calm, peaceful, traditional, realistic, soft, blurry, organic, nature"
- **Tags:** art, italian futurism, abstract, city, speed
- **Style / Reference:** Italian Futurism, Umberto Boccioni, Giacomo Balla
- **Composition:** dynamic diagonals, fragmented and intersecting planes
- **Color palette:** vibrant reds, yellows, blacks, steel greys
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_italian-futurism-city.jpg`
- **License / Attribution:** Public Domain concept
- **Notes:** Tests the model's ability to render specific historical abstract art movements and convey motion through static fragmentation.

### Suggestion: Bioluminescent Tsunami Wave
- **Date:** 2026-03-10
- **Prompt:** "A massive, towering tsunami wave caught frozen in time just before it crashes down. The water is entirely bioluminescent, glowing intensely with neon blues and purples in the dark of night. Within the translucent wall of water, silhouetted shapes of giant marine life can be seen swirling. The sky above is dark and stormy with dramatic lightning illuminating the crest of the wave. The mood is terrifying yet awe-inspiring and beautiful. Captured with a low camera angle, wide lens, and high shutter speed to freeze the water droplets."
- **Negative prompt:** "daylight, calm water, small wave, shore, people, boats, sunny"
- **Tags:** nature, ocean, tsunami, bioluminescent, dramatic
- **Style / Reference:** photorealistic, long exposure photography style
- **Composition:** imposing, low angle, wave dominating the frame
- **Color palette:** neon blues, deep purples, dark greys, bright white lightning flashes
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_bioluminescent-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing water rendering, transparency, and intense glowing emission under dark environmental lighting.

### Suggestion: Bismuth Crystal Cavern Megastructure
- **Date:** 2026-03-10
- **Prompt:** "A vast underground cavern composed entirely of gigantic, iridescent bismuth crystals. The hopper-like, step-patterned formations create an alien, geometric architecture. The metallic surfaces reflect a dazzling rainbow of thin-film interference colors—pinks, greens, golds, and blues. A small, glowing orb floats in the center, casting hard, directional light that highlights the sharp, right-angled crystal edges and creates deep, colorful reflections. The mood is mysterious, quiet, and otherworldly. Shot with a sharp focus macro lens, emphasizing the microscopic-looking geometric details scaled up to massive proportions."
- **Negative prompt:** "organic shapes, rounded, earth tones, soft lighting, daylight, water"
- **Tags:** environment, crystals, bismuth, geometric, iridescent
- **Style / Reference:** hyper-realistic, scientific macro photography scaled up
- **Composition:** symmetrical, framing the central light source, deep depth of field
- **Color palette:** iridescent rainbow colors, metallic reflections, dark background shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_bismuth-megastructure.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating metallic rendering, complex geometric displacement, and thin-film interference shaders.

### Suggestion: Origami Paper Dragon Flight
- **Date:** 2026-03-10
- **Prompt:** "An intricately folded origami dragon soaring through a sky filled with stylized, paper-cutout clouds. The dragon is made of high-quality, textured golden foil paper with sharp, precise creases. Sunlight catches the metallic surface of the paper, creating bright glints and contrasting deep shadows in the folds. The environment is entirely constructed from different types of paper (parchment, tissue, cardstock). The mood is whimsical, artistic, and delicate. Captured with sharp focus, highlighting the fibrous texture of the paper and the sharp geometric folds."
- **Negative prompt:** "real dragon, scales, fire, flesh, realistic clouds, photorealistic sky"
- **Tags:** art, origami, papercraft, dragon, whimsical
- **Style / Reference:** papercraft art, macro studio photography
- **Composition:** dynamic flight pose, rule of thirds, angled upwards
- **Color palette:** gold foil, off-white parchment, pale blue tissue paper
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260310_origami-dragon.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing varied material textures (foil vs rough paper) and sharp geometric shadowing.

### Suggestion: Afrofuturism Spaceport Market
- **Date:** 2026-03-10
- **Prompt:** "A bustling, vibrant spaceport marketplace designed in an Afrofuturism aesthetic. The architecture blends highly advanced, sleek spaceship technology with traditional African patterns, shapes, and materials like woven fibers, carved wood, and brass. People in vibrant, technologically enhanced traditional clothing navigate the busy market under the glow of holographic neon signs displaying geometric tribal motifs. The lighting is bright, sunny, and colorful, with dynamic shadows cast by overhead canopies. The mood is energetic, culturally rich, and highly advanced. Captured with a standard 50mm lens, eye-level perspective."
- **Negative prompt:** "dystopian, gloomy, cyberpunk, plain, boring, monochromatic"
- **Tags:** sci-fi, afrofuturism, market, city, vibrant
- **Style / Reference:** cinematic concept art, highly detailed, vibrant colors
- **Composition:** busy street level view, deep perspective down the market aisle
- **Color palette:** rich golds, vibrant reds and greens, sleek silver tech, neon holograms
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_afrofuturism-market.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for testing complex crowd scenes, blending organic and metallic materials, and vibrant, multi-colored lighting setups.

### Suggestion: Neoclassical Space Station
- **Date:** 2026-03-10
- **Prompt:** "A grand, Neoclassical space station interior featuring massive, fluted marble columns and a domed ceiling with a vast skylight revealing a starry cosmos. The architecture is pristine and elegant, blending ancient Roman aesthetics with highly advanced, sleek silver technology. The lighting is ethereal and soft, emanating from hidden cove lights and starlight from above, casting long, dramatic shadows. The mood is awe-inspiring, intellectual, and majestic. Captured with a wide-angle 24mm lens, emphasizing the symmetry and the immense scale of the orbital structure."
- **Negative prompt:** "dystopian, rusty, dirty, cramped, modern, boring, people"
- **Tags:** sci-fi, architecture, neoclassical, space, grand
- **Style / Reference:** neoclassical architecture, hyper-detailed 3D render
- **Composition:** symmetrical, deep perspective, low angle looking up
- **Color palette:** pristine white marble, silver chrome, deep cosmic blue, soft warm gold
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_neoclassical-space-station.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of historical architectural styles with futuristic settings and soft, indirect lighting.

### Suggestion: Titanium Termite Mound Megastructure
- **Date:** 2026-03-10
- **Prompt:** "A colossal, towering termite mound that has been cybernetically enhanced or entirely constructed from brushed titanium and complex metallic alloys. The structure dominates a desolate, crimson desert landscape under a harsh, glaring sun. The titanium surface is intricately textured with natural, organic-looking ventilation flutes that gleam brilliantly in the sunlight. The mood is alien, imposing, and industrial. Captured with a 35mm lens from a low vantage point to make the structure look incredibly massive against the sky."
- **Negative prompt:** "organic dirt, wood, lush green, soft, blurry, small"
- **Tags:** sci-fi, landscape, alien, titanium, megastructure
- **Style / Reference:** hard surface modeling, photorealistic sci-fi landscape
- **Composition:** low angle, rule of thirds, towering presence
- **Color palette:** brushed titanium grey, glaring white highlights, deep crimson sand, pale sky
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260310_titanium-termite-mound.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing complex, organic-shaped hard surface modeling and harsh, direct sunlight reflections on brushed metal.

### Suggestion: Velvet Kaleidoscope Dreamscape
- **Date:** 2026-03-10
- **Prompt:** "A mesmerizing, surreal dreamscape composed entirely of intricate, symmetrical kaleidoscope patterns made from plush, luxurious velvet. The environment is soft and tactile, with folds and ripples of velvet forming impossible, Escher-like geometry. The lighting is soft and moody, gently grazing the texture of the fabric to highlight its plushness and depth. The mood is hypnotic, comforting, and deeply surreal. Captured with a medium 50mm lens, sharp focus on the central repeating pattern while the edges softly blur into darkness."
- **Negative prompt:** "hard surfaces, metallic, sharp edges, bright daylight, realistic landscape"
- **Tags:** abstract, surreal, velvet, kaleidoscope, soft
- **Style / Reference:** surreal abstract art, highly tactile 3D render
- **Composition:** perfectly symmetrical, mandala-like, shallow depth of field
- **Color palette:** deep royal purple, rich burgundy, soft emerald green, velvety black shadows
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260310_velvet-kaleidoscope.jpg`
- **License / Attribution:** CC0
- **Notes:** An excellent test for generating soft, tactile fabric textures (velvet) and complex, symmetrical repeating patterns.

### Suggestion: Pixel Art Hydroelectric Dam
- **Date:** 2026-03-10
- **Prompt:** "A massive, brutalist hydroelectric dam nestled in a lush, mountainous gorge, rendered entirely in highly detailed, isometric pixel art. The water roaring through the spillways is animated with crisp, distinct pixels, creating a dynamic contrast with the static concrete of the dam. The lighting simulates an overcast, moody afternoon, with distinct pixel-art shading and dithering techniques. The mood is nostalgic, epic, and slightly melancholic. Captured from a fixed isometric angle, ensuring perfect grid alignment and sharp pixel edges."
- **Negative prompt:** "photorealistic, 3D render, smooth, blurry, high resolution textures, curves"
- **Tags:** pixel art, landscape, isometric, dam, brutalist
- **Style / Reference:** 16-bit era pixel art, modern high-detail pixel illustration
- **Composition:** isometric perspective, wide landscape view
- **Color palette:** concrete greys, muted forest greens, deep river blues, bright white pixel water foam
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_pixel-art-dam.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the model's capability to strictly adhere to pixel art aesthetics, isometric perspective, and dithering techniques.

### Suggestion: Deconstructivism Cork Oasis
- **Date:** 2026-03-10
- **Prompt:** "A bizarre, peaceful oasis where all the architectural structures are designed in a chaotic, fragmented Deconstructivism style, yet built entirely from natural, textured cork. The fragmented, slanted geometric shapes of the cork buildings contrast beautifully with a small, perfectly still pool of crystal-clear water and a few sparse, exotic plants. The lighting is bright, midday desert sun, casting sharp, complex shadows from the disjointed structures onto the sand. The mood is avant-garde, serene, and highly unusual. Captured with a wide 24mm lens to emphasize the chaotic angles of the architecture."
- **Negative prompt:** "traditional architecture, straight walls, metal, glass, dark, moody"
- **Tags:** surreal, architecture, deconstructivism, cork, oasis
- **Style / Reference:** deconstructivist architecture, surreal architectural visualization
- **Composition:** chaotic yet balanced geometry, central water feature
- **Color palette:** warm cork browns, sandy beige, bright turquoise water, stark black shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260310_deconstructivism-cork-oasis.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the combination of chaotic architectural styles (Deconstructivism) with unusual, specific natural materials (cork).

### Suggestion: Clockwork Universe Cosmos
- **Date:** 2026-03-24
- **Prompt:** "A majestic, wide-angle view of a Clockwork Universe, where the cosmos is driven by colossal, interwoven brass gears and gleaming astrolabes instead of gravity. The celestial subject features a giant glowing sun at its core, surrounded by mechanical planetary orbits. The lighting is cinematic, with blinding, god-ray shafts of golden sunlight glinting off the polished metal surfaces in the dark void of space. The mood is awe-inspiring, intricate, and philosophical. Captured with a wide 24mm lens to emphasize the staggering scale of the cosmic machinery."
- **Negative prompt:** "organic, empty space, simple, messy, blurry, realistic stars"
- **Tags:** sci-fi, steampunk, space, clockwork, cosmic
- **Style / Reference:** steampunk concept art, hyper-detailed 3D render
- **Composition:** wide angle, deep depth of field, centered sun
- **Color palette:** polished brass, warm gold, deep cosmic black, glowing amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260324_clockwork-universe.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing highly reflective metallic materials and intricate, interlocking geometric structures.

### Suggestion: Isometric Room
- **Date:** 2026-03-24
- **Prompt:** "A vibrant, playful isometric view of a quirky living room interior entirely decorated in the 1980s style. The subject features bold, clashing geometric furniture, zigzag patterns, and terrazzo floors. The lighting is bright, flat, and even, resembling a high-end studio lighting setup that eliminates deep shadows and highlights the vivid, saturated colors. The mood is energetic, retro, and whimsical. Captured with an orthographic camera perspective to emphasize the precise geometric layout and flat graphic qualities."
- **Negative prompt:** "dark, moody, realistic, muted colors, messy, organic shapes"
- **Tags:** retro, interior, memphis design, isometric, colorful
- **Style / Reference:** 1980s Memphis Group, isometric 3D illustration, pop art
- **Composition:** isometric perspective, centered room layout
- **Color palette:** bright cyan, hot pink, vivid yellow, black and white patterns
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260324_memphis-design-room.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing flat, even lighting, high-contrast color palettes, and strict geometric shapes without perspective distortion.

### Suggestion: Ancient Labyrinth
- **Date:** 2026-03-24
- **Prompt:** "A dusty, sun-drenched view deep inside an ancient, infinite labyrinth constructed completely from unglazed, textured terracotta bricks and clay tiles. The subject features tall, imposing walls with intricate, geometric Mayan-inspired carvings. The lighting is harsh, midday desert sunlight casting sharp, deep, and dramatic black shadows across the rough clay surfaces. The mood is mysterious, desolate, and archaic. Captured with a 35mm lens, deep focus, showing the endless, repeating corridors vanishing into the heat haze."
- **Negative prompt:** "wet, modern, shiny, metal, grass, cold, blue"
- **Tags:** architecture, ancient, labyrinth, terracotta, desert
- **Style / Reference:** archaeological visualization, photorealistic ancient ruins
- **Composition:** one-point perspective, vanishing point, leading lines
- **Color palette:** warm baked terracotta, dusty orange, deep black shadows, stark blue sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260324_terracotta-labyrinth.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of rough, porous clay textures (terracotta) under harsh, high-contrast directional sunlight.

### Suggestion: Graphene Orbital Ring City
- **Date:** 2026-03-24
- **Prompt:** "An epic, sweeping view of a massive Orbital Ring megastructure encircling a lush, green Earth-like planet. The ring itself is constructed from sleek, dark, ultra-strong graphene woven into an impossibly thin yet immense structure. The subject is dotted with glowing city lights and sprawling spaceports. The lighting features a dramatic sunrise cresting over the planet's horizon, casting a blinding white glare and long shadows across the graphene surface. The mood is utopian, vast, and technologically supreme. Captured with a wide-angle cinematic lens from low Earth orbit, emphasizing planetary scale."
- **Negative prompt:** "dystopian, broken, rusty, small, low-res, cartoon"
- **Tags:** sci-fi, megastructure, space, orbital ring, epic
- **Style / Reference:** hard sci-fi environment design, cinematic space art
- **Composition:** curved horizon, extreme wide angle, dynamic lighting
- **Color palette:** dark matte graphene grey, vibrant earth greens and blues, blinding solar white
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260324_orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of massive scale, planetary curvature, and the matte, light-absorbing properties of a massive graphene structure.

### Suggestion: Tide Pool Macro
- **Date:** 2026-03-24
- **Prompt:** "A stunning, ultra-macro photograph of a shallow tide pool basin where the rocky surface is entirely coated in shimmering, iridescent nacre (mother-of-pearl). The subject is half-submerged in crystal-clear water, refracting the sunlight into a spectacular array of pearlescent pastels. The lighting is bright, natural sunlight, catching the micro-ridges of the nacre to reveal its rainbow interference patterns. The mood is serene, delicate, and microscopic. Captured with an extreme macro 100mm lens, very shallow depth of field, blurring the background into a soft, glowing bokeh."
- **Negative prompt:** "dark, muddy, gross, rough rock, wide angle, people"
- **Tags:** macro, nature, nacre, iridescent, water
- **Style / Reference:** photorealistic macro photography, nature documentary style
- **Composition:** extreme close-up, rule of thirds, beautiful bokeh
- **Color palette:** pearlescent pinks, soft baby blues, shimmering silver, clear water
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260324_nacre-tide-pool.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating sub-surface scattering, thin-film iridescent interference on organic shapes, and clear water refraction.

### Suggestion: Ukiyo-e Solarpunk Cityscape
- **Date:** 2026-05-15
- **Prompt:** "A majestic Solarpunk city built into a steep mountainside, depicted in a traditional Japanese Ukiyo-e woodblock print style. The city is constructed with intricate porcelain towers, bamboo scaffolding, and lush vertical gardens. The lighting features a flat, stylized morning sun piercing through stylized, swirling mist. The mood is serene, harmonious, and historical yet futuristic. Captured with the flat perspective typical of classic Ukiyo-e prints, focusing on bold outlines and solid color blocks."
- **Negative prompt:** "photorealistic, 3D render, modern, dark, dystopian, messy, cluttered"
- **Tags:** solarpunk, city, ukiyo-e, retro-futuristic, serene
- **Style / Reference:** Ukiyo-e traditional woodblock print, Hokusai-inspired
- **Composition:** flat perspective, wide landscape, rule of thirds
- **Color palette:** indigo blue, muted vermilion, pale yellow, lush bamboo green
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260515_ukiyoe-solarpunk.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the model's ability to blend a specific historical art style (Ukiyo-e) with a futuristic subject (Solarpunk).

### Suggestion: Risograph Glacial Fjord
- **Date:** 2026-05-15
- **Prompt:** "A massive, towering glacier calving into a deep, freezing fjord, rendered entirely in the style of a vintage Risograph print. The icy subject is heavily textured with distinctive riso dot halftones, misregistration artifacts, and vibrant overlapping ink layers. The lighting is stylized and graphic, relying on the high-contrast interplay of only three ink colors. The mood is raw, graphic, and nostalgic. Captured with a wide-angle perspective, emphasizing the massive scale of the ice wall against the flat, textured sky."
- **Negative prompt:** "photorealistic, smooth gradients, 3D render, perfectly aligned, high resolution"
- **Tags:** landscape, glacier, risograph, graphic, vintage
- **Style / Reference:** Risograph printing, halftone dot pattern, graphic illustration
- **Composition:** wide landscape, bold graphic shapes
- **Color palette:** fluorescent pink, bright teal, sunflower yellow, off-white paper texture
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_risograph-glacier.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating stylistic constraints, specifically the generation of halftone dot patterns and limited ink palettes.

### Suggestion: Fauvism Mangrove Swamp
- **Date:** 2026-05-15
- **Prompt:** "A dense, overgrown mangrove swamp depicted in a wild, energetic Fauvism style. The twisted roots and thick, dripping slime of the swamp are painted with bold, non-naturalistic colors and thick, aggressive brushstrokes. The lighting is completely arbitrary and expressive, ignoring realistic shadows in favor of vibrant color contrasts. The mood is wild, untamed, and emotionally charged. Captured with a chaotic, immersive perspective as if standing waist-deep in the vibrant, murky water."
- **Negative prompt:** "realistic colors, photorealistic, subtle, calm, detailed textures, boring"
- **Tags:** nature, swamp, fauvism, abstract, vibrant
- **Style / Reference:** Henri Matisse inspired, thick impasto oil paint
- **Composition:** dense, immersive, lack of deep perspective
- **Color palette:** unnatural vivid reds, toxic greens, bright oranges, deep purples
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260515_fauvism-swamp.jpg`
- **License / Attribution:** Public Domain concept
- **Notes:** Tests the AI's understanding of art movements that rely on arbitrary, emotionally driven color palettes rather than realism.

### Suggestion: Crosshatched Subterranean Canyon
- **Date:** 2026-05-15
- **Prompt:** "A colossal, seemingly bottomless subterranean canyon composed entirely of jagged slate and cracked clay, rendered completely through meticulous, dense ink crosshatching. The rocky subject is detailed with thousands of fine, intersecting black lines that create depth, shadow, and texture. The lighting is harsh and directional, emanating from a single glowing fissure deep below, creating extreme contrast between the stark white paper and the deep, ink-black shadows. The mood is oppressive, detailed, and masterful. Captured with a deep perspective, drawing the eye down into the abyss."
- **Negative prompt:** "colors, grayscale gradients, smooth, photorealistic, photography, soft"
- **Tags:** landscape, canyon, crosshatching, ink, underground
- **Style / Reference:** traditional ink drawing, dense crosshatching, Gustave Doré inspired
- **Composition:** deep vertical perspective, stark contrast
- **Color palette:** pure black ink, stark white paper
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260515_crosshatched-canyon.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for pushing the model's ability to generate structural depth and shading using only fine, intersecting line art.

### Suggestion: Metaphysical Quantum Computer
- **Date:** 2026-05-15
- **Prompt:** "A highly advanced, sprawling quantum computer installation placed inexplicably in a deserted, sunbaked Italian piazza, rendered in the haunting, enigmatic style of Metaphysical Art. The sleek silicone and kevlar components of the futuristic computer contrast sharply with the ancient, arched arcades and long, dramatic afternoon shadows. The lighting is stark, melancholic, and theatrical, freezing the bizarre juxtaposition in a timeless moment. The mood is eerie, dreamlike, and profoundly still. Captured with a deep, surreal perspective and a low horizon line."
- **Negative prompt:** "busy, people, realistic sci-fi, dark, neon, cyberpunk, cluttered"
- **Tags:** sci-fi, surreal, metaphysical, quantum computer, eerie
- **Style / Reference:** Giorgio de Chirico inspired, surrealism
- **Composition:** deep perspective, low horizon, extreme long shadows
- **Color palette:** sunbaked terracotta, muted olive green, deep sky blue, stark black shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_metaphysical-quantum.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates the combination of highly advanced technological subjects with deeply historical, surreal, and melancholic art styles.


### Suggestion: Perovskite Meteor Crater
- **Date:** 2026-06-01
- **Prompt:** "A massive, ancient meteor crater situated in a desolate, rocky wasteland. The interior of the crater is lined with gigantic, glowing perovskite crystals that emit a pulsating, ethereal green and blue light. The lighting is low-key and dramatic, relying on the bioluminescent glow of the crystals contrasting with the deep shadows of the crater walls. The mood is eerie, alien, and majestic. Captured with a wide-angle 14mm lens from the rim of the crater, emphasizing the vast scale and depth of the impact site."
- **Negative prompt:** "daylight, sun, flat, smooth, modern, buildings"
- **Tags:** landscape, sci-fi, meteor crater, crystals, glowing
- **Style / Reference:** photorealistic sci-fi environment, hyper-detailed 3D render
- **Composition:** wide landscape, deep perspective, rule of thirds
- **Color palette:** dark slate grey, glowing neon green, ethereal blue, stark black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260601_perovskite-crater.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing luminescent crystal textures and extreme scale landscapes.

### Suggestion: Dadaism Wind Tunnel
- **Date:** 2026-06-01
- **Prompt:** "A chaotic and absurd Dadaism collage featuring the interior of an industrial wind tunnel testing a vintage Victorian armchair. The composition is disjointed, utilizing cut-out photographs, mismatched newspaper clippings, and bold, jarring typography. The lighting is harsh and mismatched, emphasizing the cutout nature of the elements with hard drop shadows. The mood is nonsensical, satirical, and rebellious. Captured with a flat, top-down perspective, emphasizing the two-dimensional collage aesthetic against a stark white background."
- **Negative prompt:** "realistic, 3d render, smooth, orderly, symmetric, photography"
- **Tags:** abstract, collage, dadaism, industrial, absurd
- **Style / Reference:** Dadaism art movement, Hannah Höch inspired, mixed media collage
- **Composition:** flat layout, fragmented, asymmetrical
- **Color palette:** vintage sepia, stark black and white, bold primary color accents
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260601_dadaism-windtunnel.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the model's ability to create non-realistic, flat, cutout collage styles and absurd juxtapositions.

### Suggestion: Basalt Gothcore Cathedral
- **Date:** 2026-06-01
- **Prompt:** "A colossal, foreboding Gothcore cathedral carved entirely out of dark, jagged basalt stone, standing alone on a foggy, desolate moor. The architecture features hyper-exaggerated, needle-like spires and massive flying buttresses resembling skeletal ribs. The lighting is extremely moody and cinematic, with a pale, full moon casting harsh, silvery rim light on the wet stone, while thick, rolling fog obscures the base. The mood is dark, melancholic, and menacing. Captured with a 35mm lens, low angle looking up to accentuate the imposing height of the spires."
- **Negative prompt:** "bright, sunny, colorful, modern, clean, peaceful"
- **Tags:** gothcore, architecture, dark, cathedral, basalt
- **Style / Reference:** dark fantasy concept art, photorealistic rendering
- **Composition:** low angle, symmetrical, imposing scale
- **Color palette:** deep charcoal grey, pale moonlight white, subtle sickly greens in the fog
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260601_basalt-cathedral.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for generating hyper-detailed, jagged stone textures and moody, foggy lighting.

### Suggestion: Burlap Circuit Board Macro
- **Date:** 2026-06-01
- **Prompt:** "An ultra-macro, surreal photograph of a complex computer circuit board where the fiberglass substrate is replaced by rough, woven burlap, and the intricate conductive traces are made of polished copper wire. The subject features tiny, glowing microchips and resistors. The lighting is warm and directional, grazing the rough texture of the burlap and casting sharp, tiny shadows from the copper components. The mood is a bizarre blend of rustic and highly technological. Captured with an extreme macro 100mm lens, razor-thin depth of field, highlighting the contrast between organic fabric and precise metal."
- **Negative prompt:** "wide angle, humans, outdoor, flat lighting, smooth plastic"
- **Tags:** macro, technology, surreal, burlap, circuit
- **Style / Reference:** surreal still-life photography, hyper-detailed texture study
- **Composition:** extreme close-up, shallow depth of field, diagonal leading lines
- **Color palette:** warm earth tones, bright copper, subtle glowing red LEDs
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260601_burlap-circuit.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing the contrast between rough organic textures (burlap) and polished metal elements at macro scale.

### Suggestion: Northern Renaissance Spider Web
- **Date:** 2026-06-01
- **Prompt:** "An incredibly detailed and meticulous oil painting of a complex, dew-covered spider web suspended between dead thistle branches, rendered in the precise style of the Northern Renaissance. The subject is highly symbolic and hyper-realistic, capturing every microscopic drop of moisture reflecting the world around it. The lighting is soft, natural, and diffused, creating subtle modeling on the branches and brilliant tiny specular highlights on the water drops. The mood is quiet, contemplative, and slightly grim. Captured with the flat, even perspective typical of 15th-century Flemish oil painting."
- **Negative prompt:** "modern art, abstract, photography, bright colors, sunny, rough brushstrokes"
- **Tags:** art, northern renaissance, nature, macro, detailed
- **Style / Reference:** Northern Renaissance oil painting, Jan van Eyck inspired, hyper-detailed
- **Composition:** tight framing, balanced, highly detailed foreground
- **Color palette:** muted olive greens, dark earthy browns, bright silver dew drops
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260601_renaissance-spiderweb.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests historical painting styles, specifically the meticulous detail and subtle glazing of Northern Renaissance art.

### Suggestion: Tachisme Neutron Star Collision
- **Date:** 2026-10-24
- **Prompt:** "A cataclysmic neutron star collision depicted in the expressive, non-geometric style of Tachisme. The subject is a violent, cosmic explosion of swirling matter and energy, created with spontaneous, thick splatters and drips of digital paint. The lighting is intensely bright at the core, fading into deep, chaotic space, capturing raw energy rather than realistic physics. The mood is destructive, primal, and overwhelmingly powerful. Captured with a wide perspective to frame the immense, abstract cosmic event."
- **Negative prompt:** "geometric, neat, orderly, photorealistic, photography, soft, calm"
- **Tags:** space, abstract, tachisme, explosion, cosmic
- **Style / Reference:** Tachisme, European Abstract Expressionism, spontaneous drips
- **Composition:** chaotic center, expansive edges, dynamic movement
- **Color palette:** blinding white, fiery orange, deep void black, electric blue splatters
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261024_tachisme-neutron-star.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the AI's ability to render a specific abstract art movement (Tachisme) applied to an epic cosmic event.

### Suggestion: Subterranean Sand Ant Farm
- **Date:** 2026-10-24
- **Prompt:** "A highly detailed, cross-section macro view of a giant, ancient ant farm built entirely from intricate layers of multicolored sand. The subject features massive worker ants navigating complex, glowing tunnels. The lighting is warm and directional from the surface, casting long shadows down the tunnels, with subtle bioluminescent fungi providing ambient glow in the deeper chambers. The mood is industrious, hidden, and fascinating. Captured with a macro lens, maintaining sharp focus on the granular texture of the sand and the segmented bodies of the ants."
- **Negative prompt:** "blurry, lowres, bright daylight, open sky, cartoon, simple"
- **Tags:** macro, nature, insect, sand, underground
- **Style / Reference:** photorealistic macro photography, cross-section diorama
- **Composition:** cross-section view, complex tunnel network, rule of thirds
- **Color palette:** earthy browns, warm ochre, amber, subtle bioluminescent green
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261024_sand-ant-farm.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing granular textures (sand) and complex, interwoven tunnel geometry.

### Suggestion: Aluminum Foil Cocoon
- **Date:** 2026-10-24
- **Prompt:** "An ultra-realistic, close-up shot of a mysterious, metallic cocoon hanging from a dead branch, composed entirely of crinkled, highly reflective aluminum foil. The subject is catching harsh, directional studio lighting that creates sharp, bright highlights and deep, jagged shadows across the thousands of small creases. The environment is pitch black, isolating the cocoon completely. The mood is stark, alien, and sterile. Captured with a 50mm lens, very sharp focus on the metallic crinkles."
- **Negative prompt:** "organic, soft, blurry, colorful background, bright environment, silk"
- **Tags:** macro, abstract, metallic, cocoon, isolated
- **Style / Reference:** macro studio photography, high contrast lighting
- **Composition:** centered subject, isolated on black, striking contrast
- **Color palette:** gleaming silver, pure black shadows, stark white highlights
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261024_aluminum-foil-cocoon.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of sharp, crinkled metallic textures and complex micro-reflections.

### Suggestion: Brutalist Web Design Diorama
- **Date:** 2026-10-24
- **Prompt:** "A surreal, isometric 3D diorama representing a physical manifestation of Brutalist Web Design. The subject is a miniature, clunky cityscape built from overlapping, raw HTML elements, unstyled default buttons, and harsh, unaligned text blocks. The lighting is completely flat, harsh, and artificial, resembling a glowing computer monitor with no ambient occlusion. The mood is chaotic, nostalgic, and intentionally anti-design. Captured from a strict isometric perspective, highlighting the jagged, overlapping layers of the 'webpage' physicalized."
- **Negative prompt:** "smooth, elegant, modern, gradient, realistic, soft lighting"
- **Tags:** surreal, isometric, diorama, brutalist, web
- **Style / Reference:** Brutalist Web Design, isometric 3D illustration
- **Composition:** isometric, centralized, overlapping unaligned elements
- **Color palette:** stark white, default hyperlink blue, pure black text, harsh red alerts
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261024_brutalist-web-diorama.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the translation of an abstract, digital aesthetic (Brutalist Web Design) into a physical, 3D diorama space.

### Suggestion: Granite Sundog Reflection
- **Date:** 2026-10-24
- **Prompt:** "A breathtaking, wide-angle landscape featuring a massive, perfectly polished monolithic wall of black granite standing in a frozen, snow-covered wasteland. The subject is the sky above, where a brilliant sundog (parhelion) phenomenon creates glowing halos and mock suns, which are perfectly mirrored in the pristine granite surface. The lighting is blindingly bright and freezing cold, with the sun low on the horizon. The mood is majestic, desolate, and overwhelmingly vast. Captured with an ultra-wide 14mm lens, deep depth of field to capture the sky and its reflection simultaneously."
- **Negative prompt:** "warm, tropical, cloudy, dull, blurry, rough stone"
- **Tags:** landscape, winter, phenomenon, granite, reflection
- **Style / Reference:** photorealistic nature photography, epic scale
- **Composition:** wide landscape, low horizon, perfectly mirrored reflection
- **Color palette:** blinding white snow, freezing pale blue, warm golden sundogs, deep black granite
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261024_granite-sundog.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating perfect mirror reflections on heavy stone (granite) and complex atmospheric optical phenomena (sundogs).
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
- **Styles:** Geometric Abstraction, Hard Edge Painting, Neo-Geo, Rayograph, Hard Surface Modeling, Ashcan School, Italian Futurism, Low Key Photography, Suprematism, Vorticism, Tenebrism, Biopunk, Retrowave, Digital Cubism. Afrofuturism.
- **Materials:** Chainmail, Fur, Brass, Generative Fluid Simulation, Latex, Velcro, Sandpaper, Cellophane, Chiffon, Tweed, Organza, Aerogel, Bismuth, Damascus Steel, Onyx. Graphene.
- **Subjects:** Nebula, Quasar, Pulsar, Tsunami, Ancient Ruins, Fjord, Beehive, Beaver Dam, Bird's Nest, Tide Pool, Oil Rig, Supervolcano, Magnetar, Origami, Circuit Board Macro, Skyhook, Orbital Ring, Bioluminescent Fungi, Coral Reef Megastructure, Dyson Swarm. Subterranean Garden, Clockwork Universe, Time Machine.
- **Styles:** Hard Edge Painting, Neo-Geo, Rayograph, Hard Surface Modeling, Ashcan School, Italian Futurism, Low Key Photography, Suprematism, Vorticism, Retrowave, Digital Cubism. Afrofuturism.
- **Materials:** Chainmail, Fur, Brass, Generative Fluid Simulation, Latex, Velcro, Sandpaper, Cellophane, Chiffon, Tweed, Organza, Onyx.
- **Subjects:** Geode, Supernova, Fireworks, Volcanic Eruption, Bioluminescent Forest, Nebula, Pulsar, Tsunami, Ancient Ruins, Fjord, Beehive, Beaver Dam, Bird's Nest, Tide Pool, Oil Rig, Supervolcano, Magnetar, Origami, Circuit Board Macro, Skyhook, Orbital Ring, Coral Reef Megastructure. Clockwork Universe.

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
