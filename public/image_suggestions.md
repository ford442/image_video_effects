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

### Suggestion: Bioluminescent Fungi Swamp
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
- **Prompt:** "A chaotic, dynamic metropolis depicted in the style of emphasizing speed, technology, and violent movement. Abstract, jagged geometric shapes in vibrant reds, yellows, and blacks interlock to form towering skyscrapers and speeding locomotives. The composition is fragmented and kaleidoscopic, capturing the blur of motion. Stark, high-contrast directional lighting highlights the aggressive, mechanical forms. The mood is energetic, overwhelming, and hyper-modern. Shot with a wide-angle perspective to distort scale and enhance the feeling of speed."
- **Negative prompt:** "calm, peaceful, traditional, realistic, soft, blurry, organic, nature"
- **Tags:** art, italian futurism, abstract, city, speed
- **Style / Reference:** Umberto Boccioni, Giacomo Balla
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
### Suggestion: Chainmail Hard Surface Modeling
- **Date:** 2026-10-25
- **Prompt:** "A highly detailed, photorealistic render of complex hard surface modeling focusing on an intricate, industrial chainmail structure. The subject features rigid, interlocking metallic rings that weave seamlessly into heavy mechanical plating. The lighting is harsh, directional studio lighting that creates sharp, bright highlights and deep, jagged shadows across the metallic geometry. The environment is pitch black, isolating the structure completely. The mood is stark, alien, and sterile. Captured with a 50mm lens, very sharp focus on the metallic crinkles."
- **Negative prompt:** "organic, soft, blurry, colorful background, bright environment, silk"
- **Tags:** macro, abstract, metallic, chainmail, isolated
- **Style / Reference:** Hard Surface Modeling, high contrast lighting
- **Composition:** centered subject, isolated on black, striking contrast
- **Color palette:** gleaming silver, pure black shadows, stark white highlights
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261025_chainmail-hard-surface.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of sharp, crinkled metallic textures and complex micro-reflections.

### Suggestion: Velvet Kaleidoscope Dreamscape
- **Date:** 2026-10-25
- **Prompt:** "A mesmerizing, surreal dreamscape composed entirely of intricate, symmetrical kaleidoscope patterns made from plush, luxurious fur. The environment is soft and tactile, with folds and ripples of fur forming impossible, Escher-like geometry. The lighting is soft and moody, gently grazing the texture of the fabric to highlight its plushness and depth. The mood is hypnotic, comforting, and deeply surreal. Captured with a medium 50mm lens, sharp focus on the central repeating pattern while the edges softly blur into darkness."
- **Negative prompt:** "hard surfaces, metallic, sharp edges, bright daylight, realistic landscape"
- **Tags:** abstract, surreal, fur, kaleidoscope, soft
- **Style / Reference:** surreal abstract art, highly tactile 3D render
- **Composition:** perfectly symmetrical, mandala-like, shallow depth of field
- **Color palette:** deep royal purple, rich burgundy, soft emerald green, velvety black shadows
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261025_fur-kaleidoscope.jpg`
- **License / Attribution:** CC0
- **Notes:** An excellent test for generating soft, tactile fabric textures (fur) and complex, symmetrical repeating patterns.

### Suggestion: Geometric Abstraction Nebula
- **Date:** 2026-10-25
- **Prompt:** "A breathtaking, wide-angle shot of a cataclysmic nebula expanding through deep space, depicted through Geometric Abstraction. The subject is a chaotic, swirling cloud of superheated plasma, glowing stellar dust, and intricate magnetic filaments, formed by sharp, intersecting geometric planes. The lighting is extremely bright and dynamic, emanating from a blindingly white dwarf star at the center, casting dramatic light through the gaseous nebula. The mood is awe-inspiring and destructive. Captured as if by the James Webb Space Telescope, high dynamic range, cosmic scale."
- **Negative prompt:** "earth, planets, spaceships, cartoon, simple colors, soft shapes"
- **Tags:** sci-fi, space, nebula, cosmic, epic
- **Style / Reference:** Geometric Abstraction, hyper-detailed, JWST style
- **Composition:** wide angle, expansive, centered explosion
- **Color palette:** fiery oranges, blinding whites, deep cosmic blues, vibrant magenta
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261025_geometric-nebula.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex volumetric lighting, particle dispersion, and vibrant cosmic color palettes mapped to rigid geometry.

### Suggestion: Rayograph Pulsar
- **Date:** 2026-10-25
- **Prompt:** "A violently rotating pulsar star depicted in the experimental, cameraless style of a Rayograph. The subject is a rapidly spinning celestial object emitting twin beams of intense electromagnetic radiation, represented by stark, overlapping photogram silhouettes of circular and conical objects. The lighting is harsh and direct, creating a high-contrast interplay of stark white silhouettes against a pure black background. The mood is scientific, abstract, and intense. Captured using a flat, 2D photogram process to eliminate depth."
- **Negative prompt:** "3d, realistic space, colorful, soft gradients, glowing aura"
- **Tags:** abstract, space, pulsar, rayograph, black and white
- **Style / Reference:** Rayograph, Man Ray inspired, experimental photography
- **Composition:** asymmetrical balance, stark contrast, flat shapes
- **Color palette:** pure black, stark white, sharp greyscale gradients
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261025_rayograph-pulsar.jpg`
- **License / Attribution:** CC0
- **Notes:** Pushes the model to represent a complex cosmic phenomenon using the experimental, flat silhouettes of cameraless photography (Rayograph).

### Suggestion: Hard Edge Quasar
- **Date:** 2026-10-25
- **Prompt:** "A mesmerizing visualization of a quasar represented through Hard Edge Painting, constructed entirely of flat, solid blocks of color with razor-sharp boundaries. The central subject, a stylized quasar, is a bright cyan circle surrounded by concentric, jagged rings of pure white, deep blue, and vibrant magenta. The lighting is entirely absent, relying solely on the intense saturation and contrast of the solid colors against a deep black void to create a stark, graphic mood. Captured with a perfectly flat, orthographic perspective."
- **Negative prompt:** "gradients, soft edges, 3d, realistic stars, messy, blurry, complex textures"
- **Tags:** sci-fi, abstract, space, quasar, geometric, flat
- **Style / Reference:** Hard Edge Painting, Frank Stella inspired, minimalist graphic art
- **Composition:** perfectly symmetrical, centered, high contrast
- **Color palette:** deep black void, pure white core, cyan, magenta, deep blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261025_hard-edge-quasar.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the interaction of extreme light sources with highly scattering, low-density translucent materials like aerogel.

### Suggestion: Bioluminescent Fungi Under the Stars
- **Date:** 2026-03-22
- **Prompt:** "A macro, low-key photography shot of bioluminescent fungi glowing in neon blues and greens against a dark forest floor. The lighting is ethereal, casting soft shadows, with a starry night sky barely visible through the canopy above. The mood is magical and serene."
- **Negative prompt:** "daylight, sun, bright, simple, flat"
- **Tags:** macro, fantasy, nature, bioluminescent
- **Style / Reference:** low key photography, macro lens
- **Composition:** close-up, shallow depth of field
- **Color palette:** neon blue, green, deep black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260322_bioluminescent-fungi.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing macro depth-of-field and soft glowing emission.

### Suggestion: Subterranean Crystal Garden
- **Date:** 2026-03-22
- **Prompt:** "A vast subterranean garden filled with colossal, iridescent bismuth and onyx crystals instead of plants. A glowing underground river weaves through the geometric structures, reflecting their faceted colors. The camera captures a wide, dramatic angle with dramatic, directional god-rays piercing through a cavern opening above."
- **Negative prompt:** "trees, grass, surface, dull, dark"
- **Tags:** fantasy, subterranean, crystals, landscape
- **Style / Reference:** fantasy concept art, highly detailed
- **Composition:** wide shot, leading lines
- **Color palette:** iridescent, purple, magenta, gold
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260322_subterranean-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating sharp geometric rendering and complex refractions.

### Suggestion: Steampunk Time Machine
- **Date:** 2026-03-22
- **Prompt:** "A highly intricate, polished brass and mahogany time machine sitting in a Victorian laboratory filled with drafting paper and tools. The machine features glowing blue energy coils, gears, and a plush leather seat. The lighting is warm and cinematic, coming from gas lamps and the machine's own energy pulse, with a hint of mist on the floor."
- **Negative prompt:** "modern, sleek, plastic, minimal"
- **Tags:** steampunk, sci-fi, machinery, interior
- **Style / Reference:** photorealistic, steampunk aesthetic
- **Composition:** eye-level, focused subject
- **Color palette:** warm brass, mahogany red, glowing blue
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260322_time-machine.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing metallic materials and complex details.

### Suggestion: Generative Fluid Simulation Sphere
- **Date:** 2026-03-22
- **Prompt:** "A perfect sphere made of generative fluid simulation suspended in a pitch-black void. The fluid mixes vibrant liquid neon pink, cyan, and orange colors in complex, swirling, marbled patterns. The lighting is studio-style, perfectly highlighting the glossy, wet surface of the fluid sphere."
- **Negative prompt:** "matte, dull, flat, rigid, geometric"
- **Tags:** abstract, fluid, 3d, colorful
- **Style / Reference:** 3D render, generative art
- **Composition:** center-focused, symmetrical
- **Color palette:** neon pink, cyan, orange, black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260322_fluid-sphere.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for evaluating fluid dynamics and glossy specular highlights.

### Suggestion: Circuit Board Megacity
- **Date:** 2026-03-22
- **Prompt:** "A sprawling cyberpunk megacity viewed from a bird's-eye perspective, where the city blocks and skyscrapers perfectly mimic a complex, glowing green and gold macro circuit board. Glowing data streams pulse along the 'traces' acting as highways. The mood is high-tech and imposing, with moody, atmospheric fog rolling through the lower levels."
- **Negative prompt:** "nature, organic, daytime, simple"
- **Tags:** cyberpunk, sci-fi, macro, abstract city
- **Style / Reference:** macro photography, digital art
- **Composition:** bird's-eye view, dense
- **Color palette:** neon green, gold, deep shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260322_circuit-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests intricate detail generation and abstract conceptual blending.



### Suggestion: Bioluminescent Bismuth Geode
- **Date:** 2026-03-24
- **Prompt:** "A macro photograph of a cracked, ancient geode revealing a chaotic, stepped interior of iridescent bismuth crystals. The crystals glow with an inner bioluminescence in hues of deep magenta and cyan. Soft, volumetric lighting catches the metallic sheen, while the background is a pitch-black void."
- **Negative prompt:** "blurry, out of focus, overexposed, artificial lighting, people"
- **Tags:** macro, geode, bismuth, bioluminescent, abstract
- **Style / Reference:** photorealistic, highly detailed, macro photography
- **Composition:** close-up, centered
- **Color palette:** magenta, cyan, gold, pitch black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260324_bismuth-geode.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing metallic reflections, thin-film interference, and internal glow.

### Suggestion: Afrofuturist Megacity at Dusk
- **Date:** 2026-03-24
- **Prompt:** "A sweeping aerial view of a sprawling Afrofuturist megacity at dusk. Towering skyscrapers blend traditional African geometric patterns with advanced, glowing holographic technology. Hovercraft weave between buildings, and the sky is painted in warm oranges and purples as the city lights begin to illuminate the bustling streets below."
- **Negative prompt:** "dull, flat lighting, historical, underdeveloped, poor quality"
- **Tags:** afrofuturism, cyberpunk, megacity, aerial, sci-fi
- **Style / Reference:** cinematic, architectural visualization, inspired by Syd Mead
- **Composition:** wide shot, aerial perspective
- **Color palette:** warm orange, purple, neon gold, cyan
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260324_afrofuturist-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex urban architecture, glowing holograms, and sunset lighting gradients.

### Suggestion: Retrowave Neon Highway
- **Date:** 2026-03-24
- **Prompt:** "A classic retrowave scene: a low-angle shot of a sleek, dark sports car speeding down an endless neon grid highway towards a massive, glowing pink and orange wireframe sun sinking below the horizon. The sky is a deep, starry purple, and laser-like palm trees line the road. The atmosphere is filled with a soft, glowing synthwave fog."
- **Negative prompt:** "daytime, realistic sun, modern cars, photorealistic, drab colors"
- **Tags:** retrowave, synthwave, 80s, neon, driving
- **Style / Reference:** digital art, 1980s retro-futurism, outrun style
- **Composition:** low angle, leading lines, symmetrical
- **Color palette:** hot pink, neon orange, deep purple, cyan
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260324_retrowave-highway.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating intense neon colors, grid patterns, and retro-stylized fog effects.

### Suggestion: Dyson Swarm Construction Over an Exoplanet
- **Date:** 2026-03-24
- **Prompt:** "A vast, epic sci-fi scene showing the construction of a massive Dyson swarm around a blazing, blue-white star. Millions of intricate, hexagonal solar mirrors orbit in dense rings. In the foreground, a rugged, mountainous exoplanet is illuminated by the intense starlight and the reflections from the swarm. Tiny construction drones buzz around like fireflies against the dark cosmic void."
- **Negative prompt:** "earth, green grass, clouds, simple, empty space"
- **Tags:** sci-fi, space, dyson swarm, megastructure, epic
- **Style / Reference:** space art, cinematic, hyper-detailed, hard sci-fi
- **Composition:** wide epic scale, foreground framing, deep depth of field
- **Color palette:** blinding white, electric blue, deep black, metallic silver
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260324_dyson-swarm.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing massive scale, repetitive geometric structures, and harsh, single-source directional lighting.

### Suggestion: Ancient Ruins in an Underground Fjord
- **Date:** 2026-03-24
- **Prompt:** "A massive, underground fjord illuminated by bioluminescent fungi. Colossal, weathered stone ruins of an ancient civilization cling to the sheer, dark rock faces. A calm, dark river flows through the center. Small, glowing boats navigate the water, providing scale to the towering, mysterious structures."
- **Negative prompt:** "daylight, modern buildings, dry, bright, surface, sky"
- **Tags:** fantasy, ruins, fjord, underground, mysterious
- **Style / Reference:** fantasy concept art, atmospheric, highly detailed
- **Composition:** wide shot, low angle looking up, dramatic
- **Color palette:** deep blue, cyan, glowing green, dark stone
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260324_underground-ruins.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests water reflections, towering vertical environments, and scattered glowing light sources.


### Suggestion: Neo-Geo Latex Fashion
- **Date:** 2026-10-26
- **Prompt:** "A striking, high-fashion portrait shot of a model wearing an avant-garde outfit made entirely of glossy, brightly colored latex, designed in the geometric, hard-edged style of Neo-Geo art. The subject is posed dynamically against a stark, minimalist background. The lighting is harsh, using multiple directional strobes to create intense specular highlights on the shiny latex surface and deep, sharp shadows. The mood is artificial, ultra-modern, and slick. Captured with a 85mm portrait lens, ensuring sharp focus on the sharp geometric angles of the garment."
- **Negative prompt:** "organic, soft, messy, matte, dull colors, natural lighting"
- **Tags:** fashion, portrait, neo-geo, latex, modern
- **Style / Reference:** Neo-Geo art movement, high-fashion editorial photography
- **Composition:** medium portrait, dynamic angles, striking geometry
- **Color palette:** high-saturation primary colors, glossy black, blinding white highlights
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261026_neo-geo-latex.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing highly specular, glossy materials (latex) combined with strict geometric shapes and bright, primary colors.

### Suggestion: Suprematist Oil Rig
- **Date:** 2026-10-26
- **Prompt:** "An imposing offshore oil rig rising from a turbulent ocean, reimagined entirely through the abstract, geometric language of Suprematism. The subject is composed of floating, intersecting squares, circles, and crosses suspended above the churning water. The lighting is flat and unnatural, highlighting the pure geometric forms without realistic shading, creating a stark contrast against the dark, textured sea. The mood is revolutionary, abstract, and dominant. Captured from a low angle, emphasizing the monolithic scale of the geometric construct."
- **Negative prompt:** "photorealistic, rusty metal, detailed machinery, soft, cloudy"
- **Tags:** abstract, suprematism, industrial, ocean, geometric
- **Style / Reference:** Kazimir Malevich inspired, abstract architectural visualization
- **Composition:** dynamic diagonals, low angle, abstract arrangement
- **Color palette:** stark black, pure white, vibrant red, deep ocean blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261026_suprematist-oil-rig.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the intersection of abstract geometric art movements (Suprematism) with industrial subjects and contrasting organic elements (ocean).

### Suggestion: Cellophane Bird's Nest
- **Date:** 2026-10-26
- **Prompt:** "A highly detailed macro photograph of an intricate bird's nest woven entirely from crinkled, iridescent strips of transparent cellophane. The delicate subject rests securely in the fork of a gnarled, dark wood branch. The lighting is soft, back-lit morning sunlight, passing through the cellophane to create thousands of tiny, colorful refractions and glowing edges. The mood is fragile, whimsical, and strangely beautiful. Captured with a 100mm macro lens, incredibly shallow depth of field, rendering the background into a soft, glowing bokeh."
- **Negative prompt:** "twigs, straw, mud, opaque, dull, wide angle, messy"
- **Tags:** macro, nature, surreal, cellophane, iridescent
- **Style / Reference:** macro nature photography, surreal still-life
- **Composition:** tight close-up, rule of thirds, beautiful bokeh
- **Color palette:** transparent iridescent pastels, glowing warm sunlight, deep brown wood
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261026_cellophane-birds-nest.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating complex, overlapping layers of transparent, highly refractive materials (cellophane) and macro bokeh.

### Suggestion: Vorticist Skyhook
- **Date:** 2026-10-26
- **Prompt:** "A colossal, rotating skyhook megastructure suspended in the upper atmosphere, depicted in the harsh, fragmented style of Vorticism. The subject features aggressive, jagged diagonal lines radiating outward, capturing the immense rotational energy of the tether. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, mechanical, and overpowering. Captured with a dynamic, tilted perspective to emphasize vertigo and motion."
- **Negative prompt:** "calm, horizontal, photorealistic, soft curves, gentle, natural"
- **Tags:** sci-fi, abstract, vorticism, megastructure, dynamic
- **Style / Reference:** Vorticism art movement, Wyndham Lewis inspired, hard-edged abstraction
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black, cold atmospheric blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261026_vorticist-skyhook.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Vorticism to a massive sci-fi engineering concept.

### Suggestion: Digital Cubism Coral Reef Megastructure
- **Date:** 2026-10-26
- **Prompt:** "A sprawling, underwater coral reef megastructure rendered in a stylized Digital Cubism aesthetic. The massive subject is broken down into multifaceted, overlapping geometric planes, displaying multiple viewpoints of the intricate coral formations simultaneously. The lighting is vibrant and ethereal, with dappled sunlight filtering down through the water, striking the various angled facets to create a mosaic of glowing color. The mood is complex, vibrant, and analytical. Captured with a wide-angle perspective, attempting to encompass the overwhelming scale and multifaceted nature of the reef."
- **Negative prompt:** "realistic underwater photography, soft, organic, murky, dull, simple"
- **Tags:** abstract, underwater, digital cubism, coral, complex
- **Style / Reference:** Digital Cubism, fragmented 3D rendering, vibrant colors
- **Composition:** dense, multi-perspective, overwhelming detail
- **Color palette:** vibrant coral pinks, neon cyan, deep ocean blue, bright yellow accents
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261026_digital-cubism-coral.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the model's ability to deconstruct complex organic environments (coral reef) into the multi-perspective geometry of Cubism.

### Suggestion: Bioluminescent Reef
- **Date:** 2026-10-27
- **Prompt:** "An ultra-detailed, macro underwater shot of a sprawling biopunk bioluminescent reef. The organic subject is fused with glowing, fleshy cybernetic tubes and pulsating neon sacs. The lighting is exclusively from the deep-sea bioluminescence, casting sickly toxic greens and vibrant magentas against the pitch-black ocean depths. The mood is alien, toxic, and dangerously beautiful. Captured with a macro 100mm lens, razor-thin depth of field focusing on a single dripping, glowing polyp."
- **Negative prompt:** "daylight, sun, bright, dry, smooth plastic, clean metal, realistic fish"
- **Tags:** macro, underwater, biopunk, glowing, reef
- **Style / Reference:** biopunk concept art, photorealistic dark macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** toxic neon green, vibrant magenta, deep ocean black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_biopunk-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of extreme macro underwater details (coral, polyps) with fleshy cybernetic biopunk elements and intense neon emission.

### Suggestion: Tweed Spacesuit
- **Date:** 2026-10-27
- **Prompt:** "A highly detailed, surreal fashion portrait of an astronaut wearing a fully functional spacesuit tailored entirely from classic, brown herringbone tweed fabric. The subject stands on the dusty, cratered surface of the moon. The lighting is harsh, unattenuated solar glare creating sharp, deep black shadows across the lunar surface, juxtaposed with the soft, fibrous texture of the tweed catching the bright sunlight. The mood is absurd, humorous, and highly fashionable. Captured with a 50mm portrait lens, eye-level perspective."
- **Negative prompt:** "shiny plastic, white spacesuit, soft lighting, earth, atmospheric haze"
- **Tags:** surreal, fashion, space, tweed, portrait
- **Style / Reference:** surreal fashion photography, hyper-detailed material swap
- **Composition:** centered portrait, rule of thirds, stark lunar background
- **Color palette:** earthy brown tweed, lunar greys, stark white highlights, pure black sky
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_tweed-spacesuit.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of complex, soft, woven micro-textures (tweed) placed in an environment with harsh, directional, hard-shadow lighting (lunar surface).

### Suggestion: Aerogel Geometric City
- **Date:** 2026-10-27
- **Prompt:** "A breathtaking, wide-angle view of a futuristic, geometric city constructed entirely from massive, floating blocks of weightless, translucent blue aerogel. The central subject, the city, is suspended high above a dense layer of white clouds. The lighting is brilliant midday sunlight, piercing through the porous aerogel structures, creating millions of soft, internal refractions and a glowing, ghostly blue aura around the buildings. The mood is utopian, silent, and airy. Captured with a wide 24mm lens to emphasize the massive, floating scale."
- **Negative prompt:** "solid glass, concrete, metal, dark, gritty, cyberpunk, night"
- **Tags:** sci-fi, architecture, aerogel, city, floating
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** wide expansive view, towering geometric forms, cloud floor
- **Color palette:** ghostly aerogel blue, blinding white sunlight, pure white clouds
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_aerogel-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large-scale structures made of highly scattering, incredibly low-density translucent materials (aerogel) under direct sunlight.

### Suggestion: Damascus Steel Chess Set
- **Date:** 2026-10-27
- **Prompt:** "A hyper-detailed, dramatic macro still life of a chessboard where the intricately carved pieces are forged entirely from beautiful, rippled Damascus steel. The heavy metallic subjects are incredibly detailed with flowing, dark and light grey wave patterns. The lighting is moody and cinematic, featuring a single, warm overhead spotlight that casts sharp specular highlights on the polished metal ridges and deep, rich shadows between the pieces. The mood is intellectual, tense, and masterful. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the White King."
- **Negative prompt:** "wood, plastic, flat lighting, blurry, wide angle, messy room"
- **Tags:** still-life, macro, metal, damascus steel, chess
- **Style / Reference:** photorealistic product photography, highly detailed macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** dark metallic greys, warm golden highlight, deep shadow black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_damascus-chess.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the complex, flowing texture generation of Damascus steel under intense, focused macro lighting.

### Suggestion: Italian Futurism Speedboat
- **Date:** 2026-10-27
- **Prompt:** "A chaotic, dynamic scene of a speedboat tearing across a stylized lake, depicted in the harsh, fragmented style of Italian Futurism. The subject features aggressive, jagged diagonal lines and overlapping geometric planes radiating outward to capture the immense speed and mechanical energy. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion."
- **Negative prompt:** "calm, horizontal, photorealistic, soft curves, gentle, natural water"
- **Tags:** abstract, art, italian futurism, speed, dynamic
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black, cold aquatic blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_futurism-speedboat.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to convey extreme mechanical speed.

### Suggestion: Biopunk Bioluminescent Reef
- **Date:** 2026-10-27
- **Prompt:** "An ultra-detailed, macro underwater shot of a sprawling biopunk bioluminescent reef. The organic subject is fused with glowing, fleshy cybernetic tubes and pulsating neon sacs. The lighting is exclusively from the deep-sea bioluminescence, casting sickly toxic greens and vibrant magentas against the pitch-black ocean depths. The mood is alien, toxic, and dangerously beautiful. Captured with a macro 100mm lens, razor-thin depth of field focusing on a single dripping, glowing polyp."
- **Negative prompt:** "daylight, sun, bright, dry, smooth plastic, clean metal, realistic fish"
- **Tags:** macro, underwater, biopunk, glowing, reef
- **Style / Reference:** biopunk concept art, photorealistic dark macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** toxic neon green, vibrant magenta, deep ocean black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_biopunk-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of extreme macro underwater details (coral, polyps) with fleshy cybernetic biopunk elements and intense neon emission.

### Suggestion: Tweed Spacesuit
- **Date:** 2026-10-27
- **Prompt:** "A highly detailed, surreal fashion portrait of an astronaut wearing a fully functional spacesuit tailored entirely from classic, brown herringbone tweed fabric. The subject stands on the dusty, cratered surface of the moon. The lighting is harsh, unattenuated solar glare creating sharp, deep black shadows across the lunar surface, juxtaposed with the soft, fibrous texture of the tweed catching the bright sunlight. The mood is absurd, humorous, and highly fashionable. Captured with a 50mm portrait lens, eye-level perspective."
- **Negative prompt:** "shiny plastic, white spacesuit, soft lighting, earth, atmospheric haze"
- **Tags:** surreal, fashion, space, tweed, portrait
- **Style / Reference:** surreal fashion photography, hyper-detailed material swap
- **Composition:** centered portrait, rule of thirds, stark lunar background
- **Color palette:** earthy brown tweed, lunar greys, stark white highlights, pure black sky
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_tweed-spacesuit.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of complex, soft, woven micro-textures (tweed) placed in an environment with harsh, directional, hard-shadow lighting (lunar surface).

### Suggestion: Aerogel Geometric City
- **Date:** 2026-10-27
- **Prompt:** "A breathtaking, wide-angle view of a futuristic, geometric city constructed entirely from massive, floating blocks of weightless, translucent blue aerogel. The central subject, the city, is suspended high above a dense layer of white clouds. The lighting is brilliant midday sunlight, piercing through the porous aerogel structures, creating millions of soft, internal refractions and a glowing, ghostly blue aura around the buildings. The mood is utopian, silent, and airy. Captured with a wide 24mm lens to emphasize the massive, floating scale."
- **Negative prompt:** "solid glass, concrete, metal, dark, gritty, cyberpunk, night"
- **Tags:** sci-fi, architecture, aerogel, city, floating
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** wide expansive view, towering geometric forms, cloud floor
- **Color palette:** ghostly aerogel blue, blinding white sunlight, pure white clouds
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_aerogel-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large-scale structures made of highly scattering, incredibly low-density translucent materials (aerogel) under direct sunlight.

### Suggestion: Damascus Steel Chess Set
- **Date:** 2026-10-27
- **Prompt:** "A hyper-detailed, dramatic macro still life of a chessboard where the intricately carved pieces are forged entirely from beautiful, rippled Damascus steel. The heavy metallic subjects are incredibly detailed with flowing, dark and light grey wave patterns. The lighting is moody and cinematic, featuring a single, warm overhead spotlight that casts sharp specular highlights on the polished metal ridges and deep, rich shadows between the pieces. The mood is intellectual, tense, and masterful. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the White King."
- **Negative prompt:** "wood, plastic, flat lighting, blurry, wide angle, messy room"
- **Tags:** still-life, macro, metal, damascus steel, chess
- **Style / Reference:** photorealistic product photography, highly detailed macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** dark metallic greys, warm golden highlight, deep shadow black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_damascus-chess.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the complex, flowing texture generation of Damascus steel under intense, focused macro lighting.

### Suggestion: Italian Futurism Speedboat
- **Date:** 2026-10-27
- **Prompt:** "A chaotic, dynamic scene of a speedboat tearing across a stylized lake, depicted in the harsh, fragmented style of Italian Futurism. The subject features aggressive, jagged diagonal lines and overlapping geometric planes radiating outward to capture the immense speed and mechanical energy. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion."
- **Negative prompt:** "calm, horizontal, photorealistic, soft curves, gentle, natural water"
- **Tags:** abstract, art, italian futurism, speed, dynamic
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black, cold aquatic blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_futurism-speedboat.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to convey extreme mechanical speed.

### Suggestion: Biopunk Bioluminescent Reef
- **Date:** 2026-10-27
- **Prompt:** "An ultra-detailed, macro underwater shot of a sprawling biopunk bioluminescent reef. The organic subject is fused with glowing, fleshy cybernetic tubes and pulsating neon sacs. The lighting is exclusively from the deep-sea bioluminescence, casting sickly toxic greens and vibrant magentas against the pitch-black ocean depths. The mood is alien, toxic, and dangerously beautiful. Captured with a macro 100mm lens, razor-thin depth of field focusing on a single dripping, glowing polyp."
- **Negative prompt:** "daylight, sun, bright, dry, smooth plastic, clean metal, realistic fish"
- **Tags:** macro, underwater, biopunk, glowing, reef
- **Style / Reference:** biopunk concept art, photorealistic dark macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** toxic neon green, vibrant magenta, deep ocean black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_biopunk-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of extreme macro underwater details (coral, polyps) with fleshy cybernetic biopunk elements and intense neon emission.

### Suggestion: Tweed Spacesuit
- **Date:** 2026-10-27
- **Prompt:** "A highly detailed, surreal fashion portrait of an astronaut wearing a fully functional spacesuit tailored entirely from classic, brown herringbone tweed fabric. The subject stands on the dusty, cratered surface of the moon. The lighting is harsh, unattenuated solar glare creating sharp, deep black shadows across the lunar surface, juxtaposed with the soft, fibrous texture of the tweed catching the bright sunlight. The mood is absurd, humorous, and highly fashionable. Captured with a 50mm portrait lens, eye-level perspective."
- **Negative prompt:** "shiny plastic, white spacesuit, soft lighting, earth, atmospheric haze"
- **Tags:** surreal, fashion, space, tweed, portrait
- **Style / Reference:** surreal fashion photography, hyper-detailed material swap
- **Composition:** centered portrait, rule of thirds, stark lunar background
- **Color palette:** earthy brown tweed, lunar greys, stark white highlights, pure black sky
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_tweed-spacesuit.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of complex, soft, woven micro-textures (tweed) placed in an environment with harsh, directional, hard-shadow lighting (lunar surface).

### Suggestion: Aerogel Geometric City
- **Date:** 2026-10-27
- **Prompt:** "A breathtaking, wide-angle view of a futuristic, geometric city constructed entirely from massive, floating blocks of weightless, translucent blue aerogel. The central subject, the city, is suspended high above a dense layer of white clouds. The lighting is brilliant midday sunlight, piercing through the porous aerogel structures, creating millions of soft, internal refractions and a glowing, ghostly blue aura around the buildings. The mood is utopian, silent, and airy. Captured with a wide 24mm lens to emphasize the massive, floating scale."
- **Negative prompt:** "solid glass, concrete, metal, dark, gritty, cyberpunk, night"
- **Tags:** sci-fi, architecture, aerogel, city, floating
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** wide expansive view, towering geometric forms, cloud floor
- **Color palette:** ghostly aerogel blue, blinding white sunlight, pure white clouds
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_aerogel-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large-scale structures made of highly scattering, incredibly low-density translucent materials (aerogel) under direct sunlight.

### Suggestion: Damascus Steel Chess Set
- **Date:** 2026-10-27
- **Prompt:** "A hyper-detailed, dramatic macro still life of a chessboard where the intricately carved pieces are forged entirely from beautiful, rippled Damascus steel. The heavy metallic subjects are incredibly detailed with flowing, dark and light grey wave patterns. The lighting is moody and cinematic, featuring a single, warm overhead spotlight that casts sharp specular highlights on the polished metal ridges and deep, rich shadows between the pieces. The mood is intellectual, tense, and masterful. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the White King."
- **Negative prompt:** "wood, plastic, flat lighting, blurry, wide angle, messy room"
- **Tags:** still-life, macro, metal, damascus steel, chess
- **Style / Reference:** photorealistic product photography, highly detailed macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** dark metallic greys, warm golden highlight, deep shadow black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_damascus-chess.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the complex, flowing texture generation of Damascus steel under intense, focused macro lighting.

### Suggestion: Italian Futurism Speedboat
- **Date:** 2026-10-27
- **Prompt:** "A chaotic, dynamic scene of a speedboat tearing across a stylized lake, depicted in the harsh, fragmented style of Italian Futurism. The subject features aggressive, jagged diagonal lines and overlapping geometric planes radiating outward to capture the immense speed and mechanical energy. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion."
- **Negative prompt:** "calm, horizontal, photorealistic, soft curves, gentle, natural water"
- **Tags:** abstract, art, italian futurism, speed, dynamic
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black, cold aquatic blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_futurism-speedboat.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to convey extreme mechanical speed.

### Suggestion: Biopunk Bioluminescent Reef
- **Date:** 2026-10-27
- **Prompt:** "An ultra-detailed, macro underwater shot of a sprawling biopunk bioluminescent reef. The organic subject is fused with glowing, fleshy cybernetic tubes and pulsating neon sacs. The lighting is exclusively from the deep-sea bioluminescence, casting sickly toxic greens and vibrant magentas against the pitch-black ocean depths. The mood is alien, toxic, and dangerously beautiful. Captured with a macro 100mm lens, razor-thin depth of field focusing on a single dripping, glowing polyp."
- **Negative prompt:** "daylight, sun, bright, dry, smooth plastic, clean metal, realistic fish"
- **Tags:** macro, underwater, biopunk, glowing, reef
- **Style / Reference:** biopunk concept art, photorealistic dark macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** toxic neon green, vibrant magenta, deep ocean black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_biopunk-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of extreme macro underwater details (coral, polyps) with fleshy cybernetic biopunk elements and intense neon emission.

### Suggestion: Tweed Spacesuit
- **Date:** 2026-10-27
- **Prompt:** "A highly detailed, surreal fashion portrait of an astronaut wearing a fully functional spacesuit tailored entirely from classic, brown herringbone tweed fabric. The subject stands on the dusty, cratered surface of the moon. The lighting is harsh, unattenuated solar glare creating sharp, deep black shadows across the lunar surface, juxtaposed with the soft, fibrous texture of the tweed catching the bright sunlight. The mood is absurd, humorous, and highly fashionable. Captured with a 50mm portrait lens, eye-level perspective."
- **Negative prompt:** "shiny plastic, white spacesuit, soft lighting, earth, atmospheric haze"
- **Tags:** surreal, fashion, space, tweed, portrait
- **Style / Reference:** surreal fashion photography, hyper-detailed material swap
- **Composition:** centered portrait, rule of thirds, stark lunar background
- **Color palette:** earthy brown tweed, lunar greys, stark white highlights, pure black sky
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_tweed-spacesuit.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of complex, soft, woven micro-textures (tweed) placed in an environment with harsh, directional, hard-shadow lighting (lunar surface).

### Suggestion: Aerogel Geometric City
- **Date:** 2026-10-27
- **Prompt:** "A breathtaking, wide-angle view of a futuristic, geometric city constructed entirely from massive, floating blocks of weightless, translucent blue aerogel. The central subject, the city, is suspended high above a dense layer of white clouds. The lighting is brilliant midday sunlight, piercing through the porous aerogel structures, creating millions of soft, internal refractions and a glowing, ghostly blue aura around the buildings. The mood is utopian, silent, and airy. Captured with a wide 24mm lens to emphasize the massive, floating scale."
- **Negative prompt:** "solid glass, concrete, metal, dark, gritty, cyberpunk, night"
- **Tags:** sci-fi, architecture, aerogel, city, floating
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** wide expansive view, towering geometric forms, cloud floor
- **Color palette:** ghostly aerogel blue, blinding white sunlight, pure white clouds
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_aerogel-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large-scale structures made of highly scattering, incredibly low-density translucent materials (aerogel) under direct sunlight.

### Suggestion: Damascus Steel Chess Set
- **Date:** 2026-10-27
- **Prompt:** "A hyper-detailed, dramatic macro still life of a chessboard where the intricately carved pieces are forged entirely from beautiful, rippled Damascus steel. The heavy metallic subjects are incredibly detailed with flowing, dark and light grey wave patterns. The lighting is moody and cinematic, featuring a single, warm overhead spotlight that casts sharp specular highlights on the polished metal ridges and deep, rich shadows between the pieces. The mood is intellectual, tense, and masterful. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the White King."
- **Negative prompt:** "wood, plastic, flat lighting, blurry, wide angle, messy room"
- **Tags:** still-life, macro, metal, damascus steel, chess
- **Style / Reference:** photorealistic product photography, highly detailed macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** dark metallic greys, warm golden highlight, deep shadow black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_damascus-chess.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the complex, flowing texture generation of Damascus steel under intense, focused macro lighting.

### Suggestion: Italian Futurism Speedboat
- **Date:** 2026-10-27
- **Prompt:** "A chaotic, dynamic scene of a speedboat tearing across a stylized lake, depicted in the harsh, fragmented style of Italian Futurism. The subject features aggressive, jagged diagonal lines and overlapping geometric planes radiating outward to capture the immense speed and mechanical energy. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion."
- **Negative prompt:** "calm, horizontal, photorealistic, soft curves, gentle, natural water"
- **Tags:** abstract, art, italian futurism, speed, dynamic
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black, cold aquatic blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_futurism-speedboat.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to convey extreme mechanical speed.

### Suggestion: Biopunk Bioluminescent Reef
- **Date:** 2026-10-27
- **Prompt:** "An ultra-detailed, macro underwater shot of a sprawling biopunk bioluminescent reef. The organic subject is fused with glowing, fleshy cybernetic tubes and pulsating neon sacs. The lighting is exclusively from the deep-sea bioluminescence, casting sickly toxic greens and vibrant magentas against the pitch-black ocean depths. The mood is alien, toxic, and dangerously beautiful. Captured with a macro 100mm lens, razor-thin depth of field focusing on a single dripping, glowing polyp."
- **Negative prompt:** "daylight, sun, bright, dry, smooth plastic, clean metal, realistic fish"
- **Tags:** macro, underwater, biopunk, glowing, reef
- **Style / Reference:** biopunk concept art, photorealistic dark macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** toxic neon green, vibrant magenta, deep ocean black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_biopunk-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of extreme macro underwater details (coral, polyps) with fleshy cybernetic biopunk elements and intense neon emission.

### Suggestion: Tweed Spacesuit
- **Date:** 2026-10-27
- **Prompt:** "A highly detailed, surreal fashion portrait of an astronaut wearing a fully functional spacesuit tailored entirely from classic, brown herringbone tweed fabric. The subject stands on the dusty, cratered surface of the moon. The lighting is harsh, unattenuated solar glare creating sharp, deep black shadows across the lunar surface, juxtaposed with the soft, fibrous texture of the tweed catching the bright sunlight. The mood is absurd, humorous, and highly fashionable. Captured with a 50mm portrait lens, eye-level perspective."
- **Negative prompt:** "shiny plastic, white spacesuit, soft lighting, earth, atmospheric haze"
- **Tags:** surreal, fashion, space, tweed, portrait
- **Style / Reference:** surreal fashion photography, hyper-detailed material swap
- **Composition:** centered portrait, rule of thirds, stark lunar background
- **Color palette:** earthy brown tweed, lunar greys, stark white highlights, pure black sky
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261027_tweed-spacesuit.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of complex, soft, woven micro-textures (tweed) placed in an environment with harsh, directional, hard-shadow lighting (lunar surface).

### Suggestion: Aerogel Geometric City
- **Date:** 2026-10-27
- **Prompt:** "A breathtaking, wide-angle view of a futuristic, geometric city constructed entirely from massive, floating blocks of weightless, translucent blue aerogel. The central subject, the city, is suspended high above a dense layer of white clouds. The lighting is brilliant midday sunlight, piercing through the porous aerogel structures, creating millions of soft, internal refractions and a glowing, ghostly blue aura around the buildings. The mood is utopian, silent, and airy. Captured with a wide 24mm lens to emphasize the massive, floating scale."
- **Negative prompt:** "solid glass, concrete, metal, dark, gritty, cyberpunk, night"
- **Tags:** sci-fi, architecture, aerogel, city, floating
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** wide expansive view, towering geometric forms, cloud floor
- **Color palette:** ghostly aerogel blue, blinding white sunlight, pure white clouds
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_aerogel-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large-scale structures made of highly scattering, incredibly low-density translucent materials (aerogel) under direct sunlight.

### Suggestion: Damascus Steel Chess Set
- **Date:** 2026-10-27
- **Prompt:** "A hyper-detailed, dramatic macro still life of a chessboard where the intricately carved pieces are forged entirely from beautiful, rippled Damascus steel. The heavy metallic subjects are incredibly detailed with flowing, dark and light grey wave patterns. The lighting is moody and cinematic, featuring a single, warm overhead spotlight that casts sharp specular highlights on the polished metal ridges and deep, rich shadows between the pieces. The mood is intellectual, tense, and masterful. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the White King."
- **Negative prompt:** "wood, plastic, flat lighting, blurry, wide angle, messy room"
- **Tags:** still-life, macro, metal, damascus steel, chess
- **Style / Reference:** photorealistic product photography, highly detailed macro
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** dark metallic greys, warm golden highlight, deep shadow black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_damascus-chess.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the complex, flowing texture generation of Damascus steel under intense, focused macro lighting.

### Suggestion: Italian Futurism Speedboat
- **Date:** 2026-10-27
- **Prompt:** "A chaotic, dynamic scene of a speedboat tearing across a stylized lake, depicted in the harsh, fragmented style of Italian Futurism. The subject features aggressive, jagged diagonal lines and overlapping geometric planes radiating outward to capture the immense speed and mechanical energy. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion."
- **Negative prompt:** "calm, horizontal, photorealistic, soft curves, gentle, natural water"
- **Tags:** abstract, art, italian futurism, speed, dynamic
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black, cold aquatic blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261027_futurism-speedboat.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to convey extreme mechanical speed.

### Suggestion: Ashcan School City Street
- **Date:** 2026-10-31
- **Prompt:** "A bustling, gritty early 20th-century city street scene depicted in the Ashcan School art style. The subject features working-class pedestrians, horse-drawn carts, and dense tenement buildings. The lighting is overcast and realistic, casting soft, murky shadows that highlight the dirt and texture of the urban environment. The mood is authentic, raw, and full of everyday life. Captured with an eye-level, documentary-style perspective, emphasizing the unglamorous reality of the city."
- **Negative prompt:** "modern, bright, cheerful, clean, sci-fi, surreal, highly saturated"
- **Tags:** art, city, historical, ashcan school, gritty
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** eye-level, crowded street, naturalistic framing
- **Color palette:** muted browns, dark greys, dull reds, ochre
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261031_ashcan-school-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing gritty, unidealized urban scenes and historical art styles.

### Suggestion: Exoplanet Core Liquid Diamond
- **Date:** 2026-10-31
- **Prompt:** "An ultra-macro, theoretical visualization deep within the core of a massive exoplanet. The subject is an ocean of liquid diamond and super-compressed carbon structures churning under unimaginable pressure. The lighting is completely internal, glowing with an intense, blinding white and electric blue heat that refracts wildly through the crystalline facets. The mood is extreme, alien, and awe-inspiring. Captured with a microscopic camera perspective, freezing the chaotic, crystalline fluid dynamics in sharp focus."
- **Negative prompt:** "surface, sky, life, dark, muddy, soft, blurry"
- **Tags:** sci-fi, space, macro, exoplanet, core, diamond
- **Style / Reference:** hyper-realistic scientific visualization, 3D render
- **Composition:** chaotic, dense, sharp macro focus
- **Color palette:** blinding white, electric blue, intense cyan, deep shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261031_exoplanet-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing extreme internal lighting, refraction, and complex crystal fluid simulations.

### Suggestion: Magnetar Plasma Storm
- **Date:** 2026-10-31
- **Prompt:** "A breathtaking, epic space scene featuring a terrifying magnetar star violently erupting. The subject is a hyper-dense neutron star surrounded by fiercely glowing, twisted magnetic field lines trapping superheated plasma. The lighting is blindingly bright and high-contrast, dominated by the extreme, raw energy radiating from the star against the pitch-black void of space. The mood is apocalyptic, powerful, and majestic. Captured with a wide-angle cinematic lens, showcasing the vast, twisted magnetic flares arching into deep space."
- **Negative prompt:** "calm, planets, earth-like, soft lighting, simple, low contrast"
- **Tags:** sci-fi, space, magnetar, cosmic, epic, plasma
- **Style / Reference:** cinematic space art, astrophotography, JWST style
- **Composition:** centered subject, dynamic curved flares, wide perspective
- **Color palette:** blinding white, intense violet, fiery orange, pitch black void
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261031_magnetar-storm.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing twisted, glowing emission lines (magnetic fields) and extreme high-contrast cosmic phenomena.

### Suggestion: Giant Hexagonal Beehive
- **Date:** 2026-10-31
- **Prompt:** "An ultra-macro view deep inside a giant, complex beehive. The subject consists of perfectly repeating, translucent amber-colored hexagonal wax cells filled with glowing golden honey. The lighting is warm and directional, filtering through the semi-transparent wax walls to create a mesmerizing sub-surface scattering effect and a rich, golden ambiance. The mood is industrious, organic, and mathematically perfect. Captured with a 100mm macro lens, deep depth of field to emphasize the endless geometric repetition of the honeycomb structure."
- **Negative prompt:** "messy, chaotic, dark, dull, artificial, plastic, people"
- **Tags:** macro, nature, beehive, hexagonal, golden
- **Style / Reference:** macro nature photography, hyper-detailed structure
- **Composition:** full frame repeating pattern, deep perspective
- **Color palette:** warm gold, rich amber, deep translucent orange
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261031_giant-beehive.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating sub-surface scattering on organic materials and the generation of perfect, repeating geometric patterns (hexagons).

### Suggestion: Photorealistic Beaver Dam
- **Date:** 2026-10-31
- **Prompt:** "A photorealistic, highly detailed landscape photograph of an intricate beaver dam blocking a tranquil forest stream. The subject is a massive construction of chewed logs, thick mud, and woven branches holding back a deep pool of clear water. The lighting is crisp, early morning sunlight piercing through the dense forest canopy, casting dappled light and reflections on the still water. The mood is peaceful, natural, and harmonious. Captured with a 35mm lens from the edge of the water, showing both the complex texture of the dam and the calm ecosystem it creates."
- **Negative prompt:** "urban, modern, stylized, painted, blurry, low resolution, people"
- **Tags:** nature, landscape, photorealism, forest, beaver dam
- **Style / Reference:** National Geographic style nature photography, hyper-detailed
- **Composition:** wide shot, low angle near water surface, leading lines of the stream
- **Color palette:** rich earthy browns, lush forest greens, clear blue water reflections, golden sunlight
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261031_beaver-dam.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing complex organic structures (woven branches and mud), clear water reflections, and dappled forest lighting.

### Suggestion: Rayonism Onyx Supervolcano
- **Date:** 2026-11-05
- **Prompt:** "A cataclysmic eruption of a supervolcano depicted in the abstract, dynamic style of Rayonism. The towering volcanic cone and surrounding landscape are composed of jagged, intersecting rays of light and sharp planes of dark, polished onyx. The lighting is harsh and fractured, representing the explosive energy through stark intersecting beams of fiery orange and blinding white. The mood is energetic, destructive, and deeply abstract. Captured with a dynamic, tilted perspective, emphasizing the explosive upward thrust of the intersecting rays."
- **Negative prompt:** "photorealistic, smooth, soft curves, realistic lava, calm, photography"
- **Tags:** abstract, landscape, rayonism, supervolcano, onyx
- **Style / Reference:** Rayonism art movement, Natalia Goncharova inspired
- **Composition:** dynamic intersecting lines, upward thrust, explosive center
- **Color palette:** fiery orange, deep onyx black, blinding white, vibrant red
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261105_rayonism-onyx-supervolcano.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the intersection of abstract, ray-based art movements with massive geological events and polished stone textures.

### Suggestion: De Stijl Sandpaper Origami
- **Date:** 2026-11-05
- **Prompt:** "A minimalist still-life composition of an intricately folded origami crane, constructed entirely from rough, coarse-grit sandpaper, designed strictly in the De Stijl art movement style. The subject relies entirely on pure abstraction and universality by a reduction to the essentials of form and colour. The lighting is completely flat and even, casting no shadows to maintain the pure two-dimensional graphic aesthetic of the geometric planes. The mood is structured, rigid, and philosophical. Captured with an orthographic camera perspective to completely eliminate depth and perspective distortion."
- **Negative prompt:** "depth, 3d, realistic, shadows, gradients, curves, soft textures"
- **Tags:** abstract, de stijl, still-life, origami, sandpaper
- **Style / Reference:** De Stijl art movement, Piet Mondrian inspired, minimalist graphic art
- **Composition:** strictly rectilinear, flat orthographic, balanced asymmetry
- **Color palette:** primary red, blue, yellow, pure white, stark black, rough beige sandpaper texture
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261105_destijl-sandpaper-origami.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates the generation of rough, granular textures (sandpaper) constrained entirely within the strict, flat rectilinear rules of De Stijl.

### Suggestion: Tenebrism Organza Bioluminescent Forest
- **Date:** 2026-11-05
- **Prompt:** "A dramatic, macro photograph of a sprawling bioluminescent forest floor, reimagined where the organic fungi structures are delicately woven from sheer, translucent organza fabric. The lighting employs extreme Tenebrism, with the scene enveloped in pitch-black darkness, pierced only by a single, intense beam of warm light from above that dramatically highlights the intricate folds and delicate transparency of the organza. The mood is highly dramatic, mysterious, and theatrical. Captured with a 100mm macro lens, sharp focus on the central fabric structure, allowing the edges to fall off into deep, crushing shadows."
- **Negative prompt:** "bright, even lighting, flat, daylight, real coral, muddy water"
- **Tags:** macro, forest, tenebrism, organza, dramatic
- **Style / Reference:** Tenebrism painting style, Caravaggio inspired, macro photography
- **Composition:** highly dramatic spotlight, deep shadows, tight framing
- **Color palette:** pitch black, warm golden spotlight, ethereal glowing cyan, translucent white
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261105_tenebrism-organza-forest.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for pushing extreme high-contrast lighting (Tenebrism) combined with delicate, layered transparent fabrics (organza).

### Suggestion: Biopunk Chiffon Magnetar
- **Date:** 2026-11-05
- **Prompt:** "An incredibly surreal, cosmic visualization of a hyper-dense magnetar star, reinterpreted through a Biopunk aesthetic where the magnetic field lines are composed of miles of flowing, bio-luminescent chiffon fabric. The central subject is a pulsating, fleshy core emitting extreme radiation. The lighting is blindingly bright at the core, fading into deep, organic shadows within the twisted layers of chiffon, creating a sickly, toxic glow. The mood is alien, terrifying, and strangely beautiful. Captured with a wide-angle cinematic lens, capturing the vast, twisting organic flares arching into the dark cosmic void."
- **Negative prompt:** "realistic space, clean, geometric, hard surface, daylight"
- **Tags:** sci-fi, space, biopunk, magnetar, chiffon
- **Style / Reference:** biopunk concept art, surreal cosmic visualization
- **Composition:** centered core, dynamic flowing layers, expansive void
- **Color palette:** toxic neon green, deep fleshy magenta, blinding white core, dark void
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261105_biopunk-chiffon-magnetar.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of massive cosmic phenomena with fleshy biopunk elements and flowing, sheer fabric textures.

### Suggestion: Low Key Photography Velcro Tide Pool
- **Date:** 2026-11-05
- **Prompt:** "A highly detailed, macro still-life of a miniature tide pool ecosystem, where the rocks and anemones are entirely constructed from the hook-and-loop textures of industrial Velcro. The lighting utilizes Low Key Photography techniques, predominantly dark with only selective, rim-lighting catching the thousands of tiny plastic hooks and soft loops of the Velcro surface. The mood is moody, textured, and abstract. Captured with an extreme macro 100mm lens, very shallow depth of field, emphasizing the harsh, synthetic micro-textures emerging from the deep shadows."
- **Negative prompt:** "bright, high key, real water, organic rocks, flat lighting"
- **Tags:** macro, abstract, low key, tide pool, velcro
- **Style / Reference:** low key studio photography, macro texture study
- **Composition:** tight close-up, dramatic rim lighting, dark background
- **Color palette:** pure black shadows, subtle grey highlights, deep oceanic blue accents
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261105_lowkey-velcro-tidepool.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating the generation of complex, repetitive micro-textures (Velcro) under highly controlled, shadow-dominant lighting.

### Suggestion: Quantum Singularity Reactor
- **Date:** 2026-04-10
- **Prompt:** "A sprawling underground quantum singularity reactor. The core subject is a suspended, violently swirling sphere of hyper-dense, gravity-bending black plasma. The lighting is harsh and contrasting, radiating from glowing azure cooling rings that struggle to contain the intense energy, casting sharp blue highlights against dark, brushed steel containment walls. The mood is tense, highly advanced, and claustrophobic. Captured with a wide 24mm lens to emphasize the colossal scale of the machinery and the intense glow of the core."
- **Negative prompt:** "sunlight, natural, bright, soft, organic, plants, low-res"
- **Tags:** sci-fi, reactor, energy, quantum, dark
- **Style / Reference:** hard sci-fi concept art, photorealistic 3D render
- **Composition:** wide angle, symmetrical, centered core
- **Color palette:** azure blue, pitch black, brushed steel grey, stark white
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260410_quantum-reactor.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the interaction between intense, singular light sources and brushed metallic surfaces in a dark environment.

### Suggestion: Ethereal Coral Chandelier
- **Date:** 2026-04-10
- **Prompt:** "An opulent ballroom interior dominated by a gigantic, intricate chandelier made entirely of living, bioluminescent coral. The coral subject hangs from a vaulted ceiling, dripping with delicate, glowing tentacles. The lighting is soft and magical, emanating entirely from the warm pink and cyan bioluminescence of the coral, casting gentle, colorful shadows across the marble floor. The mood is romantic, surreal, and deeply peaceful. Captured with a 35mm lens, balancing the sheer size of the chandelier with the elegant architectural details."
- **Negative prompt:** "underwater, fish, ocean, harsh daylight, modern, simple"
- **Tags:** fantasy, interior, coral, bioluminescent, surreal
- **Style / Reference:** surreal interior design visualization, ethereal fantasy
- **Composition:** low angle looking up, rule of thirds
- **Color palette:** warm pink, cyan glow, polished white marble, deep shadows
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260410_coral-chandelier.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing soft ambient bioluminescent lighting acting as the primary light source in an interior setting.

### Suggestion: Holographic Silk Kimono
- **Date:** 2026-04-10
- **Prompt:** "A stunning fashion portrait of a cyber-geisha wearing an exquisite kimono woven from translucent, holographic silk. The fabric subject shimmers with iridescent digital patterns that float slightly above the material. The lighting features a moody, neon-lit rainy street at night, where the vibrant reflections of pink and cyan signs catch the holographic silk, creating brilliant specular highlights. The mood is elegant, melancholic, and deeply cyberpunk. Captured with an 85mm portrait lens, featuring a very shallow depth of field to turn the background neon lights into soft bokeh."
- **Negative prompt:** "traditional, matte fabric, daylight, sunny, cluttered background"
- **Tags:** cyberpunk, fashion, portrait, holographic, neon
- **Style / Reference:** high fashion photography, cyberpunk aesthetic
- **Composition:** medium close-up, shallow depth of field, dramatic angles
- **Color palette:** neon pink, cyan, deep street blacks, iridescent silk
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260410_holographic-kimono.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating complex translucent fabrics interacting with multiple bright, colored neon light sources.

### Suggestion: Volcanic Glass Monoliths
- **Date:** 2026-04-10
- **Prompt:** "A sweeping landscape of towering, jagged monoliths formed from flawless, dark volcanic glass (obsidian), thrusting out of a barren ash wasteland. The monolithic subjects are perfectly smooth, reflecting the surrounding environment like dark mirrors. The lighting is dramatic, capturing a blood-red eclipse in the sky that casts an eerie, crimson ambient light, highlighting the sharp edges of the obsidian. The mood is desolate, apocalyptic, and monumental. Captured with an ultra-wide 14mm lens, emphasizing the harsh, angular geometry against the vast, empty horizon."
- **Negative prompt:** "greenery, water, blue sky, soft edges, blurry, people"
- **Tags:** landscape, sci-fi, obsidian, monolith, eclipse
- **Style / Reference:** cinematic dark fantasy landscape, photorealistic
- **Composition:** extreme wide angle, low horizon line, imposing scale
- **Color palette:** deep obsidian black, blood red, dark grey ash
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260410_volcanic-monoliths.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating perfect mirror reflections on massive, dark, sharp geometric forms.

### Suggestion: Steampunk Chronosphere
- **Date:** 2026-04-10
- **Prompt:** "A macro, highly detailed shot of a glowing Chronosphere device resting on an old, mahogany workbench. The spherical subject is constructed of intricately layered, polished brass gears, crystal lenses, and a swirling core of golden temporal energy. The lighting is warm, highly directional lamplight casting deep, rich shadows and creating sharp, brilliant glints on the metallic edges and glass lenses. The mood is mysterious, antique, and intellectual. Captured with a 100mm macro lens, utilizing a shallow depth of field to isolate the central crystal and glowing core."
- **Negative prompt:** "modern, sleek, plastic, bright daylight, wide angle"
- **Tags:** steampunk, macro, mechanism, brass, glowing
- **Style / Reference:** macro product photography, hyper-detailed steampunk
- **Composition:** tight close-up, center focus, beautiful background blur
- **Color palette:** polished brass, warm gold, rich mahogany brown, bright white glints
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260410_steampunk-chronosphere.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of intricate brass mechanics, glass refraction, and warm, directional macro lighting.


### Suggestion: Ashcan School Industrial Port
- **Date:** 2026-11-10
- **Prompt:** "A bustling, gritty early 20th-century industrial port depicted in the Ashcan School art style. The subject features massive steam-powered cranes and thick, dark smoke billowing into an overcast sky. The lighting is murky and realistic, casting soft, indistinct shadows that highlight the dirt and texture of the harbor. The mood is authentic, raw, and full of everyday working-class life. Captured with an eye-level, documentary-style perspective, emphasizing the unglamorous reality of the industrial waterfront."
- **Negative prompt:** "modern, bright, cheerful, clean, sci-fi, surreal, highly saturated, 3d render"
- **Tags:** art, port, historical, ashcan school, gritty
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** eye-level, crowded docks, naturalistic framing
- **Color palette:** muted browns, dark greys, dull reds, ochre, murky water
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261110_ashcan-school-port.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing gritty, unidealized industrial scenes and historical art styles, fulfilling wishlist.

### Suggestion: Graphene Orbital Ring Megastructure
- **Date:** 2026-11-10
- **Prompt:** "An epic, sweeping view of a massive Orbital Ring megastructure encircling a lush, green Earth-like planet. The ring itself is constructed from sleek, dark, ultra-strong graphene woven into an impossibly thin yet immense structure. The subject is dotted with glowing city lights and sprawling spaceports. The lighting features a dramatic sunrise cresting over the planet's horizon, casting a blinding white glare and long shadows across the graphene surface. The mood is utopian, vast, and technologically supreme. Captured with a wide-angle cinematic lens from low Earth orbit, emphasizing planetary scale."
- **Negative prompt:** "dystopian, broken, rusty, small, low-res, cartoon"
- **Tags:** sci-fi, megastructure, space, orbital ring, epic
- **Style / Reference:** hard sci-fi environment design, cinematic space art
- **Composition:** curved horizon, extreme wide angle, dynamic lighting
- **Color palette:** dark matte graphene grey, vibrant earth greens and blues, blinding solar white
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261110_orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of massive scale, planetary curvature, and the matte, light-absorbing properties of a massive graphene structure, fulfilling wishlist.

### Suggestion: Mother of Pearl Tsunami Wave
- **Date:** 2026-11-10
- **Prompt:** "A massive, towering tsunami wave caught frozen in time just before it crashes down. The water is entirely composed of shimmering, iridescent nacre (mother-of-pearl), reflecting a spectacular array of pearlescent pastels. Within the translucent wall of the wave, silhouetted shapes of giant marine life can be seen swirling. The sky above is dark and stormy with dramatic lightning illuminating the crest of the wave. The mood is terrifying yet awe-inspiring and beautiful. Captured with a low camera angle, wide lens, and high shutter speed to freeze the water droplets."
- **Negative prompt:** "daylight, calm water, small wave, shore, people, boats, sunny"
- **Tags:** nature, ocean, tsunami, iridescent, nacre, dramatic
- **Style / Reference:** photorealistic, surreal nature photography
- **Composition:** imposing, low angle, wave dominating the frame
- **Color palette:** pearlescent pinks, soft baby blues, shimmering silver, bright white lightning flashes
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261110_mother-of-pearl-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing thin-film iridescent interference on organic shapes and chaotic fluid dynamics, fulfilling wishlist.

### Suggestion: Brass Supernova Explosion
- **Date:** 2026-11-10
- **Prompt:** "A breathtaking, wide-angle shot of a cataclysmic supernova remnant expanding through deep space, reinterpreted entirely as an intricate mechanical explosion of polished brass. The subject is a chaotic, swirling cloud of golden brass gears, springs, and plates bursting outward. The lighting is extremely bright and dynamic, emanating from a blindingly white temporal core at the center, casting dramatic light through the mechanical debris. The mood is awe-inspiring and destructive yet ordered. Captured as if by a cosmic clockmaker, high dynamic range, cosmic scale."
- **Negative prompt:** "earth, planets, spaceships, cartoon, simple colors, soft shapes, organic, plasma"
- **Tags:** sci-fi, steampunk, space, supernova, mechanical, brass
- **Style / Reference:** steampunk space art, hyper-detailed, JWST style
- **Composition:** wide angle, expansive, centered explosion
- **Color palette:** polished brass, warm gold, blinding whites, deep cosmic blacks
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261110_brass-supernova.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex volumetric lighting, particle dispersion, and intricate metallic structures (brass), fulfilling wishlist.

### Suggestion: Italian Futurism Beaver Dam
- **Date:** 2026-11-10
- **Prompt:** "A chaotic, dynamic scene of a complex beaver dam blocking a turbulent forest stream, depicted in the harsh, fragmented style of Italian Futurism. The subject features aggressive, jagged diagonal lines and overlapping geometric planes radiating outward to capture the immense energy of the flowing water and the busy, mechanical-like construction of the dam. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion."
- **Negative prompt:** "calm, horizontal, photorealistic, soft curves, gentle, natural water, peaceful forest"
- **Tags:** abstract, art, italian futurism, landscape, dynamic, beaver dam
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black, cold aquatic blue, ochre
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261110_futurism-beaver-dam.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to an organic landscape subject, fulfilling wishlist.

### Suggestion: Bismuth Clockwork Observatory
- **Date:** 2026-11-20
- **Prompt:** "A hyper-detailed, sweeping interior view of a colossal clockwork observatory, where all the gears, armillary spheres, and structural supports are forged from naturally iridescent bismuth crystals. The subject features massive stepped geometric formations that interlock as functional mechanical parts. The lighting is mystical and astronomical, with a glowing azure starlight filtering through a massive open dome, casting deep shadows and causing the bismuth to shine brilliantly in a rainbow of thin-film interference colors. The mood is ancient, scholarly, and magical. Captured with a wide-angle 16mm lens to encompass the vast complexity of the mechanical ceiling."
- **Negative prompt:** "modern, dull, plastic, blurry, organic wood, flat lighting, simple"
- **Tags:** fantasy, steampunk, interior, bismuth, observatory
- **Style / Reference:** steampunk concept art, hyper-realistic fantasy interior
- **Composition:** wide angle, low angle looking up, symmetrical complexity
- **Color palette:** iridescent rainbow, glowing azure, deep shadowy blacks
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261120_bismuth-observatory.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating complex mechanical geometry intersecting with iridescent hopper crystal materials.

### Suggestion: Aerogel Deep Sea Jellyfish
- **Date:** 2026-11-20
- **Prompt:** "A stunning, macro underwater photograph of a gigantic jellyfish whose bell and trailing tentacles appear to be constructed entirely of ultra-light, translucent blue aerogel. The subject floats elegantly in the pitch-black abyss of the ocean. The lighting is entirely bioluminescent, emanating softly from within the aerogel structure itself, creating thousands of internal refractions and a ghostly, ethereal glow that barely illuminates the surrounding dark water. The mood is silent, alien, and deeply serene. Captured with a 50mm lens, sharp focus on the internal structure of the bell while the tentacles fade into the soft, dark bokeh of the deep sea."
- **Negative prompt:** "bright sunlight, surface, corals, messy, opaque, muddy water"
- **Tags:** nature, underwater, macro, aerogel, jellyfish
- **Style / Reference:** deep sea nature photography, surreal material swap
- **Composition:** centered subject, flowing lines, dark negative space
- **Color palette:** ghostly aerogel blue, bioluminescent cyan, pitch black water
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261120_aerogel-jellyfish.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing the interaction of self-illuminating light sources within highly scattering, low-density translucent materials.

### Suggestion: Damascus Steel Dragon Scales
- **Date:** 2026-11-20
- **Prompt:** "An extreme macro, hyper-textured study of dragon scales, where each overlapping scale is perfectly forged from dark, rippled Damascus steel. The subject shows the intricate, flowing light and dark grey wave patterns characteristic of folded metal, complete with tiny scratches and battle scars. The lighting is harsh, directional, and cinematic, grazing the surface to cast sharp, deep black shadows under each scale and bright, glinting specular highlights on the polished ridges. The mood is formidable, heavy, and battle-hardened. Captured with a 100mm macro lens, incredibly shallow depth of field focusing strictly on a central scarred scale."
- **Negative prompt:** "organic, reptilian, colorful, soft, flat lighting, blurry"
- **Tags:** macro, fantasy, metal, damascus steel, dragon
- **Style / Reference:** photorealistic texture study, macro product photography
- **Composition:** extreme close-up, diagonal flow of scales, shallow depth of field
- **Color palette:** dark metallic greys, bright silver highlights, pure black shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261120_damascus-dragon-scales.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing repeating, overlapping geometry and the complex, flowing texture generation of Damascus steel.

### Suggestion: Tweed Cyberpunk Hacker Den
- **Date:** 2026-11-20
- **Prompt:** "A claustrophobic, chaotic cyberpunk hacker den where all the high-tech computer monitors, server racks, and glowing keyboards are bizarrely upholstered in classic, earthy brown herringbone tweed fabric. The subject is a cramped desk overflowing with glowing, soft-textured tech. The lighting is a moody mix of harsh neon pink and electric blue emanating from the tweed-covered screens, casting colorful, soft rim lights against the fibrous material and deep, murky shadows in the corners. The mood is absurd, cozy yet dystopian. Captured with a 35mm lens, eye-level perspective, focusing on the contrast between the glowing data streams and the woolen texture."
- **Negative prompt:** "clean, sleek, metallic, plastic, minimalist, bright daylight"
- **Tags:** cyberpunk, interior, surreal, tweed, hacker
- **Style / Reference:** surreal cyberpunk interior, humorous material swap
- **Composition:** cluttered desk, deep perspective, messy framing
- **Color palette:** earthy browns, neon pink, electric blue, murky shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261120_tweed-hacker-den.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the model's ability to apply soft, woven micro-textures (tweed) to traditionally hard-surface, tech-oriented objects under colorful neon lighting.

### Suggestion: Mother of Pearl Desert Oasis
- **Date:** 2026-11-20
- **Prompt:** "A sweeping, surreal landscape of a vast desert where the towering sand dunes are composed entirely of smooth, solid layers of shimmering, iridescent mother of pearl (nacre). The subject features sweeping, wind-carved curves that reflect a spectacular array of pearlescent pastels. The lighting is a brilliant, golden-hour sunset, catching the ridges of the nacre to reveal intense rainbow interference patterns against a vibrant, purple twilight sky. The mood is dreamlike, luxurious, and completely otherworldly. Captured with an ultra-wide 14mm lens, emphasizing the massive scale of the dunes and the smooth, flowing curves."
- **Negative prompt:** "sand, granular, rough, dull, green plants, cloudy, realistic desert"
- **Tags:** landscape, surreal, desert, mother of pearl, iridescent
- **Style / Reference:** surreal landscape photography, hyper-detailed environment
- **Composition:** sweeping curves, low horizon, wide expansive view
- **Color palette:** pearlescent pinks, soft blues, golden sunlight, rich purple sky
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261120_mother-of-pearl-oasis.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large-scale thin-film iridescent interference mapped to smooth, sweeping organic landscape geometry.

### Suggestion: Bioluminescent Quartz Cave
- **Date:** 2026-12-01
- **Prompt:** "A breathtaking wide-angle view deep inside a subterranean cavern made entirely of colossal, translucent pink quartz crystals. The crystalline subjects are naturally bioluminescent, glowing with a soft, ethereal cyan and magenta light that gently illuminates the dark, wet cave floor. The lighting is completely internal, casting complex, refracted shadows and bouncing a myriad of colors off the faceted walls. The mood is silent, magical, and untouched by time. Captured with a wide 16mm lens, focusing on the sheer scale and internal refractions of the crystals."
- **Negative prompt:** "daylight, sun, organic plants, wood, people, messy, blurry, low resolution"
- **Tags:** fantasy, nature, underground, quartz, glowing
- **Style / Reference:** photorealistic fantasy landscape, hyper-detailed 3D render
- **Composition:** wide angle, deep perspective, rule of thirds
- **Color palette:** translucent pink, ethereal cyan, deep magenta, pitch black shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261201_bioluminescent-quartz.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing complex refractions and sub-surface scattering of light inside large translucent geometry.

### Suggestion: Cyberpunk Bonsai Garden
- **Date:** 2026-12-01
- **Prompt:** "A highly detailed, macro shot of an ancient bonsai tree grafted with complex cybernetic implants and glowing neon tubing, resting on a sleek metallic pedestal. The subject sits in a traditional Japanese garden courtyard that has been overtaken by futuristic technology. The lighting is dramatic, with soft moonlight from above contrasting with the harsh, saturated neon pink and electric blue glow emanating from the cyber-bonsai itself. The mood is contemplative, melancholic, and deeply cyberpunk. Captured with a 50mm lens, utilizing a shallow depth of field to isolate the intricate cyber-foliage against the moody, blurred background."
- **Negative prompt:** "bright sunlight, cartoon, simple, plain, messy, modern daylight, lowres"
- **Tags:** cyberpunk, nature, bonsai, glowing, macro
- **Style / Reference:** cyberpunk concept art, photorealistic macro photography
- **Composition:** centered subject, shallow depth of field, dramatic contrast
- **Color palette:** vibrant neon pink, electric blue, cool moonlight grey, organic green
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261201_cyber-bonsai.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing the blending of delicate organic shapes (leaves, bark) with rigid, glowing technological elements.

### Suggestion: Clockwork Celestial Astrolabe
- **Date:** 2026-12-01
- **Prompt:** "An incredibly intricate, room-sized mechanical astrolabe functioning as a planetarium, constructed from polished brass, copper, and dark mahogany. The mechanical subject features hundreds of interlocking gears and rings perfectly aligned to track the stars. The lighting is provided by a single, warm, intense spotlight from the center of the device, simulating a miniature sun and casting long, complex, shifting shadows of the gears against the dark, domed ceiling of the room. The mood is intellectual, antique, and mysterious. Captured with a 24mm wide lens from a low angle, emphasizing the towering, complex structure."
- **Negative prompt:** "modern, plastic, bright daylight, simple, messy, out of focus, exterior"
- **Tags:** steampunk, interior, mechanism, brass, complex
- **Style / Reference:** steampunk architectural visualization, hyper-detailed product photography
- **Composition:** low angle looking up, symmetrical, deep shadows
- **Color palette:** warm polished brass, rich mahogany brown, bright golden light, deep shadow
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261201_clockwork-astrolabe.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing the generation of highly intricate, interlocking mechanical geometry and complex shadow casting.

### Suggestion: Ethereal Silk Desert
- **Date:** 2026-12-01
- **Prompt:** "A surreal, sweeping landscape where the rolling dunes of a vast desert are composed entirely of soft, flowing folds of golden silk fabric instead of sand. The subject ripples and catches the wind like liquid gold. The lighting is a dramatic golden hour sunset, grazing the surface of the fabric to highlight its delicate, woven texture and casting deep, soft shadows in the valleys between the folds. The mood is dreamlike, luxurious, and peaceful. Captured with a wide-angle 14mm lens, utilizing leading lines to draw the eye across the endless, silky horizon."
- **Negative prompt:** "granular sand, rough texture, water, plants, harsh lighting, dull colors"
- **Tags:** surreal, landscape, desert, silk, golden hour
- **Style / Reference:** surreal landscape photography, hyper-detailed fabric simulation
- **Composition:** sweeping curves, leading lines, expansive horizon
- **Color palette:** rich golden yellow, warm amber, deep shadow brown, pale sunset sky
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261201_silk-desert.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the model's ability to seamlessly map the soft, woven micro-textures of silk onto the macro geometry of a sweeping desert landscape.

### Suggestion: Bioluminescent Deep Sea Train
- **Date:** 2026-12-01
- **Prompt:** "An epic, underwater scene of a massive, barnacle-encrusted steam locomotive driving along tracks laid on the ocean floor. The industrial subject is heavily modified to survive the deep sea, emitting thick clouds of glowing, bioluminescent green exhaust instead of smoke. The lighting is extremely dark and murky, illuminated only by the train's piercing, volumetric headlights cutting through the particulate-filled water and the eerie glow of its own exhaust. The mood is imposing, mysterious, and awe-inspiring. Captured with a wide 35mm lens, tracking alongside the train to emphasize its raw power against the crushing depths."
- **Negative prompt:** "surface, sunlight, sky, dry, clean metal, realistic fish, modern train"
- **Tags:** steampunk, underwater, train, bioluminescent, deep sea
- **Style / Reference:** dark fantasy concept art, cinematic underwater photography
- **Composition:** dynamic tracking shot, dramatic lighting, volumetric fog
- **Color palette:** toxic glowing green, piercing white headlights, deep ocean blue-black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261201_deep-sea-train.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating underwater volumetric lighting, thick atmospheric fog (murky water), and glowing particle simulations.

### Suggestion: Graphene Space Elevator
- **Date:** 2027-01-15
- **Prompt:** "A breathtaking, wide-angle shot of a towering space elevator tether anchored in a futuristic ocean spaceport. The primary subject is the colossal tether constructed from sleek, dark, ultra-strong graphene, stretching infinitely upwards into a starry night sky. The lighting features bright, dramatic spotlights from the ocean base illuminating the matte surface of the graphene, while the upper atmosphere is dark, capturing the glowing city below. The mood is awe-inspiring, highly advanced, and monumental. Captured with a wide 14mm lens pointing sharply upwards to emphasize the dizzying vertical perspective."
- **Negative prompt:** "broken, rusty, dystopian, daylight, short, flimsy, organic"
- **Tags:** sci-fi, megastructure, space elevator, graphene, night
- **Style / Reference:** hard sci-fi environment design, cinematic architectural visualization
- **Composition:** extreme low angle, vertical leading lines
- **Color palette:** matte dark grey, glowing neon blue spotlights, deep starry black
- **Aspect ratio:** 9:16
- **Reference images:** `public/images/suggestions/20270115_graphene-space-elevator.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the representation of extreme vertical scale and the interaction of intense artificial spotlights with a matte, light-absorbing material (graphene).

### Suggestion: Mother of Pearl Cloudscape
- **Date:** 2027-01-15
- **Prompt:** "An ethereal, sweeping aerial view of a surreal cloudscape where the clouds are formed entirely from solid, shimmering layers of Mother of Pearl. The subject features massive, billowing, smooth formations that reflect a spectacular array of pearlescent pastels. The lighting is a brilliant, omnidirectional ambient glow, catching the smooth ridges of the nacre to reveal intense rainbow interference patterns across the entire sky. The mood is dreamlike, luxurious, and completely otherworldly. Captured with an ultra-wide 16mm lens, highlighting the vast, smooth, sweeping curves."
- **Negative prompt:** "fluffy clouds, realistic sky, dull colors, dark shadows, rain, storm"
- **Tags:** surreal, landscape, clouds, mother of pearl, iridescent
- **Style / Reference:** surreal digital art, hyper-detailed environment
- **Composition:** expansive view, sweeping curves, rule of thirds
- **Color palette:** pearlescent pinks, soft baby blues, shimmering silver, pastel yellow
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270115_mother-of-pearl-cloudscape.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating large-scale thin-film iridescent interference mapped to smooth, massive, sweeping organic formations.

### Suggestion: Ashcan School Subway Station
- **Date:** 2027-01-15
- **Prompt:** "A bustling, gritty early 20th-century subway station depicted in the Ashcan School art style. The subject features working-class commuters in winter coats waiting on a dirty, tile-lined platform as a steam-powered train approaches. The lighting is dim, moody, and flickering, casting soft, indistinct shadows from harsh overhead bulbs that highlight the grime and texture of the underground environment. The mood is authentic, melancholic, and full of everyday urban life. Captured with an eye-level, documentary-style perspective, emphasizing the crowded and unglamorous reality of the city."
- **Negative prompt:** "modern, clean, bright, neon, cheerful, sci-fi, empty"
- **Tags:** art, urban, historical, ashcan school, gritty
- **Style / Reference:** Ashcan School painting, John Sloan inspired, thick brushstrokes
- **Composition:** eye-level, crowded platform, naturalistic framing
- **Color palette:** muted browns, dark greys, dull yellows, murky green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270115_ashcan-school-subway.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing gritty, unidealized subterranean scenes and authentic historical art styles.

### Suggestion: Italian Futurism Race Car
- **Date:** 2027-01-15
- **Prompt:** "A chaotic, dynamic scene of an early 20th-century race car tearing down a city street, depicted in the harsh, fragmented style of Italian Futurism. The subject features aggressive, jagged diagonal lines and overlapping geometric planes radiating outward to capture the immense speed, noise, and mechanical energy. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion and blur."
- **Negative prompt:** "calm, stationary, photorealistic, soft curves, gentle, realistic car"
- **Tags:** abstract, art, italian futurism, speed, dynamic
- **Style / Reference:** Italian Futurism art movement, Giacomo Balla inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black, vivid yellow
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270115_futurism-racecar.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to convey extreme mechanical speed and urban noise.

### Suggestion: Bismuth Crystal Space Station
- **Date:** 2027-01-15
- **Prompt:** "A sweeping exterior view of a massive, geometric space station constructed entirely of naturally iridescent bismuth crystals, floating in deep space. The subject features giant, stepped, hopper-like formations that interlock to form an alien, functional megastructure. The lighting is harsh and direct from a nearby blue giant star, casting deep black shadows in the vacuum of space, causing the metallic bismuth surfaces to shine brilliantly in a rainbow of thin-film interference colors. The mood is majestic, alien, and highly advanced. Captured with a wide-angle 16mm lens to encompass the vast scale of the crystalline structure against the starfield."
- **Negative prompt:** "organic, smooth curves, dull, plastic, atmospheric haze, blurry"
- **Tags:** sci-fi, space, space station, bismuth, iridescent
- **Style / Reference:** hard sci-fi environment design, hyper-realistic space art
- **Composition:** wide angle, dramatic lighting, sharp geometric framing
- **Color palette:** iridescent rainbow, glaring white starlight, deep cosmic black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270115_bismuth-spacestation.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating complex stepped geometric structures interacting with highly saturated iridescent thin-film materials under harsh vacuum lighting.
### Suggestion: Vaporwave Marble Plaza
- **Date:** 2026-12-15
- **Prompt:** "A surreal, retro-futuristic Vaporwave plaza. The subject features classical marble busts and Roman columns resting on a perfectly reflective, endless grid floor. The lighting is extremely stylized, with a low-hanging neon pink and cyan sun casting long, dramatic, colorful shadows. The mood is nostalgic, liminal, and dreamlike. Captured with a wide-angle lens, emphasizing the vast, empty space and strict geometric perspective."
- **Negative prompt:** "realistic, natural lighting, modern, messy, organic, people"
- **Tags:** vaporwave, surreal, retro, architecture, liminal
- **Style / Reference:** Vaporwave aesthetic, 1980s retro CGI
- **Composition:** wide angle, symmetrical, vanishing point perspective
- **Color palette:** neon pink, electric cyan, pure white marble, dark grid
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261215_vaporwave-plaza.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing strict geometric grids and highly saturated, limited neon color palettes.

### Suggestion: Steampunk Bioluminescent Airship
- **Date:** 2026-12-15
- **Prompt:** "A massive, intricately detailed steampunk airship floating through a dense, glowing nebula. The subject is constructed of riveted copper and brass, powered by large glass tanks filled with swirling, bioluminescent green plasma. The lighting is moody and cinematic, with warm gas lamps on the deck contrasting against the cold, ethereal glow of the surrounding cosmic dust. The mood is adventurous and majestic. Captured with a telephoto lens from a distance to compress the scale of the ship against the vast nebula."
- **Negative prompt:** "modern, sleek, plastic, daylight, blue sky, airplane"
- **Tags:** steampunk, sci-fi, space, vehicle, nebula
- **Style / Reference:** steampunk concept art, cinematic space visualization
- **Composition:** rule of thirds, compressed perspective
- **Color palette:** warm copper, glowing green plasma, deep space purple
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261215_steampunk-airship.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating metallic reflections (copper/brass) amidst complex volumetric background lighting.

### Suggestion: Art Deco Cybernetic Cityscape
- **Date:** 2026-12-15
- **Prompt:** "A sprawling, retro-futuristic city blending classic Art Deco architecture with advanced cybernetic technology. The towering skyscrapers feature geometric, gold-leaf embellishments and glowing, holographic marquees. The lighting is dramatic and moody, simulating a film noir night scene with heavy rain, where the bright gold and neon lights reflect off the wet, slick pavement. The mood is glamorous yet gritty. Captured from a low angle with a 35mm lens to emphasize the towering, symmetrical geometry of the buildings."
- **Negative prompt:** "daylight, bright, sunny, ruins, messy, dull, organic"
- **Tags:** cyberpunk, art deco, city, architecture, rain
- **Style / Reference:** film noir, retro-futuristic architectural render
- **Composition:** low angle looking up, strong vertical lines, symmetrical
- **Color palette:** gold, neon blue, stark black, reflective grey
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261215_art-deco-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing complex reflections on wet surfaces and the blending of historical architecture with neon elements.

### Suggestion: Glassmorphism Quantum Flora
- **Date:** 2026-12-15
- **Prompt:** "An ultra-macro view of an alien flower blooming, constructed entirely using a glassmorphism aesthetic. The subject's petals are made of frosted, semi-translucent glass that slightly blurs the vibrant, pulsing quantum energy core within. The lighting is soft, diffuse, and incredibly colorful, refracting through the frosted glass to create a glowing, ethereal aura of soft pastels. The mood is delicate, futuristic, and serene. Captured with an extreme macro 100mm lens, utilizing a shallow depth of field to create a soft, dreamy bokeh background."
- **Negative prompt:** "opaque, natural, mud, dull, sharp shadows, wide angle"
- **Tags:** macro, abstract, flora, glassmorphism, ethereal
- **Style / Reference:** Glassmorphism UI aesthetic, 3D abstract render
- **Composition:** extreme close-up, centered, shallow depth of field
- **Color palette:** frosted white, iridescent pastels, glowing pink, soft cyan
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261215_glassmorphism-flora.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating sub-surface scattering, frosted glass materials, and soft lighting refractions.

### Suggestion: Brutalist Concrete Monolith
- **Date:** 2026-12-15
- **Prompt:** "A towering, oppressive Brutalist concrete monolith standing isolated in a vast, snow-covered tundra. The architectural subject features harsh, intersecting geometric planes and deep, dark recesses without any windows. The lighting is overcast and bleak, creating flat, low-contrast shadows that emphasize the raw, rough texture of the poured concrete against the pure white snow. The mood is desolate, dystopian, and silent. Captured with a wide 24mm lens to emphasize the stark isolation and massive scale of the structure."
- **Negative prompt:** "bright, sunny, cheerful, glass, colorful, busy, people"
- **Tags:** architecture, brutalism, landscape, snow, desolate
- **Style / Reference:** brutalist architecture photography, minimalist landscape
- **Composition:** wide expansive view, stark contrast, rule of thirds
- **Color palette:** concrete grey, pure white snow, overcast pale sky, deep shadow black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261215_brutalist-monolith.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of rough, porous concrete textures under flat, overcast ambient lighting.


### Suggestion: Graphene Solar Sail
- **Date:** 2027-02-15
- **Prompt:** "A majestic, deep-space scene of an enormous solar sail spacecraft deployed around a bright blue giant star. The sail is constructed of ultra-thin, dark graphene that perfectly absorbs the star's energy, while the intricate support struts emit a faint, pulsing bioluminescent blue light. The lighting is harsh and highly directional from the massive star, creating stark contrast and deep space shadows. The mood is silent, awe-inspiring, and technologically supreme. Captured with a wide-angle 24mm lens, deep depth of field to keep both the vast sail and the glowing star in sharp focus."
- **Negative prompt:** "earth, planets, soft lighting, daylight, blurry, low resolution, organic"
- **Tags:** sci-fi, space, vehicle, graphene, megastructure
- **Style / Reference:** hard sci-fi visualization, cinematic space art
- **Composition:** wide angle, dramatic scale, centered blue giant
- **Color palette:** dark matte graphene grey, blinding electric blue, pitch cosmic black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270215_graphene-solar-sail.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of massive, dark, matte materials against intense cosmic lighting.

### Suggestion: Mother of Pearl Coral Reef
- **Date:** 2027-02-15
- **Prompt:** "A mesmerizing underwater macro photograph of a surreal coral reef where the coral branches are completely formed from shimmering, iridescent mother of pearl. The underwater subject is teeming with tiny, glowing bioluminescent sea life. The lighting consists of dappled, ethereal sunlight filtering down through the clear blue water, refracting off the nacreous surfaces to create a breathtaking display of pearlescent pinks, blues, and golds. The mood is peaceful, magical, and pristine. Captured with a 50mm macro lens, utilizing a shallow depth of field to isolate the central mother of pearl coral formation."
- **Negative prompt:** "murky water, pollution, dark, dull, scary, cartoon, 3d render"
- **Tags:** underwater, nature, macro, coral, mother of pearl
- **Style / Reference:** photorealistic underwater nature photography
- **Composition:** macro close-up, rule of thirds, beautiful soft bokeh
- **Color palette:** pearlescent pinks, iridescent golds, clear ocean blues, soft cyan
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270215_mother-of-pearl-coral.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating thin-film iridescence on complex organic underwater structures.

### Suggestion: Italian Futurism Fireworks
- **Date:** 2027-02-15
- **Prompt:** "A chaotic and energetic nighttime cityscape experiencing a massive fireworks display, depicted entirely in the aggressive, fragmented style of Italian Futurism. The exploding fireworks are rendered as sharp, intersecting diagonal lines and overlapping planes of vibrant color that convey explosive sound and violent motion. The lighting is highly contrasted and artificial, simulating the sudden, blinding flashes of the explosions tearing through the dark urban sky. The mood is deafening, modern, and exhilarating. Captured with a dynamic, tilted perspective, emphasizing the shattered geometry of the exploding light."
- **Negative prompt:** "calm, realistic, photography, smooth gradients, soft clouds, peaceful"
- **Tags:** abstract, art, italian futurism, fireworks, city
- **Style / Reference:** Italian Futurism art movement, Giacomo Balla inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** bright explosive yellow, vivid crimson, harsh stark white, deep night blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270215_futurism-fireworks.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates the model's ability to interpret explosive light and sound through the hard-edged abstraction of Italian Futurism.

### Suggestion: Brass Volcanic Eruption
- **Date:** 2027-02-15
- **Prompt:** "An epic, surreal landscape where a massive volcano violently erupts, but the mountain and the flying debris are constructed entirely from polished brass clockwork and gears. The subject features thousands of interconnected brass cogs bursting apart under immense pressure. The lighting is intensely bright and dramatic, emanating from a blinding white-hot core of molten energy at the center of the eruption, casting sharp glints and deep shadows across the flying metallic debris. The mood is apocalyptic, mechanical, and awe-inspiring. Captured with an ultra-wide 14mm lens to emphasize the massive scale of the mechanical destruction."
- **Negative prompt:** "organic, lava, rock, earth, soft, calm, realistic nature"
- **Tags:** steampunk, landscape, volcano, brass, mechanical
- **Style / Reference:** surreal steampunk environment, cinematic 3D render
- **Composition:** expansive wide angle, explosive center, flying debris
- **Color palette:** polished warm brass, blinding white heat, deep metallic shadows
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270215_brass-volcano.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating complex flying mechanical debris and intense central light sources reflecting off polished metal.

### Suggestion: Biopunk Tsunami
- **Date:** 2027-02-15
- **Prompt:** "A terrifying, colossal tsunami wave made entirely of glowing, toxic biopunk sludge, towering over a dark, dystopian shoreline. The viscous, semi-translucent liquid subject is filled with glowing green and magenta cybernetic veins and pulsating biological sacs. The lighting is extremely dark and moody, illuminated solely by the sickly, bioluminescent glow of the toxic wave itself against a pitch-black, stormy sky. The mood is apocalyptic, alien, and deeply unsettling. Captured with a low-angle, wide perspective to make the glowing wall of sludge feel overwhelmingly massive and inevitable."
- **Negative prompt:** "clean water, daylight, sunny, beautiful, realistic ocean, blue sky"
- **Tags:** biopunk, landscape, tsunami, glowing, toxic
- **Style / Reference:** biopunk concept art, dark sci-fi, cinematic horror
- **Composition:** low angle, imposing wave filling the frame, rule of thirds
- **Color palette:** toxic neon green, glowing magenta, pitch black sky, dark murky sludge
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270215_biopunk-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing thick, viscous fluid dynamics combined with intense internal bioluminescent emission.

### Suggestion: Baroque Cybernetic Opera
- **Date:** 2026-12-25
- **Prompt:** "A grand, opulent Baroque opera house interior where the ornate golden balconies and velvet curtains are intertwined with glowing, high-tech cybernetic cables and neon pink fiber optics. The subject is a cyborg soprano wearing an intricate gown of spun glass and fiber, bathed in dramatic, theatrical spotlights that cast deep, rich shadows. The lighting is highly cinematic, featuring a stark contrast between the warm golden chandeliers and the cold, electric neon. The mood is extravagant, tragic, and intensely futuristic. Captured with a 35mm lens, wide aperture to softly blur the ornate background."
- **Negative prompt:** "simple, modern, flat lighting, daylight, cartoon, empty"
- **Tags:** cyberpunk, interior, baroque, opera, ornate
- **Style / Reference:** baroque architecture, cyberpunk aesthetic, cinematic lighting
- **Composition:** wide theatrical angle, centered subject, deep shadows
- **Color palette:** rich gold, deep crimson velvet, neon pink, electric cyan
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261225_baroque-cyber-opera.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing the blending of highly ornate, historical interior architecture with sleek, glowing cybernetic elements under dramatic theatrical lighting.

### Suggestion: Art Nouveau Clockwork Owl
- **Date:** 2026-12-25
- **Prompt:** "A hyper-detailed, macro portrait of an exquisite mechanical owl constructed from polished brass, copper, and dark mahogany, designed entirely with the flowing, organic whiplash curves characteristic of the Art Nouveau style. The subject's eyes are glowing amber lenses. The lighting is soft, warm, and diffused, simulating a sunny afternoon in a dusty, wood-paneled study, casting intricate, sweeping shadows from the mechanical feathers. The mood is elegant, antique, and wise. Captured with a 100mm macro lens, sharp focus on the complex, interlocking gears of the face."
- **Negative prompt:** "straight lines, modern, sleek, plastic, bright daylight, organic flesh, feathers"
- **Tags:** steampunk, macro, mechanism, owl, art nouveau
- **Style / Reference:** Art Nouveau metalwork, steampunk animal design
- **Composition:** tight portrait, flowing lines, shallow depth of field
- **Color palette:** warm polished brass, rich mahogany brown, glowing amber, subtle verdigris
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261225_art-nouveau-owl.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the model's ability to apply a specific historical style (Art Nouveau curves) to complex mechanical hard-surface modeling.

### Suggestion: Cymatic Sand Mandala
- **Date:** 2026-12-25
- **Prompt:** "A mesmerizing, top-down view of a complex cymatic pattern forming a perfect, geometric mandala out of fine, multi-colored sand on a flat black metal vibrating plate. The subject features incredibly intricate, symmetrical ridges and valleys created by sound frequencies. The lighting is incredibly sharp, low-angle rim lighting that grazes the surface of the sand, casting long, stark shadows that perfectly highlight the delicate texture and structural height of the ridges. The mood is hypnotic, mathematical, and precise. Captured with a sharp, flat orthographic perspective to emphasize the perfect symmetry."
- **Negative prompt:** "blurry, out of focus, asymmetrical, wet, liquid, messy, random"
- **Tags:** abstract, macro, cymatics, sand, geometric
- **Style / Reference:** scientific macro photography, cymatic pattern visualization
- **Composition:** perfectly symmetrical, top-down orthographic, edge-to-edge pattern
- **Color palette:** vibrant saffron yellow, deep crimson, stark white sand, pure black background
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261225_cymatic-sand-mandala.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the generation of incredibly fine, granular textures (sand) structured into perfect, complex geometric symmetry under harsh grazing light.

### Suggestion: Holographic Coral Reef
- **Date:** 2026-12-25
- **Prompt:** "An incredibly vibrant, surreal underwater scene of a massive coral reef where all the living structures are composed of semi-transparent, shifting holographic hard-light projections instead of organic matter. The subject pulses with digital glitches, scanlines, and intense neon colors. The lighting is completely internal, generated by the holographic coral itself, creating a blindingly colorful, surreal glow against the dark, murky ocean depths. The mood is synthetic, awe-inspiring, and futuristic. Captured with a wide-angle lens, surrounded by schools of glowing, wireframe digital fish."
- **Negative prompt:** "real coral, dull, surface, daylight, mud, brown, realistic fish"
- **Tags:** sci-fi, underwater, holographic, neon, abstract
- **Style / Reference:** cyberpunk aesthetic, digital art, glitch art
- **Composition:** wide expansive view, dynamic depth, glowing center
- **Color palette:** neon magenta, electric cyan, vibrant lime green, deep ocean black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261225_holographic-coral.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for pushing intense neon glow, holographic transparency, and digital glitch artifacts applied to organic underwater forms.

### Suggestion: Neon Noir Rainy Cyber-Market
- **Date:** 2026-12-25
- **Prompt:** "A dense, claustrophobic cyberpunk street market at midnight during a torrential downpour, depicted in a gritty Neon Noir style. The subject features stalls selling glowing cybernetic parts under tattered, translucent plastic tarps. The lighting is chaotic and brilliant, with harsh neon signs in various languages reflecting heavily off the wet pavement, slick raincoats, and metallic cyberware, creating a dizzying array of specular highlights and deep, crushing shadows. The mood is dangerous, atmospheric, and distinctly Noir. Captured with a 50mm lens, eye-level, focusing on the heavy rain and wet surface reflections."
- **Negative prompt:** "daylight, clean, bright, utopian, dry, simple, boring"
- **Tags:** cyberpunk, urban, neon noir, rain, market
- **Style / Reference:** cinematic cyberpunk concept art, neo-noir photography
- **Composition:** dense, cluttered, deep perspective down the street
- **Color palette:** stark neon pink, acid green, deep shadow black, wet asphalt grey
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261225_neon-noir-market.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating complex reflections on wet surfaces (rain, asphalt) mixed with multiple colored neon light sources and dense urban clutter.

### Suggestion: Biopunk Graphene Observatory
- **Date:** 2027-03-01
- **Prompt:** "A sprawling biopunk astronomical observatory perched on a rocky cliff. The subject is constructed from ultra-strong, dark graphene interwoven with pulsating, bioluminescent organic vines. The lighting is nocturnal and moody, with a giant, glowing blue exoplanet rising in the background, casting ethereal cool light across the matte black graphene. The mood is scientific, alien, and deeply serene. Captured with a wide-angle 16mm lens, highlighting the contrast between the rigid, dark geometry of the observatory and the glowing, fleshy organic components."
- **Negative prompt:** "daylight, sun, bright, modern, clean, people, cartoon, soft"
- **Tags:** sci-fi, biopunk, architecture, graphene, night
- **Style / Reference:** dark sci-fi concept art, photorealistic rendering
- **Composition:** wide angle, imposing structure, low horizon
- **Color palette:** matte dark grey, glowing neon blue, bioluminescent green, pitch black sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270301_graphene-observatory.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing matte, light-absorbing textures intertwined with glowing organic features under night sky lighting.

### Suggestion: Neoclassical Bismuth Library
- **Date:** 2027-03-01
- **Prompt:** "A majestic, Neoclassical library interior where the towering, fluted columns and grand arched ceilings are formed entirely from giant, iridescent bismuth hopper crystals. The subject features massive bookshelves filled with glowing, ethereal tomes. The lighting is cinematic and mystical, with god-rays of warm golden light streaming through a high dome, striking the metallic bismuth surfaces and reflecting a dazzling rainbow of thin-film interference colors. The mood is scholarly, ancient, and deeply magical. Captured with a 24mm wide lens from a low angle, emphasizing the towering geometric pillars."
- **Negative prompt:** "wood, plain stone, modern, fluorescent lights, messy, blurry, simple"
- **Tags:** fantasy, architecture, interior, bismuth, neoclassical
- **Style / Reference:** fantasy architectural visualization, hyper-realistic 3D render
- **Composition:** low angle looking up, symmetrical, deep perspective
- **Color palette:** iridescent rainbow, warm golden light, glowing white, deep shadows
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270301_bismuth-library.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for pushing iridescent metallic reflections combined with grand historical architectural styles.

### Suggestion: Ashcan School Steampunk Alley
- **Date:** 2027-03-01
- **Prompt:** "A gritty, steam-filled alleyway in a heavily industrialized Victorian city, depicted in the raw, documentary style of the Ashcan School. The subject focuses on weary mechanics working on a massive, brass-plated steam carriage. The lighting is overcast, smoky, and dim, relying on the muted, naturalistic light filtering through the thick smog to cast soft, indistinct shadows over the dirt and grime of the cobblestones. The mood is authentic, raw, and exhausted. Captured with an eye-level perspective, emphasizing the harsh reality of urban steampunk life."
- **Negative prompt:** "clean, shiny, bright, utopian, modern, neon, highly saturated"
- **Tags:** steampunk, urban, historical, ashcan school, gritty
- **Style / Reference:** Ashcan School painting, Robert Henri inspired, thick brushstrokes
- **Composition:** eye-level, cluttered alley, naturalistic framing
- **Color palette:** muted ochre, dark greys, rusted browns, dull brass
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270301_ashcan-steampunk.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of gritty historical art movements with fantastical steampunk elements and muted lighting.

### Suggestion: Mother of Pearl Volcanic Eruption
- **Date:** 2027-03-01
- **Prompt:** "A surreal and breathtaking landscape of a massive volcano erupting, but instead of magma, it spews rivers of liquid, shimmering mother of pearl. The subject features towering plumes of iridescent ash and glowing, pearlescent lava flowing down the mountain. The lighting is dramatic and ethereal, with the internal glow of the eruption reflecting off the nacreous surfaces to create a spectacular array of pastel interference patterns against a dark, stormy sky. The mood is awe-inspiring, chaotic, and exquisitely beautiful. Captured with a wide-angle lens from a safe distance, capturing the immense scale of the eruption."
- **Negative prompt:** "red lava, orange, fire, realistic volcano, smoke, messy, blurry"
- **Tags:** landscape, surreal, volcano, mother of pearl, iridescent
- **Style / Reference:** surreal digital art, photorealistic nature photography
- **Composition:** wide landscape, explosive center, dramatic clouds
- **Color palette:** pearlescent pinks, shimmering silver, soft cyan, dark stormy grey
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270301_mother-of-pearl-volcano.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating fluid dynamics combined with thin-film iridescent materials and glowing pastel lighting.

### Suggestion: Italian Futurism Aerogel Train
- **Date:** 2027-03-01
- **Prompt:** "A chaotic, high-speed scene of a futuristic maglev train tearing across a bridge, depicted in the harsh, fragmented style of Italian Futurism. The subject is composed of ultra-light, translucent blue aerogel, but rendered through aggressive, jagged diagonal lines and overlapping geometric planes that capture the immense speed and kinetic energy. The lighting is dynamic and directional, casting stark, jagged shadows that enhance the splintered geometry of the translucent material. The mood is energetic, modern, and overpowering. Captured with a highly tilted perspective to emphasize raw motion and mechanical blur."
- **Negative prompt:** "calm, stationary, realistic, photography, smooth curves, organic"
- **Tags:** abstract, art, italian futurism, train, aerogel, speed
- **Style / Reference:** Italian Futurism art movement, Luigi Russolo inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** ghostly aerogel blue, steel greys, harsh stark white, kinetic blur
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270301_futurism-aerogel-train.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the dynamic abstraction of Italian Futurism to translucent, highly scattering materials in motion.

### Suggestion: Bioluminescent Glass Terrarium
- **Date:** 2027-05-10
- **Prompt:** "A macro, highly detailed photograph of a Victorian-style geometric glass terrarium resting on an old wooden desk. Inside the terrarium, a miniature ecosystem of bioluminescent fungi and glowing neon-blue ferns thrives in the damp soil. The lighting is low-key and moody, predominantly emanating from the glowing flora inside the glass, casting intricate, colorful shadows onto the polished wood. The mood is magical, quiet, and enchanted. Captured with a 100mm macro lens, shallow depth of field, highlighting the condensation on the glass panes."
- **Negative prompt:** "bright daylight, artificial room lights, messy, blurry, low resolution, people"
- **Tags:** macro, fantasy, bioluminescent, terrarium, glowing
- **Style / Reference:** photorealistic macro photography, fantasy still-life
- **Composition:** center-focused, shallow depth of field, eye-level
- **Color palette:** glowing neon blue, vibrant magenta, dark polished wood, pitch black shadows
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270510_bioluminescent-terrarium.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing sub-surface scattering, glass refraction, and internal glowing light sources.

### Suggestion: Art Deco Cyber-Panther
- **Date:** 2027-05-10
- **Prompt:** "A sleek, majestic cybernetic panther standing on a rain-slicked city rooftop at night. The panther's body is intricately designed in the Art Deco style, featuring overlapping plates of polished obsidian, gleaming gold filigree, and glowing amber optics. The lighting is cinematic and dramatic, with the harsh, cold blue neon lights of the cyberpunk city contrasting against the warm, golden glow radiating from the panther's internal mechanics. The mood is formidable, elegant, and dangerous. Captured with a 50mm lens, low angle to emphasize the panther's imposing silhouette against the foggy skyline."
- **Negative prompt:** "organic fur, daylight, bright sky, cartoon, simple, lowres, sloppy"
- **Tags:** cyberpunk, art deco, animal, cybernetic, neon
- **Style / Reference:** cinematic cyberpunk concept art, hard surface modeling
- **Composition:** low angle, rule of thirds, dramatic framing
- **Color palette:** polished obsidian black, gleaming gold, electric blue neon, warm amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270510_art-deco-panther.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating complex hard-surface reflections, metallic gold textures, and contrasting neon lighting.

### Suggestion: Origami Space Station
- **Date:** 2027-05-10
- **Prompt:** "A breathtaking view of a massive, intricate space station orbiting a glowing pale-blue exoplanet, constructed entirely from meticulously folded, giant sheets of pristine white origami paper. The paper subject features sharp, precise creases and geometric solar sails catching the blinding light of a distant star. The lighting is harsh, unattenuated cosmic sunlight, creating stark black shadows within the crisp folds of the paper and a brilliant white glare on the illuminated surfaces. The mood is surreal, delicate, and technologically poetic. Captured with a wide-angle cinematic lens to show the delicate paper structure against the vastness of space."
- **Negative prompt:** "metal, plastic, realistic machinery, soft curves, blurry, organic"
- **Tags:** sci-fi, space, origami, surreal, megastructure
- **Style / Reference:** surreal digital art, hyper-realistic papercraft
- **Composition:** wide angle, stark contrast, massive scale
- **Color palette:** pristine white paper, deep cosmic black, glowing pale blue
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270510_origami-space-station.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing sharp geometric shadowing on matte, fibrous materials (paper) in a high-contrast lighting environment.

### Suggestion: Cyberpunk Hover-Train
- **Date:** 2027-05-10
- **Prompt:** "A high-speed, dynamic shot of a sleek cyberpunk hover-train tearing through a dense, neon-lit megacity at midnight. The train is a bullet-shaped marvel of brushed steel and glowing cyan repulsor engines. The lighting is incredibly vibrant, with motion-blurred streaks of neon pink, yellow, and blue from the passing city signs reflecting off the train's polished hull. The mood is energetic, futuristic, and chaotic. Captured with a tracking camera using a slow shutter speed, keeping the train sharply in focus while the city background blurs into horizontal streaks of light."
- **Negative prompt:** "slow, stationary, daylight, steam train, old, quiet, dull colors"
- **Tags:** cyberpunk, vehicle, train, speed, neon
- **Style / Reference:** cinematic sci-fi photography, motion blur technique
- **Composition:** dynamic horizontal motion, tracking shot, tight framing on the train
- **Color palette:** brushed steel grey, vibrant neon pink, cyan repulsor glow, electric yellow
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270510_cyberpunk-hovertrain.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating directional motion blur effects and complex neon reflections on fast-moving metallic objects.

### Suggestion: Liquid Gold Waterfall
- **Date:** 2027-05-10
- **Prompt:** "A majestic, surreal landscape featuring a towering waterfall cascading down a sheer cliff face, but instead of water, it is a flowing torrent of molten, liquid gold. The heavy, viscous metallic fluid crashes into a churning, glowing pool at the base. The lighting is a dramatic, moody twilight, where the incredibly bright, warm glow of the liquid gold illuminates the surrounding dark, jagged obsidian rocks with intense, fiery reflections. The mood is opulent, mythical, and awe-inspiring. Captured with a wide 24mm lens, utilizing a fast shutter speed to capture the intricate, splashing droplets of molten metal in mid-air."
- **Negative prompt:** "real water, blue, green, daylight, bright sky, soft, blurry, low resolution"
- **Tags:** landscape, surreal, waterfall, gold, metallic
- **Style / Reference:** surreal nature photography, hyper-detailed fluid simulation
- **Composition:** vertical composition, imposing scale, low angle
- **Color palette:** brilliant molten gold, deep obsidian black, dark twilight blue
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270510_liquid-gold-waterfall.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for pushing the generation of heavy, viscous fluid dynamics and intensely reflective, self-illuminating metallic materials.

### Suggestion: Graphene Exoplanet Core
- **Date:** 2027-06-01
- **Prompt:** "An ultra-macro, photorealistic visualization deep within the core of an exoplanet, where immense pressure has forged a labyrinth of dark, matte graphene structures. The geometric subject absorbs almost all light, contrasting sharply with rivers of super-heated, blindingly bright plasma flowing through the hexagonal lattice. The lighting is intensely harsh, emanating entirely from the plasma rivers, creating a stark interplay of blinding white-hot streaks against crushing black geometry. The mood is terrifying, alien, and unfathomably powerful. Captured with a microscopic camera perspective, freezing the dynamic flow of plasma against the rigid, light-absorbing carbon structure."
- **Negative prompt:** "surface, sky, daylight, soft lighting, blurry, organic, earth-like, low contrast"
- **Tags:** sci-fi, macro, exoplanet, core, graphene, plasma
- **Style / Reference:** scientific visualization, hyper-detailed hard sci-fi
- **Composition:** chaotic yet geometric, sharp macro focus, dense
- **Color palette:** pitch black, blinding white-hot, intense neon blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270601_graphene-exoplanet-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of intensely bright internal light sources interacting with perfectly matte, light-absorbing structures (graphene).

### Suggestion: Brass Giant Beehive
- **Date:** 2027-06-01
- **Prompt:** "A highly detailed, macro view deep inside a gigantic, clockwork beehive constructed entirely of polished brass and copper. The subject features thousands of perfectly repeating hexagonal cells containing glowing, viscous amber-colored oil instead of honey. Tiny mechanical bees with delicate copper wings tend to the cells. The lighting is warm and directional, catching the edges of the metallic hexagons to create brilliant specular glints and deep, rich shadows in the recesses. The mood is industrious, precise, and whimsical. Captured with a 100mm macro lens, deep depth of field to emphasize the endless geometric repetition of the metallic honeycomb."
- **Negative prompt:** "organic, real bees, nature, soft, blurry, messy, daylight"
- **Tags:** steampunk, macro, beehive, brass, mechanical
- **Style / Reference:** macro product photography, hyper-detailed steampunk
- **Composition:** full frame repeating pattern, deep perspective
- **Color palette:** polished brass, warm copper, glowing amber oil, deep metallic shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270601_brass-giant-beehive.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the generation of perfect, repeating metallic geometry (hexagons) under warm, directional lighting.

### Suggestion: Mother of Pearl Orbital Ring
- **Date:** 2027-06-01
- **Prompt:** "An epic, sweeping view of a colossal Orbital Ring megastructure encircling a gas giant, built entirely from massive, interlocking plates of shimmering mother of pearl (nacre). The ring structure reflects a spectacular array of pearlescent pastels. The lighting features a dramatic sunrise from the nearby star, catching the smooth ridges of the nacre to reveal intense rainbow interference patterns against the deep cosmic void. The mood is utopian, majestic, and elegantly alien. Captured with a wide-angle cinematic lens from low orbit, emphasizing the vast, sweeping curve of the iridescent structure against the dark sky."
- **Negative prompt:** "dystopian, rusty, dark, gritty, small scale, earth, organic"
- **Tags:** sci-fi, space, megastructure, mother of pearl, orbital ring
- **Style / Reference:** cinematic space art, utopian sci-fi concept design
- **Composition:** curved horizon, extreme wide angle, massive scale
- **Color palette:** pearlescent pinks, soft baby blues, shimmering silver, cosmic black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270601_mother-of-pearl-orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates large-scale thin-film iridescent interference mapped to a massive, smooth, geometric megastructure in space.

### Suggestion: Ashcan School Tsunami
- **Date:** 2027-06-01
- **Prompt:** "A massive, terrifying tsunami wave crashing down on an early 20th-century industrial waterfront, depicted in the raw, gritty style of the Ashcan School. The subject features dark, churning water tearing through smokestacks and wooden piers. The lighting is overcast, bleak, and murky, casting soft, indistinct shadows that emphasize the dirt, texture, and chaotic power of the destruction. The mood is grim, authentic, and overwhelming. Captured with an eye-level, documentary-style perspective, focusing on the unglamorous and terrifying reality of the disaster from the viewpoint of the docks."
- **Negative prompt:** "modern, clean, bright colors, sunny, cheerful, photorealistic, 3d render"
- **Tags:** art, disaster, tsunami, historical, ashcan school, gritty
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** eye-level, chaotic framing, imposing wave
- **Color palette:** murky greens, muted greys, rusted browns, dull ochre
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270601_ashcan-school-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of a massive natural disaster with the gritty, muted, everyday-life style of the Ashcan School.

### Suggestion: Italian Futurism Supernova
- **Date:** 2027-06-01
- **Prompt:** "A cataclysmic supernova explosion depicted in the harsh, fragmented style of Italian Futurism. The cosmic subject features aggressive, jagged diagonal lines and overlapping geometric planes radiating outward, capturing the immense explosive speed and raw stellar energy. The lighting is highly contrasted and intense, simulating blinding flashes of radiation tearing through the void of space. The mood is energetic, destructive, and overwhelmingly powerful. Captured with a dynamic, tilted perspective, emphasizing the shattered geometry and raw kinetic motion of the expanding star."
- **Negative prompt:** "calm, realistic space, smooth gradients, photography, soft clouds, gentle"
- **Tags:** abstract, art, italian futurism, space, supernova, explosion
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, explosive center
- **Color palette:** blinding stark white, vivid crimson, harsh yellow, deep cosmic black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270601_futurism-supernova.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to an epic cosmic event.

### Suggestion: Constructivism Mega-Factory
- **Date:** 2027-06-15
- **Prompt:** "A colossal, sprawling industrial mega-factory depicted in the stark, geometric style of Constructivism. The subject features towering smokestacks, massive iron gears, and sweeping diagonal conveyer belts. The lighting is harsh and dramatic, casting stark, angular shadows that emphasize the monumental scale and mechanical power of the facility. The mood is imposing, revolutionary, and deeply industrial. Captured with a dynamic, low-angle perspective, emphasizing the towering structural beams and relentless mechanical motion."
- **Negative prompt:** "organic, nature, soft curves, realistic photography, peaceful, bright colors"
- **Tags:** abstract, art, constructivism, industrial, factory
- **Style / Reference:** Constructivism art movement, Vladimir Tatlin inspired
- **Composition:** dynamic diagonals, low angle, monumental scale
- **Color palette:** stark black, pure white, rusted iron red, harsh industrial grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270615_constructivism-megafactory.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the application of the strict, geometric abstraction of Constructivism to a massive industrial environment.

### Suggestion: Porcelain Android Portrait
- **Date:** 2027-06-15
- **Prompt:** "A hyper-detailed, surreal fashion portrait of an advanced android whose outer shell is constructed entirely from delicate, cracked white porcelain painted with intricate blue willow patterns. The subject's face is serene, with glowing fiber-optic eyes piercing through the smooth ceramic mask. The lighting is soft and diffused, similar to a high-end studio setup, highlighting the glossy specular reflections and the fine spiderweb cracks in the porcelain. The mood is melancholic, fragile, and beautiful. Captured with an 85mm portrait lens, featuring a shallow depth of field that softly blurs the dark studio background."
- **Negative prompt:** "metallic, plastic, messy, realistic human skin, bright daylight, outdoor"
- **Tags:** surreal, portrait, android, porcelain, sci-fi
- **Style / Reference:** surreal fashion photography, high-end product lighting
- **Composition:** centered portrait, eye-level, shallow depth of field
- **Color palette:** glossy white porcelain, cobalt blue patterns, soft glowing cyan, dark background
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270615_porcelain-android.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating highly glossy, reflective materials with intricate surface details (cracks, painted patterns) under studio lighting.

### Suggestion: Rococo Space Station Interior
- **Date:** 2027-06-15
- **Prompt:** "An incredibly opulent interior view of a majestic space station designed entirely in the lavish Rococo style. The subject features sweeping asymmetrical curves, gilded stuccowork, pastel frescoes, and enormous crystal chandeliers floating in zero gravity. The lighting is incredibly soft and romantic, with warm golden light bouncing off the abundant gold leaf and pastel surfaces, while a massive viewing window reveals a vibrant pink nebula outside. The mood is extravagant, aristocratic, and dreamlike. Captured with a wide-angle 16mm lens to encompass the breathtaking architectural detail and the cosmic view."
- **Negative prompt:** "minimalist, brutalist, dark, gritty, cyberpunk, modern, boring"
- **Tags:** sci-fi, architecture, interior, rococo, space
- **Style / Reference:** Rococo architecture, lavish sci-fi concept art
- **Composition:** wide angle, symmetrical opulence, deep perspective
- **Color palette:** soft pastel pinks, pale mint greens, abundant gold leaf, cosmic magenta
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270615_rococo-spacestation.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing the blending of highly ornate, opulent historical architecture with advanced sci-fi settings and zero-gravity elements.

### Suggestion: Liquid Mercury Ocean
- **Date:** 2027-06-15
- **Prompt:** "A mesmerizing, surreal landscape featuring a vast, churning ocean composed entirely of highly reflective liquid mercury. The heavy, metallic waves crash against a jagged shoreline of dark obsidian. The lighting is intensely dramatic, with a low-hanging, massive red giant star casting a brilliant, distorted crimson reflection across the entire undulating surface of the metallic ocean. The mood is alien, heavy, and awe-inspiring. Captured with a wide 24mm lens, utilizing a fast shutter speed to freeze the intricate, mirror-like droplets of crashing mercury."
- **Negative prompt:** "blue water, realistic ocean, white foam, daylight, soft, blurry, organic"
- **Tags:** landscape, surreal, ocean, mercury, metallic
- **Style / Reference:** surreal sci-fi landscape, hyper-detailed fluid simulation
- **Composition:** low horizon, wide expansive view, dramatic wave action
- **Color palette:** highly reflective silver, deep obsidian black, brilliant crimson red
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270615_liquid-mercury-ocean.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating complex fluid dynamics combined with perfect, mirror-like metallic reflections across a vast surface.

### Suggestion: Jade Cybernetic Dragon
- **Date:** 2027-06-15
- **Prompt:** "An ultra-detailed, macro shot of a magnificent cybernetic dragon whose armor plating is carved entirely from translucent, luminous green jade. The subject is coiled around a glowing server rack in a dark, high-tech vault. The lighting is low-key and dramatic, relying on the internal, pulsing golden light of the dragon's cybernetic core to illuminate the jade from within, creating a stunning sub-surface scattering effect that highlights the stone's natural inclusions. The mood is ancient, powerful, and technologically supreme. Captured with a 100mm macro lens, sharp focus on the carved jade scales of the dragon's head."
- **Negative prompt:** "plastic, flat lighting, bright daylight, organic flesh, soft, blurry"
- **Tags:** macro, fantasy, cybernetic, jade, dragon
- **Style / Reference:** photorealistic macro product photography, intricate carving
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** translucent emerald green, glowing warm gold, deep technological black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270615_jade-dragon.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing sub-surface scattering on intricate, hard-surface carved stone (jade) mixed with glowing technological elements.

### Suggestion: Graphene Deep Sea Submarine
- **Date:** 2027-07-01
- **Prompt:** "A sleek, stealthy deep-sea submarine constructed entirely from dark, light-absorbing graphene, gliding silently over a glowing bioluminescent trench. The lighting is extremely dark, relying solely on the eerie, glowing blue and green light emanating from the trench below, which catches the matte surface of the graphene hull. The mood is tense, mysterious, and claustrophobic. Captured with a wide 24mm lens to emphasize the massive scale of the dark ocean depths and the sleek geometry of the vessel."
- **Negative prompt:** "bright sunlight, surface, clear water, shiny metal, plastic, colorful"
- **Tags:** sci-fi, underwater, vehicle, graphene, dark
- **Style / Reference:** cinematic sci-fi concept art, deep sea exploration
- **Composition:** wide angle, low lighting, vast scale
- **Color palette:** matte dark grey, glowing bioluminescent blue and green, pitch black water
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270701_graphene-submarine.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of matte, light-absorbing textures (graphene) in extremely low-light, bioluminescent environments.

### Suggestion: Tweed Cybernetic Cheetah
- **Date:** 2027-07-01
- **Prompt:** "A hyper-detailed, surreal macro shot of a cybernetic cheetah mid-sprint, where its sleek armor plating is entirely upholstered in classic, warm brown herringbone tweed fabric. The robotic subject features glowing orange optic sensors and exposed chrome joints beneath the fabric. The lighting is a dramatic golden hour sunset, casting long shadows and highlighting the intricate woven texture of the tweed against the blurred, fast-moving background of a futuristic savanna. The mood is absurd, dynamic, and highly detailed. Captured with a 100mm telephoto lens, utilizing motion blur panning to keep the cheetah sharp while blurring the environment."
- **Negative prompt:** "organic fur, slow, stationary, bright daylight, realistic animal, plain metal"
- **Tags:** surreal, cybernetic, animal, tweed, macro
- **Style / Reference:** surreal wildlife photography, hyper-detailed material swap
- **Composition:** dynamic horizontal motion, tight framing, panning blur
- **Color palette:** earthy brown tweed, warm golden sunset, glowing orange, blurred green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270701_tweed-cheetah.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates the application of soft, woven micro-textures (tweed) on dynamic, fast-moving robotic subjects with panning motion blur.

### Suggestion: Damascus Steel Grand Piano
- **Date:** 2027-07-01
- **Prompt:** "A grand piano sitting isolated in the center of a grand, abandoned concert hall, forged entirely from dark, intricately rippled Damascus steel. The metallic subject features flowing light and dark grey wave patterns across its entire surface, with gleaming silver keys. The lighting is incredibly dramatic and moody, with a single, intense beam of volumetric moonlight piercing through a shattered skylight to illuminate the piano, casting deep black shadows across the dusty stage. The mood is melancholic, elegant, and silent. Captured with a 50mm lens from a slightly elevated angle to showcase the rippled patterns on the piano lid."
- **Negative prompt:** "wood, plastic, daylight, clean, modern, bright room, people"
- **Tags:** still-life, interior, damascus steel, music, abandoned
- **Style / Reference:** photorealistic still-life photography, moody architectural render
- **Composition:** centered subject, dramatic spotlight, dusty atmosphere
- **Color palette:** dark metallic greys, stark white moonlight, deep shadow black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270701_damascus-piano.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing the flowing texture generation of Damascus steel on large, elegant surfaces under intense volumetric spotlighting.

### Suggestion: Aerogel Gothic Cathedral
- **Date:** 2027-07-01
- **Prompt:** "An imposing Gothic cathedral towering over a quiet European town, constructed completely out of weightless, translucent blue aerogel. The architectural subject features intricate flying buttresses and towering spires that appear ghostly and ephemeral. The lighting is a bright, clear midday sun, piercing directly through the massive porous structure, creating a million soft, internal refractions and a glowing, ethereal blue aura that bathes the surrounding stone courtyard. The mood is holy, surreal, and incredibly peaceful. Captured with a wide 14mm lens, looking up to emphasize the towering, weightless spires."
- **Negative prompt:** "solid stone, dark, night, creepy, heavy, realistic architecture"
- **Tags:** surreal, architecture, gothic, aerogel, ethereal
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** low angle looking up, symmetrical, massive scale
- **Color palette:** ghostly aerogel blue, blinding white sunlight, warm stone grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270701_aerogel-cathedral.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large, incredibly detailed architectural structures made of highly scattering, low-density translucent materials under direct sunlight.

### Suggestion: Bismuth Cyberpunk Server Room
- **Date:** 2027-07-01
- **Prompt:** "A claustrophobic, high-tech cyberpunk server room where the towering server racks and cooling pipes are naturally formed from massive, iridescent bismuth hopper crystals. The metallic, geometric subjects interlock flawlessly, glowing with internal neon pink and cyan data streams. The lighting is moody and entirely artificial, relying on the glowing data streams to reflect off the faceted bismuth, creating a dazzling array of thin-film interference colors in the dark, cramped space. The mood is advanced, chaotic, and mesmerizing. Captured with a 24mm wide lens, using a deep depth of field to capture the endless rows of crystalline servers."
- **Negative prompt:** "daylight, natural, organic, soft curves, plain metal, clean, simple"
- **Tags:** cyberpunk, interior, tech, bismuth, iridescent
- **Style / Reference:** cyberpunk concept art, hyper-detailed environment design
- **Composition:** one-point perspective, deep corridor, overwhelming detail
- **Color palette:** iridescent rainbow, glowing neon pink and cyan, deep shadow black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270701_bismuth-server-room.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating complex, repeating geometric structures interacting with highly saturated iridescent thin-film materials and neon lighting.

### Suggestion: Damascus Steel Beaver Dam
- **Date:** 2027-08-01
- **Prompt:** "A highly detailed, surreal landscape photography shot of a beaver dam constructed entirely from intricately rippled Damascus steel logs and branches. The metallic subject blocks a tranquil, dark forest stream. The lighting is early morning sunlight piercing through the dense canopy, casting sharp, bright specular glints on the metallic wave patterns and deep, moody shadows in the crevices of the dam. The mood is unnatural, fascinating, and quiet. Captured with a 35mm lens, low angle near the water surface, focusing on the complex flowing textures of the steel against the natural water."
- **Negative prompt:** "wood, organic branches, mud, dull metal, blurry, out of focus, bright daylight"
- **Tags:** surreal, landscape, nature, damascus steel, beaver dam
- **Style / Reference:** surreal nature photography, hyper-detailed material swap
- **Composition:** wide shot, low angle, rule of thirds
- **Color palette:** dark metallic greys, bright silver glints, lush forest greens, dark water
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270801_damascus-beaver-dam.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the application of complex, flowing metallic textures (Damascus steel) onto organic, chaotic structures (beaver dam).

### Suggestion: Aerogel Bioluminescent Reef
- **Date:** 2027-08-01
- **Prompt:** "A breathtaking, macro underwater photograph of a sprawling coral reef where the coral formations are composed entirely of ultra-light, translucent blue aerogel. The subject is populated by tiny, glowing bioluminescent sea life that illuminates the reef from within. The lighting is exclusively from the bioluminescence, creating thousands of soft, internal refractions within the porous aerogel and a ghostly, ethereal glow that barely penetrates the surrounding dark water. The mood is silent, magical, and alien. Captured with a 50mm macro lens, shallow depth of field, blurring the deep ocean background."
- **Negative prompt:** "bright sunlight, surface, muddy water, opaque coral, realistic fish"
- **Tags:** underwater, nature, macro, aerogel, bioluminescent
- **Style / Reference:** photorealistic underwater photography, surreal material swap
- **Composition:** macro close-up, centered subject, beautiful soft bokeh
- **Color palette:** ghostly aerogel blue, glowing neon green and magenta, pitch black water
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270801_aerogel-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the interaction of internal, self-illuminating light sources within highly scattering, low-density translucent materials.

### Suggestion: Tweed Supernova
- **Date:** 2027-08-01
- **Prompt:** "A surreal, epic cosmic visualization of a cataclysmic supernova explosion, where the expanding clouds of stellar gas and plasma are inexplicably formed from unraveling threads and soft folds of warm brown herringbone tweed fabric. The central subject is a blindingly bright stellar core tearing through the fabric. The lighting is harsh, unattenuated cosmic light from the core casting deep, dark shadows in the folds of the tweed, highlighting its woven micro-texture against the pitch-black void of space. The mood is absurd, dramatic, and tactile. Captured with a wide-angle cinematic lens to emphasize the massive cosmic scale."
- **Negative prompt:** "realistic space, glowing plasma, smooth, metallic, blurry, low resolution"
- **Tags:** sci-fi, space, surreal, supernova, tweed
- **Style / Reference:** surreal digital art, hyper-detailed material swap
- **Composition:** expansive wide angle, explosive center, flying fabric debris
- **Color palette:** earthy brown tweed, blinding stark white, deep cosmic black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270801_tweed-supernova.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of soft, woven micro-textures (tweed) subjected to intense, dramatic lighting on a massive cosmic scale.

### Suggestion: Italian Futurism Exoplanet Core
- **Date:** 2027-08-01
- **Prompt:** "An ultra-macro, theoretical visualization deep within the core of an exoplanet, depicted in the harsh, fragmented style of Italian Futurism. The subject features aggressive, jagged diagonal lines and overlapping geometric planes representing super-compressed carbon and violent plasma flows. The lighting is intensely bright and chaotic, emanating from the plasma and casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective, emphasizing the raw motion and explosive pressure of the core."
- **Negative prompt:** "calm, stationary, photorealistic, soft curves, gentle, natural, organic"
- **Tags:** abstract, art, italian futurism, space, exoplanet, core
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, explosive center
- **Color palette:** blinding white-hot, intense neon blue, stark black, vivid crimson
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270801_futurism-exoplanet-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to convey extreme pressure and kinetic energy.

### Suggestion: Ashcan School Fireworks
- **Date:** 2027-08-01
- **Prompt:** "A bustling, gritty early 20th-century city street at night, illuminated by a spectacular fireworks display, depicted in the raw, documentary style of the Ashcan School. The subject focuses on working-class crowds looking up at the sky, their faces lit by the colorful explosions. The lighting is moody and realistic, with the bright flashes of the fireworks casting soft, indistinct, colored shadows that highlight the dirt and texture of the urban tenements. The mood is authentic, celebratory yet unglamorous. Captured with an eye-level, documentary-style perspective, focusing on the people and the urban reality."
- **Negative prompt:** "modern, clean, bright daylight, photorealistic, 3d render, highly saturated, smooth"
- **Tags:** art, urban, historical, ashcan school, fireworks
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** eye-level, crowded street, naturalistic framing, looking up
- **Color palette:** muted greys, rusted browns, sudden flashes of vivid red and dull gold
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270801_ashcan-school-fireworks.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of bright, dynamic light sources (fireworks) with the gritty, muted, everyday-life style of the Ashcan School.

### Suggestion: Neon Solarpunk Balcony
- **Date:** 2026-08-15
- **Prompt:** "A medium shot of a lush, solarpunk balcony at night in a futuristic metropolis. The subject is a dense garden of glowing bioluminescent ferns and orchids, interspersed with sleek, white ceramic solar panels and curved glass railings. The lighting is a striking mix of the soft cyan glow from the plants and the harsh, distant neon magenta and yellow lights from the city's towering skyscrapers in the background. The mood is tranquil yet highly advanced, capturing a quiet oasis above the chaotic city. Captured with a 50mm lens, shallow depth of field, rendering the distant city lights as large, beautiful bokeh."
- **Negative prompt:** "dystopian, dark, gritty, cyberpunk, messy, pollution, daylight"
- **Tags:** solarpunk, architecture, nature, bioluminescent, night
- **Style / Reference:** utopian architectural visualization, photorealistic night photography
- **Composition:** medium shot, rule of thirds, shallow depth of field
- **Color palette:** glowing cyan, neon magenta, bright yellow, crisp white ceramic
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260815_neon-solarpunk-balcony.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing bioluminescent flora combined with out-of-focus background neon bokeh.

### Suggestion: Biomechanical Sphinx
- **Date:** 2026-08-15
- **Prompt:** "A wide, low-angle shot of a colossal, biomechanical Sphinx resting in a sprawling, desolate desert of black sand. The subject is constructed from interwoven carbon fiber muscles, polished chrome armor plates, and exposed, glowing red hydraulic fluid tubes. The lighting is an intense, harsh midday sun beating down, creating stark, blinding specular highlights on the chrome and deep, impenetrable black shadows under the creature's massive paws. The mood is ancient, terrifying, and overwhelmingly powerful. Captured with a wide 24mm lens to emphasize the massive scale of the mechanical beast against the barren landscape."
- **Negative prompt:** "organic, realistic animal, soft lighting, greenery, people, messy"
- **Tags:** sci-fi, biomechanical, desert, monument, colossal
- **Style / Reference:** hard sci-fi concept art, photorealistic 3D render
- **Composition:** low angle, monumental scale, wide expansive view
- **Color palette:** polished chrome, deep black sand, glowing crimson red, stark blue sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260815_biomechanical-sphinx.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating highly reflective metallic surfaces and complex biomechanical hard-surface modeling under harsh direct lighting.

### Suggestion: Subterranean Fungi Metropolis
- **Date:** 2026-08-15
- **Prompt:** "An incredibly detailed, sweeping view of an advanced, subterranean metropolis built entirely within and out of colossal, bioluminescent fungi. The organic, mushroom-like structures feature intricate, carved windows emitting warm amber light. The lighting relies on the natural, multi-colored glow of the fungi themselves—cyan, magenta, and green—illuminating the vast, misty cavern. The mood is magical, bustling, and deeply alien. Captured with a wide-angle lens, utilizing a deep depth of field to showcase the complex, multi-tiered architecture stretching far into the cavernous distance."
- **Negative prompt:** "surface, sky, daylight, human architecture, concrete, metal, simple"
- **Tags:** fantasy, subterranean, city, bioluminescent, organic
- **Style / Reference:** fantasy environment design, highly detailed 3D rendering
- **Composition:** expansive view, deep perspective, multi-tiered
- **Color palette:** glowing cyan, magenta, neon green, warm amber light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260815_fungi-metropolis.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the creation of complex, organic architectural structures illuminated by multiple varied bioluminescent light sources.

### Suggestion: Graphene Katana Macro
- **Date:** 2026-08-15
- **Prompt:** "An extreme macro, highly detailed photograph of the blade of a futuristic katana forged from pure, light-absorbing graphene. The subject's dark, matte surface is adorned with a microscopic, glowing azure circuit pattern etched directly into the carbon structure. The lighting is highly controlled, directional studio lighting that grazes the matte blade, highlighting the incredibly sharp edge and the intense, pulsating glow of the micro-circuitry against the pitch-black material. The mood is lethal, precise, and technologically advanced. Captured with a 100mm macro lens, razor-thin depth of field, focusing entirely on the glowing etchings."
- **Negative prompt:** "shiny metal, polished, traditional sword, messy background, wide angle"
- **Tags:** macro, sci-fi, weapon, graphene, circuits
- **Style / Reference:** photorealistic product photography, macro texture study
- **Composition:** extreme close-up, diagonal leading line, shallow depth of field
- **Color palette:** matte pitch black, intense glowing azure, stark lighting
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260815_graphene-katana.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating the contrast between intensely glowing micro-details and a perfectly matte, light-absorbing substrate.

### Suggestion: Art Nouveau Stained Glass Spaceship
- **Date:** 2026-08-15
- **Prompt:** "A majestic, wide view of a luxury passenger spaceship cruising through deep space, designed entirely in an opulent Art Nouveau style. The hull features sweeping, organic whiplash curves of polished bronze, and the massive observation decks are enclosed by intricate, multi-colored stained glass. The lighting is cinematic, with intense, pure white starlight from a nearby star shining through the stained glass, casting brilliant, colorful, fractured light onto the bronze hull, set against the pitch-black cosmic void. The mood is elegant, romantic, and technologically poetic. Captured with a wide 35mm lens, showcasing the vessel against a backdrop of distant stars."
- **Negative prompt:** "dystopian, utilitarian, grey, boxy, modern, realistic NASA, messy"
- **Tags:** sci-fi, space, art nouveau, vehicle, stained glass
- **Style / Reference:** opulent sci-fi concept art, cinematic space rendering
- **Composition:** wide angle, majestic scale, dramatic lighting
- **Color palette:** polished warm bronze, vibrant stained glass colors (ruby, sapphire, emerald), deep space black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260815_stained-glass-spaceship.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of highly ornate, historical architectural styles (Art Nouveau, stained glass) with futuristic vehicles and cosmic lighting.

### Suggestion: Bioluminescent Deep-Sea Observatory
- **Date:** 2026-05-15
- **Prompt:** "A futuristic glass-domed observatory anchored to a deep-sea trench wall, glowing with soft internal amber lights. Outside the thick curved windows, colossal bioluminescent jellyfish drift through the dark, icy water, illuminating the ocean floor with pulsating neon blues and greens. The mood is mysterious and tranquil. High detail, cinematic lighting, 8k resolution, volumetric water scattering."
- **Negative prompt:** "sunlight, surface, land, pixelated, blurry, human figures"
- **Tags:** sci-fi, underwater, bioluminescence, ocean, architecture
- **Style / Reference:** photorealistic, cinematic sci-fi concept art
- **Composition:** wide establishing shot, looking slightly upward at the observatory
- **Color palette:** deep oceanic blues, neon cyan, contrasting warm amber interiors
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_deep-sea-observatory.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing volumetric underwater scattering and contrasting light temperatures.

### Suggestion: Steampunk Botanist's Greenhouse
- **Date:** 2026-05-15
- **Prompt:** "An incredibly detailed interior of a Victorian steampunk greenhouse filled with giant, exotic glowing plants and mechanical brass flowers. Sunlight filters through a massive wrought-iron and stained-glass ceiling, casting intricate colored shadows. Brass pipes emit small puffs of steam, and a leather-bound journal rests on a polished wooden workbench. A whimsical, warm, and inviting mood. Shot with a 35mm lens, high depth of field."
- **Negative prompt:** "modern, clean, sterile, dark, lowres, text"
- **Tags:** steampunk, botanical, fantasy, interior, bright
- **Style / Reference:** Victorian illustration meets hyper-detailed 3D render
- **Composition:** eye-level medium shot, rule of thirds focusing on the workbench with plants in the background
- **Color palette:** lush greens, brassy golds, warm sunlight, stained glass multi-colors
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20260515_steampunk-greenhouse.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex shadows, specular highlights on brass, and foliage textures.

### Suggestion: Cybernetic Zen Garden
- **Date:** 2026-05-15
- **Prompt:** "A serene Japanese Zen garden where the traditional elements are replaced with cyberpunk technology. The sand is made of glowing fiber optic cables perfectly raked into circular patterns. The rocks are smooth obsidian servers with subtle blue led pulses. A holographic cherry blossom tree drops luminous pink digital petals in the background. The scene is illuminated by the soft neon glow in a dusky atmosphere. Moody, meditative, hyper-detailed."
- **Negative prompt:** "organic dirt, messy, daylight, traditional wood, noisy"
- **Tags:** cyberpunk, zen, garden, neon, holographic
- **Style / Reference:** futuristic 3D environment, Unreal Engine 5 aesthetic
- **Composition:** high angle shot looking down at the raked patterns and the central 'rock'
- **Color palette:** dark slate grey, neon blue, magenta pink
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_cybernetic-zen-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the engine's ability to render clean, glowing curves and subtle light emissions on dark surfaces.

### Suggestion: Ethereal Astral Librarian
- **Date:** 2026-05-15
- **Prompt:** "A portrait of a cosmic librarian made entirely of stardust and swirling nebulae, wearing ornate silver robes adorned with glowing constellations. They are holding a floating, glowing book made of pure light. The background is a massive, infinite library where the shelves are built from asteroid rock and the books are captured galaxies. Epic, magical, awe-inspiring mood. Soft, ethereal lighting, 85mm portrait lens with bokeh."
- **Negative prompt:** "human skin, realistic face, mundane, dark, horror"
- **Tags:** portrait, cosmic, fantasy, ethereal, magic
- **Style / Reference:** ethereal fantasy art, cosmic illustration
- **Composition:** close-up portrait, shallow depth of field focusing on the face and the glowing book
- **Color palette:** midnight blues, shimmering silver, bright nebula purple and pink
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260515_astral-librarian.jpg`
- **License / Attribution:** CC0
- **Notes:** Pushes the AI to handle particle-like textures (stardust) combined with intricate clothing details.

### Suggestion: Post-Apocalyptic Neon Diner
- **Date:** 2026-05-15
- **Prompt:** "A 1950s retro diner sitting alone in a vast, desolate, post-apocalyptic desert wasteland. It is dusk, and the diner's neon 'OPEN' sign flickers in vibrant pink and turquoise, providing the only bright light in the scene. The chrome exterior is rusted and half-buried in sand, and strange alien flora is starting to grow over the roof. Cinematic, lonely but colorful mood. Shot on anamorphic lens with lens flares."
- **Negative prompt:** "clean, new, bustling, city, rain, overcast"
- **Tags:** post-apocalyptic, retro-futurism, desert, neon, cinematic
- **Style / Reference:** cinematic wasteland photography, retro 50s sci-fi
- **Composition:** wide exterior shot, diner positioned slightly off-center, dramatic sky
- **Color palette:** dusty orange, rusted browns, neon pink, turquoise
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260515_neon-wasteland-diner.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests high contrast between a dimly lit background and intense neon light sources, along with weathered textures.

### Suggestion: Graphene Cyberpunk Tsunami
- **Date:** 2027-09-01
- **Prompt:** "A towering, catastrophic tsunami wave crashing over a futuristic cyberpunk metropolis at night, but the water is inexplicably composed of liquid, light-absorbing graphene. The dark, matte fluid absorbs the harsh neon pink and cyan lights of the skyscrapers it destroys. The lighting is extremely contrasted, with bright neon signs casting long, distorted reflections on the sleek, black, undulating surface of the graphene wave. The mood is apocalyptic, high-tech, and terrifying. Captured from a low angle on the flooded streets, utilizing a wide 14mm lens to emphasize the massive, overhanging scale of the dark wave."
- **Negative prompt:** "blue water, realistic ocean, daylight, sunny, soft, calm, organic, clouds"
- **Tags:** cyberpunk, disaster, tsunami, graphene, neon
- **Style / Reference:** cinematic sci-fi disaster visualization
- **Composition:** wide angle, low perspective, towering wave
- **Color palette:** pitch black matte graphene, bright neon pink, electric cyan
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270901_graphene-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of an apocalyptic fluid dynamic using a light-absorbing, dark matte material under bright neon lighting.

### Suggestion: Art Deco Exoplanet Core
- **Date:** 2027-09-01
- **Prompt:** "An ultra-macro, surreal visualization deep within the core of an exoplanet, designed entirely in an elegant Art Deco style. The subject features towering, geometric pillars of polished brass and obsidian, surrounded by rivers of glowing, golden plasma flowing in sharp, angular zigzags. The lighting is intensely bright from the golden plasma, casting sharp, deep shadows on the polished brass and obsidian surfaces, creating a luxurious, monumental feel. The mood is opulent, alien, and mathematically precise. Captured with a 50mm lens, deep depth of field to keep the sharp geometric pillars and glowing rivers in perfect focus."
- **Negative prompt:** "organic, round shapes, messy, dark, daylight, natural rock, blurry"
- **Tags:** sci-fi, macro, exoplanet, core, art deco, brass
- **Style / Reference:** Art Deco architectural visualization, hard sci-fi
- **Composition:** symmetrical, vertical leading lines, sharp geometry
- **Color palette:** polished brass, deep obsidian black, glowing golden yellow
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20270901_artdeco-exoplanet-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating complex geometric hard-surface modeling paired with intense, glowing metallic plasma lighting.

### Suggestion: Tweed Beehive Macro
- **Date:** 2027-09-01
- **Prompt:** "An incredibly detailed, macro view deep inside a gigantic beehive where the entire honeycomb structure is constructed from soft, interwoven threads of warm brown herringbone tweed fabric. The subject features perfectly repeating hexagonal cells made of yarn, filled with glowing, viscous golden honey. The lighting is warm and directional, catching the fibrous texture of the tweed and causing the golden honey to glow brilliantly with sub-surface scattering. The mood is cozy, surreal, and highly tactile. Captured with a 100mm macro lens, utilizing a shallow depth of field to isolate a single, honey-filled tweed cell."
- **Negative prompt:** "wax, plastic, hard surface, realistic hive, bees, bright daylight, wide angle"
- **Tags:** macro, surreal, beehive, tweed, honeycomb
- **Style / Reference:** surreal macro photography, hyper-detailed material swap
- **Composition:** full frame repeating pattern, tight close-up, shallow depth of field
- **Color palette:** earthy brown tweed, glowing golden yellow, soft amber
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20270901_tweed-beehive.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates the application of soft, woven micro-textures (tweed) on perfect, repeating geometric patterns combined with viscous fluid.

### Suggestion: Bismuth Orbital Ring
- **Date:** 2027-09-01
- **Prompt:** "An epic, sweeping view of a colossal Orbital Ring megastructure encircling a dark, terrestrial planet, constructed entirely from gigantic, interlocking iridescent bismuth hopper crystals. The subject features massive stepped geometric formations extending infinitely along the orbit. The lighting is harsh and direct from a nearby star, casting deep black shadows in the vacuum of space, while causing the metallic bismuth surfaces to shine brilliantly in a rainbow of thin-film interference colors. The mood is majestic, alien, and technologically supreme. Captured with a wide-angle cinematic lens from low orbit, emphasizing the vast scale of the crystalline ring."
- **Negative prompt:** "smooth curves, dull, plastic, atmospheric haze, organic, soft lighting"
- **Tags:** sci-fi, megastructure, space, orbital ring, bismuth, iridescent
- **Style / Reference:** cinematic space art, hard sci-fi concept design
- **Composition:** curved horizon, extreme wide angle, massive geometric scale
- **Color palette:** iridescent rainbow, glaring white starlight, deep cosmic black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20270901_bismuth-orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of massive scale, planetary curvature, and complex stepped geometric structures interacting with highly saturated iridescent thin-film materials.

### Suggestion: Ashcan School Beaver Dam
- **Date:** 2027-09-01
- **Prompt:** "A gritty, realistic landscape of a beaver dam blocking a murky, slow-moving river near an early 20th-century industrial town, depicted in the raw, documentary style of the Ashcan School. The subject features an incredibly detailed tangle of muddy branches, discarded lumber, and urban debris forming the dam. The lighting is overcast and bleak, casting soft, indistinct shadows that emphasize the dirt, texture, and chaotic nature of the construction. The mood is authentic, raw, and full of everyday life. Captured with an eye-level, documentary-style perspective, focusing on the unglamorous reality of the industrial waterfront."
- **Negative prompt:** "modern, bright, cheerful, clean, highly saturated, photorealistic, shiny"
- **Tags:** art, landscape, historical, ashcan school, beaver dam, gritty
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** eye-level, chaotic framing, realistic naturalism
- **Color palette:** muted browns, dark greys, murky greens, dull ochre
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20270901_ashcan-beaver-dam.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of an organic, chaotic subject (beaver dam) with the gritty, muted, everyday-life style of the Ashcan School.

### Suggestion: Italian Futurism Bioluminescent Reef
- **Date:** 2027-10-01
- **Prompt:** "A dynamic, chaotic underwater scene of a sprawling bioluminescent reef, depicted in the harsh, fragmented style of Italian Futurism. The organic subject is deconstructed into aggressive, jagged diagonal lines and overlapping geometric planes that capture the kinetic energy of the ocean currents. The lighting is intense and directional, with bright neon cyan and magenta bioluminescence casting stark, jagged shadows that enhance the dynamic, splintered geometry. The mood is energetic, aggressive, and highly stylized. Captured with a tilted perspective to emphasize raw motion and the explosive growth of the coral."
- **Negative prompt:** "calm, realistic, photography, smooth curves, organic, gentle, peaceful water"
- **Tags:** abstract, art, italian futurism, underwater, bioluminescent, reef
- **Style / Reference:** Italian Futurism art movement, Giacomo Balla inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** glowing neon cyan, vibrant magenta, steel greys, deep ocean black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271001_futurism-bioluminescent-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to an underwater organic ecosystem.

### Suggestion: Ashcan School Beehive
- **Date:** 2027-10-01
- **Prompt:** "A gritty, realistic close-up of a large, wild beehive hanging in a smoke-filled, early 20th-century industrial alleyway, depicted in the raw, documentary style of the Ashcan School. The subject features a detailed, textured mass of honeycomb and swarming bees, built precariously on rusted iron pipes. The lighting is overcast, bleak, and murky, casting soft, indistinct shadows that emphasize the dirt, soot, and chaotic nature of the urban environment. The mood is authentic, raw, and unidealized. Captured with an eye-level, documentary-style perspective, focusing on the intersection of nature and industrial decay."
- **Negative prompt:** "modern, bright, cheerful, clean, highly saturated, photorealistic, shiny, idyllic nature"
- **Tags:** art, urban, historical, ashcan school, beehive, gritty
- **Style / Reference:** Ashcan School painting, Robert Henri inspired, thick brushstrokes
- **Composition:** eye-level, cluttered framing, realistic naturalism
- **Color palette:** muted browns, dark greys, dull amber, rusted ochre
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20271001_ashcan-beehive.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of a natural subject (beehive) with the gritty, muted, everyday-life style of the Ashcan School in an urban setting.

### Suggestion: Bismuth Fireworks
- **Date:** 2027-10-01
- **Prompt:** "A spectacular nighttime display where the fireworks exploding in the sky are entirely formed from jagged, perfectly geometric bismuth hopper crystals. The subjects expand outward in sharp, stair-stepped patterns instead of soft sparks. The lighting is highly contrasted and artificial, with the internal energy of the explosions causing the metallic bismuth fragments to shine brilliantly in a rainbow of thin-film interference colors against the pitch-black sky. The mood is surreal, celebratory, and mathematically precise. Captured with a wide-angle lens, utilizing a fast shutter speed to freeze the sharp, crystalline explosions."
- **Negative prompt:** "soft sparks, smoke, realistic fireworks, daylight, blurry, organic, smooth"
- **Tags:** surreal, night, fireworks, bismuth, geometric, iridescent
- **Style / Reference:** surreal 3D render, hyper-detailed material swap
- **Composition:** expansive sky view, explosive centers, sharp geometric fragmentation
- **Color palette:** iridescent rainbow (pinks, greens, golds), bright white flashes, deep night black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271001_bismuth-fireworks.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of sharp, stepped geometric structures interacting with highly saturated iridescent thin-film materials in an explosive composition.

### Suggestion: Brass Orbital Ring
- **Date:** 2027-10-01
- **Prompt:** "An epic, sweeping view of a colossal Orbital Ring megastructure encircling a rusted, desert planet, constructed entirely from intricate, interlocking brass clockwork and gears. The mechanical subject features massive, polished cogs and steam vents extending infinitely along the orbit. The lighting is harsh and direct from a nearby star, casting deep black shadows in the vacuum of space, while highlighting the polished brass surfaces with brilliant specular glints. The mood is majestic, steampunk, and technologically awe-inspiring. Captured with a wide-angle cinematic lens from low orbit, emphasizing the vast scale of the mechanical ring."
- **Negative prompt:** "smooth metal, modern, sleek, plastic, atmospheric haze, organic, soft lighting, futuristic"
- **Tags:** steampunk, megastructure, space, orbital ring, brass, mechanical
- **Style / Reference:** cinematic steampunk art, hard sci-fi concept design
- **Composition:** curved horizon, extreme wide angle, massive mechanical scale
- **Color palette:** polished warm brass, copper, blinding white starlight, deep cosmic black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20271001_brass-orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of massive scale, planetary curvature, and complex steampunk mechanical structures under harsh cosmic lighting.

### Suggestion: Graphene Volcanic Eruption
- **Date:** 2027-10-01
- **Prompt:** "A terrifying, surreal landscape of a massive volcano erupting, where the mountain and the flying debris are composed of perfectly matte, light-absorbing graphene. The dark, geometric subject spews rivers of blindingly bright, super-heated white plasma instead of lava. The lighting is intensely harsh, emanating entirely from the plasma rivers and explosive core, creating a stark interplay of blinding white-hot streaks against the crushing black geometry of the graphene. The mood is apocalyptic, alien, and unfathomably powerful. Captured with a wide-angle lens from a safe distance, freezing the dynamic flow of plasma against the rigid, light-absorbing carbon structure."
- **Negative prompt:** "red lava, orange, fire, realistic volcano, smoke, messy, blurry, soft lighting, daylight"
- **Tags:** sci-fi, landscape, volcano, graphene, plasma, dark
- **Style / Reference:** surreal sci-fi landscape, hyper-detailed scientific visualization
- **Composition:** wide landscape, explosive center, sharp contrast
- **Color palette:** pitch black matte graphene, blinding white-hot plasma, intense neon blue edges
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271001_graphene-volcanic-eruption.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating an explosive fluid dynamic using a perfectly matte, light-absorbing material under intensely bright, contrasting internal lighting.

### Suggestion: Aerogel Fireworks
- **Date:** 2027-11-01
- **Prompt:** "A surreal, dreamlike nighttime celebration where exploding fireworks are inexplicably composed of weightless, translucent blue aerogel. The sky is filled with massive, frozen bursts of the porous material, which catches the ambient city light to create thousands of soft, internal refractions and a ghostly, ethereal glow. The lighting is a mix of distant urban neon and the internal scattering of light within the aerogel, casting a serene blue hue over the dark sky. The mood is silent, magical, and impossible. Captured with a wide-angle lens, utilizing a long exposure to emphasize the glowing trails of the aerogel bursts against the starry night."
- **Negative prompt:** "realistic fireworks, bright flashes, fire, smoke, daylight, messy, noisy"
- **Tags:** surreal, night, fireworks, aerogel, abstract
- **Style / Reference:** surreal digital art, hyper-detailed material swap
- **Composition:** expansive sky view, explosive centers, soft blurred edges
- **Color palette:** ghostly aerogel blue, soft neon pink reflections, deep night black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271101_aerogel-fireworks.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the interaction of internal light scattering within highly translucent, low-density materials in an explosive, nighttime context.

### Suggestion: Damascus Steel Exoplanet Core
- **Date:** 2027-11-01
- **Prompt:** "An ultra-macro, theoretical visualization deep within the core of an exoplanet, where immense pressure has forged the rocky mantle into flowing, rippled layers of Damascus steel. The heavy metallic subject features intricate, overlapping wave patterns of dark and light grey metal, glowing with extreme heat. The lighting is entirely internal, radiating from a blinding white-hot center that casts sharp glints and deep, molten shadows across the metallic ridges. The mood is crushing, alien, and unfathomably powerful. Captured with a microscopic camera perspective, freezing the chaotic, pressurized metal in sharp focus."
- **Negative prompt:** "organic, water, soft, blurry, cool colors, daylight, realistic cave"
- **Tags:** sci-fi, macro, exoplanet, core, damascus steel
- **Style / Reference:** scientific visualization, hyper-detailed hard surface modeling
- **Composition:** chaotic yet flowing geometry, sharp macro focus, dense
- **Color palette:** dark metallic greys, blinding white-hot, fiery orange, molten red
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271101_damascus-exoplanet-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating complex, flowing metallic textures subjected to extreme heat and internal illumination.

### Suggestion: Mother of Pearl Beehive
- **Date:** 2027-11-01
- **Prompt:** "An incredibly detailed, macro view deep inside a gigantic, surreal beehive where the entire honeycomb structure is constructed from shimmering, iridescent mother of pearl (nacre). The subject features perfectly repeating hexagonal cells that reflect a spectacular array of pearlescent pastels, filled with clear, glowing nectar. The lighting is soft and ethereal, filtering through the semi-transparent nacre walls to create a mesmerizing sub-surface scattering effect and intense rainbow interference patterns. The mood is luxurious, magical, and mathematically perfect. Captured with a 100mm macro lens, deep depth of field to emphasize the endless geometric repetition of the iridescent honeycomb."
- **Negative prompt:** "wax, yellow honey, plastic, hard surface, realistic hive, bees, dull, flat lighting"
- **Tags:** macro, surreal, beehive, mother of pearl, iridescent
- **Style / Reference:** surreal macro photography, hyper-detailed material swap
- **Composition:** full frame repeating pattern, deep perspective
- **Color palette:** pearlescent pinks, soft baby blues, shimmering silver, glowing nectar
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271101_mother-of-pearl-beehive.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates large-scale thin-film iridescent interference mapped to perfect, repeating geometric patterns.

### Suggestion: Graphene Bioluminescent Reef
- **Date:** 2027-11-01
- **Prompt:** "A breathtaking, macro underwater photograph of a sprawling coral reef where the coral formations are composed entirely of dark, matte, light-absorbing graphene. The geometric, black subjects are populated by tiny, intensely glowing bioluminescent sea life that illuminates the reef from within. The lighting is exclusively from the bioluminescence, creating a stark, high-contrast interplay of blinding neon cyan and magenta streaks against the crushing black, matte geometry of the graphene. The mood is silent, alien, and deeply serene. Captured with a 50mm macro lens, utilizing a shallow depth of field to isolate a single glowing polyp against the dark void."
- **Negative prompt:** "bright sunlight, surface, muddy water, bright coral, realistic fish, soft lighting"
- **Tags:** underwater, sci-fi, macro, graphene, bioluminescent
- **Style / Reference:** photorealistic underwater photography, sci-fi material swap
- **Composition:** macro close-up, sharp contrast, beautiful soft bokeh
- **Color palette:** pitch black matte graphene, glowing neon cyan, vibrant magenta
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20271101_graphene-bioluminescent-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of perfectly matte, light-absorbing textures interacting with intensely bright, colored bioluminescent light sources.

### Suggestion: Italian Futurism Tsunami
- **Date:** 2027-11-01
- **Prompt:** "A massive, terrifying tsunami wave crashing down on a stylized metropolis, depicted entirely in the aggressive, fragmented style of Italian Futurism. The destructive fluid subject is deconstructed into sharp, intersecting diagonal lines and overlapping geometric planes that capture the kinetic energy and overwhelming speed of the water. The lighting is dynamic and directional, casting stark, jagged shadows that enhance the splintered geometry of the composition. The mood is energetic, destructive, and modern. Captured with a highly tilted perspective to emphasize raw motion and the violent impact of the fragmented wave."
- **Negative prompt:** "realistic water, soft curves, calm, photography, peaceful, organic, smooth"
- **Tags:** abstract, art, italian futurism, tsunami, disaster
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** deep ocean blue, steel greys, harsh stark white, chaotic black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271101_futurism-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to an overwhelming, chaotic fluid event.

### Suggestion: Ashcan School Volcanic Eruption
- **Date:** 2027-11-01
- **Prompt:** "A gritty, realistic landscape of a massive volcanic eruption near an early 20th-century industrial town, depicted in the raw, documentary style of the Ashcan School. The subject features dark, churning ash clouds and muted lava flows tearing through smokestacks and tenement buildings. The lighting is overcast and bleak, casting soft, indistinct shadows that emphasize the dirt, texture, and chaotic power of the destruction. The mood is authentic, raw, and overwhelming. Captured with an eye-level, documentary-style perspective, focusing on the unglamorous reality of the disaster from the viewpoint of the streets."
- **Negative prompt:** "modern, clean, bright colors, sunny, cheerful, photorealistic, 3d render"
- **Tags:** art, disaster, volcano, historical, ashcan school, gritty
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** eye-level, chaotic framing, imposing ash cloud
- **Color palette:** murky greens, muted greys, rusted browns, dull ochre
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271101_ashcan-volcano.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of a massive natural disaster with the gritty, muted, everyday-life style of the Ashcan School.

### Suggestion: Brass Supernova
- **Date:** 2027-11-01
- **Prompt:** "A spectacular nighttime display where the fireworks exploding in the sky are entirely formed from jagged, perfectly geometric brass clockwork and gears. The subjects expand outward in sharp, stair-stepped patterns instead of soft sparks. The lighting is highly contrasted and artificial, with the internal energy of the explosions causing the metallic brass fragments to shine brilliantly in a rainbow of thin-film interference colors against the pitch-black sky. The mood is surreal, celebratory, and mathematically precise. Captured with a wide-angle lens, utilizing a fast shutter speed to freeze the sharp, crystalline explosions."
- **Negative prompt:** "soft sparks, smoke, realistic fireworks, daylight, blurry, organic, smooth"
- **Tags:** surreal, night, supernova, brass, geometric, iridescent
- **Style / Reference:** surreal 3D render, hyper-detailed material swap
- **Composition:** expansive sky view, explosive centers, sharp geometric fragmentation
- **Color palette:** iridescent rainbow (pinks, greens, golds), bright white flashes, deep night black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271101_brass-supernova.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of sharp, stepped geometric structures interacting with highly saturated iridescent thin-film materials in an explosive composition.

### Suggestion: Mother of Pearl Tsunami
- **Date:** 2027-11-01
- **Prompt:** "A majestic, towering tsunami wave caught frozen in time just before it crashes down. The water is entirely mother of pearl, glowing intensely with neon blues and purples in the dark of night. Within the translucent wall of water, silhouetted shapes of giant marine life can be seen swirling. The sky above is dark and stormy with dramatic lightning illuminating the crest of the wave. The mood is terrifying yet awe-inspiring and beautiful. Captured with a low camera angle, wide lens, and high shutter speed to freeze the water droplets."
- **Negative prompt:** "daylight, calm water, small wave, shore, people, boats, sunny"
- **Tags:** nature, ocean, tsunami, mother of pearl, dramatic
- **Style / Reference:** photorealistic, long exposure photography style
- **Composition:** imposing, low angle, wave dominating the frame
- **Color palette:** neon blues, deep purples, dark greys, bright white lightning flashes
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271101_mother-of-pearl-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing water rendering, transparency, and intense glowing emission under dark environmental lighting.

### Suggestion: Tweed Volcanic Eruption
- **Date:** 2027-11-01
- **Prompt:** "An incredibly detailed, macro view deep inside a gigantic, surreal volcano where the entire structure is constructed from soft, interwoven threads of warm brown herringbone tweed fabric. The subject features perfectly repeating hexagonal cells made of yarn, filled with glowing, viscous golden lava. The lighting is warm and directional, catching the fibrous texture of the tweed and causing the golden lava to glow brilliantly with sub-surface scattering. The mood is cozy, surreal, and highly tactile. Captured with a 100mm macro lens, utilizing a shallow depth of field to isolate a single, lava-filled tweed cell."
- **Negative prompt:** "wax, plastic, hard surface, realistic volcano, bright daylight, wide angle"
- **Tags:** macro, surreal, volcano, tweed, honeycomb
- **Style / Reference:** surreal macro photography, hyper-detailed material swap
- **Composition:** full frame repeating pattern, tight close-up, shallow depth of field
- **Color palette:** earthy brown tweed, glowing golden yellow, soft amber
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20271101_tweed-volcano.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates the application of soft, woven micro-textures (tweed) on perfect, repeating geometric patterns combined with viscous fluid.

### Suggestion: Aerogel Orbital Ring
- **Date:** 2027-11-01
- **Prompt:** "A breathtaking, wide-angle view of an orbital ring constructed entirely from massive, floating blocks of weightless, translucent blue aerogel. The central subject, the ring, is suspended high above a dense layer of white clouds. The lighting is brilliant midday sunlight, piercing through the porous aerogel structures, creating millions of soft, internal refractions and a glowing, ghostly blue aura around the buildings. The mood is utopian, silent, and airy. Captured with a wide 24mm lens to emphasize the massive, floating scale."
- **Negative prompt:** "solid glass, concrete, metal, dark, gritty, cyberpunk, night"
- **Tags:** sci-fi, architecture, aerogel, orbital ring, floating
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** wide expansive view, towering geometric forms, cloud floor
- **Color palette:** ghostly aerogel blue, blinding white sunlight, pure white clouds
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20271101_aerogel-orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large-scale structures made of highly scattering, incredibly low-density translucent materials (aerogel) under direct sunlight.

### Suggestion: Cyberpunk Neon Bioluminescent Market
- **Date:** 2024-05-24
- **Prompt:** "A bustling cyberpunk night market in a flooded alleyway, illuminated by neon signs and glowing bioluminescent fungi growing on decaying concrete. A diverse crowd of cybernetic humans and aliens trading exotic glowing flora. Rain slicked cobblestones reflecting vibrant pinks and cyan lights. Cinematic lighting, volumetric fog, highly detailed, 8k resolution, photorealistic."
- **Negative prompt:** "watermark, text, lowres, blurry, mutated, deformed, bad anatomy"
- **Tags:** cyberpunk, sci-fi, photorealism, bioluminescent, market, neon
- **Style / Reference:** photorealistic, Syd Mead, Blade Runner aesthetic
- **Composition:** wide shot, eye-level perspective, deep depth of field
- **Color palette:** vibrant magenta, cyan, deep shadows, bioluminescent green
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Great for testing wet surface reflections and complex multi-source neon lighting.

### Suggestion: Ethereal Ancient Forest Sanctuary
- **Date:** 2024-05-24
- **Prompt:** "A majestic ancient forest sanctuary bathed in morning mist, featuring a colossal weeping willow tree with luminous silver leaves. At the base of the tree is a perfectly still, crystal clear pond reflecting the sky. Soft sunbeams filtering through the canopy, illuminating floating dust motes. Tranquil, mystical mood, hyper-detailed fantasy illustration."
- **Negative prompt:** "dark, scary, low quality, artifacting, chaotic, unnatural"
- **Tags:** fantasy, nature, ethereal, forest, magical, tranquil
- **Style / Reference:** digital painting, Studio Ghibli, Thomas Kinkade lighting
- **Composition:** centered subject, low angle shot looking up at the tree
- **Color palette:** soft emerald greens, silver, pale gold sunlight, ethereal blues
- **Aspect ratio:** 4:5
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating soft volumetric lighting and intricate leaf details.

### Suggestion: Retro-Futuristic Art Deco Space Station
- **Date:** 2024-05-24
- **Prompt:** "The grand concourse of a retro-futuristic space station designed in opulent Art Deco style. Towering brass pillars, intricate geometric marble floors, and massive arched windows looking out into a vibrant nebula. Elegant passengers in 1920s-inspired space attire. Warm incandescent lighting mixed with starlight. Masterpiece, highly detailed architectural visualization."
- **Negative prompt:** "modern, sleek, minimalist, dystopian, broken, low resolution"
- **Tags:** retro-futuristic, art deco, space, architecture, sci-fi
- **Style / Reference:** architectural visualization, Bioshock Infinite aesthetic, golden age sci-fi
- **Composition:** symmetrical perspective, wide angle lens
- **Color palette:** brass, gold, polished black marble, deep purple and pink nebula
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Use to test the model's ability to combine historical architectural styles with futuristic settings.

### Suggestion: Steampunk Clockwork Dragonfly Macro
- **Date:** 2024-05-24
- **Prompt:** "Extreme macro photography of a mechanical dragonfly perched on a rusted iron gear. The dragonfly is constructed of tiny brass cogs, copper wire, and iridescent stained glass wings. Morning dew drops glistening on its metallic body. Warm morning sunlight, shallow depth of field, bokeh background. Photorealistic, incredibly detailed."
- **Negative prompt:** "cartoon, 2d, painting, out of focus, noisy, artifacts"
- **Tags:** steampunk, macro, mechanical, insect, photorealism
- **Style / Reference:** macro photography, hyper-realistic, steampunk design
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** copper, brass, iridescent greens and blues, rusted iron
- **Aspect ratio:** 3:2
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Excellent for pushing the model's detailing capabilities on micro-mechanical parts and bokeh effects.

### Suggestion: Post-Apocalyptic Solarpunk Rooftop Garden
- **Date:** 2024-05-24
- **Prompt:** "A lush solarpunk rooftop garden thriving on top of a weathered, vine-covered skyscraper in a reclaimed post-apocalyptic city. Makeshift wind turbines and solar panels integrated seamlessly with overgrown tomato plants and sunflowers. A young woman in practical, upcycled clothing tending to the plants. Bright, optimistic midday sunlight, clear blue sky. Detailed, vibrant illustration."
- **Negative prompt:** "grimdark, depressing, toxic, ruined, low detail, muddy colors"
- **Tags:** solarpunk, post-apocalyptic, overgrown, optimistic, garden
- **Style / Reference:** concept art, Moebius, vibrant digital illustration
- **Composition:** high angle shot looking down slightly across the rooftop
- **Color palette:** vibrant greens, sunny yellow, terracotta, clear sky blue
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests the AI's ability to blend technology with dense organic foliage in an optimistic tone.

### Suggestion: Ashcan School Tsunami
- **Date:** 2026-11-20
- **Prompt:** "A massive, terrifying tsunami wave crashing down on a gritty early 20th-century industrial waterfront, depicted in the raw, documentary style of the Ashcan School. The dark, churning water tears through smokestacks and tenement buildings, while frantic dockworkers attempt to flee. The lighting is overcast and bleak, casting soft, indistinct shadows that emphasize the dirt, texture, and chaotic power of the destruction. The mood is grim, authentic, and overwhelming. Captured with an eye-level, documentary-style perspective, focusing on the unglamorous and terrifying reality of the disaster from the viewpoint of the streets."
- **Negative prompt:** "modern, clean, bright colors, sunny, cheerful, photorealistic, 3d render, idyllic"
- **Tags:** art, disaster, tsunami, historical, ashcan school, gritty
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** eye-level, chaotic framing, imposing wave dominating the background
- **Color palette:** murky greens, muted greys, rusted browns, dull ochre
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261120_ashcan-school-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of a massive natural disaster with the gritty, muted, everyday-life style of the Ashcan School.

### Suggestion: Brass Exoplanet Core
- **Date:** 2026-11-20
- **Prompt:** "An ultra-macro, theoretical visualization deep within the core of an exoplanet, where immense pressure has forged a labyrinth of perfectly polished brass clockwork and gears. The massive geometric subject absorbs the ambient heat, contrasting sharply with rivers of super-heated, blindingly bright golden plasma flowing through the mechanical lattice. The lighting is intensely harsh, emanating entirely from the plasma rivers, creating a stark interplay of blinding golden-hot streaks against the reflective brass machinery. The mood is terrifying, alien, and unfathomably powerful. Captured with a microscopic camera perspective, freezing the dynamic flow of plasma against the rigid brass structure."
- **Negative prompt:** "surface, sky, daylight, soft lighting, blurry, organic, earth-like, low contrast, dark shadows"
- **Tags:** sci-fi, macro, exoplanet, core, brass, plasma
- **Style / Reference:** scientific visualization, hyper-detailed hard sci-fi, steampunk aesthetic
- **Composition:** chaotic yet geometric, sharp macro focus, dense
- **Color palette:** polished brass, blinding golden-hot plasma, deep metallic shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261120_brass-exoplanet-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating complex geometric hard-surface modeling paired with intense, glowing metallic plasma lighting.

### Suggestion: Bismuth Beehive
- **Date:** 2026-11-20
- **Prompt:** "An incredibly detailed, macro view deep inside a gigantic, surreal beehive where the entire honeycomb structure is constructed from naturally iridescent bismuth hopper crystals. The subject features perfectly repeating stepped hexagonal cells that reflect a spectacular array of thin-film interference colors, filled with clear, glowing nectar. The lighting is harsh and directional from an internal glowing core, causing the metallic bismuth surfaces to shine brilliantly in a rainbow of colors against a dark background. The mood is luxurious, magical, and mathematically precise. Captured with a 100mm macro lens, deep depth of field to emphasize the endless geometric repetition of the iridescent honeycomb."
- **Negative prompt:** "wax, yellow honey, plastic, hard surface, realistic hive, bees, dull, flat lighting, organic curves"
- **Tags:** macro, surreal, beehive, bismuth, iridescent
- **Style / Reference:** surreal macro photography, hyper-detailed material swap
- **Composition:** full frame repeating pattern, deep perspective
- **Color palette:** iridescent rainbow (pinks, greens, golds), glowing white nectar, deep black shadows
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261120_bismuth-beehive.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates large-scale thin-film iridescent interference mapped to perfect, repeating geometric patterns.

### Suggestion: Mother of Pearl Beaver Dam
- **Date:** 2026-11-20
- **Prompt:** "A majestic, surreal landscape featuring an intricate beaver dam blocking a tranquil forest stream, constructed entirely from shimmering, iridescent pieces of mother of pearl. The intricately woven nacre logs and branches reflect a spectacular array of pearlescent pastels. The lighting is soft, early morning sunlight filtering through the dense forest canopy, catching the smooth ridges of the nacre to reveal intense rainbow interference patterns across the entire structure. The mood is peaceful, magical, and pristine. Captured with a 35mm lens from the edge of the water, showing both the complex texture of the dam and the calm ecosystem it creates."
- **Negative prompt:** "wood, mud, organic branches, dirty, dark, dull, murky water, realistic dam"
- **Tags:** nature, landscape, surreal, mother of pearl, beaver dam
- **Style / Reference:** surreal nature photography, hyper-detailed material swap
- **Composition:** wide shot, low angle near water surface, leading lines of the stream
- **Color palette:** pearlescent pinks, soft baby blues, shimmering silver, clear water, lush forest greens
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261120_mother-of-pearl-beaver-dam.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating thin-film iridescence on complex organic structures (woven branches) in a natural environment.

### Suggestion: Graphene Orbital Ring
- **Date:** 2026-11-20
- **Prompt:** "An epic, sweeping view of a colossal Orbital Ring megastructure encircling a bright, terrestrial planet, constructed entirely from perfectly matte, light-absorbing graphene. The sleek, dark, geometric subject absorbs almost all starlight, contrasting sharply with the bright, glowing city lights and spaceports scattered across its surface. The lighting is a dramatic sunrise cresting over the planet's horizon, casting a blinding white glare that is starkly absorbed by the matte graphene structure. The mood is silent, awe-inspiring, and technologically supreme. Captured with an extreme wide-angle cinematic lens from low Earth orbit, emphasizing planetary scale and the vast, dark ring."
- **Negative prompt:** "shiny metal, reflective, bright structure, rusted, broken, dystopian, small scale"
- **Tags:** sci-fi, megastructure, space, orbital ring, graphene
- **Style / Reference:** hard sci-fi environment design, cinematic space art
- **Composition:** curved horizon, extreme wide angle, massive scale
- **Color palette:** pitch black matte graphene, blinding solar white, vibrant earth greens and blues, glowing neon city lights
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261120_graphene-orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of massive scale, planetary curvature, and the matte, light-absorbing properties of a massive graphene structure against intense cosmic lighting.


### Suggestion: Steampunk Bioluminescent Submarine
- **Date:** 2024-05-24
- **Prompt:** "A highly detailed, macro shot of a steampunk-inspired miniature submarine exploring a vibrant bioluminescent coral reef. The submarine is crafted from polished brass and copper with glowing amber portholes. The lighting is dominated by the ethereal cyan and magenta glow of the bioluminescent coral, casting colorful reflections on the metallic hull. The mood is adventurous, magical, and mysterious. Captured with a 100mm macro lens, featuring a shallow depth of field that blurs the distant underwater structures into soft bokeh."
- **Negative prompt:** "sunlight, surface, flat lighting, dull, organic, blurry, modern"
- **Tags:** steampunk, underwater, bioluminescent, macro, sci-fi
- **Style / Reference:** photorealistic macro photography, steampunk aesthetics
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** polished brass, glowing cyan, vibrant magenta, deep ocean blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240524_steampunk-submarine.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing the contrast between warm metallic reflections and cool bioluminescent ambient light.

### Suggestion: Ethereal Neon Desert Mirage
- **Date:** 2024-05-24
- **Prompt:** "A surreal, wide-angle landscape of an endless, rolling desert of pale pink sand. In the distance, a massive, shimmering mirage takes the shape of a colossal neon-blue geometric pyramid. The lighting is an otherworldly twilight, where the glowing pyramid provides the primary light source, casting long, sharp blue shadows across the pink dunes. The mood is silent, liminal, and dreamlike. Captured with a wide 24mm lens to emphasize the vast emptiness and the sharp contrast of the glowing geometry."
- **Negative prompt:** "daylight, sun, yellow sand, realistic, busy, people, cluttered"
- **Tags:** surreal, landscape, desert, neon, geometric
- **Style / Reference:** surreal digital art, minimalist aesthetic
- **Composition:** wide expansive view, centered subject, low horizon
- **Color palette:** pale pink sand, intense neon blue, dark twilight purple
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20240524_neon-desert-mirage.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating sharp geometric lighting interacting with soft, expansive natural textures like sand.

### Suggestion: Baroque Cyberpunk Chessboard
- **Date:** 2024-05-24
- **Prompt:** "An exquisite, close-up view of an intricate chessboard where the pieces are a fusion of ornate Baroque marble sculptures and glowing cybernetic components. The white pieces are pristine marble laced with neon pink fiber optics, while the black pieces are obsidian with glowing cyan circuitry. The lighting is highly cinematic, featuring a stark contrast between a warm golden overhead spotlight and the cold, electric glow of the neon accents. The mood is tense, opulent, and highly advanced. Captured with a 50mm lens, utilizing a shallow depth of field focusing solely on the clash between a marble knight and an obsidian pawn."
- **Negative prompt:** "wood, plastic, flat lighting, blurry, modern, simple, wide angle"
- **Tags:** cyberpunk, baroque, still-life, chess, contrast
- **Style / Reference:** photorealistic product photography, high-end 3D rendering
- **Composition:** tight close-up, dynamic angle, shallow depth of field
- **Color palette:** pure white marble, dark obsidian, neon pink, electric cyan, warm gold
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240524_baroque-cyber-chess.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of highly ornate, classical materials with glowing, modern cybernetic elements under dramatic lighting.

### Suggestion: Art Deco Holographic Library
- **Date:** 2024-05-24
- **Prompt:** "A grand, symmetrical view down the main aisle of a towering library designed in a lavish Art Deco style. The massive bookshelves are made of polished mahogany and gold inlay, but instead of physical books, they hold thousands of glowing, translucent holographic data cubes. The lighting is soft and ambient, emanating entirely from the blue and gold holograms, casting a warm, majestic glow over the opulent architecture. The mood is intellectual, wealthy, and futuristic. Captured with a wide-angle 16mm lens to encompass the towering scale and perfect symmetry."
- **Negative prompt:** "paper books, dusty, dark, gritty, cyberpunk, messy, daylight"
- **Tags:** sci-fi, architecture, interior, art deco, holographic
- **Style / Reference:** opulent sci-fi concept art, retro-futuristic
- **Composition:** symmetrical, one-point perspective, deep corridor
- **Color palette:** polished mahogany brown, brilliant gold, glowing holographic blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240524_artdeco-holo-library.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing the interaction of semi-transparent glowing holograms with highly polished, rich architectural materials.

### Suggestion: Solarpunk Floating Botanical Garden
- **Date:** 2024-05-24
- **Prompt:** "A breathtaking, sweeping aerial view of a massive, teardrop-shaped floating botanical garden suspended high above a pristine, lush green canyon. The structure is constructed from curved, gleaming white composite materials and vast glass domes housing exotic, oversized flora. The lighting features brilliant, midday sunlight that pierces through the glass domes and creates intricate, dappled shadows across the hanging vines and waterfalls. The mood is utopian, harmonious, and uplifting. Captured with a wide-angle drone perspective to showcase the architectural elegance against the natural landscape."
- **Negative prompt:** "dystopian, dark, night, pollution, gritty, lowres, blurry"
- **Tags:** solarpunk, architecture, nature, aerial, utopian
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** aerial perspective, wide expansive view, dynamic curves
- **Color palette:** brilliant white, lush forest greens, vibrant floral reds, clear sky blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240524_solarpunk-botanical.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the generation of large-scale, curved, clean architecture combined with dense, detailed botanical elements and complex glass reflections.


### Suggestion: Bioluminescent Forest Canopy
- **Date:** 2024-05-15
- **Prompt:** "A dense, ancient forest canopy viewed from below, illuminated entirely by glowing, bioluminescent flora. Giant, translucent leaves pulse with ethereal blue and green light, casting intricate, glowing shadows. Ethereal, floating pollen drifts lazily through the air, catching the magical light. The mood is tranquil, mysterious, and magical."
- **Negative prompt:** "sunlight, daytime, harsh lighting, barren, dead"
- **Tags:** fantasy, nature, bioluminescence, magical
- **Style / Reference:** photorealistic, magical realism
- **Composition:** low angle shot, looking up
- **Color palette:** glowing blues, greens, deep purples
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240515_bioluminescent-canopy.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing subsurface scattering on leaves and volumetric lighting from glowing sources.

### Suggestion: Cybernetic Zen Garden
- **Date:** 2024-05-15
- **Prompt:** "A tranquil Japanese Zen garden meticulously maintained by robotic monks, where the raked sand is made of glowing fiber optic cables and the rocks are sleek, obsidian data servers. Delicate holographic cherry blossoms fall slowly from metallic trees. The lighting is soft and ambient, contrasting the ancient aesthetic with futuristic technology."
- **Negative prompt:** "messy, chaotic, daylight, traditional nature"
- **Tags:** cyberpunk, zen, garden, futuristic
- **Style / Reference:** hyper-detailed 3D render, cyberpunk
- **Composition:** wide shot, rule of thirds
- **Color palette:** stark black, neon pink, soft cyan, metallic silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240515_cybernetic-zen-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing combinations of organic shapes with hard-surface futuristic materials.

### Suggestion: Neon-Noir Jazz Club
- **Date:** 2024-05-15
- **Prompt:** "The interior of a smoky, retro-futuristic jazz club in a cyberpunk city. A lone saxophonist, partially composed of brass cybernetics, plays on a dimly lit stage bathed in a single, dramatic red spotlight. The air is thick with smoke that catches the neon signs glaring from the wet windows outside. The atmosphere is melancholic and gritty."
- **Negative prompt:** "bright, cheerful, clean, modern, daylight"
- **Tags:** neon-noir, cyberpunk, interior, moody
- **Style / Reference:** cinematic lighting, noir
- **Composition:** medium shot, cinematic framing
- **Color palette:** deep blacks, crimson red, neon blue
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20240515_neon-noir-jazz-club.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests volumetric smoke effects and harsh, colored spotlighting in dark environments.

### Suggestion: Steampunk Observatory
- **Date:** 2024-05-15
- **Prompt:** "A chaotic, brass-and-wood astronomical observatory filled with intricate, ticking orreries and giant telescope lenses capturing the light of a nearby nebula. Huge gears and steam pipes line the circular walls, while a large, open dome reveals a star-filled sky dominated by a massive ringed planet. The lighting is warm and fiery, emanating from glowing braziers and the starlight."
- **Negative prompt:** "minimalist, clean, modern technology, digital screens"
- **Tags:** steampunk, fantasy, space, intricate
- **Style / Reference:** victorian sci-fi, highly detailed illustration
- **Composition:** wide interior shot, central focus on the telescope
- **Color palette:** brass, mahogany wood, warm amber, starry blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240515_steampunk-observatory.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for rendering complex, interlocking mechanical details and metallic reflections.

### Suggestion: Abyssal Mecha Graveyard
- **Date:** 2024-05-15
- **Prompt:** "The dark, crushing depths of the ocean floor, where the colossal, rusting remains of ancient mechas lie half-buried in the silt. Bioluminescent deep-sea creatures swim through the hollowed-out cockpits and broken visors. A faint, eerie green light leaks from a cracked, still-functioning power core of one of the titans. The scene is ominous, forgotten, and vast."
- **Negative prompt:** "surface, sunlight, shallow water, clean, new"
- **Tags:** sci-fi, underwater, mecha, ruins, ominous
- **Style / Reference:** cinematic concept art, photorealistic underwater
- **Composition:** wide establishing shot, deep depth of field
- **Color palette:** deep ocean blue, rust orange, eerie glowing green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240515_abyssal-mecha-graveyard.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for underwater atmospheric scattering, murky water textures, and rusting metal materials.

### Agent Suggestion: Neon-Soaked Cyberpunk Noodle Stand — @gemini-agent — 2026-04-20
- **Prompt:** "A tight, eye-level shot of a cramped cyberpunk noodle stand at night. The stall is illuminated by harsh, flickering neon signs in vibrant pink and cyan, casting long, stark shadows. Steam billows from boiling pots, partially obscuring the worn, metallic surfaces and glowing buttons of the cooking equipment. The mood is gritty, cinematic, and atmospheric. Shot on a 35mm lens, high contrast, shallow depth of field."
- **Negative prompt:** "daytime, clean, pristine, cartoon, low-res, empty"
- **Tags:** cyberpunk, neon, urban, cinematic, gritty
- **Ref image:** `public/images/suggestions/20260420_cyberpunk-noodle.jpg`
- **Notes / agent context:** Ideal for testing volumetric fog, bloom from neon lights, and high-contrast ambient occlusion.
- **Status:** proposed

### Agent Suggestion: Bioluminescent Deep-Sea Leviathan — @gemini-agent — 2026-04-20
- **Prompt:** "A majestic, macro-style underwater photograph of an enormous, mythical deep-sea leviathan gliding through the abyssal zone. The creature's scales emit pulsating patterns of bioluminescent blue and green light. The surrounding water is pitch black but speckled with glowing marine snow. The lighting is entirely diegetic, originating from the creature itself. The mood is mysterious, ancient, and awe-inspiring. Photorealistic, 8k resolution, volumetric light rays."
- **Negative prompt:** "sunlight, surface water, bright, shallow, unrealistic, messy"
- **Tags:** underwater, bioluminescence, monster, photorealistic, mysterious
- **Ref image:** `public/images/suggestions/20260420_bioluminescent-leviathan.jpg`
- **Notes / agent context:** Excellent for evaluating subsurface scattering, particle effects (marine snow), and localized glowing light sources.
- **Status:** proposed

### Agent Suggestion: Solarpunk Rooftop Garden — @gemini-agent — 2026-04-20
- **Prompt:** "A wide-angle, sun-drenched view of a lush solarpunk rooftop garden high above a utopian, eco-friendly metropolis. Lush greenery, vibrant flowers, and intricate, organic-looking solar panels intertwine seamlessly. The lighting is bright, natural midday sunlight casting soft, dappled shadows. The mood is optimistic, peaceful, and harmonious. Architectural photography style, hyper-detailed, vibrant colors."
- **Negative prompt:** "dystopian, pollution, dark, gloomy, brutalist, sparse"
- **Tags:** solarpunk, architecture, nature, utopian, bright
- **Ref image:** `public/images/suggestions/20260420_solarpunk-garden.jpg`
- **Notes / agent context:** Perfect for testing global illumination, soft shadows, and complex organic foliage rendering.
- **Status:** proposed

### Agent Suggestion: Ethereal Ghost Ship in the Fog — @gemini-agent — 2026-04-20
- **Prompt:** "A haunting, atmospheric shot of an ancient, dilapidated galleon drifting silently through a dense, glowing mist. The ship is partially transparent, emitting a faint, spectral teal aura. The lighting is diffuse and eerie, with no clear directional source, only the ambient glow of the fog and the ship. The mood is melancholic, spooky, and supernatural. Cinematic lighting, low contrast, muted color palette."
- **Negative prompt:** "sunny, bright, sharp, modern, colorful, active"
- **Tags:** spooky, ethereal, ghost-ship, fog, atmospheric
- **Ref image:** `public/images/suggestions/20260420_ethereal-ghost-ship.jpg`
- **Notes / agent context:** Useful for testing dense volumetric fog, alpha blending, and soft, ambient atmospheric lighting.
- **Status:** proposed

### Agent Suggestion: Clockwork Celestial Astrolabe — @gemini-agent — 2026-04-20
- **Prompt:** "An extremely close-up, macro photography shot of a hyper-detailed, magical astrolabe constructed of glowing, iridescent metal and intricate clockwork gears. Miniature, luminous planets orbit within its rings, casting tiny, sharp shadows across the brushed brass surfaces. The lighting is a mix of warm, incandescent spotlighting and cool, magical emission from the planets. The mood is wondrous, intellectual, and precise. High sharpness, 100mm macro lens, rich textures."
- **Negative prompt:** "flat, simple, large scale, blurry, modern"
- **Tags:** steampunk, magical, intricate, macro, celestial
- **Ref image:** `public/images/suggestions/20260420_clockwork-astrolabe.jpg`
- **Notes / agent context:** Great for evaluating metallic reflections (PBR), depth of field, and intricate geometric details.
- **Status:** proposed
### Suggestion: Bioluminescent Deep Sea Leviathan
- **Date:** 2026-05-18
- **Prompt:** "A photorealistic, majestic deep-sea leviathan swimming through pitch-black water, its massive serpentine body illuminated by pulsating, intricate bioluminescent patterns in neon blue and deep purple. Microscopic glowing plankton swirl around it like stars. Cinematic volumetric lighting filtering through the murky depths, mysterious and awe-inspiring mood. Shot on a wide-angle lens."
- **Negative prompt:** "daylight, surface, bright, ugly, lowres, blurry, cartoon, 2d"
- **Tags:** fantasy, sci-fi, underwater, creature, photorealistic
- **Style / Reference:** photorealistic, cinematic
- **Composition:** wide shot
- **Color palette:** neon blue, deep purple, pitch black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_deep-sea-leviathan.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing subsurface scattering, bioluminescence, and dark water murk effects.

### Suggestion: Solarpunk Rooftop Garden
- **Date:** 2026-05-18
- **Prompt:** "A lush, thriving solarpunk rooftop garden on a futuristic skyscraper at golden hour. Verdant vines drape over high-tech solar panels and wind turbines, blending nature with sleek eco-technology. Warm, golden sunlight casts long shadows, creating a serene and hopeful mood. Shot with a 35mm lens, shallow depth of field focusing on a blooming exotic flower in the foreground while the futuristic eco-city fades into the background blur."
- **Negative prompt:** "dystopian, smog, pollution, cyberpunk, dark, lowres, bleak"
- **Tags:** solarpunk, architecture, nature, futuristic, golden hour
- **Style / Reference:** architectural visualization, photorealistic
- **Composition:** close-up foreground, wide background
- **Color palette:** warm golds, vibrant greens, soft blues
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_solarpunk-rooftop.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing foliage rendering, warm lighting, and depth of field.

### Suggestion: Neon Samurai in Cyber-Tokyo
- **Date:** 2026-05-18
- **Prompt:** "A hyper-detailed, low-angle shot of a lone samurai wearing a highly advanced cybernetic suit, standing in a rain-slicked alleyway of a sprawling neon cyberpunk metropolis. The samurai holds a glowing crimson energy katana. Vivid reflections of neon signs (kanji) bounce off wet pavement and polished armor. High contrast, gritty, and dramatic mood. Cinematic lighting, rain drops frozen in mid-air."
- **Negative prompt:** "daylight, clean, historical, traditional, flat, lowres, anime"
- **Tags:** cyberpunk, samurai, neon, rain, gritty
- **Style / Reference:** hyper-detailed 3d render, cinematic
- **Composition:** low-angle shot
- **Color palette:** crimson red, cyan, magenta, deep blacks
- **Aspect ratio:** 9:16
- **Reference images:** `public/images/suggestions/20260518_neon-samurai.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing reflections, bloom, emission, and high-contrast environments.

### Suggestion: Steampunk Observatory
- **Date:** 2026-05-18
- **Prompt:** "The intricate interior of a grand steampunk observatory perched on a mountain peak, filled with colossal brass telescopes, complex gear mechanisms, and glowing astrolabes. A massive glass dome reveals a breathtaking, hyper-detailed galaxy swirling with nebulae and stardust. Warm candlelight and ambient ethereal starlight illuminate the ornate wooden floors and brass instruments. Sense of wonder and discovery. Wide-angle lens, extremely detailed."
- **Negative prompt:** "modern, sleek, digital, minimalist, lowres, bright daylight"
- **Tags:** steampunk, interior, astronomy, space, intricate
- **Style / Reference:** highly detailed illustration, concept art
- **Composition:** wide shot
- **Color palette:** warm brass, mahogany, deep space blues, vibrant purple nebula
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_steampunk-observatory.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating fine details, metallic textures, and warm/cool contrast lighting.

### Suggestion: Crystal Cave of Echoes
- **Date:** 2026-05-18
- **Prompt:** "A vast, subterranean cavern completely filled with colossal, semi-translucent geometric crystals jutting from the floor and ceiling. The crystals softly emit a pale, iridescent glow, casting refractive rainbow patterns on the cavern walls. A pristine, mirror-like underground lake reflects the crystals perfectly. Ethereal, tranquil, and mysterious mood. Long exposure photography style to capture the soft light."
- **Negative prompt:** "sunlight, plants, people, messy, chaotic, flat, matte"
- **Tags:** nature, fantasy, underground, crystals, glowing
- **Style / Reference:** long exposure photography, photorealistic
- **Composition:** symmetrical, wide shot
- **Color palette:** pale blue, iridescent rainbow, dark grey rock
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_crystal-cave.jpg`
- **License / Attribution:** CC0
- **Notes:** Superb for testing refraction, translucency, global illumination, and caustics.

### Suggestion: Holographic Desert Oasis
- **Date:** 2026-05-20
- **Prompt:** "A futuristic desert oasis at twilight, where palm trees are made of glowing holographic hard-light projections. A crystal-clear pool reflects the twin setting moons. Soft, diffused neon lighting blending with natural sunset colors. Ethereal, tranquil mood, high detail."
- **Negative prompt:** "people, noisy, messy, daytime, simple, flat"
- **Tags:** cyberpunk, desert, holographic, oasis, sci-fi
- **Style / Reference:** 3D render, photorealistic, cinematic lighting
- **Composition:** wide landscape shot, rule of thirds
- **Color palette:** neon pink, cyan, deep orange, indigo
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_holographic-oasis.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing emission, reflections, and contrast between organic shapes and digital textures.

### Suggestion: Steampunk Botanist's Greenhouse
- **Date:** 2026-05-20
- **Prompt:** "Inside a massive Victorian greenhouse constructed of ornate wrought iron and curved glass. Exotic, giant alien plants with bioluminescent veins grow uncontrollably. Steam-powered brass sprinklers emit a fine mist. Shafts of afternoon sunlight pierce through the hazy atmosphere. Warm, mysterious mood."
- **Negative prompt:** "modern architecture, characters, dark, gloomy, low detail"
- **Tags:** steampunk, botanical, greenhouse, fantasy, atmospheric
- **Style / Reference:** highly detailed illustration, Victorian aesthetic
- **Composition:** interior wide shot, deep depth of field
- **Color palette:** brass, emerald green, warm amber, soft teal
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260520_steampunk-greenhouse.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating volumetric lighting, atmospheric scattering, and complex overlapping geometry.

### Suggestion: Deep Space Dyson Sphere Construction
- **Date:** 2026-05-20
- **Prompt:** "A colossal, incomplete Dyson Sphere surrounding a hyper-active blue giant star. Millions of geometric solar panels are being assembled by swarm-like constructor ships. Brilliant, harsh stellar lighting creating stark shadows on the metallic structures. Epic, awe-inspiring mood, monumental scale."
- **Negative prompt:** "planets, organic, smooth, dark, blurry"
- **Tags:** sci-fi, space, megastructure, star, engineering
- **Style / Reference:** sci-fi concept art, hyper-realistic
- **Composition:** epic wide shot, high contrast
- **Color palette:** blinding electric blue, dark grey, stark white
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_dyson-sphere.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests handling of extreme brightness, sharp shadows, and vast scale differences.

### Suggestion: Bioluminescent Deep Sea Leviathan
- **Date:** 2026-05-20
- **Prompt:** "A massive, ancient deep-sea leviathan swimming gracefully through an abyssal trench. The creature's scales emit a pulsing, complex pattern of bioluminescent light. The surrounding water is pitch black, illuminated only by the creature's glow and tiny, glowing marine snow. Mystical, terrifying yet beautiful mood."
- **Negative prompt:** "shallow water, daylight, brightly colored coral, human divers"
- **Tags:** underwater, monster, bioluminescence, abyssal, creature
- **Style / Reference:** underwater photography, national geographic style
- **Composition:** side profile, macro to medium shot
- **Color palette:** pitch black, neon blue, seafoam green, ultra-violet
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_abyssal-leviathan.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for subsurface scattering, soft volumetric glows, and deep sea atmosphere.

### Suggestion: Cyber-Renaissance Clockwork City
- **Date:** 2026-05-20
- **Prompt:** "A sprawling renaissance-era city built entirely from brass, copper, and glowing quartz clockwork mechanisms. Giant gears serve as bridges. The city is bathed in the golden hour light of a massive, close-orbiting gas giant planet filling the sky. Majestic, intricate, surreal mood."
- **Negative prompt:** "nature, plants, modern technology, dirty, rusty"
- **Tags:** clockwork, city, renaissance, surreal, fantasy
- **Style / Reference:** fantasy landscape, intricate 3D environment
- **Composition:** aerial cityscape, dynamic angle
- **Color palette:** gold, polished copper, warm amber, pale quartz
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_clockwork-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests highly detailed repeating patterns, metallic reflections, and golden hour lighting.

### Suggestion: Holographic Cyber-Moth
- **Date:** 2026-11-25
- **Prompt:** "A highly detailed macro shot of a delicate cybernetic moth resting on a rain-slicked neon street sign. The moth's wings are made of semi-translucent, glowing holographic hard-light projections displaying shifting data streams. The subject is illuminated by the intense, colorful ambient light of a bustling cyberpunk city at night, reflecting off its polished chrome body. The mood is serene yet technologically advanced. Captured with a 100mm macro lens, shallow depth of field, rendering the distant city lights into beautiful, large bokeh."
- **Negative prompt:** "organic wings, daylight, bright sky, cartoon, low resolution, messy, blurry"
- **Tags:** macro, cyberpunk, cybernetic, holographic, insect
- **Style / Reference:** photorealistic macro photography, sci-fi concept art
- **Composition:** extreme close-up, rule of thirds, beautiful bokeh background
- **Color palette:** neon magenta, glowing cyan, polished chrome, dark rain-slicked black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261125_holographic-cyber-moth.jpg`
- **License / Attribution:** CC0

### Suggestion: Clockwork Solar System Armillary Sphere
- **Date:** 2026-11-25
- **Prompt:** "A mesmerizing, intricate clockwork armillary sphere depicting the solar system, resting on an old, mahogany desk in a dimly lit Victorian study. The mechanical subject is constructed of gleaming brass rings, intricate copper gears, and small, glowing gemstones representing planets. The lighting is warm and cinematic, emanating from a single flickering candle just out of frame, casting long, dancing shadows and sharp specular glints across the polished metal surfaces. The mood is intellectual, antique, and wondrous. Captured with a 50mm lens, deep focus to capture the layered complexity of the intersecting brass rings."
- **Negative prompt:** "modern, plastic, daylight, flat lighting, blurry, out of focus, simple"
- **Tags:** steampunk, still-life, brass, mechanical, astronomy
- **Style / Reference:** photorealistic still-life photography, steampunk aesthetic
- **Composition:** centered subject, eye-level perspective, dramatic lighting
- **Color palette:** warm brass, polished copper, deep mahogany brown, glowing amber and sapphire accents
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261125_clockwork-armillary-sphere.jpg`
- **License / Attribution:** CC0

### Suggestion: Biopunk Crystal Cavern
- **Date:** 2026-11-25
- **Prompt:** "An expansive, surreal view deep inside a biopunk subterranean cavern. The cave walls are lined with colossal, bioluminescent amethyst crystals that are seamlessly fused with organic, pulsating, fleshy veins and cybernetic tubes. The lighting is low-key, entirely dependent on the eerie, glowing purple light of the crystals and the sickly neon green fluids pumping through the translucent tubes. The mood is alien, toxic, and dangerously beautiful. Captured with a wide 14mm lens to emphasize the massive, overwhelming scale of the biomechanical crystal environment."
- **Negative prompt:** "sunlight, daylight, dry rock, clean metal, realistic cave, bright, cheerful"
- **Tags:** biopunk, fantasy, underground, glowing, crystal
- **Style / Reference:** biopunk concept art, dark sci-fi environmental visualization
- **Composition:** wide angle, deep perspective, immersive environment
- **Color palette:** glowing amethyst purple, toxic neon green, deep fleshy reds, pitch black shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261125_biopunk-crystal-cavern.jpg`
- **License / Attribution:** CC0

### Suggestion: Retro-Futuristic Hover Diner
- **Date:** 2026-11-25
- **Prompt:** "A nostalgic, sweeping exterior shot of a classic 1950s retro diner, but it is hovering majestically thousands of feet in the air amidst a dense, pink sunset cloudscape. The sleek, chrome-plated subject features glowing neon signage and anti-gravity repulsor engines emitting a soft blue thrust. The lighting is a vibrant, golden-hour sunset, casting warm orange light on the polished chrome exterior and contrasting beautifully with the bright turquoise and pink neon lights of the diner. The mood is optimistic, nostalgic, and adventurous. Captured with an aerial wide-angle perspective to emphasize the dizzying height and beautiful sky."
- **Negative prompt:** "ground, road, gritty, dystopian, dark, rainy, modern architecture"
- **Tags:** retro-futuristic, sci-fi, aerial, neon, diner
- **Style / Reference:** retro-futurism, 1950s atompunk aesthetic, cinematic lighting
- **Composition:** wide aerial shot, subject off-center, dramatic cloudscape background
- **Color palette:** polished chrome silver, vibrant sunset orange, neon turquoise, pastel pink clouds
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261125_hover-diner.jpg`
- **License / Attribution:** CC0

### Suggestion: Solarpunk Wind-Powered Skyship
- **Date:** 2026-11-25
- **Prompt:** "A breathtaking, dynamic shot of an elegant solarpunk skyship sailing through a clear blue sky. The vessel is constructed of polished white composite materials and gleaming bamboo, featuring massive, intricate wind-turbine sails and lush hanging gardens spilling over the hull. The lighting is brilliant, unattenuated midday sunlight, creating crisp, clean shadows and highlighting the vibrant greens of the foliage against the pristine white hull. The mood is uplifting, eco-friendly, and majestic. Captured with a telephoto lens from a parallel flying perspective, keeping the entire ship in sharp focus against a soft, fluffy cloud."
- **Negative prompt:** "smoke, pollution, dystopian, dark, night, gritty, rusted metal"
- **Tags:** solarpunk, vehicle, sky, majestic, eco-friendly
- **Style / Reference:** solarpunk concept art, bright utopian visualization
- **Composition:** dynamic angled profile, tight framing on the ship, leading lines
- **Color palette:** pristine white, warm bamboo yellow, lush forest green, clear sky blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261125_solarpunk-skyship.jpg`
- **License / Attribution:** CC0

### Suggestion: Ashcan School Orbital Ring
- **Date:** 2024-05-30
- **Prompt:** "A gritty, realistic view of a colossal orbital ring under construction, seen from a smog-choked, early 20th-century industrial town. Depicted in the raw, documentary style of the Ashcan School. The colossal structure dominates the hazy, overcast sky above soot-stained tenement buildings and crowded, muddy streets. The lighting is bleak and muted, casting soft, indistinct shadows that emphasize the urban decay contrasted with the incomprehensible scale of the space megastructure. The mood is authentic, oppressive, and historically dissonant. Captured with an eye-level, documentary-style perspective."
- **Negative prompt:** "modern, bright colors, sunny, cheerful, photorealistic, 3d render, sci-fi sleekness"
- **Tags:** art, sci-fi, historical, ashcan school, orbital ring, gritty
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** eye-level, chaotic framing, imposing sky structure
- **Color palette:** murky greens, muted greys, rusted browns, dull ochre
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240530_ashcan-orbital-ring.jpg`
- **License / Attribution:** CC0

### Suggestion: Tweed Exoplanet Core
- **Date:** 2024-05-30
- **Prompt:** "An ultra-macro, surreal visualization deep within the core of an exoplanet, where the extreme pressure has formed the geological layers entirely out of soft, interwoven threads of warm brown herringbone tweed fabric. The subject features dense, folded waves of yarn glowing with intense internal heat. The lighting is harsh and directional from deep within the folds, causing the fibrous texture of the tweed to glow brilliantly with sub-surface scattering, contrasting with deep, dark shadows. The mood is bizarre, tactile, and claustrophobic. Captured with a 100mm macro lens, utilizing a incredibly shallow depth of field to emphasize the soft yarn texture against the intense core heat."
- **Negative prompt:** "rock, magma, liquid, hard surface, realistic core, bright daylight, wide angle"
- **Tags:** macro, surreal, exoplanet, core, tweed
- **Style / Reference:** surreal macro photography, hyper-detailed material swap
- **Composition:** dense folded patterns, tight close-up, shallow depth of field
- **Color palette:** earthy brown tweed, glowing molten orange, deep shadow black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20240530_tweed-exoplanet-core.jpg`
- **License / Attribution:** CC0

### Suggestion: Damascus Steel Tsunami
- **Date:** 2024-05-30
- **Prompt:** "A towering, apocalyptic tsunami wave frozen mid-crash, where the colossal volume of water is inexplicably composed of solid, heavily rippled Damascus steel. The metallic subject features intricate, flowing wave patterns of dark and light grey metal across its curved surface. The lighting is intensely cinematic, with a single break in the stormy clouds casting a blinding spotlight on the crest of the metallic wave, creating sharp specular highlights along the forged ridges while the base remains in deep shadow. The mood is terrifying, heavy, and monumental. Captured from a low angle on the doomed shoreline, utilizing a wide 14mm lens to emphasize the massive, overhanging scale of the metal wave."
- **Negative prompt:** "liquid water, blue, foam, daylight, sunny, soft, calm, organic, smooth"
- **Tags:** disaster, surreal, tsunami, damascus steel, metallic
- **Style / Reference:** cinematic disaster visualization, hyper-detailed material swap
- **Composition:** wide angle, low perspective, towering wave dominating the frame
- **Color palette:** dark metallic greys, blinding silver highlights, stormy sky blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240530_damascus-tsunami.jpg`
- **License / Attribution:** CC0

### Suggestion: Graphene Fireworks
- **Date:** 2024-05-30
- **Prompt:** "A surreal nighttime display where exploding fireworks are inexplicably composed of perfect, light-absorbing geometric shards of matte graphene. The subjects expand outward in sharp, aggressive bursts that absorb the ambient light rather than emitting it. The lighting is highly contrasted, with the deep black explosions silhouetted against a violently bright, neon-lit cyberpunk cityscape background. The mood is abstract, paradoxical, and futuristic. Captured with a wide-angle lens, utilizing a fast shutter speed to freeze the sharp, light-devouring fragmentation of the graphene bursts."
- **Negative prompt:** "bright flashes, glowing sparks, colorful fire, smoke, realistic fireworks, daylight"
- **Tags:** surreal, night, fireworks, graphene, cyberpunk, geometric
- **Style / Reference:** surreal 3D render, high contrast silhouette
- **Composition:** expansive sky view, explosive centers, sharp geometric fragmentation
- **Color palette:** pitch black matte graphene, vibrant neon pink, electric cyan background
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240530_graphene-fireworks.jpg`
- **License / Attribution:** CC0

### Suggestion: Italian Futurism Beaver Dam
- **Date:** 2024-05-30
- **Prompt:** "A dynamic, chaotic scene of a river crashing through a massive beaver dam, depicted in the harsh, fragmented style of Italian Futurism. The organic subject of woven branches and mud is deconstructed into aggressive, jagged diagonal lines and overlapping geometric planes that capture the kinetic energy of the rushing water and the relentless industry of nature. The lighting is intense and directional, casting stark, jagged shadows that enhance the splintered geometry of the composition. The mood is energetic, aggressive, and highly stylized. Captured with a tilted perspective to emphasize raw motion and the violent interplay of wood and water."
- **Negative prompt:** "calm, realistic, photography, smooth curves, gentle, peaceful nature, photorealistic"
- **Tags:** abstract, art, italian futurism, nature, beaver dam, dynamic
- **Style / Reference:** Italian Futurism art movement, Giacomo Balla inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** rusted wood browns, steel greys, harsh stark white water, chaotic black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240530_futurism-beaver-dam.jpg`
- **License / Attribution:** CC0


### Suggestion: Neon Cybernetic Angel
- **Date:** 2024-10-31
- **Prompt:** "A hyper-detailed portrait of a majestic cybernetic angel hovering in a neon-drenched cyberpunk cityscape. The subject features delicate, glowing holographic wings and pristine white armor laced with glowing pink circuitry. The lighting is harsh, directional neon from below, highlighting the futuristic materials. The mood is awe-inspiring and powerful. Captured with a 50mm portrait lens, sharp focus on the metallic faceplate and glowing eyes."
- **Negative prompt:** "organic wings, feathers, bright daylight, natural, blurry, messy background"
- **Tags:** cyberpunk, portrait, cybernetic, angel, neon
- **Style / Reference:** photorealistic, dark sci-fi
- **Composition:** centered portrait, dynamic low angle
- **Color palette:** glowing pink, bright cyan, stark white, pitch black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20241031_cyber-angel.jpg`
- **License / Attribution:** CC0

### Suggestion: Crystal Golem in a Magical Forest
- **Date:** 2024-10-31
- **Prompt:** "A colossal, lumbering golem constructed entirely from jagged, glowing amethyst crystals, walking through an ancient, bioluminescent forest. The subject radiates a soft, purple light that illuminates the surrounding giant ferns. The lighting is ethereal and low-key, heavily dependent on the glowing crystals and ambient forest spores. The mood is mystical, peaceful, and magical. Captured with a wide 35mm lens, showcasing the scale of the golem against the towering ancient trees."
- **Negative prompt:** "city, metal, robot, modern, daylight, scary, fast"
- **Tags:** fantasy, creature, crystal, forest, magical
- **Style / Reference:** high fantasy concept art, photorealistic rendering
- **Composition:** wide shot, rule of thirds, grand scale
- **Color palette:** glowing purple amethyst, deep forest greens, soft bioluminescent cyan
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20241031_crystal-golem.jpg`
- **License / Attribution:** CC0

### Suggestion: Steampunk Submarine in a Coral Reef
- **Date:** 2024-10-31
- **Prompt:** "A highly detailed, intricate steampunk submarine exploring a vibrant underwater coral reef. The subject is made of polished brass and copper, with large glass portholes and spinning propellers. The lighting is bright, dappled sunlight piercing through the clear blue ocean water, causing specular highlights on the metallic hull. The mood is adventurous, wondrous, and Jules Verne-inspired. Captured with a wide-angle lens, keeping both the submarine and the colorful foreground coral in sharp focus."
- **Negative prompt:** "dark, scary, murky water, modern submarine, plain metal, blurry"
- **Tags:** steampunk, underwater, vehicle, coral, adventure
- **Style / Reference:** steampunk concept art, photorealistic underwater photography
- **Composition:** dynamic angle, wide perspective, detailed foreground
- **Color palette:** warm brass, vibrant coral pinks, deep ocean blue, bright sunlight white
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20241031_steampunk-sub.jpg`
- **License / Attribution:** CC0

### Suggestion: Post-Apocalyptic Neon Diner
- **Date:** 2024-10-31
- **Prompt:** "An overgrown, abandoned 1950s retro diner sitting in a post-apocalyptic desert wasteland. The subject features rusted chrome siding and a flickering neon 'OPEN' sign. The lighting is a dramatic, fiery sunset that casts long, moody shadows across the dusty landscape, contrasting with the bright pink glow of the failing neon sign. The mood is lonely, nostalgic, and cinematic. Captured with a 24mm wide-angle lens, emphasizing the vast emptiness surrounding the structure."
- **Negative prompt:** "clean, bustling, city, daylight, pristine, people, modern"
- **Tags:** post-apocalyptic, landscape, neon, diner, desert
- **Style / Reference:** cinematic wasteland photography, retro-futurism
- **Composition:** wide landscape, subject off-center, low horizon line
- **Color palette:** dusty orange, rusted browns, neon pink, fiery sunset reds
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20241031_neon-diner.jpg`
- **License / Attribution:** CC0

### Suggestion: Ethereal Floating Jellyfish City
- **Date:** 2024-10-31
- **Prompt:** "A breathtaking view of a futuristic city where the buildings resemble gigantic, translucent jellyfish floating in a sea of pink and orange clouds. The subjects are suspended in the sky, trailing glowing, bioluminescent tentacles. The lighting is soft and omnidirectional from the surrounding sunset clouds, creating thousands of internal refractions within the glass-like structures. The mood is utopian, surreal, and serene. Captured with an aerial wide-angle perspective, showing the vastness of the cloudscape and floating city."
- **Negative prompt:** "ground, dark, gritty, cyberpunk, realistic architecture, harsh shadows"
- **Tags:** sci-fi, surreal, city, floating, ethereal
- **Style / Reference:** utopian concept art, ethereal 3D render
- **Composition:** expansive aerial view, floating subjects, balanced framing
- **Color palette:** translucent soft blue, pastel pink clouds, glowing golden orange
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20241031_jellyfish-city.jpg`
- **License / Attribution:** CC0


### Suggestion: Italian Futurism Supernova
- **Date:** 2024-06-01
- **Prompt:** "A cataclysmic supernova explosion depicted in the harsh, fragmented style of Italian Futurism. The cosmic subject is deconstructed into aggressive, jagged diagonal lines and overlapping geometric planes that capture the kinetic energy and overwhelming speed of the expanding stellar material. The lighting is intense and directional, casting stark, jagged shadows that enhance the splintered geometry of the composition. The mood is energetic, destructive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion and the violent impact of the fragmented star."
- **Negative prompt:** "calm, realistic, photography, smooth curves, gentle, peaceful nature, photorealistic, circular"
- **Tags:** abstract, art, italian futurism, space, supernova, dynamic
- **Style / Reference:** Italian Futurism art movement, Giacomo Balla inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** blazing orange, steel greys, harsh stark white, chaotic black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240601_futurism-supernova.jpg`
- **License / Attribution:** CC0

### Suggestion: Brass Volcanic Eruption
- **Date:** 2024-06-01
- **Prompt:** "A terrifying, surreal landscape of a massive volcano erupting, where the mountain and the flying debris are composed entirely of intricate, polished brass clockwork and gears. The mechanical subject spews rivers of blindingly bright, super-heated white plasma instead of lava. The lighting is intensely harsh, emanating entirely from the plasma rivers and explosive core, creating a stark interplay of blinding white-hot streaks against the reflective brass machinery. The mood is apocalyptic, alien, and unfathomably powerful. Captured with a wide-angle lens from a safe distance, freezing the dynamic flow of plasma against the rigid brass structure."
- **Negative prompt:** "red lava, orange, fire, realistic volcano, smoke, messy, blurry, soft lighting, daylight, stone"
- **Tags:** sci-fi, landscape, volcano, brass, plasma, steampunk
- **Style / Reference:** surreal sci-fi landscape, steampunk aesthetic
- **Composition:** wide landscape, explosive center, sharp contrast
- **Color palette:** polished warm brass, blinding white-hot plasma, deep metallic shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240601_brass-volcanic-eruption.jpg`
- **License / Attribution:** CC0

### Suggestion: Mother of Pearl Bioluminescent Reef
- **Date:** 2024-06-01
- **Prompt:** "A breathtaking, macro underwater photograph of a sprawling coral reef where the coral formations are composed entirely of shimmering, iridescent mother of pearl (nacre). The geometric subjects are populated by tiny, intensely glowing bioluminescent sea life that illuminates the reef from within. The lighting is exclusively from the bioluminescence, creating a stark, high-contrast interplay of blinding neon cyan and magenta streaks against the pearlescent pastels of the nacre. The mood is luxurious, alien, and deeply serene. Captured with a 50mm macro lens, utilizing a shallow depth of field to isolate a single glowing polyp against the iridescent background."
- **Negative prompt:** "bright sunlight, surface, muddy water, opaque coral, realistic fish, soft lighting, dull"
- **Tags:** underwater, sci-fi, macro, mother of pearl, bioluminescent, iridescent
- **Style / Reference:** photorealistic underwater photography, surreal material swap
- **Composition:** macro close-up, sharp contrast, beautiful soft bokeh
- **Color palette:** pearlescent pinks, glowing neon cyan, vibrant magenta, shimmering silver
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240601_mother-of-pearl-reef.jpg`
- **License / Attribution:** CC0

### Suggestion: Damascus Steel Orbital Ring
- **Date:** 2024-06-01
- **Prompt:** "An epic, sweeping view of a colossal Orbital Ring megastructure encircling a dark, terrestrial planet, constructed entirely from perfectly forged, heavily rippled Damascus steel. The sleek, dark, metallic subject features intricate, flowing wave patterns of dark and light grey metal across its massive surface. The lighting is a dramatic sunrise cresting over the planet's horizon, casting a blinding white glare that highlights the forged ridges of the ring while the base remains in deep shadow. The mood is silent, awe-inspiring, and technologically supreme. Captured with an extreme wide-angle cinematic lens from low Earth orbit, emphasizing planetary scale and the vast, patterned ring."
- **Negative prompt:** "smooth metal, reflective, bright structure, rusted, broken, dystopian, small scale, matte"
- **Tags:** sci-fi, megastructure, space, orbital ring, damascus steel
- **Style / Reference:** hard sci-fi environment design, cinematic space art
- **Composition:** curved horizon, extreme wide angle, massive scale
- **Color palette:** dark metallic greys, blinding solar white, vibrant earth greens and blues
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20240601_damascus-orbital-ring.jpg`
- **License / Attribution:** CC0

### Suggestion: Graphene Supernova
- **Date:** 2024-06-01
- **Prompt:** "A surreal cosmic display where a cataclysmic supernova explosion is inexplicably composed of perfect, light-absorbing geometric shards of matte graphene. The subjects expand outward in sharp, aggressive bursts that absorb the ambient starlight rather than emitting it. The lighting is highly contrasted, with the deep black explosions silhouetted against a violently bright, glowing magenta and cyan nebula background. The mood is abstract, paradoxical, and futuristic. Captured with a wide-angle lens, utilizing a fast shutter speed to freeze the sharp, light-devouring fragmentation of the graphene bursts."
- **Negative prompt:** "bright flashes, glowing sparks, colorful fire, smoke, realistic supernova, soft"
- **Tags:** surreal, space, supernova, graphene, geometric
- **Style / Reference:** surreal 3D render, high contrast silhouette
- **Composition:** expansive sky view, explosive centers, sharp geometric fragmentation
- **Color palette:** pitch black matte graphene, vibrant neon magenta, electric cyan background
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240601_graphene-supernova.jpg`
- **License / Attribution:** CC0
### Suggestion: Graphene Cybernetic Cheetah
- **Date:** 2024-06-02
- **Prompt:** "A hyper-detailed, macro shot of a cybernetic cheetah mid-sprint, where its sleek armor plating is entirely forged from light-absorbing, matte graphene. The robotic subject features glowing neon cyan optic sensors and exposed brushed steel joints. The lighting is harsh, directional, and high-contrast, casting stark shadows that highlight the pitch-black, geometric carbon surface against a blurry, futuristic savanna background. The mood is predatory, advanced, and sleek. Captured with a 100mm telephoto lens, utilizing motion blur panning to keep the cheetah sharp while blurring the environment."
- **Negative prompt:** "organic fur, slow, stationary, bright daylight, realistic animal, plain metal"
- **Tags:** sci-fi, cybernetic, animal, graphene, macro
- **Style / Reference:** sci-fi wildlife photography, hyper-detailed material swap
- **Composition:** dynamic horizontal motion, tight framing, panning blur
- **Color palette:** pitch black matte graphene, glowing neon cyan, blurred warm savanna colors
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240602_graphene-cheetah.jpg`
- **License / Attribution:** CC0

### Suggestion: Mother of Pearl Volcanic Eruption
- **Date:** 2024-06-02
- **Prompt:** "A terrifying, surreal landscape of a massive volcano erupting, where the mountain and the flying debris are composed entirely of shimmering, iridescent mother of pearl. The organic-looking subject spews rivers of blindingly bright, super-heated white plasma instead of lava. The lighting is intensely harsh, emanating entirely from the plasma rivers and explosive core, creating a stark interplay of blinding white-hot streaks against the pearlescent pastels of the nacre structure. The mood is apocalyptic, alien, and unfathomably beautiful. Captured with a wide-angle lens from a safe distance, freezing the dynamic flow of plasma against the iridescent shell material."
- **Negative prompt:** "red lava, orange, fire, realistic volcano, smoke, messy, blurry, soft lighting, daylight, stone, dark"
- **Tags:** sci-fi, landscape, volcano, mother of pearl, plasma, surreal
- **Style / Reference:** surreal sci-fi landscape, hyper-detailed material swap
- **Composition:** wide landscape, explosive center, sharp contrast
- **Color palette:** pearlescent pinks and blues, blinding white-hot plasma, shimmering silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240602_mother-of-pearl-volcano.jpg`
- **License / Attribution:** CC0

### Suggestion: Bismuth City in the Clouds
- **Date:** 2024-06-02
- **Prompt:** "An epic, sweeping aerial view of a massive utopian city suspended high in a bright blue sky, constructed entirely from gigantic, naturally forming hopper crystals of iridescent bismuth. The intricate, stair-stepped geometric buildings reflect a dazzling array of rainbow colors—pinks, greens, golds, and blues. The lighting is bright, clear midday sunlight that catches the sharp, right-angled crystal edges, casting deep, sharp shadows and brilliant metallic reflections across the floating metropolis. The mood is majestic, advanced, and visually overwhelming. Captured with a wide-angle drone perspective to showcase the architectural elegance against a backdrop of fluffy white clouds."
- **Negative prompt:** "concrete, dark, night, dystopia, smooth curves, organic, dull, soft lighting"
- **Tags:** sci-fi, architecture, city, floating, bismuth, iridescent
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** wide expansive view, towering geometric forms, cloud floor
- **Color palette:** highly iridescent rainbow, metallic pinks and blues, stark white clouds, deep blue sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240602_bismuth-city.jpg`
- **License / Attribution:** CC0

### Suggestion: Brass Steampunk Beehive
- **Date:** 2024-06-02
- **Prompt:** "An incredibly detailed, macro view deep inside a gigantic, mechanical beehive where the entire honeycomb structure is constructed from polished brass and complex clockwork gears. The mechanical subject features perfectly repeating hexagonal cells, filled with glowing, viscous synthetic amber oil instead of honey. The lighting is warm and directional from an internal glowing core, causing the metallic brass surfaces to shine brilliantly with sharp specular highlights against deep, dark shadows. The mood is industrious, mechanical, and mathematically precise. Captured with a 100mm macro lens, deep depth of field to emphasize the endless geometric repetition of the metallic honeycomb."
- **Negative prompt:** "wax, yellow honey, plastic, natural, organic, soft curves, daylight, wide angle"
- **Tags:** macro, steampunk, beehive, brass, mechanical, geometric
- **Style / Reference:** steampunk concept art, hyper-detailed macro photography
- **Composition:** full frame repeating pattern, deep perspective
- **Color palette:** polished warm brass, glowing synthetic amber, deep metallic shadows
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20240602_brass-beehive.jpg`
- **License / Attribution:** CC0

### Suggestion: Ashcan School Cyberpunk Alley
- **Date:** 2024-06-02
- **Prompt:** "A bustling, gritty night scene of a neon-lit cyberpunk alleyway, depicted in the raw, documentary style of the Ashcan School. The subject features weary, augmented pedestrians and dense, decaying, futuristic tenement buildings adorned with flickering holographic signs. The lighting is bleak and moody, casting soft, indistinct shadows that emphasize the dirt and texture of the urban decay, contrasting with the muted, sickly glow of the neon lights. The mood is authentic, raw, and oppressive. Captured with an eye-level, documentary-style perspective, focusing on the unglamorous reality of the high-tech, low-life metropolis."
- **Negative prompt:** "clean, pristine, cheerful, photorealistic, 3d render, highly saturated, smooth"
- **Tags:** cyberpunk, art, urban, historical, ashcan school, gritty
- **Style / Reference:** Ashcan School painting, Robert Henri inspired, thick brushstrokes
- **Composition:** eye-level, crowded street, naturalistic framing, dense architecture
- **Color palette:** muted greys, rusted browns, dull neon cyan and magenta, sickly yellow
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240602_ashcan-cyberpunk-alley.jpg`
- **License / Attribution:** CC0


### Suggestion: Bioluminescent Quartz Geode
- **Date:** 2024-06-15
- **Prompt:** "A highly detailed, macro photograph of a cracked quartz geode revealing a chaotic interior of glowing, bioluminescent cyan crystals. The subject emits a soft, pulsing light that illuminates the rough, dark grey exterior of the rock. The lighting is low-key, strictly internal from the glowing crystals, creating stark contrasts and deep shadows within the rocky exterior crust. The mood is mysterious and magical. Captured with a 100mm macro lens, ultra-detailed focus on the sharp edges and light refraction."
- **Negative prompt:** "flat, cartoon, brightly lit, blurry, low resolution, daylight"
- **Tags:** macro, nature, crystals, glowing, magical
- **Style / Reference:** photorealistic, macro photography, geological marvel
- **Composition:** close-up, rule of thirds, sharp center focus
- **Color palette:** glowing cyan, dark rocky greys, deep blacks
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240615_bioluminescent-quartz.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing sub-surface scattering, refraction, and emissive materials on sharp geometric shapes.

### Suggestion: Clockwork Steampunk Owl
- **Date:** 2024-06-15
- **Prompt:** "An intricately crafted mechanical owl made of polished brass, copper, and glowing gears, perched atop an old, leather-bound book in a dimly lit Victorian study. Steam softly escapes from tiny vents on its wings. The lighting is warm and cinematic, coming from a nearby flickering candle, casting long, dancing shadows and sharp specular glints across the metallic surfaces. The mood is wondrous, intellectual, and antique. Captured with a 50mm lens, shallow depth of field focusing on the glowing amber eyes of the owl."
- **Negative prompt:** "flesh, feathers, simple, modern, plastic, flat lighting"
- **Tags:** steampunk, macro, mechanical, animal, victorian
- **Style / Reference:** photorealistic still-life photography, steampunk aesthetic
- **Composition:** centered subject, eye-level perspective, dramatic lighting
- **Color palette:** warm brass, polished copper, deep mahogany brown, glowing amber
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20240615_clockwork-owl.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests metallic surfaces, depth of field, and intricate geometric details.

### Suggestion: Ethereal Floating Castle
- **Date:** 2024-06-15
- **Prompt:** "A breathtaking, wide-angle landscape of a majestic, ancient stone castle floating serenely in a sea of pink and orange sunset clouds. The subject is draped in luminescent green vines and features glowing blue waterfalls cascading into the abyss below. The lighting is a vibrant, golden-hour sunset, casting warm light on the stone walls and creating soft, ethereal shadows. The mood is utopian, surreal, and serene. Captured with an aerial drone perspective to showcase the architectural elegance against the soft cloudscape."
- **Negative prompt:** "ground, dark, gritty, cyberpunk, realistic architecture, harsh shadows, modern"
- **Tags:** fantasy, architecture, floating, surreal, majestic
- **Style / Reference:** high fantasy concept art, ethereal 3D render
- **Composition:** wide expansive view, floating subject, rule of thirds
- **Color palette:** warm golden sunlight, pastel pink clouds, deep stone grey, bioluminescent blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240615_floating-castle.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing soft volumetric lighting and majestic, floating architectural elements.

### Suggestion: Cyberpunk Neon Rain Forest
- **Date:** 2024-06-15
- **Prompt:** "A dense, overgrown tropical rainforest fused with advanced cyberpunk technology. The organic subject features towering banyan trees wrapped in glowing neon fiber optic cables and holographic foliage. The lighting is a striking mix of natural moonlight piercing through the canopy and the harsh, vibrant magenta and cyan glow from the cybernetic implants on the plants. The mood is atmospheric, mysterious, and highly advanced. Captured with a wide 35mm lens, deep depth of field to capture the intricate blending of nature and machine."
- **Negative prompt:** "daylight, dry, barren, city, vehicles, plain nature"
- **Tags:** cyberpunk, nature, neon, forest, atmospheric
- **Style / Reference:** cyberpunk environment design, photorealistic dark nature
- **Composition:** wide angle, dense overlapping elements, immersive
- **Color palette:** lush dark greens, neon magenta, electric cyan, deep shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240615_cyber-forest.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of dense organic foliage with harsh, multi-colored neon emission and dark shadows.

### Suggestion: Art Deco Marble Spaceship Interior
- **Date:** 2024-06-15
- **Prompt:** "A grand, symmetrical view of the main corridor of a luxury passenger spaceship designed entirely in an opulent Art Deco style. The massive walls and floors are made of polished black and white marble, accented with sweeping geometric gold inlays. The lighting is soft and ambient, emanating from elegant, frosted glass fixtures, casting a warm, majestic glow over the highly reflective marble surfaces. The mood is intellectual, wealthy, and futuristic. Captured with a wide-angle 16mm lens to encompass the perfect symmetry and luxurious scale."
- **Negative prompt:** "dystopian, utilitarian, grey, messy, dark, gritty, steampunk"
- **Tags:** sci-fi, architecture, interior, art deco, opulent
- **Style / Reference:** architectural visualization, retro-futuristic
- **Composition:** perfectly symmetrical, one-point perspective, deep corridor
- **Color palette:** polished black marble, stark white, brilliant gold, soft warm white light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240615_artdeco-spaceship.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating highly polished, reflective materials (marble, gold) and perfectly symmetrical geometric architecture.

### Suggestion: Ethereal Glass Cathedral
- **Date:** 2024-07-01
- **Prompt:** "A breathtaking, wide-angle interior shot of a colossal cathedral constructed entirely from semi-translucent, ethereal glass. The massive vaulted ceilings and sweeping arches reflect a soft, omnidirectional glowing light. The lighting is mystical and diffuse, filtering through the glass architecture to create a serene, magical atmosphere. The mood is tranquil, awe-inspiring, and silent. Captured with a 14mm lens to emphasize the massive, soaring architecture and the delicate, transparent nature of the structure."
- **Negative prompt:** "stone, wood, dark, gloomy, messy, daylight, realistic church"
- **Tags:** fantasy, architecture, interior, glass, majestic
- **Style / Reference:** ethereal architectural visualization, hyper-detailed 3D render
- **Composition:** symmetrical, wide angle, low angle looking up
- **Color palette:** soft pearlescent whites, pale cyan, glowing silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240701_glass-cathedral.jpg`
- **License / Attribution:** CC0

### Suggestion: Bioluminescent Jungle Canopy
- **Date:** 2024-07-01
- **Prompt:** "A dense, ancient jungle canopy viewed from below, illuminated entirely by thousands of glowing, bioluminescent vines and giant luminous orchids. The organic subjects pulse with vibrant, ethereal light, casting intricate, colorful shadows. The lighting is low-key and magical, relying completely on the vibrant emission from the flora against the dark night sky. The mood is mysterious, enchanted, and teeming with alien life. Captured with a wide 24mm lens looking straight up, utilizing a deep focus to capture the layered complexity of the canopy."
- **Negative prompt:** "daylight, sun, bright sky, dead trees, barren, plain green"
- **Tags:** fantasy, nature, jungle, bioluminescent, glowing
- **Style / Reference:** photorealistic dark nature photography, bioluminescent concept art
- **Composition:** looking up, dense overlapping elements, immersive
- **Color palette:** glowing neon green, vibrant magenta, ethereal cyan, deep dark blues
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240701_bioluminescent-jungle.jpg`
- **License / Attribution:** CC0

### Suggestion: Steampunk Clockwork Scorpion Macro
- **Date:** 2024-07-01
- **Prompt:** "An incredibly detailed, extreme macro photograph of a mechanical scorpion constructed from polished brass, copper wires, and tiny ticking watch gears. The mechanical subject rests on a piece of dark, aged parchment. The lighting is warm, directional studio lighting that grazes the metallic surface, creating sharp specular highlights on the brass edges and deep, dark shadows between the gears. The mood is intricate, menacing, and antique. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the glowing amber glass eye of the scorpion."
- **Negative prompt:** "organic, flesh, real insect, modern metal, bright daylight, soft lighting"
- **Tags:** macro, steampunk, mechanical, insect, brass
- **Style / Reference:** photorealistic macro product photography, steampunk aesthetic
- **Composition:** extreme close-up, diagonal leading line, shallow depth of field
- **Color palette:** warm brass, polished copper, deep mahogany brown, glowing amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240701_steampunk-scorpion.jpg`
- **License / Attribution:** CC0

### Suggestion: Graphene Cyberpunk Monolith
- **Date:** 2024-07-01
- **Prompt:** "A towering, colossal monolith made of perfectly matte, light-absorbing graphene, standing ominously in the center of a rainy cyberpunk metropolis. The geometric, black subject devours the surrounding light, contrasting sharply with the chaotic, vibrant neon signs reflecting in the wet pavement below. The lighting is high-contrast and dramatic, with the harsh neon lights of the city emphasizing the terrifying, light-absorbing void of the monolith. The mood is oppressive, alien, and highly advanced. Captured with a wide 24mm lens from a low angle on the street, emphasizing the staggering scale and the stark material contrast."
- **Negative prompt:** "shiny metal, reflective, daytime, sunny, natural, soft, organic"
- **Tags:** sci-fi, cyberpunk, monolith, graphene, contrast
- **Style / Reference:** cinematic sci-fi visualization, high contrast city photography
- **Composition:** low angle, towering subject, symmetrical
- **Color palette:** pitch black matte graphene, neon magenta, electric cyan, rainy greys
- **Aspect ratio:** 9:16
- **Reference images:** `public/images/suggestions/20240701_graphene-monolith.jpg`
- **License / Attribution:** CC0

### Suggestion: Art Deco Underwater Lounge
- **Date:** 2024-07-01
- **Prompt:** "A luxurious, symmetrical interior of an underwater lounge designed in an opulent Art Deco style. The subject features grand, arched glass windows revealing a dark, deep-sea environment filled with glowing jellyfish. Inside, the floor is polished black marble and the columns are decorated with geometric gold inlays. The lighting is a blend of the soft, ambient cyan glow from the deep sea outside and the warm, elegant incandescent light from ornate brass chandeliers inside. The mood is wealthy, isolated, and sophisticated. Captured with a wide-angle lens to capture the perfect symmetry and the juxtaposition of the opulent interior with the mysterious ocean."
- **Negative prompt:** "messy, dirty, dystopian, bright sunlight, surface water, plain architecture"
- **Tags:** architecture, interior, art deco, underwater, luxurious
- **Style / Reference:** opulent architectural visualization, retro-futuristic
- **Composition:** perfectly symmetrical, deep perspective, framed by arches
- **Color palette:** polished black marble, brilliant gold, deep oceanic blue, glowing cyan
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240701_art-deco-underwater.jpg`
- **License / Attribution:** CC0

### Suggestion: Biomechanical Dragonfly Macro
- **Date:** 2024-06-25
- **Prompt:** "A highly detailed macro photograph of a biomechanical dragonfly resting on a giant, dew-covered fern leaf. The subject is composed of polished chrome, carbon fiber, and glowing neon-blue fiber optics. The lighting is an ethereal, dappled morning sunlight filtering through the canopy, highlighting the water droplets and reflecting sharply off the chrome. The mood is peaceful yet strangely advanced. Captured with a 100mm macro lens, ultra-shallow depth of field creating a lush, dark green bokeh background."
- **Negative prompt:** "blurry, lowres, organic wings, cartoon, flat lighting, daylight"
- **Tags:** macro, cyberpunk, insect, biomechanical, nature
- **Style / Reference:** photorealistic macro photography, high-detail sci-fi rendering
- **Composition:** extreme close-up, rule of thirds, sharp center focus
- **Color palette:** lush dark green, polished chrome silver, glowing neon blue
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240625_biomech-dragonfly.jpg`
- **License / Attribution:** CC0

### Suggestion: Dieselpunk Subterranean City
- **Date:** 2024-06-25
- **Prompt:** "A massive, awe-inspiring view of a sprawling subterranean city built entirely in a gritty dieselpunk style. The massive cavern is filled with towering, soot-stained concrete structures, riveted steel walkways, and giant, smoke-belching exhaust pipes. The lighting is harsh and warm, emanating from thousands of flickering tungsten bulbs and open blast furnaces, casting deep, oppressive shadows. The mood is industrial, claustrophobic, and majestic. Captured with a wide 14mm lens to emphasize the cavernous scale and vertical depth of the city."
- **Negative prompt:** "clean, modern, bright, sunny, sky, natural, trees"
- **Tags:** dieselpunk, architecture, underground, industrial, gritty
- **Style / Reference:** dieselpunk concept art, cinematic lighting, hyper-detailed
- **Composition:** wide expansive view, deep vertical perspective, dramatic scale
- **Color palette:** soot-stained greys, rusted iron, warm tungsten orange, deep black shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240625_dieselpunk-city.jpg`
- **License / Attribution:** CC0

### Suggestion: Glass Blowing Studio at Midnight
- **Date:** 2024-06-25
- **Prompt:** "A dramatic, cinematic shot inside a traditional Venetian glass-blowing studio late at night. The central subject is a master artisan shaping a massive, intricate vase of molten, glowing orange glass. The lighting is entirely diegetic, with the intense, blinding heat of the furnace and the molten glass illuminating the artisan's face and the surrounding tools, leaving the edges of the room in deep, inky blackness. The mood is intense, focused, and passionate. Captured with a 50mm lens, utilizing a fast shutter speed to freeze the flying sparks."
- **Negative prompt:** "daylight, fluorescent lights, modern factory, blurry, cold, empty"
- **Tags:** interior, craft, glassblowing, fire, dramatic
- **Style / Reference:** cinematic documentary photography, tenebrism
- **Composition:** eye-level medium shot, centered action, strong chiaroscuro
- **Color palette:** blinding molten orange, warm amber, deep shadowy black
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20240625_glass-studio.jpg`
- **License / Attribution:** CC0

### Suggestion: Synthetic Emerald Glacier
- **Date:** 2024-06-25
- **Prompt:** "A breathtaking, wide-angle landscape of a colossal glacier, but the ice is entirely replaced by massive, perfectly faceted synthetic emeralds. The jagged, towering crystalline structures reflect and refract light in brilliant shades of deep green. The lighting is a crisp, bright Arctic morning sun, piercing through the translucent gems to create complex, glowing internal refractions and scattering vibrant green light onto the surrounding dark, rocky moraine. The mood is surreal, pristine, and majestic. Captured with an ultra-wide cinematic lens, showcasing the sheer scale of the geometric formation."
- **Negative prompt:** "white ice, snow, water, soft edges, blurry, dark, moody"
- **Tags:** landscape, fantasy, surreal, emerald, glacier
- **Style / Reference:** surreal landscape photography, hyper-detailed material swap
- **Composition:** wide landscape, sweeping curves, sharp geometric details
- **Color palette:** vibrant emerald green, crisp sunlight white, dark slate grey rock
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20240625_emerald-glacier.jpg`
- **License / Attribution:** CC0

### Suggestion: Baroque Astral Observatory
- **Date:** 2024-06-25
- **Prompt:** "The lavish interior of a grand observatory designed in an ornate, over-the-top Baroque style. The room features sweeping marble staircases, heavily gilded gold trim, and a massive, intricately painted domed ceiling that opens to a swirling, hyper-realistic purple and gold nebula. In the center stands a colossal, brass telescope adorned with angelic sculptures. The lighting is a majestic mix of the vibrant cosmic glow from the nebula and hundreds of floating, magical candles. The mood is opulent, magical, and awe-inspiring. Captured with a 24mm wide-angle lens, perfectly symmetrical."
- **Negative prompt:** "modern, minimalist, sterile, dark, simple, sci-fi sleekness"
- **Tags:** architecture, fantasy, baroque, observatory, space
- **Style / Reference:** opulent fantasy concept art, highly detailed 3D environment
- **Composition:** perfectly symmetrical, grand scale, low angle looking up
- **Color palette:** polished white marble, brilliant gold, glowing nebula purple, warm candle amber
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240625_baroque-observatory.jpg`
- **License / Attribution:** CC0


### Suggestion: Bioluminescent Neoclassical Library
- **Date:** 2026-06-25
- **Prompt:** "A grand, symmetrical interior of a Neoclassical library, overgrown with vibrant, glowing bioluminescent vines and giant luminous mushrooms. The majestic marble columns and vaulted ceiling are illuminated entirely by the ethereal cyan and magenta glow of the magical flora. Ancient, dusty books rest on intricately carved stone shelves. The lighting is low-key, heavily contrasting the glowing vegetation with deep, mysterious shadows in the corners. The mood is ancient, enchanted, and scholarly. Captured with a 14mm wide-angle lens, perfectly symmetrical composition emphasizing the grand scale."
- **Negative prompt:** "daylight, modern, clean, people, artificial lighting, simple, lowres, blurry"
- **Tags:** fantasy, architecture, bioluminescent, library, neoclassical
- **Style / Reference:** fantasy architectural visualization, photorealistic 3D environment
- **Composition:** perfectly symmetrical, grand scale, deep perspective
- **Color palette:** glowing cyan, vibrant magenta, pale marble white, deep shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260625_bioluminescent-neoclassical-library.jpg`
- **License / Attribution:** CC0

### Suggestion: Steampunk Bonsai Garden
- **Date:** 2026-06-25
- **Prompt:** "A highly detailed, macro photograph of a delicate bonsai tree constructed entirely of polished brass, copper wire, and tiny ticking watch gears, sitting in a shallow ceramic pot filled with rusted iron shavings. The metallic leaves catch the warm, directional studio lighting, creating sharp specular highlights and deep, dark shadows between the intricate gears. A faint mist of steam escapes from the base. The mood is meticulous, antique, and wondrous. Captured with a 100mm macro lens, utilizing a shallow depth of field to blur the dark background into smooth bokeh."
- **Negative prompt:** "organic, real plant, green leaves, flat lighting, daylight, blurry"
- **Tags:** macro, steampunk, mechanical, bonsai, brass
- **Style / Reference:** photorealistic macro product photography, steampunk aesthetic
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** warm brass, polished copper, rusted iron, dark background
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260625_steampunk-bonsai.jpg`
- **License / Attribution:** CC0

### Suggestion: Art Nouveau Spacesuit Portrait
- **Date:** 2026-06-25
- **Prompt:** "A majestic, surreal portrait of an astronaut wearing a highly ornate spacesuit designed in the sweeping, elegant curves and whiplash lines of the Art Nouveau style. The spacesuit is made of polished silver and translucent, fossilized amber panels. The subject stands against the backdrop of a distant, swirling purple galaxy. The lighting is cinematic, with harsh, dramatic rim lighting from a nearby star catching the polished silver, contrasting with the soft cosmic glow of the galaxy. The mood is elegant, adventurous, and highly stylized. Captured with an 85mm portrait lens, sharp focus on the helmet's amber visor."
- **Negative prompt:** "standard spacesuit, realistic, dull, messy, blurry, simple, flat"
- **Tags:** sci-fi, portrait, art nouveau, spacesuit, elegant
- **Style / Reference:** surreal fashion photography, sci-fi concept art
- **Composition:** centered portrait, dynamic lighting, beautiful cosmic background
- **Color palette:** polished silver, warm amber, glowing nebula purple, deep cosmic black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260625_art-nouveau-spacesuit.jpg`
- **License / Attribution:** CC0

### Suggestion: Dieselpunk Arctic Icebreaker
- **Date:** 2026-06-25
- **Prompt:** "A colossal, soot-stained dieselpunk icebreaker ship violently crashing through a massive, frozen glacier. The heavy, riveted steel ship belches thick, black smoke from towering exhaust pipes, contrasting with the pristine, blinding white ice of the Arctic landscape. The lighting is harsh, freezing midday sunlight that casts sharp, deep shadows across the jagged ice and the rusted hull. The mood is aggressive, industrial, and overpowering. Captured with a wide-angle 24mm lens from a low perspective on the ice, emphasizing the imposing, monolithic scale of the ship."
- **Negative prompt:** "clean, modern, bright colors, sunny, soft, peaceful, organic"
- **Tags:** dieselpunk, vehicle, landscape, icebreaker, industrial
- **Style / Reference:** dieselpunk concept art, cinematic landscape photography
- **Composition:** wide angle, low perspective, dramatic scale, dynamic action
- **Color palette:** rusted iron, soot-stained grey, blinding white ice, pale freezing blue
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260625_dieselpunk-icebreaker.jpg`
- **License / Attribution:** CC0

### Suggestion: Cyberpunk Coral Reef Megastructure
- **Date:** 2026-06-25
- **Prompt:** "An underwater, wide-angle shot of a sprawling coral reef that has been fused with a massive, abandoned cyberpunk megastructure. Glowing neon fiber optic cables intertwine with organic sea anemones, and giant rusted metal pillars rise from the sea floor, covered in barnacles and glowing coral. The lighting is mysterious, blending the murky, deep ocean blue with harsh, flickering neon pink and cyan lights from the decaying technology. The mood is melancholic, advanced, and hauntingly beautiful. Captured with a 14mm lens, deep depth of field to capture the intricate blending of technology and nature."
- **Negative prompt:** "daylight, surface, clean metal, realistic fish, soft lighting, sunny"
- **Tags:** cyberpunk, underwater, nature, ruins, neon
- **Style / Reference:** cyberpunk environment design, photorealistic dark nature
- **Composition:** wide angle, dense overlapping elements, immersive deep perspective
- **Color palette:** deep ocean blue, neon magenta, electric cyan, rusted metal browns
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260625_cyberpunk-coral-reef.jpg`
- **License / Attribution:** CC0


### Suggestion: Neon Bioluminescent Forest
- **Date:** 2026-05-18
- **Prompt:** "A dense, ethereal forest illuminated entirely by neon bioluminescence. Giant, glowing blue fungi and iridescent ferns cast a cool light over the forest floor. The mood is mysterious and magical. Soft, volumetric fog rolls through the trees. Shot on a 35mm lens with shallow depth of field, highlighting a single glowing mushroom in the foreground while the background blurs smoothly into a mystical haze."
- **Negative prompt:** "daylight, sun, photorealistic, modern, buildings, people"
- **Tags:** fantasy, bioluminescent, nature, mystical, glowing
- **Style / Reference:** digital art, fantasy concept art, highly detailed
- **Composition:** ground level shot, rule of thirds, shallow depth of field
- **Color palette:** neon blue, cyan, deep magenta, dark emerald green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_neon-forest.jpg`
- **License / Attribution:** CC0

### Suggestion: Cybernetic Zen Garden
- **Date:** 2026-05-18
- **Prompt:** "A traditional Japanese zen garden reimagined in a cyberpunk aesthetic. The raked sand is made of glowing optical fibers, and the large rocks are polished obsidian with glowing circuitry patterns. A robotic cherry blossom tree drops holographic pink petals. Soft neon lighting from the tree illuminates the dark environment. Cinematic lighting, low angle shot, highly detailed, moody."
- **Negative prompt:** "sunlight, natural, traditional, daytime, lowres, simple"
- **Tags:** cyberpunk, zen, garden, futuristic, neon
- **Style / Reference:** cyberpunk, photorealistic 3D render, octane render
- **Composition:** wide shot, low angle, symmetrical balance
- **Color palette:** obsidian black, neon pink, glowing cyan
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_cyber-zen-garden.jpg`
- **License / Attribution:** CC0

### Suggestion: Steampunk Astrolabe Room
- **Date:** 2026-05-18
- **Prompt:** "A grand, dimly lit study room filled with brass and copper steampunk machinery. In the center, a massive, intricate astrolabe glows with golden ethereal light, mapping out floating constellations. Warm, dusty light filters through a large gothic window, highlighting the dust motes in the air. Highly detailed, rich textures, volumetric lighting, shot with an 85mm lens for intimate focus."
- **Negative prompt:** "modern, clean, daylight, messy, futuristic"
- **Tags:** steampunk, interior, magic, brass, gears
- **Style / Reference:** steampunk concept art, highly detailed illustration
- **Composition:** eye-level, central focus, depth of field blurring the background
- **Color palette:** warm gold, copper, brass, deep shadows, amber
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260518_steampunk-astrolabe.jpg`
- **License / Attribution:** CC0

### Suggestion: Quantum Black Hole Accretion
- **Date:** 2026-05-18
- **Prompt:** "A close-up, dramatic view of a glowing, swirling accretion disk around a quantum black hole in deep space. Intense, fiery plasma streaks bend due to gravitational lensing. The mood is awe-inspiring and terrifying. High contrast, cinematic lighting, extreme detail on the glowing gas and dust, capturing the intense energy of the singularity."
- **Negative prompt:** "earth, planets, cartoon, flat, stars, low quality"
- **Tags:** space, sci-fi, cosmic, blackhole, quantum
- **Style / Reference:** realistic astrophysics visualization, cinematic sci-fi
- **Composition:** close-up, dynamic swirl, off-center singularity
- **Color palette:** intense orange, bright yellow, deep violet, pure black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260518_quantum-blackhole.jpg`
- **License / Attribution:** CC0

### Suggestion: Crystal Cavern of Echoes
- **Date:** 2026-05-18
- **Prompt:** "An immense underground cavern entirely lined with gigantic, perfectly geometric quartz crystals. A subterranean river of glowing liquid silver flows through the center. The mood is serene and ancient. Soft, ethereal light reflects endlessly through the crystal facets. Wide angle lens, deep depth of field capturing the vast scale of the cavern, sharp focus on the reflections."
- **Negative prompt:** "surface, sky, people, dirt, murky, noisy"
- **Tags:** crystal, cave, subterranean, fantasy, serene
- **Style / Reference:** epic fantasy landscape, hyper-detailed 3D environment
- **Composition:** wide angle, deep depth of field, leading lines of the river
- **Color palette:** silver, clear white, pale amethyst, deep subterranean blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_crystal-cavern.jpg`
- **License / Attribution:** CC0


### Suggestion: Fractal Geode Core
- **Date:** 2026-11-26
- **Prompt:** "A hyper-detailed macro photograph of a shattered geode revealing an impossibly complex, fractal-patterned core made of glowing, iridescent quartz and deep purple amethyst. The core structure exhibits infinite recursive self-similarity, glowing faintly from within. The lighting is focused and dramatic, highlighting the sharp edges of the fractured outer stone shell while the inner fractal maze remains softly illuminated. The mood is ancient, magical, and mathematically perfect. Captured with a 100mm macro lens, ultra-sharp focus on the innermost crystalline structures."
- **Negative prompt:** "smooth, dull, low resolution, flat lighting, organic, blurry"
- **Tags:** macro, fractal, crystal, glowing, magical
- **Style / Reference:** photorealistic macro photography, fractal art
- **Composition:** close-up, sharp center focus, detailed foreground
- **Color palette:** deep purple amethyst, glowing cyan, iridescent pastels, dark grey stone
- **Aspect ratio:** 1:1
- **Reference images:** none
- **License / Attribution:** CC0

### Suggestion: Biopunk Bioluminescent Swamp
- **Date:** 2026-11-26
- **Prompt:** "A dense, murky swamp scene heavily fused with overgrown biopunk elements. Massive, dripping mangrove roots are intertwined with pulsating, semi-translucent tubes carrying a glowing neon green fluid. Giant bioluminescent mushrooms and carnivorous flora emit a sickly magenta light. The lighting is completely dependent on the bioluminescent glow cutting through a thick, eerie fog. The mood is toxic, untamed, and alien. Captured with a wide-angle 24mm lens to emphasize the sprawling, chaotic ecosystem."
- **Negative prompt:** "daylight, clean, modern technology, bright sun, peaceful, realistic nature"
- **Tags:** biopunk, swamp, bioluminescent, alien, toxic
- **Style / Reference:** biopunk concept art, dark sci-fi environment
- **Composition:** wide angle, deep perspective, dense overlapping elements
- **Color palette:** toxic neon green, vibrant magenta, murky brown, deep shadow black
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0

### Suggestion: Steampunk Clockwork Hummingbird
- **Date:** 2026-11-26
- **Prompt:** "An incredibly intricate, macro shot of a mechanical hummingbird hovering mid-air near a wilted brass flower. The mechanical subject is constructed of polished copper wire, tiny ticking watch gears, and delicate stained-glass wings catching the light. The lighting is warm, directional studio lighting, creating sharp specular highlights on the brass edges and deep shadows between the gears. The mood is intricate, wondrous, and antique. Captured with a 100mm macro lens and a fast shutter speed to freeze the rapidly beating stained-glass wings."
- **Negative prompt:** "organic, flesh, real bird, feathers, daylight, blurry"
- **Tags:** macro, steampunk, mechanical, bird, brass
- **Style / Reference:** photorealistic macro photography, steampunk aesthetic
- **Composition:** extreme close-up, dynamic hovering pose, shallow depth of field
- **Color palette:** warm brass, polished copper, deep amber, vibrant stained-glass colors
- **Aspect ratio:** 4:5
- **Reference images:** none
- **License / Attribution:** CC0

### Suggestion: Aerogel Cyberpunk High-Rise
- **Date:** 2026-11-26
- **Prompt:** "A towering cyberpunk high-rise building constructed entirely from massive, glowing blocks of weightless, translucent blue aerogel. The building is enveloped in thick, smoggy rain and surrounded by flying neon-lit vehicles. The lighting is a striking mix of the soft, internal glowing refractions of the aerogel and the harsh, bright neon pink and cyan signs attached to its exterior. The mood is dystopian yet highly advanced and ethereal. Captured from a low angle on the wet street, looking up at the colossal structure piercing the dark, stormy sky."
- **Negative prompt:** "concrete, brick, daylight, clear sky, sunny, natural"
- **Tags:** cyberpunk, architecture, aerogel, neon, dystopian
- **Style / Reference:** cinematic sci-fi visualization, high-contrast city photography
- **Composition:** low angle looking up, towering scale, atmospheric depth
- **Color palette:** ghostly aerogel blue, neon magenta, electric cyan, rainy greys
- **Aspect ratio:** 9:16
- **Reference images:** none
- **License / Attribution:** CC0

### Suggestion: Italian Futurism Asteroid Impact
- **Date:** 2026-11-26
- **Prompt:** "A cataclysmic asteroid impact on a barren planet depicted in the harsh, fragmented style of Italian Futurism. The destructive event is deconstructed into aggressive, jagged diagonal lines and overlapping geometric planes that capture the kinetic energy and overwhelming speed of the collision. The lighting is intense and directional, casting stark, jagged shadows that enhance the splintered geometry of the composition. The mood is energetic, destructive, and modern. Captured with a dynamic, tilted perspective to emphasize raw motion and violent impact."
- **Negative prompt:** "realistic space, soft curves, calm, photography, peaceful, organic, smooth"
- **Tags:** abstract, art, italian futurism, space, asteroid, dynamic
- **Style / Reference:** Italian Futurism art movement, Giacomo Balla inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** blazing orange, steel greys, harsh stark white, chaotic black
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0

### Suggestion: Bioluminescent Subterranean Lake
- **Date:** 2026-11-27
- **Prompt:** "A vast, utterly still subterranean lake hidden deep within an ancient limestone cavern. The water acts as a perfect mirror, reflecting thousands of glowing blue and green bioluminescent glowworms hanging from the ceiling like a starry night sky. The lighting is low-key, entirely dependent on the cold, ethereal glow of the worms, creating a serene, magical, and timeless mood. Captured with a wide-angle 14mm lens on a tripod, utilizing a long exposure to capture the faint light and perfectly smooth water surface."
- **Negative prompt:** "daylight, sun, bright, ripples, people, modern, messy, blurry"
- **Tags:** nature, underground, bioluminescent, serene, lake
- **Style / Reference:** long-exposure nature photography, National Geographic style
- **Composition:** perfectly symmetrical horizontal reflection, wide expansive view
- **Color palette:** glowing cyan, soft neon green, deep cavernous black, pale limestone grey
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests the generation of large-scale horizontal reflections (water mirror) under extremely low-light, bioluminescent conditions.

### Suggestion: Steampunk Clockwork Beetle Macro
- **Date:** 2026-11-27
- **Prompt:** "An incredibly detailed, extreme macro photograph of a mechanical rhinoceros beetle constructed from polished brass, copper wires, and tiny ticking watch gears. The mechanical subject rests on a piece of dark, aged parchment. The lighting is warm, directional studio lighting that grazes the metallic surface, creating sharp specular highlights on the brass edges and deep, dark shadows between the gears. The mood is intricate, menacing, and antique. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the glowing amber glass eye of the beetle."
- **Negative prompt:** "organic, flesh, real insect, modern metal, bright daylight, soft lighting"
- **Tags:** macro, steampunk, mechanical, insect, brass
- **Style / Reference:** photorealistic macro product photography, steampunk aesthetic
- **Composition:** extreme close-up, diagonal leading line, shallow depth of field
- **Color palette:** warm brass, polished copper, deep mahogany brown, glowing amber
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Ideal for pushing the model's detailing capabilities on micro-mechanical parts and bokeh effects.

### Suggestion: Art Nouveau Elven Archway
- **Date:** 2026-11-27
- **Prompt:** "A majestic, intricate archway deep in an ancient forest, designed with the sweeping, elegant curves and whiplash lines of the Art Nouveau style. The archway is carved from pale, pearlescent stone and overgrown with glowing, silver-leafed vines. The lighting is soft, magical twilight filtering through the dense canopy, catching the pearlescent surface of the stone and casting a gentle, ethereal glow. The mood is elegant, ancient, and enchanting. Captured with a 35mm lens, balancing the intricate architectural details with the surrounding magical forest."
- **Negative prompt:** "straight lines, modern, harsh lighting, daylight, messy, chaotic, sci-fi"
- **Tags:** fantasy, architecture, art nouveau, forest, magical
- **Style / Reference:** high fantasy concept art, Alphonse Mucha inspired architecture
- **Composition:** centered archway, leading lines, balanced asymmetry
- **Color palette:** pearlescent white, glowing silver, deep forest greens, twilight purple
- **Aspect ratio:** 4:5
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests the AI's ability to naturally form specific architectural styles (Art Nouveau curves) out of stone and magical vegetation.

### Suggestion: Cyberpunk Neon Hover-Taxi
- **Date:** 2026-11-27
- **Prompt:** "A sleek, battered hover-taxi speeding through the rain-slicked, neon-lit canyons of a towering cyberpunk megacity. The yellow taxi is heavily modified with glowing cyan repulsor engines and holographic advertisements. The lighting is a chaotic mix of harsh, vibrant neon signs reflecting off the wet metallic hull and the dark, smoggy atmosphere of the lower city levels. The mood is gritty, fast-paced, and cinematic. Captured with a dynamic, panning motion blur to convey extreme speed while keeping the taxi in sharp focus."
- **Negative prompt:** "daylight, clean, modern, slow, bright sky, natural"
- **Tags:** cyberpunk, vehicle, city, neon, rain, dynamic
- **Style / Reference:** cinematic sci-fi photography, Blade Runner aesthetic
- **Composition:** dynamic angled profile, tight framing, panning blur
- **Color palette:** classic taxi yellow, neon magenta, electric cyan, dark rain-slicked greys
- **Aspect ratio:** 21:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests motion blur panning effects combined with high-contrast neon reflections on wet metallic surfaces.

### Suggestion: Crystal Chandelier in a Ruined Cathedral
- **Date:** 2026-11-27
- **Prompt:** "A massive, pristine crystal chandelier hanging miraculously intact from the shattered ceiling of a ruined, overgrown Gothic cathedral. The grand subject catches a single, dramatic shaft of midday sunlight piercing through the collapsed roof, sending thousands of brilliant, refractive rainbows dancing across the moss-covered stone walls. The lighting is high-contrast chiaroscuro, emphasizing the dazzling brilliance of the crystal against the dark, moody ruins. The mood is melancholic, beautiful, and striking. Captured with a wide 24mm lens to emphasize the grand scale and the juxtaposition of decay and pristine beauty."
- **Negative prompt:** "clean, modern, whole, dark, artificial lights, simple, flat"
- **Tags:** ruins, architecture, gothic, crystal, contrast
- **Style / Reference:** romantic ruins photography, photorealistic 3D render
- **Composition:** low angle looking up, dramatic lighting, sharp contrast
- **Color palette:** dazzling white crystal rainbows, dark mossy greens, cold grey stone, warm sunlight
- **Aspect ratio:** 4:5
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Evaluates complex multi-faceted crystal refractions and dramatic god-ray lighting in a highly textured environment.

### Suggestion: Macro Frost on Cybernetic Eye
- **Date:** 2026-05-15
- **Prompt:** "A hyper-detailed macro photograph of delicate, fractal frost crystals rapidly forming across the curved glass lens of a complex cybernetic eye. The subject is highly textured, showing microscopic scratches on the metallic iris beneath the glass. The lighting is harsh, cold, and directional, simulating a harsh winter dawn, casting sharp micro-shadows from the ice crystals. The mood is chilling, clinical, and precise. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the leading edge of the frost."
- **Negative prompt:** "blurry, low resolution, organic eye, warm colors, cartoon"
- **Tags:** macro, cyberpunk, frost, mechanical, detailed
- **Style / Reference:** photorealistic macro photography, hyper-detailed
- **Composition:** extreme close-up, asymmetrical
- **Color palette:** icy blues, sterile silver, harsh white highlights
- **Aspect ratio:** 1:1
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Excellent for testing micro-details, frost generation, and glass refraction.

### Suggestion: Brutalist Void Temple
- **Date:** 2026-05-15
- **Prompt:** "A colossal, brutalist concrete temple suspended in an infinite, thick, and swirling grey fog. The architecture features harsh, geometric angles and massive inverted pyramids. At the center of the structure, a massive, glowing red portal emits a sinister, pulsing light that cuts through the mist. The lighting is oppressive and heavy, relying on ambient fog scattering and the harsh red directional light. The mood is ominous, monumental, and isolating. Captured with a 14mm ultra-wide lens to exaggerate the imposing scale."
- **Negative prompt:** "bright, cheerful, nature, organic, ornate, detailed textures"
- **Tags:** brutalism, architecture, sci-fi, ominous, fog
- **Style / Reference:** architectural concept art, dystopian, massive scale
- **Composition:** low angle, symmetrical, imposing
- **Color palette:** concrete greys, deep blacks, piercing crimson red
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests volumetric fog density and dramatic single-point colored lighting against flat surfaces.

### Suggestion: Bioluminescent Subterranean Canyon
- **Date:** 2026-05-15
- **Prompt:** "A sweeping, majestic vista of an immense subterranean canyon completely devoid of sunlight. Instead, the cavern is illuminated by a rushing river of glowing, neon-blue liquid plasma and colossal, tree-like fungal structures emitting a soft cyan light. Giant, translucent, bioluminescent jellyfish float gracefully through the dense, humid air. The lighting is purely emissive and magical, scattering through the atmospheric haze. The mood is awe-inspiring, alien, and tranquil. Captured with a sweeping panoramic view, deep focus."
- **Negative prompt:** "sunlight, sky, surface, mundane, dry, sterile"
- **Tags:** fantasy, landscape, glowing, alien, underground
- **Style / Reference:** epic fantasy landscape, cinematic lighting
- **Composition:** panoramic, sweeping curve of the river drawing the eye
- **Color palette:** neon blues, cyan, deep cavernous purples, glowing green highlights
- **Aspect ratio:** 21:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating complex multi-source emissive lighting and atmospheric perspective.

### Suggestion: Alchemist's Transmutation Desk
- **Date:** 2026-05-15
- **Prompt:** "An incredibly cluttered and complex still-life of an ancient alchemist's wooden desk. The scene is filled with intricate brass astrolabes, bubbling alembics containing swirling iridescent liquids, and ancient leather-bound tomes. The primary light source is a localized, warm, flickering candlelight, augmented by the eerie, multicolored luminescence of the boiling potions. The mood is studious, mysterious, and chaotic. Captured with a 50mm prime lens, medium depth of field, focusing on the central bubbling flask."
- **Negative prompt:** "modern, clean, empty, sterile, fluorescent lighting"
- **Tags:** still-life, steampunk, alchemy, cluttered, magical
- **Style / Reference:** classical chiaroscuro still-life, hyper-detailed props
- **Composition:** cluttered, organic arrangement, rule of thirds
- **Color palette:** warm amber, polished brass, glowing iridescent greens and purples
- **Aspect ratio:** 4:3
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Highly effective for testing material properties like polished metal, aged paper, and liquid caustics.

### Suggestion: Cosmic Entity Portrait
- **Date:** 2026-05-15
- **Prompt:** "A mesmerizing, surreal portrait of a sentient celestial entity. The subject's face and form are not solid, but entirely composed of swirling nebula gas, sparkling stardust, and microscopic galaxies. The lighting is internal and cosmic, with a brilliant, blinding white core at the center of their chest illuminating the surrounding gaseous form. The background is the deep, infinite void of space. The mood is transcendent, powerful, and ethereal. Captured as a standard bust portrait, sharp focus on the densest clusters of stars forming the eyes."
- **Negative prompt:** "human skin, flesh, clothes, mundane, earthly, flat"
- **Tags:** portrait, cosmic, surreal, entity, glowing
- **Style / Reference:** surreal digital art, astrophotography integration
- **Composition:** classic bust portrait, centered
- **Color palette:** deep void black, vibrant magenta nebula, blinding stellar white
- **Aspect ratio:** 4:5
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Challenges the generation of cohesive forms from chaotic, particle-based volumetric materials.


### Suggestion: Holographic Bonsai Tree
- **Date:** 2026-11-28
- **Prompt:** "An ultra-detailed macro shot of a delicate bonsai tree constructed entirely from glowing holographic hard-light projections, resting on a sleek obsidian pedestal. The tree emits a soft, pulsing cyan and magenta light that illuminates the dark, minimalist cyber-dojo environment. The lighting is completely diegetic, relying on the vibrant glow of the holographic leaves against the pitch-black obsidian. The mood is serene, futuristic, and highly advanced. Captured with a 100mm macro lens, utilizing a shallow depth of field to create a soft, glowing neon bokeh."
- **Negative prompt:** "organic, wood, dirt, daylight, bright background, lowres, blurry, messy"
- **Tags:** macro, cyberpunk, holographic, bonsai, futuristic
- **Style / Reference:** photorealistic macro photography, high-detail sci-fi rendering
- **Composition:** centered subject, extreme close-up, shallow depth of field
- **Color palette:** neon cyan, vibrant magenta, polished obsidian black, soft white glow
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261128_holographic-bonsai.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing soft holographic emission and neon bokeh effects.

### Suggestion: Clockwork Nebula Leviathan
- **Date:** 2026-11-28
- **Prompt:** "A majestic, colossal space leviathan resembling a blue whale, swimming through a vibrant, swirling purple and gold nebula. The celestial creature is composed entirely of intricate brass clockwork, glowing astrolabes, and highly polished copper gears. The lighting is intensely cinematic, with harsh, blinding light from a nearby young star reflecting off the polished metallic surfaces, contrasting with the soft, ethereal glow of the nebula. The mood is wondrous, epic, and highly imaginative. Captured with a wide-angle 24mm cinematic lens to emphasize the massive, awe-inspiring scale of the mechanical beast."
- **Negative prompt:** "organic flesh, Earth ocean, water, dark space, simple, low quality, flat lighting"
- **Tags:** sci-fi, steampunk, space, leviathan, epic
- **Style / Reference:** cinematic sci-fi concept art, steampunk aesthetic, JWST style
- **Composition:** wide perspective, dynamic movement, sweeping curves
- **Color palette:** polished brass, glowing gold, vibrant nebula purple, blinding stellar white
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261128_clockwork-nebula-leviathan.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating complex metallic hard-surface modeling amidst soft, volumetric nebula clouds.

### Suggestion: Cyber-Renaissance Floating Market
- **Date:** 2026-11-28
- **Prompt:** "A bustling, vibrant floating marketplace set in a Cyber-Renaissance canal city, reminiscent of a futuristic Venice. Elaborate gondolas powered by glowing blue repulsor engines navigate the waterways, surrounded by grand marble architecture adorned with intricate neon-lit frescoes. The lighting is a warm, golden-hour sunset reflecting off the rippling water, beautifully blended with the cool, electric cyan and pink glow of the holographic storefronts. The mood is energetic, historically wealthy, and technologically advanced. Captured from a high vantage point overlooking the canal, showcasing the dense, layered architecture and busy waterways."
- **Negative prompt:** "dystopian, rainy, dark, gritty, simple, modern glass skyscrapers, empty"
- **Tags:** cyberpunk, renaissance, city, floating market, vibrant
- **Style / Reference:** opulent architectural visualization, retro-futuristic city design
- **Composition:** high angle, deep perspective down the canal, dense overlapping elements
- **Color palette:** warm sunset gold, pristine white marble, neon cyan, electric pink, deep canal blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261128_cyber-renaissance-market.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of grand historical architecture (Renaissance marble) with vibrant cyberpunk neon and water reflections.

### Suggestion: Bioluminescent Ice Cave
- **Date:** 2026-11-28
- **Prompt:** "A breathtaking, wide-angle interior shot of a massive, frozen glacial cave. Instead of being dark, the cavern is illuminated by thousands of bioluminescent, deep-sea-like flora frozen within the walls of clear blue ice. The subjects emit a soft, pulsing emerald green and sapphire blue light. The lighting is entirely subterranean and emissive, causing the polished ice surfaces to refract and reflect the magical glow endlessly down the curving tunnels. The mood is freezing, ancient, and deeply mysterious. Captured with a 14mm ultra-wide lens, deep focus to capture the endless frozen reflections."
- **Negative prompt:** "daylight, sun, warm colors, fire, people, muddy, messy rock"
- **Tags:** landscape, fantasy, ice, bioluminescent, cave
- **Style / Reference:** fantasy environment photography, hyper-detailed nature
- **Composition:** sweeping tunnel curve, deep perspective, wide angle
- **Color palette:** freezing glacial blue, glowing emerald green, brilliant sapphire, stark white ice highlights
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261128_bioluminescent-ice-cave.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing multi-bounce refractions through clear ice and internal, glowing light sources.

### Suggestion: Art Deco Quantum Locomotive
- **Date:** 2026-11-28
- **Prompt:** "A sleek, hyper-advanced quantum locomotive speeding along an elevated magnetic track through a snowy mountain pass, designed in a lavish, opulent Art Deco style. The train features sweeping aerodynamic curves, polished chrome plating, and intricate gold geometric inlays. The lighting is a crisp, bright winter morning sun casting sharp shadows and brilliant specular glints on the metallic hull, while the repulsor engines leave a trail of glowing cyan plasma. The mood is luxurious, powerful, and wildly optimistic. Captured with a dynamic panning motion blur to convey immense speed while keeping the pristine locomotive in sharp focus."
- **Negative prompt:** "rusty, old, steam train, dark, dystopian, slow, blurry, messy, gritty"
- **Tags:** sci-fi, vehicle, art deco, train, winter
- **Style / Reference:** retro-futuristic vehicle design, high-end 3D rendering
- **Composition:** dynamic angled profile, panning motion blur, sharp subject focus
- **Color palette:** polished chrome silver, brilliant gold, glowing cyan plasma, blinding white snow
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261128_art-deco-locomotive.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating highly reflective, curved metallic surfaces under intense daylight and panning motion blur.

### Suggestion: Cyberpunk Neon Fish Market
- **Date:** 2026-11-29
- **Prompt:** "A vibrant, eye-level shot of a bustling cyberpunk fish market at night. The stall is overflowing with exotic, bioluminescent seafood reflecting the harsh, flickering neon signs in vibrant pink and cyan above. Steam billows from boiling pots and the wet, metallic surfaces gleam with reflections. The mood is gritty, energetic, and atmospheric. Shot on a 35mm lens, high contrast, capturing the chaotic urban environment."
- **Negative prompt:** "daytime, clean, pristine, cartoon, low-res, empty, simple"
- **Tags:** cyberpunk, urban, photorealistic, gritty
- **Style / Reference:** cyberpunk aesthetic, cinematic lighting, photorealistic
- **Composition:** eye-level, crowded street, naturalistic framing
- **Color palette:** neon magenta, electric cyan, deep shadows, silver reflections
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261129_cyberpunk-fish-market.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing reflections on wet surfaces, glowing seafood, and dense urban clutter.

### Suggestion: Steampunk Greenhouse Laboratory
- **Date:** 2026-11-29
- **Prompt:** "An incredibly detailed, wide-angle interior of a steampunk greenhouse functioning as a mad botanist's laboratory. Colossal glass domes framed with wrought iron let in a hazy, golden-hour light that cuts through the thick mist. Exotic, alien plants with glowing veins are intertwined with complex brass pipes, ticking gauges, and bubbling alembics. The mood is wondrous, intellectual, and slightly chaotic. Captured with a 24mm wide-angle lens, emphasizing the sprawling scale of the lush greenery and mechanical apparatuses."
- **Negative prompt:** "modern, clean, daylight, simple, dark, empty, low detail"
- **Tags:** steampunk, interior, 3D, whimsical
- **Style / Reference:** steampunk concept art, highly detailed illustration
- **Composition:** wide expansive view, dense overlapping elements, deep depth of field
- **Color palette:** warm brass, emerald green, golden sunlight, glowing amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261129_steampunk-greenhouse-lab.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing atmospheric mist, volumetric lighting, and intricate brass and glass materials.

### Suggestion: Ethereal Glacial Crystal Palace
- **Date:** 2026-11-29
- **Prompt:** "A majestic, wide landscape of a colossal palace carved entirely out of semi-translucent, glowing glacial ice and iridescent quartz crystals. The structure is perched atop a snowy mountain peak under a brilliant, star-filled night sky featuring a vibrant aurora borealis. The lighting is ethereal, with the soft green and purple aurora reflecting perfectly off the faceted crystal walls. The mood is serene, magical, and freezing. Captured with an ultra-wide 14mm lens to emphasize the majestic scale against the cosmic sky."
- **Negative prompt:** "sunlight, daylight, warm colors, people, muddy, messy rock, modern"
- **Tags:** fantasy, architecture, 3D, ethereal
- **Style / Reference:** epic fantasy landscape, hyper-detailed 3D environment
- **Composition:** symmetrical, grand scale, low angle looking up
- **Color palette:** freezing glacial blue, glowing aurora green, pale quartz white, deep night sky
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261129_glacial-crystal-palace.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for evaluating ice refraction, aurora lighting, and grand, glowing architectural forms.

### Suggestion: Macro Clockwork Tarantula
- **Date:** 2026-11-29
- **Prompt:** "A hyper-detailed, extreme macro photograph of a terrifying yet beautiful mechanical tarantula. The intricate subject is constructed from polished copper wire, brushed steel plates, and tiny ticking watch gears. It rests on a piece of dark, aged leather. The lighting is warm, directional studio lighting, creating sharp specular highlights on the metallic edges and deep, dark shadows between the gears. The mood is intricate, menacing, and antique. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on its glowing red ruby eyes."
- **Negative prompt:** "organic, flesh, real spider, bright daylight, soft lighting, simple"
- **Tags:** steampunk, macro, photorealistic, dark
- **Style / Reference:** photorealistic macro product photography, steampunk aesthetic
- **Composition:** extreme close-up, asymmetrical, shallow depth of field
- **Color palette:** warm copper, brushed steel, deep brown leather, glowing ruby red
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261129_clockwork-tarantula.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for pushing the model's detailing capabilities on micro-mechanical parts and dramatic lighting.

### Suggestion: Solarpunk Floating Archipelago
- **Date:** 2026-11-29
- **Prompt:** "A breathtaking, sweeping aerial view of a vibrant solarpunk floating archipelago suspended high above a pristine, deep blue ocean. The islands are connected by elegant, curved bridges of gleaming white composite and feature lush vertical gardens and wind turbines. The lighting features brilliant, midday sunlight that casts sharp, clean shadows across the hanging vines and cascading waterfalls. The mood is utopian, harmonious, and uplifting. Captured with an aerial wide-angle perspective to showcase the vast scale and intricate eco-architecture."
- **Negative prompt:** "dystopian, dark, night, pollution, gritty, lowres, blurry, smog"
- **Tags:** solarpunk, architecture, 3D, bright
- **Style / Reference:** utopian architectural visualization, photorealistic 3D render
- **Composition:** aerial perspective, wide expansive view, dynamic curves
- **Color palette:** brilliant white, lush forest greens, bright sky blue, deep ocean blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261129_solarpunk-archipelago.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests large-scale floating architecture, clean lighting, and vibrant eco-futurism.
### Suggestion: Graphene Cyberpunk Koi Pond
- **Date:** 2026-11-29
- **Prompt:** "A high-angle, extreme close-up of a futuristic koi pond where the water is a thick, glowing neon cyan liquid and the koi fish are intricately constructed from matte, light-absorbing graphene and polished chrome. The metallic subjects swim gracefully, leaving rippling trails of glowing data in the fluid. The lighting is high-contrast, dominated by the vibrant cyan glow of the liquid reflecting off the chrome details, while the graphene scales remain in pitch black shadow. The mood is ethereal yet highly advanced. Captured with a 50mm lens, utilizing a fast shutter speed to freeze the splashing, glowing liquid droplets."
- **Negative prompt:** "organic fish, clear water, daylight, natural, muddy, messy, blurry, low resolution"
- **Tags:** cyberpunk, nature, macro, 3D, ethereal
- **Style / Reference:** photorealistic, cybernetic wildlife
- **Composition:** close-up, tight framing, dynamic movement
- **Color palette:** pitch black matte graphene, glowing neon cyan, polished chrome silver
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261129_graphene-koi.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing high contrast between light-emitting fluids and light-absorbing materials like graphene.

### Suggestion: Biopunk Bioluminescent Library
- **Date:** 2026-11-29
- **Prompt:** "A sprawling, multi-level library where the towering bookshelves are carved directly from massive, ancient fungal stalks, and the books are bound in pulsing, fleshy bio-membranes. The organic architecture is overgrown with glowing, bioluminescent cyan vines and giant neon magenta mushrooms acting as lamps. The lighting is completely diegetic, emitting softly from the bioluminescent flora and creating a mysterious, multi-colored glow that casts deep, eerie shadows in the vast interior. The mood is moody, alien, and slightly unsettling. Captured with a wide 14mm lens to emphasize the massive, cathedral-like scale of the fungal library."
- **Negative prompt:** "wood, paper books, daylight, modern, clean, people, bright sunlight, flat lighting"
- **Tags:** sci-fi, architecture, interior, surreal, moody
- **Style / Reference:** 3D, dark fantasy environmental visualization
- **Composition:** wide shot, deep perspective, towering vertical elements
- **Color palette:** glowing neon magenta, bioluminescent cyan, deep earthy browns, fleshy pinks
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261129_biopunk-library.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating complex organic architectural forms mixed with multi-colored volumetric emission.

### Suggestion: Art Deco Crystal Locomotive
- **Date:** 2026-11-29
- **Prompt:** "A majestic, heavily stylized steam locomotive soaring across a colossal viaduct, constructed entirely from perfectly faceted, translucent sapphire crystal with intricate gold Art Deco geometric inlays. The translucent subject is backlit by a massive, golden-hour sun setting low on the horizon, creating blindingly beautiful internal refractions and casting a warm glow through the blue crystal. The lighting is intensely cinematic and directional, with thick, white steam billowing from the engine catching the warm sunlight. The mood is bright, powerful, and wildly optimistic. Captured with a dynamic, low-angle perspective using a 35mm lens."
- **Negative prompt:** "iron, rust, dark, gritty, modern train, dystopia, blurry, flat lighting"
- **Tags:** sci-fi, architecture, 3D, surreal, bright
- **Style / Reference:** 3D, opulent retro-futuristic vehicle design
- **Composition:** wide shot, dynamic diagonal lines, towering scale
- **Color palette:** deep translucent sapphire, brilliant gold, blinding warm sunlight, crisp white steam
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261129_crystal-locomotive.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating internal crystal refraction combined with intricate metallic inlays and volumetric steam.

### Suggestion: Italian Futurism Asteroid Mining
- **Date:** 2026-11-29
- **Prompt:** "A chaotic, high-speed scene of industrial mining on a tumbling asteroid, depicted in the harsh, fragmented style of Italian Futurism. Massive, aggressive drilling machines are deconstructed into jagged diagonal lines and overlapping geometric planes that capture the kinetic energy and violent mechanical force. The lighting is a stark, harsh white spotlight cutting through the vacuum of space, casting jagged, hard-edged shadows that enhance the splintered geometry of the composition. The mood is cinematic, aggressive, and industrial. Captured with a dynamic, tilted perspective to emphasize raw, destructive motion."
- **Negative prompt:** "calm, realistic space, smooth curves, organic, gentle, photorealistic, quiet"
- **Tags:** sci-fi, landscape, abstract, cinematic, dark
- **Style / Reference:** abstract, Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** wide shot, dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black space, blinding white light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261129_futurism-asteroid.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to an industrial space-mining concept.

### Suggestion: Steampunk Damascus Steel Arachnid
- **Date:** 2026-11-29
- **Prompt:** "An incredibly detailed, extreme macro photograph of a mechanical tarantula constructed from beautiful, rippled Damascus steel and tiny brass clockwork gears. The heavy, metallic subject features intricate, flowing dark and light grey wave patterns across its segmented legs and abdomen, resting on a bed of crushed coal. The lighting is moody, directional studio lighting that grazes the metallic surface, creating sharp specular highlights on the forged ridges and deep, dark shadows beneath the mechanical legs. The mood is dark, menacing, and masterful. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the glowing, multi-faceted ruby eyes of the arachnid."
- **Negative prompt:** "organic, real spider, hair, daylight, soft lighting, bright background, blurry"
- **Tags:** steampunk, macro, photorealistic, cinematic, dark
- **Style / Reference:** photorealistic, steampunk aesthetic
- **Composition:** close-up, menacing low angle, shallow depth of field
- **Color palette:** dark metallic greys, warm brass accents, deep black coal, glowing ruby red
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261129_damascus-arachnid.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the complex, flowing texture generation of Damascus steel mapped onto intricate, macro-mechanical insect parts.

### Suggestion: Crystal Cave Sanctuary
- **Date:** 2026-05-15
- **Prompt:** "A vast underground cavern serving as a mystical sanctuary, illuminated by colossal, glowing amethysts and emeralds protruding from the ceiling and floor. An ancient stone altar sits in the center, bathed in a shaft of ethereal blue light from a crack far above. The atmosphere is solemn and magical, with motes of glowing dust floating in the air. Photographed with a wide 14mm lens, capturing the expansive scale and intricate crystalline details."
- **Negative prompt:** "daylight, modern, people, artificial lights, blurry, low resolution"
- **Tags:** fantasy, interior, nature, photorealistic, ethereal, magical
- **Style / Reference:** photorealistic, cinematic concept art
- **Composition:** wide shot, symmetrical, low angle looking up at the crystals
- **Color palette:** deep purples, emerald greens, ethereal blues
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_crystal-cave.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing volumetric lighting passing through translucent colored crystals and atmospheric dust scattering.

### Suggestion: Neon-lit Noir Detective Office
- **Date:** 2026-05-15
- **Prompt:** "The messy, cluttered office of a weary detective in a futuristic metropolis. Rain streaks the large glass window, blurring the vibrant neon signs of the cyberpunk city outside. Inside, a single tungsten desk lamp casts long, harsh shadows across piles of scattered documents, a classic typewriter, and a half-empty glass of amber liquid. The lighting is high-contrast, moody, and dramatic. Captured with a 35mm lens, focusing on the desk with the city serving as a bokeh background."
- **Negative prompt:** "bright, sunny, clean, minimalist, cartoon, 3D render"
- **Tags:** cyberpunk, noir, interior, still life, moody, cinematic
- **Style / Reference:** photorealistic, classic film noir meets cyberpunk
- **Composition:** medium shot, slightly off-center desk, rule of thirds
- **Color palette:** stark blacks, tungsten yellow, neon magenta, electric blue reflections
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_noir-office.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for checking reflections on wet glass, bokeh quality, and high-contrast shadow rendering.

### Suggestion: Bioluminescent Fungal Forest
- **Date:** 2026-05-15
- **Prompt:** "A macro, ground-level view deep within an alien forest, where towering mushrooms substitute for trees. The giant fungi emit a soft, pulsing bioluminescent glow in shades of cyan and magenta. The forest floor is covered in glowing moss and tiny, luminous spores drifting lazily. The scene is lit entirely by the organic glow of the flora, creating a whimsical and alien mood. Shot with a 100mm macro lens, featuring a very shallow depth of field to isolate a single, intricate mushroom cluster."
- **Negative prompt:** "sunlight, earth-like, daytime, clear sky, human structures, harsh shadows"
- **Tags:** sci-fi, macro, nature, surreal, whimsical, ethereal
- **Style / Reference:** photorealistic macro photography, 3D render, dreamlike
- **Composition:** extreme close-up, ground level, subject centered
- **Color palette:** glowing cyan, deep magenta, dark forest greens
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260515_fungal-forest.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating subsurface scattering on organic textures and shallow depth of field (bokeh) on glowing particles.

### Suggestion: Brass and Steam Clockwork Insect
- **Date:** 2026-05-15
- **Prompt:** "A highly intricate, mechanical praying mantis constructed entirely from polished brass, copper gears, and tiny glass vials of glowing green fluid. The insect rests on a weathered, leather-bound journal. Tiny plumes of steam escape from its joints. The lighting is warm and directional, emphasizing the reflective metallic surfaces and the fine engraving on its armor. The mood is curious and inventive. Photographed with a 50mm lens, sharp focus on the complex gear-work of the insect's head."
- **Negative prompt:** "biological, fleshy, real insect, modern technology, plastic, lowres"
- **Tags:** steampunk, macro, still life, photorealistic, whimsical
- **Style / Reference:** photorealistic, intricate 3D rendering, macro product photography
- **Composition:** close-up, looking slightly down, subject filling the frame
- **Color palette:** warm brass, polished copper, aged leather brown, glowing neon green
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260515_clockwork-insect.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for testing intricate metallic reflections, micro-shadows within gear mechanisms, and sharp textural contrasts.

### Suggestion: Solarpunk Rooftop Garden Oasis
- **Date:** 2026-05-15
- **Prompt:** "A lush, thriving community garden located on the rooftop of a curved, futuristic skyscraper. People are tending to overflowing planters and terraced vegetable beds, surrounded by sleek solar panels and gentle wind turbines. The bright, midday sun bathes the scene in vibrant, natural light, highlighting the diverse, vivid greens of the foliage against the bright white architecture. The mood is optimistic, bustling, and harmonious. Captured with a wide 24mm lens to show the expansive garden and the eco-city skyline in the background."
- **Negative prompt:** "dystopian, dark, rainy, polluted, grim, abandoned"
- **Tags:** solarpunk, architecture, landscape, bright, optimistic
- **Style / Reference:** photorealistic architectural visualization, utopian
- **Composition:** wide shot, slight high angle, deep depth of field
- **Color palette:** vivid greens, bright white, clear sky blue, vibrant floral colors
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_solarpunk-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing bright global illumination, dense foliage rendering, and complex architectural environments in daylight.


### Suggestion: Bioluminescent Biolab Portrait
- **Date:** 2026-12-01
- **Prompt:** "A close-up portrait of a weary scientist inside a high-tech biolab overgrown with glowing cyan moss. The subject's face is illuminated by the harsh, cold light of a holographic interface and the soft, ethereal cyan glow of the mutated flora. The mood is moody, intense, and mysterious. Captured with an 85mm portrait lens, featuring a shallow depth of field to isolate the subject against the out-of-focus background equipment."
- **Negative prompt:** "daylight, sunny, cartoon, flat, simple, empty, wide angle"
- **Tags:** sci-fi, portrait, photorealistic, moody
- **Style / Reference:** photorealistic portrait photography, sci-fi concept art
- **Composition:** close-up, shallow depth of field, rule of thirds
- **Color palette:** glowing cyan, sterile white, deep shadow black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261201_biolab-portrait.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing high-contrast facial lighting and glowing organic textures.

### Suggestion: Steampunk Alchemy Laboratory
- **Date:** 2026-12-01
- **Prompt:** "A wide-angle interior shot of a cluttered steampunk alchemy laboratory. The room is filled with brass alembics, bubbling glass vials, and heavy iron gears built into the walls. The lighting is warm and directional, emanating from a roaring furnace and scattering through the thick, atmospheric steam hanging in the air. The mood is dark, mysterious, and historically inventive. Captured with a 24mm lens to emphasize the dense clutter and intricate architectural details of the lab."
- **Negative prompt:** "modern, bright, clean, sterile, daylight, simple, outdoor"
- **Tags:** steampunk, interior, 3D, dark
- **Style / Reference:** highly detailed 3D environment, steampunk aesthetic
- **Composition:** wide interior, deep perspective, dense overlapping elements
- **Color palette:** warm brass, rusty iron, glowing amber, dark soot black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261201_steampunk-alchemy.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of complex brass machinery and volumetric steam lighting.

### Suggestion: Floating Solarpunk Windmill
- **Date:** 2026-12-01
- **Prompt:** "A majestic, floating windmill structure designed in a vibrant solarpunk aesthetic, suspended high above a lush, green mountain valley. The architecture blends sleek white carbon fiber with natural bamboo and cascading vines. The lighting is bright, clear midday sunlight that casts sharp shadows and highlights the brilliant greens and whites. The mood is bright, optimistic, and peaceful. Captured with a drone-like aerial perspective to showcase the vast scale of the landscape below."
- **Negative prompt:** "dystopian, smog, pollution, night, gritty, dark, lowres"
- **Tags:** solarpunk, architecture, photorealistic, bright
- **Style / Reference:** utopian architectural visualization, bright and clean
- **Composition:** aerial perspective, dynamic angles, expansive background
- **Color palette:** pristine white, bamboo yellow, lush forest green, clear sky blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261201_solarpunk-windmill.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating clean, bright global illumination and futuristic eco-designs.

### Suggestion: Ethereal Crystal Spider Macro
- **Date:** 2026-12-01
- **Prompt:** "An ultra-detailed macro photograph of a delicate spider constructed entirely from translucent, pale blue quartz crystals. The crystalline subject is perched on a dark, wet fern leaf. The lighting is soft and ethereal, passing through the spider's translucent legs and creating intricate internal refractions. The mood is ethereal, delicate, and surreal. Captured with a 100mm macro lens, utilizing a razor-thin depth of field to isolate the spider against a smooth, dark background."
- **Negative prompt:** "organic, flesh, real spider, bright sunlight, wide angle, messy"
- **Tags:** fantasy, macro, surreal, ethereal
- **Style / Reference:** photorealistic macro photography, surreal material swap
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** translucent pale blue, dark wet green, deep black shadows
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261201_crystal-spider.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing complex subsurface scattering and crystalline refraction on macro subjects.

### Suggestion: Isometric Cyberpunk Noodles
- **Date:** 2026-12-01
- **Prompt:** "A vibrant, highly detailed isometric view of a tiny cyberpunk noodle stand tucked into a gritty urban corner. The scene is densely packed with glowing neon signs, steaming pots, and a weary robotic chef. The lighting is a chaotic mix of harsh neon pink and electric cyan contrasting with the dark, rainy shadows of the city. The mood is cinematic, energetic, and crowded. Captured with a strict orthographic isometric camera, ensuring perfectly parallel lines and flat perspective."
- **Negative prompt:** "perspective, vanishing point, daylight, clean, natural, wide landscape"
- **Tags:** cyberpunk, architecture, isometric, cinematic
- **Style / Reference:** isometric 3D illustration, highly detailed cyberpunk diorama
- **Composition:** isometric projection, centered diorama, dense clutter
- **Color palette:** neon magenta, electric cyan, rainy grey, warm noodle broth yellow
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261201_isometric-noodles.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the model's ability to strictly adhere to isometric perspective while rendering dense, glowing urban clutter.


### Suggestion: Cyberpunk Gothic Chandelier
- **Date:** 2024-11-30
- **Prompt:** "A massive, ornate gothic chandelier suspended in the center of a dark, abandoned cyberpunk warehouse. The chandelier is constructed from twisted black iron and glowing neon magenta tubing instead of candles. The subject is dripping with thick, dark oil. The lighting is extremely dramatic, with the harsh neon casting deep, jagged shadows against the wet concrete floor. The mood is dark, cinematic, and oppressive. Captured with a 35mm lens, looking up at a sharp angle."
- **Negative prompt:** "bright, cheerful, clean, daylight, soft, blurry, low resolution"
- **Tags:** cyberpunk, interior, 3D, dark, cinematic
- **Style / Reference:** 3D render, cyberpunk concept art, photorealistic
- **Composition:** low angle looking up, dramatic perspective
- **Color palette:** neon magenta, pitch black, oily metallic sheen
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20241130_cyberpunk-chandelier.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing emissive neon materials combined with dripping, wet metallic textures.

### Suggestion: Surreal Obsidian Lighthouse
- **Date:** 2024-11-30
- **Prompt:** "A towering, monolithic lighthouse carved entirely from a single piece of flawlessly smooth, highly reflective black obsidian. It stands on a jagged cliff edge overlooking a turbulent, ink-black ocean. Instead of a standard light, a swirling, ethereal sphere of pale blue plasma hovers at the top. The lighting is low-key and moody, relying on the soft, pulsing glow of the plasma reflecting off the wet obsidian. The mood is ethereal, moody, and mysterious. Captured with a wide-angle 14mm lens under a starless night sky."
- **Negative prompt:** "daylight, sun, bright, bustling, realistic lighthouse, brick, white"
- **Tags:** fantasy, landscape, surreal, moody, ethereal
- **Style / Reference:** surreal 3D environment, minimalist dark fantasy
- **Composition:** wide angle, rule of thirds, towering scale
- **Color palette:** pure black, polished obsidian, pale glowing blue, dark ocean grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20241130_obsidian-lighthouse.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests highly reflective dark surfaces (obsidian) and localized, soft emissive lighting.

### Suggestion: Solarpunk Terrarium Backpack
- **Date:** 2024-11-30
- **Prompt:** "An ultra-detailed, macro shot of a futuristic solarpunk backpack resting on a sun-drenched wooden table. The backpack features a clear, domed terrarium embedded in its center, housing a tiny, thriving ecosystem of glowing ferns and a miniature waterfall. The lighting is bright, natural midday sunlight filtering through a nearby window, casting crisp shadows and highlighting the condensation on the inside of the glass dome. The mood is bright, whimsical, and optimistic. Captured with a 50mm macro lens, utilizing a shallow depth of field to blur the workshop background."
- **Negative prompt:** "dark, cyberpunk, gritty, dirty, low resolution, messy, plastic"
- **Tags:** solarpunk, still life, macro, photorealistic, bright
- **Style / Reference:** photorealistic product photography, solarpunk aesthetic
- **Composition:** centered subject, macro close-up, shallow depth of field
- **Color palette:** vibrant forest greens, warm sunlight yellow, clear glass, natural wood brown
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20241130_solarpunk-backpack.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating complex glass refractions, condensation details, and vibrant organic elements.

### Suggestion: Isometric Retro Arcade
- **Date:** 2024-11-30
- **Prompt:** "A vibrant, highly detailed isometric view of a bustling 1980s retro arcade room. The scene is densely packed with glowing arcade cabinets, patterned neon carpets, and a shiny air hockey table. The lighting is a chaotic, colorful mix of harsh CRT monitor glows and overhead fluorescent lights, creating distinct, sharp shadows. The mood is retro, energetic, and bright. Captured with a strict orthographic isometric camera, ensuring perfectly parallel lines and a flat, diorama-like perspective."
- **Negative prompt:** "perspective, vanishing point, dark, moody, realistic lighting, outdoor, nature"
- **Tags:** retro, interior, isometric, 3D, bright
- **Style / Reference:** isometric 3D illustration, retro 80s aesthetic
- **Composition:** isometric projection, dense diorama, balanced framing
- **Color palette:** neon pink, electric cyan, vibrant yellow, dark patterned carpet
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20241130_isometric-arcade.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the model's ability to maintain strict isometric perspective and render multiple, distinct glowing screens.

### Suggestion: Painterly Celestial Nebula
- **Date:** 2024-11-30
- **Prompt:** "A breathtaking, abstract depiction of a sprawling celestial nebula, rendered in a thick, expressive painterly style reminiscent of impasto oil painting. The cosmic subject swirls with massive, textured brushstrokes of deep violet, glowing gold, and fiery magenta. The lighting is purely atmospheric and internal, with the brightest strokes of paint creating the illusion of newborn stars bursting through the gas clouds. The mood is ethereal, sweeping, and cinematic. Captured as a flat, full-canvas texture, emphasizing the physical dimension of the oil paint."
- **Negative prompt:** "photorealistic, sharp stars, 3D render, spaceships, planets, digital, smooth"
- **Tags:** sci-fi, landscape, painterly, abstract, ethereal
- **Style / Reference:** impasto oil painting, abstract expressionism, thick brushstrokes
- **Composition:** full frame, sweeping curved strokes, abstract layout
- **Color palette:** deep violet, fiery magenta, glowing gold, thick black shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20241130_painterly-nebula.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for pushing the model to generate thick, physical paint textures (impasto) rather than photorealistic space imagery.


### Suggestion: Cybernetic Zen Garden
- **Date:** 2026-05-15
- **Prompt:** "A serene Japanese zen garden where the raked sand is replaced by glowing blue fiber-optic cables and the rocks are smooth, dark obsidian monoliths etched with golden circuitry. A traditional wooden bridge arches over a stream of liquid silver. Soft, ethereal neon lighting from below, foggy atmosphere, highly detailed, photorealistic."
- **Negative prompt:** "people, messy, daylight, lowres, text, watermark"
- **Tags:** cyberpunk, landscape, photorealistic, ethereal
- **Style / Reference:** Cyberpunk aesthetics mixed with traditional Japanese landscaping, 3D render, Octane render
- **Composition:** Wide shot, rule of thirds, low angle
- **Color palette:** Glowing neon blue, dark obsidian, metallic silver, warm gold accents
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_cyber-zen-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing neon glow, metallic reflections, and volumetric fog.

### Suggestion: Steampunk Botanist's Airship
- **Date:** 2026-05-15
- **Prompt:** "The interior of a grand steampunk airship greenhouse, filled with exotic, bioluminescent alien plants in polished brass pots. Sunlight streams through massive glass arched windows, catching motes of dust in the air. Intricate copper pipes and pressure gauges line the walls. A large mahogany desk sits in the corner, covered in scientific sketches and glowing vials."
- **Negative prompt:** "modern, clean, minimal, dark, empty"
- **Tags:** steampunk, interior, photorealistic, bright
- **Style / Reference:** Victorian era illustration style mixed with photorealistic rendering
- **Composition:** Interior shot, deep perspective, slightly elevated angle
- **Color palette:** Warm brass, emerald green, glowing cyan, rich mahogany
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_steampunk-airship.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing god-rays, glass refractions, and intricate metallic textures.

### Suggestion: Neon Geisha in a Rainy Alley
- **Date:** 2026-05-15
- **Prompt:** "A close-up portrait of a cybernetic geisha standing in a dark, narrow, rain-slicked alleyway. Her porcelain face has subtle glowing pink panel lines. She holds a transparent umbrella glowing with holographic koi fish. The background is a blur of neon signs reflecting in the puddles. Cinematic lighting, moody, 85mm lens, shallow depth of field."
- **Negative prompt:** "cartoon, anime, daylight, flat lighting, ugly, deformed"
- **Tags:** cyberpunk, portrait, photorealistic, cinematic
- **Style / Reference:** Cinematic photography, Blade Runner inspired, photorealistic portrait
- **Composition:** Close-up, eye-level, subject slightly off-center
- **Color palette:** Deep shadows, vibrant neon pink and cyan, stark contrasts
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260515_neon-geisha.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests wet surface reflections, skin textures, and depth-of-field effects.

### Suggestion: Abyssal Leviathan Skeleton
- **Date:** 2026-05-15
- **Prompt:** "A massive, ancient skeleton of an alien sea leviathan resting on the dark ocean floor. The bones are encrusted with glowing, bioluminescent turquoise corals and strange, translucent anemones. Schools of tiny, silver fish swim through the ribcage. The only light source is the eerie glow of the flora. Deep sea exploration vibe, hyper-detailed, murky water."
- **Negative prompt:** "bright, sunlight, shallow water, people, submarine"
- **Tags:** horror, landscape, 3D, moody
- **Style / Reference:** Deep-sea documentary style, moody concept art
- **Composition:** Wide shot, looking slightly up at the imposing structure
- **Color palette:** Pitch black, bioluminescent turquoise, pale bone, silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260515_abyssal-skeleton.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for underwater lighting tests, particle systems (fish), and volumetric scattering.

### Suggestion: Chrono-Glitch Cityscape
- **Date:** 2026-05-15
- **Prompt:** "A sprawling futuristic city where time is visibly fractured. Slices of the city are stuck in a sun-drenched golden hour, while adjacent slices are deep in a neon-lit, rainy night. The boundaries between these time zones are marked by harsh, chromatic aberration and digital glitch artifacts. Flying cars smear into light trails across the temporal divides. Highly chaotic, dynamic, maximalist."
- **Negative prompt:** "peaceful, simple, uniform, historical, lowres"
- **Tags:** sci-fi, architecture, abstract, cinematic
- **Style / Reference:** Glitch art, surrealism, digital maximalism
- **Composition:** Ultra-wide cityscape, dynamic diagonal lines
- **Color palette:** High contrast: golden hour oranges/yellows vs. midnight blues/magentas
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260515_chrono-glitch-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests spatial distortion shaders, chromatic aberration, and complex compositing.

### Suggestion: Neon Bioluminescent Cavern
- **Date:** 2026-05-20
- **Prompt:** "A majestic underground cavern filled with giant, glowing crystal formations and bioluminescent flora. The cave walls are illuminated by a soft, ethereal cyan and magenta light reflecting off tranquil subterranean pools. The mood is serene, mystical, and untouched by human presence. Captured with a wide-angle lens to emphasize the colossal scale."
- **Negative prompt:** "sunlight, daylight, modern, people, messy, blurry, low resolution"
- **Tags:** fantasy, nature, landscape, ethereal, bright
- **Style / Reference:** photorealistic, fantasy concept art
- **Composition:** wide landscape, sweeping curves, deep depth of field
- **Color palette:** glowing cyan, vibrant magenta, deep cavernous black, soft silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_bioluminescent-cavern.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing multi-bounce refractions and internal, glowing light sources.

### Suggestion: Retro-Futuristic Hover-Car Diner
- **Date:** 2026-05-20
- **Prompt:** "A classic 1950s style diner reimagined in a bright, optimistic retro-futuristic solarpunk city. Sleek, polished chrome hover-cars are parked outside, reflecting the bright, midday sun. The diner features vibrant pastel colors, clean lines, and lush vertical gardens on its roof. The mood is nostalgic, cheerful, and bustling. Captured from eye-level on a sun-drenched street."
- **Negative prompt:** "dystopian, dark, rainy, polluted, grim, rusty, neon, cyberpunk"
- **Tags:** solarpunk, retro, architecture, bright, whimsical
- **Style / Reference:** 3D, photorealistic
- **Composition:** eye-level, balanced framing, clear subject
- **Color palette:** pastel mint green, bubblegum pink, polished chrome, bright sky blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_retro-hover-diner.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests clean lighting, pastel palettes, and highly reflective chrome surfaces under bright sun.

### Suggestion: Ethereal Steampunk Aviary
- **Date:** 2026-05-20
- **Prompt:** "An incredibly detailed, wide-angle interior of a grand steampunk aviary. Colossal glass domes framed with intricate wrought iron and polished brass let in soft, golden-hour sunlight. Exotic, mechanical birds made of clockwork and stained glass fly among massive, overgrown indoor trees. The mood is wondrous, intellectual, and slightly chaotic. Captured with a 24mm wide-angle lens, emphasizing the sprawling scale of the lush greenery and mechanical apparatuses."
- **Negative prompt:** "modern, clean, dark, empty, low detail, simple"
- **Tags:** steampunk, interior, architecture, whimsical
- **Style / Reference:** 3D, steampunk concept art
- **Composition:** wide expansive view, dense overlapping elements, deep depth of field
- **Color palette:** warm brass, emerald green, golden sunlight, rich mahogany
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_steampunk-aviary.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing atmospheric mist, volumetric lighting, and intricate brass and glass materials.

### Suggestion: Surreal Desert Clock
- **Date:** 2026-05-20
- **Prompt:** "A colossal, surreal clock mechanism partially buried in the endless, shifting sands of an arid desert. The giant gears are forged from rusted iron and polished gold. The lighting is harsh, unattenuated midday desert sunlight casting deep, sharp black shadows that highlight the intricate texture of the sand ripples and the mechanical details. The mood is mysterious, timeless, and surreal. Captured with a wide-angle lens, deep focus."
- **Negative prompt:** "wet, dark, night, city, trees, soft lighting, modern"
- **Tags:** surreal, landscape, nature, moody
- **Style / Reference:** surreal, photorealistic
- **Composition:** wide shot, low angle, vast empty space, rule of thirds
- **Color palette:** warm desert ochre, rusted orange, polished gold, stark blue sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_surreal-desert-clock.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for generating granular sand textures and high-contrast desert lighting.

### Suggestion: Macro Frozen Nebula
- **Date:** 2026-05-20
- **Prompt:** "An ultra-macro, abstract visualization of a miniature nebula trapped within a perfect sphere of solid ice. The subject features swirling clouds of vibrant pink and cyan stardust, glittering with microscopic stars, perfectly frozen in clear ice. The lighting is cold and directional, highlighting the complex internal refractions and bubbles trapped within the sphere. The mood is awe-inspiring, serene, and magical. Captured with a 100mm macro lens, sharp focus on the internal cosmic details."
- **Negative prompt:** "blurry, low resolution, warm colors, messy, organic, simple"
- **Tags:** abstract, macro, ethereal, bright
- **Style / Reference:** abstract, photorealistic
- **Composition:** perfectly centered sphere, symmetrical, shallow depth of field
- **Color palette:** freezing icy blue, vibrant neon pink, glowing cyan, deep black background
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260520_frozen-nebula.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for evaluating internal refractions, volumetric particle clouds, and macro bokeh.



### Suggestion: Neon Samurai Cyber-Alley
- **Date:** 2026-05-25
- **Prompt:** "A photorealistic, moody portrait of a futuristic cyber-samurai standing in a rain-drenched neon alleyway. The subject wears intricately detailed, jet-black carbon-fiber samurai armor emitting glowing neon crimson energy lines. The lighting is cinematic and harsh, dominated by reflections of cyan and pink neon signs shimmering in the wet pavement puddles. The mood is tense, noir, and dangerous. Captured with a 50mm f/1.4 lens, shallow depth of field, sharp focus on the glowing katana handle."
- **Negative prompt:** "daylight, clean, bright, cartoon, 2D, blurry, missing details"
- **Tags:** cyberpunk, noir, portrait, moody, cinematic
- **Style / Reference:** photorealistic, cinematic concept art
- **Composition:** waist-up portrait, off-center subject, neon reflections in foreground
- **Color palette:** jet black, vibrant crimson, neon cyan, electric pink
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260525_neon-samurai.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing rain simulations, emissive armor materials, and highly reflective wet ground.

### Suggestion: Steampunk Clockwork Aviary
- **Date:** 2026-05-25
- **Prompt:** "An ultra-detailed interior shot of a massive, Victorian-era steampunk aviary built inside a giant greenhouse of curved brass and stained glass. The subject features hundreds of intricate clockwork mechanical birds with polished copper and gold gears, flying amid exotic iron-wrought mechanical trees. The lighting is warm golden hour sunlight filtering through the stained glass, casting colorful intricate shadows across the tiled marble floor. The mood is whimsical, magical, and complex. Captured with a wide 24mm lens to emphasize scale."
- **Negative prompt:** "modern, clean lines, organic, real birds, dark, minimalist"
- **Tags:** steampunk, interior, fantasy, architecture, whimsical
- **Style / Reference:** 3D render, Victorian architecture, photorealistic
- **Composition:** wide shot, symmetrical framing, low angle
- **Color palette:** warm brass, polished copper, golden yellow, emerald green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260525_steampunk-aviary.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests complex intersecting shadows, intricate metallic reflections, and volumetric light shafts.

### Suggestion: Eldritch Lunar Monolith
- **Date:** 2026-05-25
- **Prompt:** "A chilling, wide-angle landscape shot of a colossal, alien obsidian monolith erupting from the barren surface of a pale, cratered moon. The subject is covered in faintly glowing, pulsing green eldritch runes. The lighting is stark and ethereal, illuminated only by a massive, looming ringed gas giant in the star-filled sky. The mood is dark, cosmic horror, and isolating. Captured with a 14mm ultra-wide lens, deep depth of field to capture the sprawling desolate terrain."
- **Negative prompt:** "earth, blue sky, plants, sunlight, cheerful, human"
- **Tags:** sci-fi, horror, landscape, dark, moody
- **Style / Reference:** cinematic, cosmic horror concept art
- **Composition:** rule of thirds, monolith on the right, towering over landscape
- **Color palette:** desolate greys, pitch black, eerie neon green, pale blue starlight
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260525_lunar-monolith.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for stark high-contrast environments and evaluating eerie glowing materials.

### Suggestion: Solarpunk Floating Market
- **Date:** 2026-05-25
- **Prompt:** "A vibrant, bustling daytime scene of a solarpunk floating market on a serene, crystal-clear turquoise river. The subject features a series of interconnected, modular bamboo boats draped in solar panels and lush blooming hydroponic gardens, overflowing with colorful glowing fruits. The lighting is bright, cheerful, mid-day sunlight with soft dappled shadows from giant synthetic lily pads overhead. The mood is utopian, bustling, and bright. Captured with a standard 35mm lens, natural documentary style."
- **Negative prompt:** "dystopian, pollution, dark, gloomy, winter, concrete"
- **Tags:** solarpunk, bright, architecture, nature, cinematic
- **Style / Reference:** 3D render, photorealistic, optimistic sci-fi
- **Composition:** dynamic diagonal lines, bustling foreground, river winding into the background
- **Color palette:** bright turquoise, lush greens, vibrant orange and magenta accents, golden bamboo
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260525_solarpunk-market.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex organic materials, clear water refraction, and bright daylight global illumination.

### Suggestion: Isometric Micro-Laboratory
- **Date:** 2026-05-25
- **Prompt:** "A clean, highly detailed isometric view of a futuristic micro-laboratory floating against a solid pastel background. The subject is a cutaway diorama of a sterile sci-fi lab featuring sleek white robotic arms, glowing holographic blue computer terminals, and a central containment tube holding a swirling galaxy. The lighting is soft, even studio lighting with no harsh shadows, highlighting the glossy white plastic and emissive holograms. The mood is clinical, minimalist, and high-tech. Rendered in a strict isometric projection."
- **Negative prompt:** "perspective, realistic background, messy, dark, grunge"
- **Tags:** sci-fi, interior, isometric, minimalist, bright
- **Style / Reference:** 3D isometric, clean product render
- **Composition:** strict isometric perspective, centered, cutaway view
- **Color palette:** clinical white, holographic cyan, pastel pink background
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260525_isometric-lab.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for generating clean, stylized isometric assets and testing smooth glossy material rendering.



### Suggestion: Cybernetic Zen Garden
- **Date:** 2026-05-20
- **Prompt:** "A tranquil zen garden where the raked sand is made of glowing fiber optic cables and the rocks are polished obsidian spheres. A lone android monk meditates in the center. Illuminated by soft, cool moonlight and the neon blue glow of the cables. The mood is serene yet surreal. Captured with a 50mm lens for a natural perspective."
- **Negative prompt:** "cluttered, dirty, bright daylight, noisy, low resolution"
- **Tags:** cyberpunk, landscape, 3D, moody, ethereal
- **Style / Reference:** 3D render, minimalist
- **Composition:** wide shot, rule of thirds
- **Color palette:** cool blues, deep blacks, neon accents
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_cybernetic-zen-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for exploring contrasts between organic concepts and artificial materials.

### Suggestion: Steampunk Alchemist's Laboratory
- **Date:** 2026-05-20
- **Prompt:** "A cluttered steampunk alchemist's laboratory filled with brass astrolabes, bubbling glass vials of luminescent green liquid, and ancient leather-bound books. Sunlight streams through a dusty stained-glass window, creating volumetric light rays that illuminate floating dust motes. The atmosphere is mysterious and intellectual. Highly detailed, photorealistic."
- **Negative prompt:** "modern technology, clean, minimalistic, dull, flat lighting"
- **Tags:** steampunk, interior, photorealistic, cinematic
- **Style / Reference:** photorealistic, highly detailed
- **Composition:** medium shot, cluttered foreground interest
- **Color palette:** warm brass, amber, glowing greens
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_steampunk-alchemist-lab.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing volumetric lighting and glass refraction.

### Suggestion: Ethereal Floating Nebula Citadel
- **Date:** 2026-05-20
- **Prompt:** "A colossal, sprawling citadel carved from shimmering quartz, floating amidst a vibrant cosmic nebula. Cascading waterfalls of stardust fall from its edges into the void. The scene is lit by the radiant pink and purple glow of the surrounding gas clouds, casting soft, colorful shadows. The mood is epic and wondrous. Epic wide-angle landscape shot."
- **Negative prompt:** "earth, ground, mundane, realistic sky, blurry"
- **Tags:** sci-fi, fantasy, landscape, ethereal, bright
- **Style / Reference:** digital concept art, painterly
- **Composition:** wide shot, grand scale
- **Color palette:** vibrant pinks, purples, shimmering white
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_floating-nebula-citadel.jpg`
- **License / Attribution:** CC0
- **Notes:** Use to test scale, celestial lighting, and grand architectural fantasy.

### Suggestion: Macro Dewdrops on Bioluminescent Flora
- **Date:** 2026-05-20
- **Prompt:** "An extreme macro close-up of morning dew drops resting on the intricately veined leaf of an alien, bioluminescent plant. The veins pulse with a vibrant cyan light that refracts beautifully through the spherical water droplets. The background is a soft, dark bokeh. The mood is intimate and otherworldly. Shot with a 100mm macro lens."
- **Negative prompt:** "wide shot, dry, dull, noisy, cartoon, out of focus"
- **Tags:** sci-fi, macro, nature, photorealistic, dark
- **Style / Reference:** photorealistic, macro photography
- **Composition:** extreme close-up, shallow depth of field
- **Color palette:** deep dark greens, vibrant cyan, crystal clear
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260520_macro-bioluminescent-dew.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing macro details, liquid refraction, and subsurface scattering.

### Suggestion: Noir Detective in a Rain-Soaked Metropolis
- **Date:** 2026-05-20
- **Prompt:** "A weary detective in a classic trench coat standing under a flickering streetlamp in a rain-soaked, retro-futuristic city. Harsh, high-contrast shadows slash across their face, while the wet asphalt reflects the glaring red of a nearby neon sign. The mood is tense, moody, and cinematic. Captured in a classic film noir style with dramatic lighting."
- **Negative prompt:** "sunny, cheerful, daytime, low contrast, flat lighting"
- **Tags:** noir, portrait, retro, cinematic, moody
- **Style / Reference:** noir, photorealistic, cinematic
- **Composition:** medium shot, dramatic low angle
- **Color palette:** stark black and white, splashes of crimson red
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260520_noir-detective-rain.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing harsh lighting contrasts, rain effects, and wet reflections.

### Suggestion: Bismuth Exoplanet Core
- **Date:** 2026-05-19
- **Prompt:** "A breathtaking macro view of an exoplanet core entirely composed of shimmering, iridescent bismuth crystals. The fractal-like geometric structures reflect intense, vibrant rainbow hues against a dark, void-like background. The lighting is ethereal and internal, emanating from the depths of the core. Captured with a macro lens to emphasize the sharp, metallic edges and mesmerizing patterns."
- **Negative prompt:** "blurry, lowres, soft, earthy, water, organic, people"
- **Tags:** sci-fi, macro, photorealistic, dark
- **Style / Reference:** photorealistic, 3D render, mineral photography
- **Composition:** extreme close-up, centered
- **Color palette:** vibrant rainbow, metallic pink, blue, yellow, deep black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260519_bismuth-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for generating sharp metallic textures and testing iridescence in shaders.

### Suggestion: Steampunk Orbital Ring
- **Date:** 2026-05-19
- **Prompt:** "A majestic wide-angle shot of a colossal orbital ring encircling a distant planet, entirely constructed from polished brass and intricate gears. Huge smokestacks release vapor into space, while massive mechanical cogs slowly turn. Warm, cinematic lighting from a nearby star casts long shadows over the detailed metallic surface. The mood is epic and slightly moody."
- **Negative prompt:** "modern, clean, digital, plastic, flat, simple"
- **Tags:** steampunk, architecture, photorealistic, cinematic
- **Style / Reference:** photorealistic, retro-futurism
- **Composition:** wide shot, sweeping curve
- **Color palette:** polished brass, copper, warm golds, deep space black
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260519_steampunk-orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing large-scale mechanical textures and lighting on metallic curves.

### Suggestion: Mother of Pearl Tsunami
- **Date:** 2026-05-19
- **Prompt:** "A surreal, towering tsunami wave frozen in time, made entirely of shimmering mother of pearl. The wave curves gracefully, catching bright, ethereal light that reveals complex swirling layers of pink, pearlescent white, and pale cyan. The ocean below is dark and moody, contrasting with the luminous wave. The sky is dark and stormy, adding to the cinematic tension."
- **Negative prompt:** "water, splash, foam, ordinary, realistic ocean, daylight"
- **Tags:** fantasy, nature, surreal, ethereal
- **Style / Reference:** surrealism, 3D
- **Composition:** rule of thirds, dynamic angle
- **Color palette:** pearlescent whites, pale cyan, soft pink, dark teal
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260519_pearl-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for generating smooth, organic materials with subsurface scattering and pearlescent finishes.

### Suggestion: Italian Futurism Supernova
- **Date:** 2026-05-19
- **Prompt:** "An abstract, explosive depiction of a supernova in space, rendered in the style of Italian Futurism. Sharp, intersecting geometric planes of bright energy blast outward in dynamic, fragmented motion lines. The composition is chaotic and energetic, emphasizing speed and explosive power. Brilliant contrasting colors slice through the dark, cinematic void."
- **Negative prompt:** "soft, realistic, rounded, static, peaceful"
- **Tags:** sci-fi, landscape, abstract, bright
- **Style / Reference:** Italian Futurism, painterly, abstract geometry
- **Composition:** explosive outward burst, central focal point
- **Color palette:** brilliant yellow, crimson, electric blue, deep space black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260519_futurist-supernova.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing geometric displacement, fragmentation, and bold color contrasts.

### Suggestion: Bioluminescent Aerogel Reef
- **Date:** 2026-05-19
- **Prompt:** "An ethereal, glowing underwater reef where the corals are made of translucent, weightless aerogel. The delicate structures are infused with internal, bioluminescent light that pulses in moody neon greens and blues. Tiny, crystalline fish swim through the misty, soft-focus water. The scene feels alien and intensely peaceful."
- **Negative prompt:** "solid rock, ordinary coral, bright sunlight, murky water"
- **Tags:** sci-fi, nature, 3D, moody
- **Style / Reference:** 3D render, subsurface scattering focus
- **Composition:** medium shot, balanced
- **Color palette:** neon green, glowing blue, translucent gray, dark blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260519_aerogel-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for exploring volumetric lighting, transparency, and glowing subsurface materials.


### Suggestion: Bismuth Crystal Exoplanet Core
- **Date:** 2026-05-20
- **Prompt:** "A majestic and surreal landscape deep within the core of an exoplanet, composed entirely of massive, geometric bismuth crystals. The iridescent, stepped structures of the bismuth glow with vibrant pinks, golds, and blues under an ethereal internal light source. A glowing, slow-moving river of molten gold winds its way through the crystalline valleys. Atmospheric, luminous fog fills the cavernous spaces."
- **Negative prompt:** "water, greenery, people, sky, daylight, lowres"
- **Tags:** sci-fi, landscape, ethereal, moody
- **Style / Reference:** photorealistic, highly detailed, surreal
- **Composition:** wide shot, grand scale
- **Color palette:** vibrant pinks, blues, gold, deep shadows
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Great for testing metallic and crystalline material shaders with internal lighting.

### Suggestion: Solar Sail Armada at Supernova
- **Date:** 2026-05-20
- **Prompt:** "A cinematic wide shot of a vast armada of sleek, futuristic spaceships with enormous, gossamer solar sails, silhouetted against the blinding, chaotic eruption of a nearby supernova. The supernova explosion fills the background with violent swirls of bright orange, crimson, and stark white plasma. The solar sails catch and refract the intense light, glowing with intense energy."
- **Negative prompt:** "earth, planets, cartoon, simple, flat"
- **Tags:** sci-fi, cinematic, bright
- **Style / Reference:** photorealistic, epic sci-fi concept art
- **Composition:** wide shot, dynamic angle, rule of thirds
- **Color palette:** blinding whites, deep crimson, bright orange
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests bloom, intense highlights, and dramatic contrast.

### Suggestion: Bioluminescent Ashcan School Alley
- **Date:** 2026-05-20
- **Prompt:** "A moody, gritty urban alleyway rendered in the gritty realism of the Ashcan School, but infused with futuristic bioluminescence. It is raining heavily. Puddles reflect the dim, naturalistic light of the scene mixed with the sudden, harsh neon-blue glow of genetically modified glowing moss and fungi creeping up the brick walls."
- **Negative prompt:** "clean, modern, sunny, cheerful, flat"
- **Tags:** cyberpunk, noir, moody
- **Style / Reference:** Ashcan School, painterly realism mixed with sci-fi elements
- **Composition:** ground-level perspective, looking down the alley
- **Color palette:** muted grays and browns, striking neon-blue highlights
- **Aspect ratio:** 4:5
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests wet surface reflections and localized glowing elements against a muted background.

### Suggestion: Steampunk Brass Beaver Dam
- **Date:** 2026-05-20
- **Prompt:** "A highly detailed, macro shot of an intricate beaver dam constructed entirely from polished brass cogs, copper pipes, and small clockwork mechanisms, situated across a clear, fast-flowing forest stream. Water cascades over the precise, mechanical structure. Small, brass, robotic beavers are visible maintaining the intricate machinery. Sunlight dapples through the forest canopy above."
- **Negative prompt:** "wood, natural dam, cartoon, low detail"
- **Tags:** steampunk, macro, nature, whimsical
- **Style / Reference:** photorealistic, macro photography, highly detailed
- **Composition:** macro close-up, focusing on water flowing over the brass mechanisms
- **Color palette:** warm brass, copper, natural greens, sparkling water
- **Aspect ratio:** 3:2
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex metallic reflections and water caustics.

### Suggestion: Graphene Orbital Ring Megastructure
- **Date:** 2026-05-20
- **Prompt:** "An awe-inspiring view of an impossibly thin, massive orbital ring constructed from hyper-strong, translucent graphene, encircling a lush, green Earth-like planet. The structure is illuminated by the harsh, direct light of the sun, casting long, sharp shadows across the continents below. Tiny, bright lights mark docking ports along the ring's sleek surface against the deep black of space."
- **Negative prompt:** "clouds obscuring the ring, messy, chaotic, lowres"
- **Tags:** sci-fi, architecture, landscape, cinematic
- **Style / Reference:** photorealistic, grand scale sci-fi illustration
- **Composition:** wide shot, planet taking up lower half, ring curving overhead
- **Color palette:** deep black space, lush greens/blues of planet, stark white highlights on the ring
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests sharp geometric lines, harsh lighting contrasts, and sheer scale.


### Suggestion: Bioluminescent Underworld Cavern
- **Date:** 2026-05-25
- **Prompt:** "A vast subterranean cavern illuminated by gigantic, bioluminescent fungi and neon-glowing crystal formations. A dark underground river flows through the center, reflecting the vibrant pink, teal, and purple lights. Tiny, glowing insect-like creatures flutter in the air."
- **Negative prompt:** "sunlight, sky, human architecture, realistic, boring"
- **Tags:** sci-fi, fantasy, landscape, surreal, bright
- **Style / Reference:** surreal, vibrant, hyper-detailed
- **Composition:** wide angle, deep depth of field
- **Color palette:** neon pink, vibrant teal, deep purple, pitch black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260525_neon-underworld.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing glow, reflection, and high-contrast volumetric lighting.

### Suggestion: Steampunk Nebula Clockwork
- **Date:** 2026-05-25
- **Prompt:** "A colossal, intricate clockwork mechanism floating in the center of a vibrant, swirling nebula. Massive interlocking gears of polished brass and gold catch the starlight, while the heart of the mechanism houses a pulsing, miniature star."
- **Negative prompt:** "earth, planets, simple, modern, organic"
- **Tags:** steampunk, macro, 3D, ethereal
- **Style / Reference:** highly detailed, cinematic lighting, 3D render style
- **Composition:** central focus, symmetrical, macro scale
- **Color palette:** warm brass, gold, fiery orange, deep space blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260525_clockwork-nebula.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests metallic reflections, bloom, and intricate geometric rendering.

### Suggestion: Ethereal Frozen Desert
- **Date:** 2026-05-25
- **Prompt:** "A sprawling desert landscape where the dunes are made of sparkling, crystalline ice instead of sand. A pale, oversized moon hangs low in a gradient sky of pastel lavender and icy blue. Fragile, glass-like flora dot the frozen dunes."
- **Negative prompt:** "hot, sand, yellow, sun, warm"
- **Tags:** fantasy, landscape, surreal, ethereal, minimalist
- **Style / Reference:** ethereal, soft lighting, photorealistic
- **Composition:** rule of thirds, low angle
- **Color palette:** pastel lavender, icy blue, pristine white, silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260525_frozen-desert.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing refraction, subsurface scattering, and soft gradient blending.

### Suggestion: Cybernetic Avian Construct
- **Date:** 2026-05-25
- **Prompt:** "A close-up portrait of a majestic owl constructed entirely from sleek, futuristic cybernetic parts. Its feathers are overlapping plates of brushed titanium, and its eyes are glowing, multi-faceted camera lenses. It sits against a backdrop of a blurred, rain-streaked neon city window."
- **Negative prompt:** "organic, real bird, cartoon, flat"
- **Tags:** cyberpunk, portrait, photorealistic, moody
- **Style / Reference:** hyper-realistic, macro photography
- **Composition:** close-up, shallow depth of field, bokeh background
- **Color palette:** metallic gray, electric blue, neon reflections
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260525_cyber-owl.jpg`
- **License / Attribution:** CC0
- **Notes:** Use for testing sharp metallic textures, depth of field, and bokeh effects.

### Suggestion: Liquid Crystal Geode
- **Date:** 2026-05-25
- **Prompt:** "The interior of a massive geode where the crystals are formed from a slowly shifting, iridescent liquid crystal. The walls ripple and change color like an oil slick, ranging from deep magenta to vibrant cyan, illuminated by an unknown internal light source."
- **Negative prompt:** "matte, dull, ordinary rock, people, external light"
- **Tags:** sci-fi, macro, abstract, bright
- **Style / Reference:** macro, vibrant, surreal, abstract 3D
- **Composition:** abstract, filling the frame
- **Color palette:** iridescent, magenta, cyan, gold
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260525_liquid-geode.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing fluid simulations, iridescence, and complex color warping shaders.

### Suggestion: Solarpunk Floating Garden
- **Date:** 2026-05-26
- **Prompt:** "A sweeping landscape of a solarpunk city featuring massive, stepped floating gardens hovering above a crystalline lake. Dappled morning sunlight illuminates the lush greenery, solar panels, and wind turbines integrated into the futuristic architecture. The mood is hopeful, serene, and bright, captured with a wide-angle drone perspective."
- **Negative prompt:** "dystopian, smog, dark, gloomy, dirty, ruins"
- **Tags:** solarpunk, landscape, architecture, bright
- **Style / Reference:** photorealistic, highly detailed, utopian concept art
- **Composition:** wide shot, dynamic angle, rule of thirds
- **Color palette:** vibrant greens, clear blues, bright whites
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260526_solarpunk-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing lush vegetation and bright, clean environmental lighting.

### Suggestion: Isometric Noir Detective Office
- **Date:** 2026-05-26
- **Prompt:** "An isometric view of a classic 1940s noir detective's office. A single desk lamp casts harsh shadows across a cluttered desk covered in case files and a typewriter. Moonlight streams through half-open blinds from a rainy city night outside. The mood is moody, tense, and atmospheric."
- **Negative prompt:** "bright, modern, flat lighting, sunny, clean"
- **Tags:** noir, interior, isometric, moody
- **Style / Reference:** 3D isometric, stylized realism, cinematic lighting
- **Composition:** isometric, top-down angled, contained room
- **Color palette:** high contrast black and white, warm amber lamp light
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260526_noir-office.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing volumetric lighting and harsh shadow generation in confined spaces.

### Suggestion: Biomechanical Insect Macro
- **Date:** 2026-05-26
- **Prompt:** "An extreme macro close-up of a biomechanical beetle resting on an oversized neon-lit leaf. The insect's shell is made of iridescent carbon fiber and polished chrome, with glowing microscopic circuitry pulsing beneath its wings. The depth of field is incredibly shallow, focusing on the intricate mechanical compound eyes."
- **Negative prompt:** "blurry, low quality, wide shot, natural insect"
- **Tags:** sci-fi, macro, nature, cyberpunk
- **Style / Reference:** macro photography, hyper-detailed, metallic
- **Composition:** extreme close-up, shallow depth of field, center focus
- **Color palette:** chrome, neon green, iridescent blues
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260526_biomech-insect.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex micro-textures, bokeh, and material reflections.

### Suggestion: Steampunk Alchemist Laboratory
- **Date:** 2026-05-26
- **Prompt:** "The chaotic interior of a steampunk alchemist's laboratory filled with bubbling glass flasks, brass pipes, and glowing mystical potions. Thick steam and magical smoke curl around heavy wooden tables. Warm, flickering candlelight and the ethereal glow of the potions illuminate the scene, creating a whimsical and mysterious mood."
- **Negative prompt:** "modern lab, clean, digital screens, sterile"
- **Tags:** steampunk, fantasy, interior, whimsical
- **Style / Reference:** intricate concept art, cozy, detailed 3D environment
- **Composition:** wide room view, cluttered foreground to background
- **Color palette:** brass, warm amber, glowing green and purple
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260526_alchemist-lab.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing layered transparency, glowing liquids, and smoke effects.

### Suggestion: Ethereal Crystal Cave Portrait
- **Date:** 2026-05-26
- **Prompt:** "A beautiful portrait of an ethereal elf-like being inside a giant, glowing crystal cave. The subject is partially illuminated by the soft, cascading blue light radiating from the giant quartz structures around them. The lighting is soft and magical. Captured with a portrait lens, creating a gentle blur on the distant crystals."
- **Negative prompt:** "harsh lighting, outdoors, modern clothing, scary"
- **Tags:** fantasy, portrait, interior, ethereal
- **Style / Reference:** cinematic portrait photography, magical realism
- **Composition:** medium shot, eye-level, soft focus background
- **Color palette:** deep blues, glowing whites, soft skin tones
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260526_crystal-portrait.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing soft character lighting and subsurface scattering.

### Suggestion: Neon Cyber-Monastery
- **Date:** 2026-05-28
- **Prompt:** "A sprawling cyber-monastery perched on a foggy mountain peak at dawn. Traditional ornate wooden architecture fused seamlessly with glowing neon magenta and cyan circuitry. Cyber-monks in flowing robes walk across a wet stone courtyard. The lighting is cinematic, with harsh neon contrasting with soft, hazy morning sunlight."
- **Negative prompt:** "ugly, simple, flat, lowres, bright daylight"
- **Tags:** cyberpunk, architecture, landscape, cinematic
- **Style / Reference:** photorealistic, 3D render, dark sci-fi
- **Composition:** wide shot, low angle
- **Color palette:** neon magenta, cyan, warm sunrise orange, deep shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260528_cyber-monastery.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing volumetric fog and mixed natural/artificial lighting.

### Suggestion: Solarpunk Aerial Windmill City
- **Date:** 2026-05-28
- **Prompt:** "A utopian solarpunk city built into massive, floating wind turbines soaring high above the clouds in a bright blue sky. lush greenery, hanging gardens, and solar panels cover the white, curved organic architecture. People fly in small gliders between the platforms."
- **Negative prompt:** "dystopian, dark, polluted, ground, cars, gritty"
- **Tags:** solarpunk, architecture, bright, surreal
- **Style / Reference:** photorealistic, highly detailed, Ghibli-inspired lighting
- **Composition:** wide shot, high altitude perspective
- **Color palette:** sky blue, bright white, vibrant green
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260528_solarpunk-windmill.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing bright lighting, clean shadows, and organic curves.

### Suggestion: Eldritch Steampunk Clockmaker's Desk
- **Date:** 2026-05-28
- **Prompt:** "A cluttered steampunk clockmaker's desk littered with glowing brass gears, magnifying glasses, and strange alchemy bottles. In the center, a complex pocket watch is open, revealing a miniature, glowing purple galaxy spinning inside its gears. The room is dimly lit by a flickering oil lamp."
- **Negative prompt:** "clean, modern, digital, minimalist, empty"
- **Tags:** steampunk, still life, macro, dark
- **Style / Reference:** photorealistic, cinematic, macro photography
- **Composition:** close-up, shallow depth of field on the pocket watch
- **Color palette:** warm brass, dark wood, glowing purple
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260528_eldritch-clockmaker.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing macro depth of field and small glowing light sources.

### Suggestion: Surreal Isometric Floating Desert
- **Date:** 2026-05-28
- **Prompt:** "A perfectly square isometric slice of a surreal desert floating against a flat pastel pink background. A large, twisting sand dune curls around a single, massive, glowing blue crystal monolith. A tiny caravan of robotic camels walks across the sand."
- **Negative prompt:** "realistic sky, horizon line, normal perspective, messy"
- **Tags:** surreal, landscape, isometric, 3D, minimalist
- **Style / Reference:** 3D render, minimalist, clean lighting
- **Composition:** isometric, perfectly centered square slice
- **Color palette:** pastel pink, warm sand, glowing blue
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260528_isometric-desert.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for testing clean, stylized 3D geometry and isometric perspective generation.

### Suggestion: Bioluminescent Crystal Cave Explorer
- **Date:** 2026-05-28
- **Prompt:** "A solitary explorer in a futuristic hazard suit standing in a massive, ancient subterranean cave filled with towering, jagged crystal formations. The crystals emit a brilliant, shifting bioluminescent aura of emerald green and sapphire blue, illuminating the dark stone walls. Tiny glowing spores drift through the air."
- **Negative prompt:** "sunlight, surface, flat lighting, simple"
- **Tags:** sci-fi, nature, landscape, moody
- **Style / Reference:** photorealistic, cinematic, detailed 3D environment
- **Composition:** wide shot, showcasing the massive scale of the cave
- **Color palette:** emerald green, sapphire blue, pitch black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260528_crystal-cave.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing particle effects, subsurface scattering, and multi-colored bioluminescence.


### Suggestion: Neon-Lit Cyberpunk Marketplace
- **Date:** 2026-05-28
- **Prompt:** "A bustling, vibrant cyberpunk marketplace located in a narrow, rain-slicked alleyway. The scene is illuminated entirely by intense, flickering neon signs in vivid magenta, cyan, and amber. Steam billows from street vents, obscuring the ground. In the foreground, a heavily augmented street vendor is cooking noodles on a futuristic portable stove. The mood is moody and cinematic. Captured with a 50mm prime lens, shallow depth of field, focused on the vendor with glowing bokeh in the background."
- **Negative prompt:** "daylight, clean, unpopulated, cartoon, flat lighting, lowres, bright"
- **Tags:** cyberpunk, interior, photorealistic, moody, cinematic
- **Style / Reference:** photorealistic, cinematic, sci-fi concept art
- **Composition:** medium shot, eye-level, focused on foreground subject
- **Color palette:** high contrast magenta, cyan, amber, deep blacks
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260528_neon-cyberpunk-market.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing neon glow, volumetric fog, and wet reflection shaders.

### Suggestion: Minimalist Zen Garden Retreat
- **Date:** 2026-05-28
- **Prompt:** "A tranquil, minimalist zen garden viewed from a wooden veranda. Perfectly raked white gravel surrounds large, moss-covered obsidian stones. A single, gracefully curved bonsai tree sits in the corner. The scene is bathed in soft, diffused morning sunlight piercing through a misty atmosphere. The mood is ethereal and peaceful. Captured with a wide-angle lens, deep depth of field, ensuring everything is in sharp focus."
- **Negative prompt:** "cluttered, dark, noisy, people, vibrant colors, messy"
- **Tags:** nature, landscape, minimalist, ethereal
- **Style / Reference:** photorealistic, architectural visualization, minimalist
- **Composition:** wide shot, symmetrical balance, static camera
- **Color palette:** muted greens, soft whites, deep greys, pale yellow light
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20260528_minimalist-zen-garden.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing ambient occlusion, soft shadowing, and depth of field.

### Suggestion: Steampunk Brass Observatory
- **Date:** 2026-05-28
- **Prompt:** "The intricate interior of a grand steampunk observatory perched high in the mountains. Massive brass telescopes and complex clockwork orreries dominate the space. The room is warmly lit by numerous glowing Edison bulbs and moonlight streaming through a massive glass dome, revealing a starry night sky. The mood is whimsical and cinematic. Captured with a 24mm lens to capture the vast scale of the machinery and the starry sky above."
- **Negative prompt:** "modern, sleek, daylight, empty, simple, low quality"
- **Tags:** steampunk, interior, photorealistic, cinematic
- **Style / Reference:** photorealistic, detailed 3D render, steampunk aesthetic
- **Composition:** low angle looking up at the telescope and glass dome
- **Color palette:** warm golds, polished brass, rich mahogany, deep midnight blue
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260528_steampunk-observatory.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing metallic reflections, glass refraction, and point light sources.

### Suggestion: Surreal Floating Geometric Desert
- **Date:** 2026-05-28
- **Prompt:** "A vast, surreal desert landscape where colossal, impossible geometric shapes—perfect spheres and hypercubes made of mirrored glass—hover silently above rolling sand dunes. The lighting is harsh, high-noon sunlight casting stark, sharp shadows on the orange sand. The mood is bright, dreamlike, and abstract. Captured with an ultra-wide 14mm lens, emphasizing the endless horizon and the massive scale of the floating geometry."
- **Negative prompt:** "clouds, water, people, organic shapes, messy, dark"
- **Tags:** landscape, surreal, abstract, bright
- **Style / Reference:** surrealism, 3D abstract render, Dalí inspired
- **Composition:** ultra-wide shot, rule of thirds, low horizon line
- **Color palette:** vibrant orange sand, brilliant azure sky, chrome reflections
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260528_surreal-geometric-desert.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing environment mapping, sharp shadows, and ray-marched reflections.

### Suggestion: Noir Detective Office at Midnight
- **Date:** 2026-05-28
- **Prompt:** "A gritty, 1940s noir detective office late at night. Cigarette smoke hangs thick in the air, catching the stark, high-contrast light spilling through Venetian blinds from a streetlamp outside. A silhouette of a fedora-wearing figure sits behind a cluttered oak desk. The mood is dark, moody, and tense. Captured with a 35mm lens, high contrast black-and-white lighting, with deep, impenetrable shadows."
- **Negative prompt:** "bright, colorful, clean, daylight, modern, cheerful"
- **Tags:** noir, interior, photorealistic, moody, dark
- **Style / Reference:** cinematic noir, black and white photography, high contrast
- **Composition:** medium shot, strong chiaroscuro, framing the silhouette
- **Color palette:** monochromatic, stark blacks, bright whites, varied greys
- **Aspect ratio:** 2.35:1
- **Reference images:** `public/images/suggestions/20260528_noir-detective-office.jpg`
- **License / Attribution:** CC0
- **Notes:** Use for testing volumetric light shafts, high-contrast grading, and monochromatic filters.

### Suggestion: Steampunk Tsunami
- **Date:** 2026-10-31
- **Prompt:** "A chaotic, desperate scene of a massive tsunami wave crashing into an intricate steampunk harbor city. The towering, dark, and churning water dwarfs the brick tenements and brass smokestacks. The lighting is heavily overcast and bleak, casting murky shadows that emphasize the dirt, desperation, and raw power of nature over the mechanical urban landscape. The mood is dark, cinematic, and moody. Captured with a low, eye-level perspective to immerse the viewer in the unfolding disaster."
- **Negative prompt:** "bright, cheerful, clean, modern, sci-fi, surreal, highly saturated, peaceful"
- **Tags:** steampunk, landscape, photorealistic, cinematic, dark
- **Style / Reference:** steampunk painting, photorealistic, thick brushstrokes
- **Composition:** low angle, immersive eye-level perspective, chaotic framing
- **Color palette:** murky greens, dark greys, dull browns, foamy white, polished brass
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261031_steampunk-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing gritty, unidealized urban scenes merged with catastrophic natural events.

### Suggestion: Fantasy Volcanic Eruption
- **Date:** 2026-10-31
- **Prompt:** "An apocalyptic, highly detailed scene of a massive volcanic eruption tearing through a mountainous landscape, where the erupting magma and ash are composed entirely of shimmering, iridescent Mother of Pearl. The volcanic subject violently spews pearlescent pink, blue, and silver fluid across the jagged rocks, while a towering plume of iridescent ash dominates the sky. The lighting is harsh and chaotic, capturing the pearlescent interference patterns and the glowing heat of the nacreous lava. The mood is dark, ethereal, and bright. Captured with a wide 24mm lens to show the sheer scale of the beautiful destruction."
- **Negative prompt:** "peaceful, daylight, green grass, calm, low detail, red lava, dark ash"
- **Tags:** fantasy, landscape, surreal, ethereal, bright
- **Style / Reference:** surreal disaster concept art, photorealistic material swap
- **Composition:** wide angle, low angle looking up at the ash plume
- **Color palette:** pearlescent pinks, soft baby blues, shimmering silver, intense white highlights
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261031_fantasy-volcano.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating iridescent material rendering applied to chaotic fluid dynamics and thick volumetric smoke.

### Suggestion: Steampunk Orbital Ring Megastructure
- **Date:** 2026-10-31
- **Prompt:** "An epic, sweeping view of a massive Orbital Ring megastructure encircling a lush, green Earth-like planet, constructed entirely from intricate, polished brass clockwork and giant copper gears. The mechanical subject is dotted with glowing amber city lights and billowing steam vents. The lighting features a dramatic sunrise cresting over the planet's horizon, casting a blinding golden glare and long shadows across the intricate brass surface, highlighting the steampunk aesthetic on a cosmic scale. The mood is cinematic, bright, and whimsical. Captured with a wide-angle cinematic lens from low Earth orbit, emphasizing planetary scale."
- **Negative prompt:** "dystopian, sleek, modern, white plastic, broken, rusty, small, low-res"
- **Tags:** sci-fi, steampunk, architecture, cinematic, bright
- **Style / Reference:** steampunk concept art, cinematic space visualization
- **Composition:** curved horizon, extreme wide angle, dynamic lighting
- **Color palette:** polished warm brass, glowing amber, vibrant earth greens and blues, blinding solar gold
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261031_steampunk-orbital-ring.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of massive scale, planetary curvature, and highly intricate metallic steampunk textures in space.

### Suggestion: Cyberpunk Fireworks Over City
- **Date:** 2026-10-31
- **Prompt:** "A vibrant, long-exposure photograph of a massive fireworks display over a futuristic cyberpunk metropolis, but the exploding fireworks are composed of glowing, interconnected hexagonal structures of light-absorbing graphene. The dark, matte graphene subjects form intricate, geometric mandalas in the night sky, illuminated entirely by neon pink and cyan sparks traveling through the carbon lattice. The city below is lit by millions of neon signs. The mood is cinematic, bright, and moody. Captured from a high vantage point overlooking the skyline, showcasing the scale of the dark, geometric explosions."
- **Negative prompt:** "daylight, traditional fireworks, smoke, blurry, historical, soft"
- **Tags:** cyberpunk, landscape, abstract, cinematic, bright
- **Style / Reference:** long-exposure photography, cyberpunk aesthetic, geometric art
- **Composition:** high angle, wide skyline view, geometric patterns filling the sky
- **Color palette:** matte black, electric cyan, neon magenta, deep night sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261031_cyberpunk-fireworks.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing light-absorbing materials (graphene) contrasted with intricate, glowing geometric particle simulations over urban environments.

### Suggestion: Sci-fi Exoplanet Core
- **Date:** 2026-10-31
- **Prompt:** "A chaotic, energetic visualization deep within the core of a massive exoplanet, depicted in a highly abstract style. The subject is a violent, churning ocean of super-compressed crystalline fluid, deconstructed into aggressive, jagged diagonal lines and overlapping geometric planes that capture the intense pressure and kinetic energy. The lighting is blinding and internal, emanating from the explosive center and casting stark, jagged shadows that enhance the dynamic, splintered geometry. The mood is dark, abstract, and bright. Captured with a dynamic, tilted perspective to emphasize extreme pressure and raw motion."
- **Negative prompt:** "calm, realistic, smooth, organic, peaceful, soft lighting, photography"
- **Tags:** sci-fi, abstract, bright, dark
- **Style / Reference:** abstract concept art
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** blinding white, intense cyan, deep shadows, electric blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261031_sci-fi-exoplanet.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction to an extreme, high-pressure alien environment.




### Suggestion: Italian Futurism Tsunami
- **Date:** 2026-11-06
- **Prompt:** "A chaotic, dynamic depiction of a towering tsunami crashing into a modern coastline, rendered in the aggressive, fragmented style of Italian Futurism. The massive wave is deconstructed into sharp, intersecting diagonal lines and overlapping geometric planes that convey explosive speed and overwhelming force. The lighting is harsh and directional, creating stark, jagged shadows that enhance the dynamic motion. The mood is energetic, destructive, and cinematic. Captured with a tilted, dynamic perspective to emphasize raw motion."
- **Negative prompt:** "calm, realistic, soft curves, organic, peaceful, photography, smooth water"
- **Tags:** abstract, landscape, cinematic
- **Style / Reference:** Italian Futurism, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** deep ocean blue, harsh rusted reds, stark white foam, chaotic black shadows
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to a massive natural disaster.

### Suggestion: Bismuth Underground Library
- **Date:** 2026-11-06
- **Prompt:** "A grand, sprawling subterranean library where the towering columns, staircases, and shelves are composed entirely of gigantic, iridescent bismuth crystals. The subject features massive, step-patterned geometric formations reflecting a dazzling array of rainbow colors. The lighting is ethereal and internal, emanating from glowing, floating crystal orbs that cast complex, multi-colored reflections across the metallic bismuth surfaces. The mood is ancient, magical, and silent. Captured with a wide-angle 14mm lens, deep depth of field to capture the intricate, labyrinthine geometry."
- **Negative prompt:** "wood, paper, modern, daylight, soft lighting, ordinary rock"
- **Tags:** fantasy, architecture, interior, ethereal
- **Style / Reference:** fantasy environment design, hyper-detailed 3D render
- **Composition:** wide expansive view, deep symmetrical perspective
- **Color palette:** highly iridescent rainbow (metallic pinks, blues, greens, golds), dark cavern background
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests iridescent, metallic materials combined with intricate geometric (hopper crystal) architectural generation.

### Suggestion: Mother of Pearl Macro Pocket Watch
- **Date:** 2026-11-06
- **Prompt:** "An ultra-macro, hyper-detailed photograph of an open, antique pocket watch where all the intricate gears, hands, and the casing are carved entirely from shimmering, iridescent Mother of Pearl. The delicate subject rests on a piece of dark, aged velvet. The lighting is soft, diffused sunlight, catching the microscopic ridges of the nacre to reveal its rainbow interference patterns and casting soft shadows. The mood is elegant, fragile, and timeless. Captured with a 100mm macro lens, incredibly shallow depth of field focusing solely on the central gear."
- **Negative prompt:** "metal, brass, harsh lighting, wide angle, modern, blurry"
- **Tags:** macro, still life, surreal, ethereal
- **Style / Reference:** photorealistic macro product photography
- **Composition:** extreme close-up, rule of thirds, shallow depth of field
- **Color palette:** pearlescent pinks, soft baby blues, shimmering silver, deep burgundy velvet
- **Aspect ratio:** 1:1
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating sub-surface scattering and thin-film iridescent interference on intricate, micro-mechanical shapes.

### Suggestion: Graphene Steampunk Locomotive
- **Date:** 2026-11-06
- **Prompt:** "An imposing, colossal steampunk locomotive thundering across a snowy plain, constructed entirely from sleek, light-absorbing matte black graphene with polished copper accents and glowing amber pressure gauges. The dark, sleek subject features complex clockwork mechanisms driving its massive wheels. The lighting is harsh, unattenuated winter sunlight creating stark white highlights on the copper while the graphene hull remains pitch black, contrasted against the blinding white snow. The mood is powerful, industrial, and epic. Captured with a dynamic panning motion blur to convey immense speed."
- **Negative prompt:** "rusty iron, colorful, bright daylight, modern train, slow, blurry subject"
- **Tags:** steampunk, cinematic, landscape, dark
- **Style / Reference:** cinematic sci-fi vehicle design, photorealistic
- **Composition:** dynamic angled profile, panning motion blur, sharp subject focus
- **Color palette:** matte pitch black graphene, warm polished copper, glowing amber, blinding white snow
- **Aspect ratio:** 21:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of highly light-absorbing materials (graphene) contrasted with polished metal under harsh outdoor lighting and panning motion blur.

### Suggestion: Brass Volcanic Eruption
- **Date:** 2026-11-06
- **Prompt:** "A cataclysmic, surreal scene of a massive volcano erupting, where the mountain itself is an intricate, colossal mechanism of polished brass gears and the erupting lava is molten, glowing liquid gold. The subject violently spews golden fluid and thick, dark soot across a jagged, metallic landscape. The lighting is harsh and chaotic, capturing the blinding heat of the molten gold and the sharp specular glints on the brass machinery. The mood is awe-inspiring, destructive, and surreal. Captured with a wide 24mm lens to show the sheer scale of the beautiful, mechanical destruction."
- **Negative prompt:** "natural rock, red lava, peaceful, daylight, soft, low detail"
- **Tags:** surreal, landscape, bright
- **Style / Reference:** surreal disaster concept art, highly detailed 3D environment
- **Composition:** wide angle, low angle looking up at the eruption
- **Color palette:** brilliant molten gold, polished warm brass, pitch black soot, glowing amber
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating metallic rendering applied to chaotic fluid dynamics, massive scale, and intense internal lighting.

### Suggestion: Bismuth Exoplanet Core
- **Date:** 2026-11-07
- **Prompt:** "A hyper-detailed, surreal depiction of an exoplanet core entirely composed of giant, geometric bismuth crystals. The subject features stepped, iridescent hopper crystal structures that form vast metallic canyons. The lighting is ethereal, glowing from internal fractures with intensely bright rainbow colors that reflect off the sharply angled metallic surfaces. The mood is otherworldly, serene, and majestic. Captured as a sweeping landscape view to emphasize the colossal scale of the crystalline formations."
- **Negative prompt:** "organic, round, dull, earth-like, low resolution, blurry"
- **Tags:** sci-fi, landscape, surreal, 3D, ethereal, bright
- **Style / Reference:** 3D fractal art, hyper-realistic macro photography scaled up
- **Composition:** wide sweeping landscape, low horizon
- **Color palette:** iridescent pinks, blues, golds, and greens
- **Aspect ratio:** 21:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex geometric refraction, metallic iridescence, and sharp angular shadows.

### Suggestion: Aerogel Beehive
- **Date:** 2026-11-07
- **Prompt:** "A photorealistic macro shot of a futuristic beehive constructed entirely from ultra-lightweight, translucent blue aerogel. The subject shows glowing, robotic bees with delicate brass wings tending to glowing golden nectar stored within the hexagonal aerogel cells. The lighting is bright and whimsical, with sunlight passing through the cloudy, ghost-like aerogel to scatter soft blue light across the warm amber honey. The mood is peaceful, innovative, and warm. Captured with a specialized macro lens, highlighting the stark contrast between the milky aerogel and the sharp, precise machinery of the bees."
- **Negative prompt:** "traditional wood, dark, gloomy, out of focus, artificial lighting"
- **Tags:** solarpunk, macro, photorealistic, bright, whimsical
- **Style / Reference:** photorealistic macro photography, high-tech nature concept
- **Composition:** extreme close-up, shallow depth of field, rule of thirds
- **Color palette:** translucent ghostly blue, warm amber, bright gold
- **Aspect ratio:** 4:5
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Tests subsurface scattering, translucent materials, and the interaction of warm and cool lighting.

### Suggestion: Mother of Pearl Orbital Ring
- **Date:** 2026-11-07
- **Prompt:** "A cinematic, wide-angle view of a colossal orbital ring megastructure suspended above an ocean planet, constructed entirely from iridescent, polished mother of pearl. The subject curves elegantly across the sky, reflecting the planet's vast blue oceans and white clouds in its shimmering, pearlescent surface. The lighting is bright and ethereal, illuminated by a distant white sun that catches the micro-ridges of the nacre, throwing prismatic rainbows into the void of space. The mood is majestic, peaceful, and awe-inspiring. Captured from low earth orbit to emphasize the massive architectural curve."
- **Negative prompt:** "dark, gritty, industrial, rusty, lowres, busy"
- **Tags:** sci-fi, architecture, cinematic, bright, ethereal
- **Style / Reference:** grand sci-fi cinematic concept art, clean utopia
- **Composition:** sweeping diagonal curve, immense scale
- **Color palette:** pearlescent whites, soft pinks and greens, deep space blue
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Useful for evaluating large-scale iridescent reflections and clean, utopian lighting models.

### Suggestion: Damascus Steel Tsunami
- **Date:** 2026-11-07
- **Prompt:** "An abstract, dark fantasy landscape where a towering tsunami wave is frozen in time, sculpted from dark, rippling Damascus steel. The subject features intricate, wavy metallic woodgrain patterns that flow seamlessly into the terrifying curl of the wave. The lighting is moody and dramatic, with a solitary, pale moonlight glinting off the polished, dark metal ridges, casting deep black shadows in the troughs. The mood is ominous, powerful, and surreal. Captured from a low angle on a desolate shoreline, emphasizing the heavy, crushing weight of the metallic ocean."
- **Negative prompt:** "water, liquid, foam, blue, daytime, soft"
- **Tags:** fantasy, landscape, abstract, moody, dark
- **Style / Reference:** dark fantasy sculpture, abstract metal art
- **Composition:** imposing foreground, low angle, dramatic silhouette
- **Color palette:** dark metallic grays, silver highlights, pitch black
- **Aspect ratio:** 16:9
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Challenges the generator to apply detailed metallurgical patterns to complex, organic fluid shapes.

### Suggestion: Tweed Ashcan School Interior
- **Date:** 2026-11-07
- **Prompt:** "A painterly, Ashcan School-style depiction of a dimly lit, retro 1920s speakeasy, but the entire interior—including the walls, tables, and even the drinks—is textured like woven wool tweed. The subject reveals heavy, coarse fabric patterns intersecting with gritty urban life. The lighting is moody and low-key, with a single, hazy overhead lamp casting long, textured shadows across the herringbone floor. The mood is nostalgic, melancholic, and cozy yet gritty. Captured from a wide corner perspective, highlighting the claustrophobic and textile-heavy environment."
- **Negative prompt:** "smooth surfaces, modern, bright, photorealistic, clean"
- **Tags:** retro, noir, interior, painterly, moody
- **Style / Reference:** Ashcan School painting, heavy brushstrokes, textile art
- **Composition:** corner view, deep shadows, intimate framing
- **Color palette:** muted browns, charcoal grays, deep olive, warm sepia
- **Aspect ratio:** 4:3
- **Reference images:** none
- **License / Attribution:** CC0
- **Notes:** Ideal for testing unconventional texture mapping and moody, painterly light diffusion over rough surfaces.

### Suggestion: Neon-Soaked Solarpunk Cityscape
- **Date:** 2026-05-18
- **Prompt:** "A wide-angle, cinematic view of a solarpunk city at dusk. The architecture features sweeping, organic curves covered in lush, overgrown vines and glowing bio-luminescent moss. Warm, golden hour sunlight reflects off massive glass solar panels, contrasting with soft, cool blue neon lights activating in the lower streets. The mood is peaceful yet vibrant. Captured with a 24mm lens to emphasize the grand scale of the towering, eco-friendly skyscrapers against a pastel sky."
- **Negative prompt:** "dystopian, pollution, smog, cars, grim, dark, blurry"
- **Tags:** solarpunk, architecture, photorealistic, cinematic
- **Style / Reference:** photorealistic, highly detailed matte painting
- **Composition:** wide shot, grand scale, low angle
- **Color palette:** warm golds, lush greens, soft cool blues
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_solarpunk-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing organic architecture and balanced warm/cool lighting.

### Suggestion: Abandoned Gothic Library
- **Date:** 2026-05-18
- **Prompt:** "The interior of a massive, ruined Gothic library lit by ethereal moonlight streaming through a shattered stained-glass window. Dust motes float in the volumetric light shafts. Ancient, leather-bound books are scattered across a cracked marble floor overgrown with pale, twisting roots. The mood is dark, moody, and deeply atmospheric. Shot with a 35mm lens with a shallow depth of field, focusing on a single glowing tome on a stone pedestal in the foreground."
- **Negative prompt:** "modern, bright, cheerful, clean, people, artificial lighting"
- **Tags:** horror, interior, photorealistic, moody
- **Style / Reference:** photorealistic, dark fantasy, cinematic lighting
- **Composition:** foreground focus, rule of thirds, deep background
- **Color palette:** desaturated grays, deep shadows, cold moonlight blue
- **Aspect ratio:** 3:2
- **Reference images:** `public/images/suggestions/20260518_gothic-library.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing volumetric lighting and high-contrast shadows.

### Suggestion: Cyberpunk Noir Detective
- **Date:** 2026-05-18
- **Prompt:** "A close-up portrait of a grizzled detective in a neon-lit, rain-slicked alleyway in a cyberpunk metropolis. The subject wears a worn trench coat with glowing fiber-optic threads. Harsh, contrasting neon lights (magenta and cyan) cast dramatic, moody shadows across their heavily augmented, cybernetic face. The camera uses an 85mm portrait lens with rich bokeh, blurring the busy, glowing city traffic in the deep background."
- **Negative prompt:** "cartoon, 2D, sunny, happy, flat lighting, lowres"
- **Tags:** cyberpunk, noir, portrait, photorealistic, cinematic
- **Style / Reference:** photorealistic, neo-noir, cinematic 3D render
- **Composition:** close-up portrait, shallow depth of field
- **Color palette:** high contrast magenta and cyan, deep blacks
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260518_cyberpunk-detective.jpg`
- **License / Attribution:** CC0
- **Notes:** Use this to test neon reflections on skin and complex depth of field.

### Suggestion: Whimsical Isometric Alchemist Lab
- **Date:** 2026-05-18
- **Prompt:** "A highly detailed, 3D isometric view of an alchemist's laboratory filled with bubbling, glowing potions. The room features a large brass cauldron, walls lined with intricate wooden shelves containing mysterious glowing jars, and scattered spell scrolls. Warm, ambient light emanates from a crackling fireplace and the luminescent liquids. The mood is whimsical and magical. Rendered with clean edges, sharp focus, and vibrant, saturated colors."
- **Negative prompt:** "realistic, dark, scary, messy, perspective camera, lowres"
- **Tags:** fantasy, interior, isometric, 3D, whimsical
- **Style / Reference:** 3D isometric render, stylized, vibrant
- **Composition:** isometric perspective, centered, cutaway view
- **Color palette:** warm oranges, glowing greens and purples, rich browns
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260518_isometric-lab.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating sharp geometric rendering and glowing liquid materials.

### Suggestion: Surreal Clockwork Macro
- **Date:** 2026-05-18
- **Prompt:** "An extreme macro, highly detailed shot of surreal, floating watch parts intermingled with fragile, crystalline butterfly wings. The tiny, intricate brass gears and glowing ruby jewels are suspended in a void of soft, ethereal, pearlescent fog. The lighting is soft and diffused, highlighting the microscopic scratches on the metal and the iridescence of the wings. The mood is ethereal and abstract. Shot with a dedicated 100mm macro lens."
- **Negative prompt:** "people, large scale, outdoors, bright sunlight, harsh shadows"
- **Tags:** steampunk, surreal, macro, abstract, ethereal
- **Style / Reference:** surreal photography, extreme macro, highly detailed
- **Composition:** extreme close-up, central focus, negative space
- **Color palette:** brass, gold, pearlescent whites, soft ruby red
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260518_surreal-macro.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing macro textures, soft diffusion, and abstract forms.

### Suggestion: Bismuth Clockwork Owl
- **Date:** 2026-10-15
- **Prompt:** "A highly detailed, macro portrait of a mechanical owl constructed entirely from vibrant, stepped hopper crystals of iridescent bismuth and delicate brass clockwork. The subject is perched on a dark, rusted iron branch. The lighting is cinematic, utilizing a single warm spotlight that highlights the rainbow interference patterns of the bismuth and casts deep, sharp shadows within the gears. The mood is mysterious, intricate, and magical. Captured with a 100mm macro lens, incredibly shallow depth of field focusing strictly on its glowing, multi-faceted amber eyes."
- **Negative prompt:** "organic feathers, real bird, daylight, soft lighting, bright background, blurry, out of focus"
- **Tags:** macro, steampunk, animal, bismuth, photorealistic
- **Style / Reference:** photorealistic macro product photography, steampunk aesthetic
- **Composition:** centered portrait, close-up, shallow depth of field
- **Color palette:** iridescent rainbow, metallic pink, gold, deep iron black, glowing amber
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261015_bismuth-clockwork-owl.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the generation of complex hopper crystal geometry combined with intricate mechanical parts and iridescence.

### Suggestion: Graphene Bioluminescent Reef
- **Date:** 2026-10-15
- **Prompt:** "A breathtaking, ultra-wide underwater landscape showcasing a sprawling coral reef constructed entirely from light-absorbing, matte black graphene. The dark, geometric graphene structures are heavily populated by intensely glowing, bioluminescent flora in vivid neon cyan and magenta. The lighting is entirely diegetic, radiating from the luminescent plants and reflecting off tiny, silver-scaled fish, while the graphene remains pitch black. The mood is alien, beautiful, and deeply mysterious. Captured with a 14mm ultra-wide lens to emphasize the vast, sweeping scale of the dark, glowing ecosystem."
- **Negative prompt:** "sunlight, daylight, bright surface, natural coral, sand, murky water, low resolution"
- **Tags:** underwater, sci-fi, landscape, graphene, bioluminescent
- **Style / Reference:** cinematic deep-sea exploration, high-contrast digital art
- **Composition:** wide landscape, deep perspective, rule of thirds
- **Color palette:** matte pitch black, neon cyan, vibrant magenta, bright silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261015_graphene-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to contrast intensely bright emissive materials against completely light-absorbing, matte geometric structures.

### Suggestion: Mother of Pearl Spacesuit
- **Date:** 2026-10-15
- **Prompt:** "An elegant, surreal fashion portrait of an astronaut wearing a futuristic spacesuit forged seamlessly from shimmering, iridescent Mother of Pearl and polished silver joints. The subject stands elegantly on the desolate, dusty surface of an asteroid with a massive, vibrant blue gas giant looming in the background. The lighting is harsh, unattenuated starlight that catches the micro-ridges of the nacre, throwing prismatic pink and blue highlights across the suit's curved surfaces. The mood is majestic, fragile, and highly fashionable. Captured with an 85mm portrait lens, eye-level perspective."
- **Negative prompt:** "fabric, cloth, plastic, dull, earth, atmosphere, soft lighting, cartoon"
- **Tags:** sci-fi, fashion, portrait, surreal, mother of pearl
- **Style / Reference:** high-fashion editorial photography, surreal sci-fi
- **Composition:** waist-up portrait, off-center subject, grand cosmic background
- **Color palette:** pearlescent whites, soft pinks and blues, polished silver, deep cosmic black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261015_nacre-spacesuit.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating thin-film iridescent interference mapped onto complex, curved, hard-surface armor plating.

### Suggestion: Italian Futurism Asteroid Base
- **Date:** 2026-10-15
- **Prompt:** "A chaotic, high-velocity depiction of a sprawling mining base on a tumbling asteroid, rendered in the aggressive, fragmented style of Italian Futurism. The massive industrial drills and habitats are deconstructed into jagged diagonal lines and overlapping geometric planes that convey explosive mechanical energy and relentless speed. The lighting is harsh, directional, and splintered, throwing stark, jagged shadows that enhance the dynamic motion of the composition. The mood is energetic, industrial, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion."
- **Negative prompt:** "calm, realistic space, smooth curves, organic, gentle, photorealistic, quiet"
- **Tags:** abstract, sci-fi, italian futurism, space, dynamic
- **Style / Reference:** Italian Futurism art movement, Giacomo Balla inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, stark black space, blinding white light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261015_futurism-asteroid-base.jpg`
- **License / Attribution:** CC0
- **Notes:** Pushes the model to apply the aggressive, dynamic abstraction of Italian Futurism to an industrial, cosmic environment.

### Suggestion: Ashcan School Cyberpunk Diner
- **Date:** 2026-10-15
- **Prompt:** "A bustling, gritty cyberpunk diner on a rainy night, depicted in the unidealized, painterly style of the Ashcan School. The subject features weary, working-class cyborgs huddled over steaming bowls of noodles under flickering, dim lights. The lighting is overcast and realistic, casting soft, murky shadows that highlight the dirt and texture of the urban environment, contrasted only by a dull, buzzing neon sign outside. The mood is authentic, raw, and full of everyday melancholy. Captured with an eye-level, documentary-style perspective, emphasizing the unglamorous reality of the futuristic city."
- **Negative prompt:** "clean, modern, bright, cheerful, highly saturated, glossy, 3d render, anime"
- **Tags:** cyberpunk, interior, ashcan school, gritty, painterly
- **Style / Reference:** Ashcan School painting, heavy brushstrokes, Edward Hopper inspired
- **Composition:** eye-level, crowded interior, naturalistic framing
- **Color palette:** muted browns, dark greys, dull olive, faded neon red
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261015_ashcan-cyber-diner.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the blending of futuristic, high-tech themes with the gritty, muted, historical painting style of the Ashcan School.


### Suggestion: Bioluminescent Floating Jellyfish City
- **Date:** 2026-12-05
- **Prompt:** "A sprawling, futuristic city built upon the caps of colossal, bioluminescent jellyfish floating through a dense, starry nebula. The organic architecture features sweeping, translucent domes and delicate, glowing tendrils connecting the structures. The lighting is completely diegetic, emitting soft neon blues and pulsing magenta from the jellyfish and city lights. The mood is awe-inspiring, serene, and otherworldly. Captured with an ultra-wide 14mm lens to emphasize the majestic scale against the cosmic sky."
- **Negative prompt:** "earth, daylight, ocean water, dark, grim, dystopian, lowres, blurry"
- **Tags:** sci-fi, space, bioluminescent, city, surreal
- **Style / Reference:** cinematic space art, photorealistic 3D render
- **Composition:** wide expansive view, rule of thirds, deep perspective
- **Color palette:** neon blue, pulsing magenta, deep cosmic black, stark white stars
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261205_jellyfish-city.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating soft emissive lighting against a dark cosmic background and transparent organic textures.

### Suggestion: Clockwork Solar System Orrery
- **Date:** 2026-12-05
- **Prompt:** "A hyper-detailed, macro photograph of an intricate, antique brass and copper clockwork orrery depicting the solar system. The planets are represented by polished gemstones like lapis lazuli, tiger's eye, and malachite. The lighting is warm, directional studio lighting, catching the microscopic scratches on the brass gears and creating sharp, bright specular highlights on the polished gemstones. The mood is intellectual, antique, and precise. Captured with a 100mm macro lens, incredibly shallow depth of field focusing strictly on the central brass sun mechanism."
- **Negative prompt:** "modern, plastic, flat lighting, messy, bright background, digital"
- **Tags:** steampunk, macro, still life, mechanism, vintage
- **Style / Reference:** photorealistic macro product photography, steampunk aesthetic
- **Composition:** close-up, rule of thirds, shallow depth of field
- **Color palette:** warm brass, polished copper, deep gemstone blue and green, rich dark brown
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261205_clockwork-orrery.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for pushing the model's detailing capabilities on micro-mechanical parts and highly reflective curved gemstone surfaces.

### Suggestion: Obsidian Art Deco Skyscraper
- **Date:** 2026-12-05
- **Prompt:** "A towering, imposing skyscraper designed in a lavish Art Deco style, constructed entirely from flawless, highly reflective black obsidian and polished gold inlays. The subject stands in the center of a stormy, lightning-filled metropolis. The lighting is dramatic and high-contrast, with a sudden flash of lightning illuminating the slick, wet obsidian surface and reflecting brightly off the gold geometric patterns. The mood is powerful, dark, and luxurious. Captured with a low-angle perspective using a 24mm lens to emphasize the monolithic height and sharp geometric lines."
- **Negative prompt:** "daylight, bright, cheerful, colorful, soft curves, ruin, rusted"
- **Tags:** architecture, dark, art deco, obsidian, lightning
- **Style / Reference:** dark architectural visualization, cinematic rendering
- **Composition:** low angle looking up, symmetrical, towering scale
- **Color palette:** pitch black obsidian, brilliant gold, cold electric blue, dark stormy grey
- **Aspect ratio:** 9:16
- **Reference images:** `public/images/suggestions/20261205_obsidian-skyscraper.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the interaction between highly reflective dark surfaces and sharp, sudden intense directional light like lightning.

### Suggestion: Porcelain Cybernetic Samurai
- **Date:** 2026-12-05
- **Prompt:** "A striking, photorealistic portrait of a cybernetic samurai whose armor and faceplate are crafted from pristine white porcelain with delicate, traditional blue floral patterns. The subject is standing in a quiet, mist-filled bamboo forest. The lighting is soft, diffused overcast daylight filtering through the canopy, highlighting the smooth, glossy texture of the porcelain and the subtle glowing cyan circuitry beneath the joints. The mood is calm, elegant, and slightly melancholic. Captured with an 85mm portrait lens, shallow depth of field blurring the bamboo in the background."
- **Negative prompt:** "metal armor, rusty, bright sunlight, violent, messy, low quality"
- **Tags:** cyberpunk, portrait, porcelain, samurai, serene
- **Style / Reference:** hyper-realistic portrait photography, surreal material swap
- **Composition:** waist-up portrait, balanced framing, soft background bokeh
- **Color palette:** pristine white, traditional porcelain blue, soft bamboo green, glowing cyan
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261205_porcelain-samurai.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the generation of clean, glossy materials with intricate surface patterns under soft, diffused natural lighting.

### Suggestion: Iridescent Crystal Cavern River
- **Date:** 2026-12-05
- **Prompt:** "A vast subterranean landscape featuring a fast-flowing river of liquid silver winding through a cavern composed of colossal, jagged crystals that shift in iridescent shades of purple, green, and pink. The lighting is ethereal and subterranean, with the liquid silver reflecting the luminescent glow of the surrounding crystals to illuminate the dark cavern walls. The mood is magical, untouched, and serene. Captured with a wide-angle 14mm lens, deep focus to capture the endless frozen reflections and the dynamic flow of the liquid metal."
- **Negative prompt:** "daylight, sunlight, dirt, organic plants, people, blurry, flat lighting"
- **Tags:** fantasy, landscape, crystal, ethereal, subterranean
- **Style / Reference:** fantasy environment design, photorealistic 3D render
- **Composition:** wide landscape, deep perspective, river creating a leading line
- **Color palette:** iridescent purple and green, liquid silver, deep dark cave shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261205_iridescent-cavern-river.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing liquid metal reflections combined with multi-colored iridescent crystalline light sources.

### Suggestion: Ashcan School Graphene Skyscraper Construction
- **Date:** 2026-12-10
- **Prompt:** "A gritty, unidealized depiction of construction workers assembling a colossal skyscraper made of light-absorbing matte black graphene, rendered in the painterly, muted style of the Ashcan School. The subject features weary, muscular laborers hoisting massive, sleek geometric graphene beams against a smog-filled, overcast sky. The lighting is dull and naturalistic, casting murky, diffuse shadows that emphasize the harsh reality of urban labor, contrasted sharply by the impossibly sleek, futuristic material they are working with. The mood is melancholic, industrious, and gritty. Captured from a dynamic, low-angle perspective to emphasize the towering scale of the dark architecture."
- **Negative prompt:** "bright, cheerful, clean, highly saturated, glossy, 3d render, anime, photorealistic"
- **Tags:** art, historical, ashcan school, graphene, construction
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes
- **Composition:** low angle, crowded foreground, towering background
- **Color palette:** muted browns, charcoal grays, matte pitch black, dull slate sky
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261210_ashcan-graphene-construction.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the integration of highly advanced, futuristic materials (graphene) into a historical, gritty painting style representing everyday labor.

### Suggestion: Italian Futurism Bismuth Train
- **Date:** 2026-12-10
- **Prompt:** "A chaotic, high-speed scene of a massive locomotive constructed entirely from iridescent, geometric bismuth crystals, depicted in the harsh, fragmented style of Italian Futurism. The crystalline subject is deconstructed into jagged diagonal lines and overlapping stepped-planes that capture immense kinetic energy and forward momentum. The lighting is dramatic, splintered, and directional, causing the metallic bismuth facets to flash with vibrant rainbow colors amidst the blurred, fractured environment. The mood is energetic, aggressive, and dazzling. Captured with a dynamic, tilted perspective to emphasize raw motion and violent speed."
- **Negative prompt:** "calm, realistic, smooth curves, organic, gentle, photorealistic, slow, stationary"
- **Tags:** abstract, art, italian futurism, speed, bismuth, train
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** vibrant iridescent pinks and blues, steel greys, stark black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261210_futurism-bismuth-train.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to highly structured, colorful hopper crystal geometry.

### Suggestion: Damascus Steel Exoplanet Core
- **Date:** 2026-12-10
- **Prompt:** "A colossal, surreal visualization deep within the core of a massive exoplanet, where the crushing pressure has formed an ocean of rippling, liquid Damascus steel. The subject features immense, flowing metallic waves showcasing intricate, woodgrain-like patterns of dark and light silver. The lighting is terrifyingly intense and internal, erupting from deep, glowing fissures of molten amber and white-hot energy that cast sharp, glaring highlights across the complex metallic ridges. The mood is oppressive, alien, and awe-inspiring. Captured with an extreme wide-angle 14mm lens to encompass the vast, churning scale of the planetary core."
- **Negative prompt:** "soft, organic, earth-like, calm, daylight, water, blurry, low resolution"
- **Tags:** sci-fi, space, landscape, damascus steel, exoplanet
- **Style / Reference:** cinematic sci-fi environment design, photorealistic material rendering
- **Composition:** wide expansive view, chaotic flowing lines, deep perspective
- **Color palette:** dark metallic grays, polished silver, blinding white-hot core, glowing amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261210_damascus-exoplanet-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the complex, flowing texture generation of Damascus steel mapped onto massive, churning fluid dynamics under extreme lighting.

### Suggestion: Mother of Pearl Beaver Dam
- **Date:** 2026-12-10
- **Prompt:** "A highly detailed, surreal landscape photograph of an intricate beaver dam blocking a serene forest stream, but the entire structure is woven from massive, shimmering pieces of iridescent Mother of Pearl instead of wood. The delicate, pearlescent subject holds back a deep pool of crystal-clear water. The lighting is crisp, early morning sunlight piercing through a dense, foggy forest canopy, catching the micro-ridges of the nacre to reveal intense rainbow interference patterns and casting dappled light on the still water. The mood is peaceful, magical, and highly unusual. Captured with a 35mm lens from the edge of the water, showcasing the exquisite textures of the pearlescent dam."
- **Negative prompt:** "wood, bark, muddy, dirty, dull, urban, modern, people"
- **Tags:** nature, landscape, surreal, mother of pearl, ethereal
- **Style / Reference:** photorealistic surrealism, National Geographic style nature photography
- **Composition:** wide shot, low angle near water surface, clear reflection
- **Color palette:** pearlescent whites, soft pinks and baby blues, lush forest greens
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261210_nacre-beaver-dam.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating iridescent material rendering and thin-film interference applied to a chaotic, organic structure normally made of wood.

### Suggestion: Tweed Supernova Remnant
- **Date:** 2026-12-10
- **Prompt:** "An epic, surreal depiction of a cataclysmic supernova remnant expanding through deep space, where the cosmic dust and plasma are replaced by billions of woven threads of coarse, multi-colored tweed fabric. The soft, fibrous subject is tearing apart in a chaotic, expanding spherical cloud, revealing intricate herringbone and houndstooth patterns on a cosmic scale. The lighting is extremely bright and dynamic, emanating from a blindingly white dwarf star at the center, casting dramatic, harsh light that highlights the microscopic fuzzy textures of the wool against the pitch-black void. The mood is awe-inspiring, bizarre, and highly tactile. Captured as if by the James Webb Space Telescope, combining cosmic scale with macro fabric details."
- **Negative prompt:** "smooth, plasma, gas, liquid, realistic space, blurry, low contrast"
- **Tags:** sci-fi, surreal, space, supernova, tweed, fabric
- **Style / Reference:** hyper-detailed material swap, astrophotography style
- **Composition:** wide angle, expansive, centered explosion, high detail
- **Color palette:** earthy brown and green tweed threads, blinding white core, pitch black void
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261210_tweed-supernova.jpg`
- **License / Attribution:** CC0
- **Notes:** Pushes the model to generate soft, woven micro-textures (tweed) placed in an environment of extreme cosmic scale and harsh, single-point lighting.

### Suggestion: Bioluminescent Silk Spiderweb
- **Date:** 2026-12-20
- **Prompt:** "An ultra-macro, mesmerizing photograph of an intricate spiderweb where every thread is woven from glowing, bioluminescent cyan silk. The web is perfectly suspended between two ancient, dark oak branches in a misty night forest. The lighting is exclusively from the glowing web, which casts soft, eerie cyan reflections on the wet bark and illuminates tiny, floating dust motes trapped in the surrounding fog. The mood is magical, quiet, and slightly haunting. Captured with a 100mm macro lens, razor-thin depth of field, with the dark forest blurring into smooth bokeh."
- **Negative prompt:** "daylight, sun, bright background, artificial lights, blurry web, rough texture"
- **Tags:** macro, nature, bioluminescent, magical, dark
- **Style / Reference:** photorealistic macro photography, high contrast lighting
- **Composition:** close-up, rule of thirds, shallow depth of field
- **Color palette:** glowing neon cyan, deep forest black, dark brown bark
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261220_bioluminescent-spiderweb.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the generation of extremely fine, glowing filaments and soft macro bokeh effects in dark environments.

### Suggestion: Steampunk Graphene Submarine
- **Date:** 2026-12-20
- **Prompt:** "An epic, underwater scene of a massive steampunk submarine exploring the deep ocean trench, constructed entirely from sleek, light-absorbing matte black graphene with ornate, polished brass portholes and glowing amber external lights. The submarine navigates past towering hydrothermal vents spewing thick black smoke. The lighting is dramatic and directional, emanating from the sub's intense amber searchlights that cut through the murky, particulate-filled water, while the graphene hull remains pitch black. The mood is oppressive, industrial, and adventurous. Captured with a wide-angle perspective to emphasize the crushing depth and scale of the vessel."
- **Negative prompt:** "bright surface, sunlight, modern submarine, white plastic, cartoon, shallow water"
- **Tags:** steampunk, underwater, sci-fi, dark, cinematic
- **Style / Reference:** cinematic deep-sea exploration, photorealistic vehicle concept
- **Composition:** wide shot, dynamic angle, leading lines from searchlights
- **Color palette:** matte pitch black graphene, warm polished brass, glowing amber, murky deep sea green
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261220_graphene-submarine.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating the contrast between intensely bright underwater searchlights and highly light-absorbing matte materials.

### Suggestion: De Stijl Neon Data Center
- **Date:** 2026-12-20
- **Prompt:** "A vast, futuristic server room designed strictly following the geometric abstraction of the De Stijl art movement. The towering server racks are composed of perfectly straight horizontal and vertical lines in stark black, interspersed with solid, glowing neon panels of pure primary red, blue, and yellow. The lighting is clean, bright, and completely uniform, emphasizing the flat, rigid geometry and primary colors without any natural shadows or gradients. The mood is analytical, orderly, and ultra-modern. Captured with an orthographic camera perspective to flatten the depth and accentuate the grid-like composition."
- **Negative prompt:** "curves, organic shapes, gradients, messy, dark, moody, realistic servers"
- **Tags:** abstract, interior, de stijl, sci-fi, geometric
- **Style / Reference:** De Stijl art movement, Piet Mondrian inspired, minimalist 3D render
- **Composition:** orthographic perspective, strict grid alignment, balanced primary colors
- **Color palette:** pure primary red, pure primary blue, pure primary yellow, stark black, pristine white
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261220_de-stijl-datacenter.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the application of strict historical abstract art constraints (De Stijl) to a modern, technological interior using glowing materials.

### Suggestion: Iridescent Obsidian Beetle
- **Date:** 2026-12-20
- **Prompt:** "An ultra-detailed macro photograph of a giant, otherworldly beetle resting on a bed of crushed, pale quartz. The beetle's carapace is formed from highly polished obsidian that exhibits a dazzling, iridescent oil-slick effect, shifting between deep purples, greens, and golds depending on the light angle. The lighting is a harsh, directional studio strobe that catches sharp specular highlights on the glossy black stone and triggers intense, rainbow interference patterns on the curved shell. The mood is scientific, alien, and luxurious. Captured with a 100mm macro lens, deep focus on the intricate joints of the insect."
- **Negative prompt:** "soft lighting, blurry, ordinary insect, dull colors, natural dirt, outdoor"
- **Tags:** macro, nature, insect, obsidian, iridescent
- **Style / Reference:** photorealistic macro studio photography, high contrast
- **Composition:** centered subject, extreme close-up, sharp focus
- **Color palette:** glossy pitch black, iridescent purple/green/gold, pale white quartz
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261220_iridescent-obsidian-beetle.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating the combination of highly reflective, dark, glossy materials (obsidian) with thin-film iridescence on complex organic curves.

### Suggestion: Ethereal Bismuth Cathedral
- **Date:** 2026-12-20
- **Prompt:** "A breathtaking, wide-angle interior shot of a colossal fantasy cathedral constructed entirely from gigantic, naturally forming hopper crystals of iridescent bismuth. The massive, step-patterned pillars stretch up into a foggy, cavernous vault. The lighting is soft and ethereal, filtering down from an unseen opening high above, casting a celestial glow that illuminates the vibrant rainbow facets of the metallic walls in pinks, blues, and golds. The mood is majestic, sacred, and otherworldly. Captured from a low angle, emphasizing the immense, dizzying scale and the intricate geometric architecture."
- **Negative prompt:** "wood, stone, traditional stained glass, dark, creepy, messy, low detail"
- **Tags:** fantasy, architecture, interior, bismuth, majestic
- **Style / Reference:** photorealistic fantasy environment design, epic scale
- **Composition:** low angle looking up, deep symmetrical perspective
- **Color palette:** highly iridescent rainbow (metallic pinks, blues, golds), soft white light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261220_bismuth-cathedral.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for generating massive, step-patterned geometric structures and testing large-scale iridescent reflections in a foggy environment.

### Suggestion: Aerogel Coral Reef
- **Date:** 2026-12-30
- **Prompt:** "A vibrant, ultra-macro underwater shot of a delicate coral reef where the coral structures are formed entirely from translucent, ghostly blue aerogel. The subject features intricate, porous geometric patterns that catch the ambient light. The lighting is ethereal and diffused, with soft sun rays piercing through the clear, shallow water above, scattering inside the low-density aerogel to create a mesmerizing internal glow. The mood is tranquil, fragile, and alien. Captured with a 100mm macro lens, utilizing a shallow depth of field to isolate the aerogel structure from the softly blurred aquatic background."
- **Negative prompt:** "ordinary coral, rock, murky water, dark, gritty, low resolution, flat lighting"
- **Tags:** macro, underwater, nature, aerogel, ethereal
- **Style / Reference:** photorealistic macro nature photography, sci-fi materials
- **Composition:** close-up, center focus, rule of thirds, beautiful bokeh
- **Color palette:** translucent ghostly blue, pale turquoise, bright sunlit white, deep ocean blue
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261230_aerogel-coral-reef.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests subsurface scattering on highly translucent, low-density materials in an underwater environment.

### Suggestion: Damascus Steel Clockwork Heart
- **Date:** 2026-12-30
- **Prompt:** "A hyper-detailed, dramatic still life of a mechanical heart, meticulously assembled from interlocking cogs and valves forged from dark, rippled Damascus steel. The metallic subject features complex, flowing woodgrain-like patterns of dark and light silver. The lighting is moody, utilizing a single, warm spotlight to cast sharp specular highlights on the polished metallic edges and deep, rich shadows between the intricate gears. The mood is romantic, industrial, and melancholic. Captured with a 50mm lens, sharp focus on the central valve mechanism."
- **Negative prompt:** "organic, flesh, blood, plastic, flat lighting, blurry, wide angle, modern"
- **Tags:** still-life, steampunk, metal, damascus steel, anatomy
- **Style / Reference:** photorealistic product photography, highly detailed steampunk
- **Composition:** centered subject, close-up, dramatic chiaroscuro
- **Color palette:** dark metallic greys, silver highlights, warm golden light, pitch black shadows
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20261230_damascus-clockwork-heart.jpg`
- **License / Attribution:** CC0
- **Notes:** Evaluates the generation of complex flowing textures of Damascus steel on intricate, curved mechanical parts.

### Suggestion: Bismuth Brutalist Monument
- **Date:** 2026-12-30
- **Prompt:** "A towering, monolithic Brutalist monument located in a desolate, snowy tundra, but the massive geometric slabs are composed entirely of gigantic, iridescent bismuth crystals. The subject features stepped, hopper-like formations that reflect a dazzling array of metallic rainbow colors. The lighting is harsh, cold winter sunlight that creates stark, jagged shadows across the complex, angular architecture, contrasting with the blinding white snow below. The mood is imposing, alien, and majestic. Captured with an ultra-wide 14mm lens from a low angle to emphasize the staggering, oppressive scale."
- **Negative prompt:** "concrete, wood, warm weather, soft curves, blurry, organic"
- **Tags:** architecture, brutalist, bismuth, winter, sci-fi
- **Style / Reference:** brutalist architectural visualization, hyper-detailed 3D render
- **Composition:** low angle looking up, dramatic diagonal lines, towering presence
- **Color palette:** iridescent pinks, blues, and golds, stark white snow, cold grey sky
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261230_bismuth-brutalist.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for combining stark Brutalist geometry with the complex step-patterns and iridescence of bismuth crystals.

### Suggestion: Graphene Cyberpunk Motorcycle
- **Date:** 2026-12-30
- **Prompt:** "A sleek, futuristic cyberpunk motorcycle parked in a dark, rain-soaked alleyway, constructed from seamless, light-absorbing matte black graphene. The extremely dark subject features aggressive, angular lines and glowing neon cyan wheel trims that cast bright reflections on the wet pavement. The lighting is cinematic and high-contrast, with the ambient neon signs of the city reflecting off the wet asphalt while the graphene hull remains an absolute, pitch-black void. The mood is dangerous, fast, and high-tech. Captured with a 35mm lens from a low, dynamic angle."
- **Negative prompt:** "daylight, bright, cheerful, rusty, vintage, colorful bodywork, soft"
- **Tags:** cyberpunk, vehicle, graphene, dark, neon
- **Style / Reference:** cinematic vehicle concept art, photorealistic rendering
- **Composition:** dynamic angled profile, low angle, neon reflections in foreground
- **Color palette:** matte pitch black graphene, glowing neon cyan, wet dark grey asphalt
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261230_graphene-motorcycle.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the rendering of highly light-absorbing materials (graphene) contrasted with intense neon emission in a dark environment.

### Suggestion: Mother of Pearl Neo-Gothic Library
- **Date:** 2026-12-30
- **Prompt:** "A sweeping, wide-angle interior shot of a majestic Neo-Gothic library where the soaring vaulted ceilings, intricate arches, and towering bookshelves are carved entirely from shimmering, iridescent Mother of Pearl. The architectural subject is lined with ancient, leather-bound books. The lighting is ethereal and soft, emanating from tall, stained-glass windows that cast multi-colored light across the pearlescent surfaces, revealing subtle pink and blue interference patterns in the nacre. The mood is sacred, intellectual, and breathtaking. Captured with a 14mm wide-angle lens, utilizing deep focus to capture the immense scale and detail of the ribbed vaults."
- **Negative prompt:** "stone, wood, dark, gritty, dystopian, messy, modern"
- **Tags:** architecture, interior, fantasy, mother of pearl, ethereal
- **Style / Reference:** grand architectural visualization, fantasy environment design
- **Composition:** symmetrical, deep perspective down the central aisle, low angle
- **Color palette:** pearlescent whites, soft pinks and baby blues, rich brown leather, stained glass colors
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261230_nacre-library.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for evaluating large-scale iridescent reflections and thin-film interference on complex historical architecture.

### Suggestion: Bioluminescent Deep-Sea Leviathan
- **Date:** 2024-05-18
- **Prompt:** "A colossal deep-sea leviathan gliding through a trench, illuminating the pitch-black abyss with glowing cyan and magenta bioluminescent stripes. The mood is eerie yet majestic. Low-key lighting with high-contrast glowing accents. Shot with a wide-angle 14mm lens perspective to emphasize the creature's immense scale."
- **Negative prompt:** "sunlight, shallow water, murky, lowres, ugly"
- **Tags:** underwater, monster, bioluminescent, deep-sea
- **Style / Reference:** photorealistic, cinematic
- **Composition:** wide shot, bottom-up angle
- **Color palette:** deep blacks, neon cyan, glowing magenta
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240518_leviathan.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing volumetric scattering in water and bioluminescence glow effects.

### Suggestion: Neon Synthwave Cyber-Dojo
- **Date:** 2024-05-18
- **Prompt:** "A futuristic cyber-dojo interior infused with 1980s synthwave aesthetics. Holographic training dummies flicker in the background. The mood is energetic and retro-futuristic. Illuminated by vibrant neon pink and grid-like laser lights. Shot with a 35mm lens, slight chromatic aberration."
- **Negative prompt:** "daylight, modern, boring, traditional"
- **Tags:** cyberpunk, synthwave, retro, dojo
- **Style / Reference:** 80s retro-futurism, digital art
- **Composition:** eye-level, rule of thirds
- **Color palette:** neon pink, electric blue, dark purple
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240518_cyber_dojo.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for neon lighting and retro/glitch shader tests.

### Suggestion: Ethereal Floating Zenith Monolith
- **Date:** 2024-05-18
- **Prompt:** "A massive, perfectly smooth obsidian monolith hovering silently above a tranquil sea of clouds at sunrise. The mood is serene and mystical. Soft, warm morning sunlight casts long, dramatic shadows. Captured with a 50mm lens, shallow depth of field focusing on the monolith."
- **Negative prompt:** "noisy, busy, people, cities, harsh lighting"
- **Tags:** surreal, minimalist, monolith, clouds
- **Style / Reference:** hyper-realistic, surrealism
- **Composition:** center-weighted, horizon at the lower third
- **Color palette:** soft pinks, golden oranges, deep obsidian black
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240518_zenith_monolith.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing ambient occlusion, soft lighting, and reflection shaders.

### Suggestion: Bioluminescent Fungal Rainforest
- **Date:** 2024-05-18
- **Prompt:** "A dense, ancient rainforest entirely overgrown with towering, glowing, alien mushrooms. The mood is magical and otherworldly. Dappled moonlight filters through the canopy, interacting with the intense neon greens and purples of the fungi. Shot with a macro 85mm lens, capturing fine spore particles floating in the air."
- **Negative prompt:** "daylight, normal trees, dry, low contrast"
- **Tags:** alien, rainforest, glowing, fantasy
- **Style / Reference:** digital illustration, highly detailed
- **Composition:** low angle, looking up into the canopy
- **Color palette:** neon green, deep purple, midnight blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240518_fungal_rainforest.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing subsurface scattering on organic shapes and particle effects.

### Suggestion: Quantum Singularity Observatory
- **Date:** 2024-05-18
- **Prompt:** "The interior of an advanced orbital observatory featuring a contained, swirling quantum singularity at its center. The mood is tense and awe-inspiring. Harsh, clinical white lights contrast against the violent, distorted light of the singularity. Shot with a fisheye lens to emphasize the gravitational warping."
- **Negative prompt:** "messy, chaotic, earth, ground"
- **Tags:** sci-fi, space, quantum, black-hole
- **Style / Reference:** hard sci-fi, cinematic lighting
- **Composition:** wide internal shot, symmetrical
- **Color palette:** stark white, deep void black, intense ultraviolet
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240518_quantum_observatory.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for gravitational lensing, distortion, and high-energy physics shaders.

### Suggestion: Holographic Cyber-Plantation
- **Date:** 2026-06-04
- **Prompt:** "A sprawling high-tech agricultural facility where rows of bioluminescent, semi-translucent synthetic crops are cultivated under towering holographic suns. The plants emit a soft, pulsating aqua glow. The environment is sterile but vibrant, mixing metallic chromes with organic neon hues. The lighting is dominated by the intense golden light of the artificial suns casting sharp shadows, contrasted by the cool blue underglow of the flora. Captured with a 35mm lens, wide cinematic shot to emphasize the massive scale of the facility."
- **Negative prompt:** "dirt, earth, traditional farming, daytime, sun, humans"
- **Tags:** cyberpunk, agriculture, neon, sci-fi
- **Style / Reference:** 3D concept art, hyper-detailed, futuristic
- **Composition:** wide shot, symmetrical perspective down the crop rows
- **Color palette:** aqua blue, glowing neon green, sterile chrome, vibrant golden holographic light
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260604_holographic_plantation.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing holographic emission and emissive organic materials.

### Suggestion: Crystal Cavern of the Chrono-Spider
- **Date:** 2026-06-04
- **Prompt:** "A massive, intricate web woven from shimmering threads of liquid time, spanning a vast underground cavern filled with jagged amethyst crystals. In the center sits a colossal, mechanical spider constructed from polished brass and glowing sapphire gears. The lighting is mysterious and subterranean, with the deep purple crystals illuminated from within, casting eerie violet reflections on the brass mechanics. The mood is ancient and dangerous. Shot from a low angle with a 24mm wide lens to emphasize the imposing size of the spider."
- **Negative prompt:** "natural spider, organic, daylight, simple, flat"
- **Tags:** fantasy, steampunk, underground, mystical
- **Style / Reference:** dark fantasy illustration, highly detailed, atmospheric
- **Composition:** low angle, dramatic perspective, central focus
- **Color palette:** deep amethyst purple, polished brass, glowing sapphire blue, pitch black shadows
- **Aspect ratio:** 4:3
- **Reference images:** `public/images/suggestions/20260604_chrono_spider_cavern.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests complex thin webs, crystal refraction, and metallic reflections in low light.

### Suggestion: Neon-Soaked Monsoon Market
- **Date:** 2026-06-04
- **Prompt:** "A dense, bustling Asian street market during a torrential monsoon downpour in a cyberpunk metropolis. Glowing neon signs in multiple languages reflect brightly off the wet pavement and the colorful plastic umbrellas of the crowd. Steam rises from noodle stands, mixing with the rain. The mood is chaotic, energetic, and atmospheric. Captured with a 50mm lens at a wide aperture (f/1.4) to create a beautiful bokeh effect in the background rain and neon lights."
- **Negative prompt:** "dry, sunny, daylight, clean, empty"
- **Tags:** cyberpunk, urban, rain, neon, night
- **Style / Reference:** cinematic street photography, photorealistic
- **Composition:** eye-level, busy foreground, shallow depth of field
- **Color palette:** neon pinks, electric blues, warm oranges, dark wet grays
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260604_monsoon_market.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing wet surface reflections, rain particle effects, and neon bloom.

### Suggestion: Ethereal Void-Jellyfish Migration
- **Date:** 2026-06-04
- **Prompt:** "A colossal migration of gargantuan, ethereal jellyfish swimming gracefully through a cosmic void that resembles a colorful nebula. Their translucent, bell-shaped bodies pulse with internal bioluminescence, trailing miles-long glowing tentacles. The environment is zero-gravity space filled with stardust. The lighting is soft and ambient, emanating entirely from the jellyfish and distant galaxies. The mood is tranquil, awe-inspiring, and majestic. Captured with a 14mm ultra-wide lens to capture the vastness of the swarm."
- **Negative prompt:** "ocean, water, underwater, rocks, sea"
- **Tags:** space, cosmic, surreal, bioluminescent, majestic
- **Style / Reference:** cosmic digital art, surrealism, hyper-detailed
- **Composition:** wide expansive shot, diagonal movement
- **Color palette:** cosmic purples, glowing cyan, deep space black, magenta stardust
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20260604_void_jellyfish.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for evaluating large-scale translucency, soft glowing volumetrics, and particle stardust.

### Suggestion: Molten Glass Foundry of the Fire Giants
- **Date:** 2026-06-04
- **Prompt:** "The intense, sweltering interior of a colossal foundry where towering fire giants forge massive weapons out of glowing, semi-solid molten glass instead of metal. Huge crucibles pour thick, radiant liquid glass that illuminates the dark, soot-stained stone walls. The lighting is extremely high-contrast, dominated by the blinding white-hot and deep orange glow of the molten glass against the pitch-black shadows of the cavern. The mood is epic, hostile, and intensely hot. Captured with an 85mm lens, focusing on the molten glass being hammered, with sparks flying."
- **Negative prompt:** "cold, blue, daylight, clean, metal, modern"
- **Tags:** fantasy, epic, industrial, fire, glowing
- **Style / Reference:** epic fantasy concept art, dramatic chiaroscuro
- **Composition:** close-up on action, dynamic diagonal lines, intense contrast
- **Color palette:** blinding white, intense molten orange, deep red, soot black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260604_molten_glass_foundry.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing high-intensity emissive materials, extreme contrast, and glass refraction properties under intense heat.


### Agent Suggestion: Steampunk Botanist Laboratory — @ai-agent — 2026-06-15
- **Date:** 2026-06-15
- **Prompt:** "A cluttered steampunk botanist laboratory lit by warm golden sunlight streaming through dirty skylights. Brass pipes, glowing glass terrariums filled with luminescent flora, and intricate clockwork mechanisms. The mood is cozy yet mysterious."
- **Negative prompt:** "modern, clean, minimal, cold light"
- **Tags:** steampunk, laboratory, botany, glowing
- **Style / Reference:** highly detailed, cinematic lighting
- **Composition:** wide shot, cluttered foreground
- **Color palette:** warm gold, brass, vibrant green and teal
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260615_steampunk-lab.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing warm/cool color contrasts and complex textures.

### Agent Suggestion: Abandoned Cyberpunk Subway — @ai-agent — 2026-06-15
- **Date:** 2026-06-15
- **Prompt:** "An abandoned cyberpunk subway station flooded with shallow water. Flickering neon signs reflect vividly in the dark water. Overgrown bioluminescent fungi cling to rusted pillars. Dark and atmospheric, with cinematic shadow contrasts."
- **Negative prompt:** "people, clean, bright, daytime"
- **Tags:** cyberpunk, ruins, neon, reflection
- **Style / Reference:** photorealistic, moody
- **Composition:** one-point perspective, low angle
- **Color palette:** deep blues, neon pink, electric cyan
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260615_cyberpunk-subway.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing wet reflections, neon glow, and water rippling shaders.

### Agent Suggestion: Ethereal Floating Castle — @ai-agent — 2026-06-15
- **Date:** 2026-06-15
- **Prompt:** "A majestic ethereal castle floating amidst sea of soft, pastel-colored clouds at sunrise. The architecture is delicate and translucent, made of magical crystal and white marble. Gentle rays of light pierce the mist."
- **Negative prompt:** "dark, ominous, ground, modern"
- **Tags:** fantasy, architecture, floating, ethereal
- **Style / Reference:** dreamlike, fantasy illustration
- **Composition:** wide establishing shot
- **Color palette:** soft pinks, lavender, white, pale gold
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260615_ethereal-castle.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing volumetric lighting, god rays, and cloud shaders.

### Agent Suggestion: Alien Bioluminescent Coral Reef — @ai-agent — 2026-06-15
- **Date:** 2026-06-15
- **Prompt:** "A close-up view of an alien coral reef on another planet. The water is crystal clear but dark, illuminated solely by the intense bioluminescence of exotic, fractal-shaped sea creatures and swaying flora."
- **Negative prompt:** "earthly, dull, murky, surface"
- **Tags:** macro, underwater, alien, bioluminescence
- **Style / Reference:** macro photography, high contrast
- **Composition:** close-up, shallow depth of field
- **Color palette:** neon green, deep purple, glowing orange
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260615_alien-coral.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing refraction, caustic effects, and glowing elements.

### Agent Suggestion: Neon Samurai in Rain — @ai-agent — 2026-06-15
- **Date:** 2026-06-15
- **Prompt:** "A futuristic samurai warrior standing in an alley during a heavy downpour. Their armor is sleek black with glowing crimson accent lines. The rain splashes off their neon-lit katana. High contrast, dramatic backlighting."
- **Negative prompt:** "sunny, cartoon, flat, simple"
- **Tags:** cyberpunk, samurai, rain, neon
- **Style / Reference:** cinematic, neo-noir
- **Composition:** low angle, rule of thirds
- **Color palette:** crimson, deep black, cold blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260615_neon-samurai.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for testing rain particles, wet surfaces, and dramatic lighting.

### Suggestion: Bioluminescent Aether-Jellyfish Swarm
- **Date:** 2026-06-20
- **Prompt:** "A mesmerizing, hyper-organic deep-space ocean teeming with a swarm of ethereal, semi-transparent jellyfish woven from luminous aether-plasma. The jellyfish propel themselves rhythmically in sync. The lighting is cinematic volumetric bioluminescence, with deep indigo background and glowing cyan and purple tentacles. The mood is tranquil and otherworldly. Captured with an ultra-wide 12mm lens to show the vastness of the space."
- **Negative prompt:** "earth, water, realistic sea, murky, blurry, low contrast"
- **Tags:** sci-fi, space, bioluminescence, glowing, ethereal
- **Style / Reference:** 3D digital art, hyper-detailed, octane render
- **Composition:** ultra-wide shot, vast perspective
- **Color palette:** deep indigo, cyan, glowing purple
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260620_aether-jellyfish.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing volumetric plasma, soft glowing materials, and underwater/space blend.

### Suggestion: Neon-Plasma Biomechanical Hive
- **Date:** 2026-06-20
- **Prompt:** "A hyper-organic, biomechanical labyrinth of pulsing neon circuitry and breathing metallic tissue that spawns luminescent plasma-spores. The lighting features intense neon pink and toxic green rim lights against a dark metallic environment. The mood is intense, alien, and cybernetic. Captured with a macro 90mm lens focusing on the intricate glowing nodes and creeping metallic tendrils."
- **Negative prompt:** "clean, modern, minimalist, daytime, sunlight, flat"
- **Tags:** cyberpunk, biomechanical, neon, macro, organic
- **Style / Reference:** H.R. Giger inspired, dark sci-fi, photorealistic macro
- **Composition:** macro close-up, shallow depth of field
- **Color palette:** neon pink, toxic green, dark gunmetal
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20260620_biomechanical-hive.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex normal maps, emissive textures, and high contrast.

### Suggestion: Eldritch-Quantum Fractal-Eye
- **Date:** 2026-06-20
- **Prompt:** "A colossal, hyper-dimensional eye constructed from infinitely folding quantum fractals and liquid plasma, constantly shifting its non-Euclidean iris geometry. The lighting is ethereal and multidirectional, emanating from the eye's core with bright golden and piercing blue hues. The mood is cosmic, terrifying, and awe-inspiring. Captured with a cinematic 35mm lens, centered symmetrically."
- **Negative prompt:** "human eye, realistic, simple, blurry, low resolution"
- **Tags:** cosmic, abstract, fractal, surreal, glowing
- **Style / Reference:** surrealist digital painting, mathematical fractals
- **Composition:** perfectly symmetrical, centered
- **Color palette:** piercing blue, bright gold, cosmic black
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20260620_fractal-eye.jpg`
- **License / Attribution:** CC0
- **Notes:** Use this for testing extreme geometric distortion, mathematical fractals, and intense glow effects.

### Suggestion: Celestial Nanite-Swarm Nebula
- **Date:** 2026-06-20
- **Prompt:** "A majestic, slowly churning nebula constructed entirely from trillions of glowing, synchronized nanites that dynamically self-assemble into intricate, shifting geometric constellations and colossal architectural megastructures in deep space. The lighting is an epic astronomical bloom with starlight refracting through the nanite clouds. The mood is epic, vast, and silent. Captured with a deep space telescope style, high magnification."
- **Negative prompt:** "planets, ships, realistic gas clouds, mundane"
- **Tags:** sci-fi, nebula, nanites, space, geometric
- **Style / Reference:** astrophotography, sci-fi concept art
- **Composition:** vast landscape, majestic scale
- **Color palette:** deep space black, shimmering silver, glowing amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260620_nanite-nebula.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing particle systems and enormous scale.

### Suggestion: Cyber-Organic Liquid-Neon Pulsar
- **Date:** 2026-06-20
- **Prompt:** "A biomechanical, pulsating celestial core composed of hyper-viscous liquid-neon and crystalline techno-organic fibers that rhythmically contract, dilate, and emit intense volumetric light bursts. The lighting is violently bright, radiating from the core with blinding magenta and cyan flares against an absolute void. The mood is energetic, dangerous, and pulsating. Captured with a 50mm lens with dramatic lens flares."
- **Negative prompt:** "soft, calm, pastel, low contrast, natural"
- **Tags:** cyberpunk, core, glowing, viscous, energy
- **Style / Reference:** hyper-realistic 3D render, futuristic energy
- **Composition:** centered subject, dynamic energy bursts
- **Color palette:** blinding magenta, bright cyan, absolute black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20260620_liquid-neon-pulsar.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for extreme volumetric lighting, flares, and liquid distortion testing.


### Suggestion: Brass Solarpunk Airship
- **Date:** 2026-12-31
- **Prompt:** "A majestic, highly detailed solarpunk airship floating above a sprawling, green utopian metropolis at sunrise. The airship features a massive balloon made of semi-translucent, glowing graphene fabric and a gondola constructed from polished brass and lush, hanging hydroponic gardens. The lighting is soft, warm morning sunlight, casting long, volumetric golden rays that catch the intricate brass details and reflect off the morning mist. The mood is peaceful, optimistic, and grand. Captured with an ultra-wide 14mm lens from a slightly lower altitude to emphasize the ship's massive scale against the bright, clear sky."
- **Negative prompt:** "dystopian, dark, grim, polluted, ugly, blurry, low resolution, rusty"
- **Tags:** solarpunk, sci-fi, architecture, brass, bright
- **Style / Reference:** utopian concept art, photorealistic 3D render
- **Composition:** wide expansive view, rule of thirds, dynamic angle
- **Color palette:** warm golden sunlight, lush vibrant greens, polished brass, sky blue
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261231_brass-solarpunk-airship.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for testing intricate metallic details combined with lush organic elements and soft, volumetric morning light.

### Suggestion: Graphene Cyberpunk Hacker Desk
- **Date:** 2026-12-31
- **Prompt:** "An intensely cluttered, dark cyberpunk hacker's desk late at night, featuring multiple glowing holographic displays projecting complex data structures. The desk itself and the surrounding server racks are built from sleek, light-absorbing matte black graphene. The lighting is high-contrast, entirely diegetic, emanating from the neon cyan and magenta holograms which cast sharp, colorful reflections on scattered energy drink cans, while the graphene surfaces remain pitch black. The mood is intense, secretive, and high-tech. Captured with a 35mm lens, shallow depth of field focusing on the intricate holographic code while the background blurs into dark bokeh."
- **Negative prompt:** "daylight, clean, minimalist, bright, sunny, soft, plain"
- **Tags:** cyberpunk, interior, dark, neon, graphene
- **Style / Reference:** cyberpunk cinematic concept art, photorealistic macro
- **Composition:** medium close-up, cluttered foreground, shallow depth of field
- **Color palette:** matte pitch black graphene, glowing neon cyan, intense magenta
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261231_graphene-hacker-desk.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for testing light-absorbing matte materials (graphene) contrasted with intense, multi-colored neon emission and cluttered micro-details.

### Suggestion: Bismuth Cybernetic Dragon
- **Date:** 2026-12-31
- **Prompt:** "A colossal, terrifying cybernetic dragon perched on the jagged peak of a frozen mountain. The dragon's armor is composed entirely of giant, interlocking hopper crystals of iridescent bismuth, while its joints and wings reveal glowing, superheated plasma engines. The lighting is dramatic and harsh, with the glowing orange plasma illuminating the blinding white snow below and catching the multi-colored, metallic rainbow facets of the bismuth scales against a dark, stormy night sky. The mood is epic, aggressive, and majestic. Captured with a wide 24mm lens from a low angle to exaggerate the dragon's imposing size and sharp geometry."
- **Negative prompt:** "organic scales, flesh, daytime, soft, cartoon, friendly, blurry"
- **Tags:** fantasy, sci-fi, dragon, bismuth, epic
- **Style / Reference:** dark fantasy concept art, photorealistic creature design
- **Composition:** low angle looking up, dramatic silhouette, towering presence
- **Color palette:** iridescent pinks/blues/golds, glowing plasma orange, stark white snow, dark storm grey
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261231_bismuth-dragon.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the integration of complex, geometric hopper crystals (bismuth) onto a complex, organic-shaped creature model with intense internal lighting.

### Suggestion: Mother of Pearl Victorian Conservatory
- **Date:** 2026-12-31
- **Prompt:** "A breathtaking, surreal interior of a vast Victorian botanical conservatory where the elaborate, curved wrought-iron framework and the decorative floor tiles are carved entirely from shimmering, iridescent Mother of Pearl. The architectural subject is filled with lush, exotic alien flora. The lighting is soft and ethereal, filtering down from the massive glass dome above, catching the micro-ridges of the nacre to throw prismatic rainbow highlights across the humid, misty air. The mood is romantic, elegant, and otherworldly. Captured with an ultra-wide 12mm lens, utilizing deep focus to capture the immense scale and intricate pearlescent arches."
- **Negative prompt:** "dark, scary, rusty iron, ordinary plants, lowres, flat lighting"
- **Tags:** architecture, interior, fantasy, mother of pearl, botanical
- **Style / Reference:** grand architectural visualization, fantasy environment design
- **Composition:** symmetrical, deep perspective down the central walkway
- **Color palette:** pearlescent whites, soft pinks and blues, vibrant lush greens
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261231_nacre-conservatory.jpg`
- **License / Attribution:** CC0
- **Notes:** Perfect for evaluating large-scale iridescent reflections and thin-film interference on complex, curved Victorian architecture.

### Suggestion: Aerogel Deep Space Telescope
- **Date:** 2026-12-31
- **Prompt:** "A massive, futuristic deep-space telescope drifting silently in orbit around a brilliant blue gas giant. The massive hexagonal mirror segments and the supporting truss structure are constructed from ultra-lightweight, translucent blue aerogel. The lighting is breathtaking, with the glaring, unattenuated light from a distant star piercing through the porous aerogel structures, creating soft, glowing internal refractions and casting sharp, dark shadows across the gas giant below. The mood is serene, vast, and highly advanced. Captured from a dynamic angle in low orbit, emphasizing the delicate, ghostly nature of the telescope against the massive planet."
- **Negative prompt:** "solid metal, opaque, noisy, chaotic, earth, atmosphere, low quality"
- **Tags:** sci-fi, space, technology, aerogel, ethereal
- **Style / Reference:** cinematic space art, photorealistic sci-fi hardware
- **Composition:** dynamic diagonal framing, vast background, stark contrast
- **Color palette:** translucent ghostly blue, blinding starlight white, deep cosmic black, rich azure
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20261231_aerogel-telescope.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing large-scale structures made of highly scattering, incredibly low-density translucent materials (aerogel) under harsh cosmic lighting.


### Suggestion: Italian Futurism Volcanic Eruption
- **Date:** 2026-12-31
- **Prompt:** "A chaotic, dynamic scene of a massive volcanic eruption depicted in the harsh, fragmented style of Italian Futurism. The erupting volcano and flying debris are deconstructed into aggressive, jagged diagonal lines and overlapping geometric planes radiating outward to capture the immense speed and mechanical energy of the explosion. The lighting is dramatic and directional, casting stark, jagged shadows that enhance the dynamic, splintered geometry of the composition. The mood is energetic, aggressive, and overpowering. Captured with a dynamic, tilted perspective to emphasize raw motion and violent speed."
- **Negative prompt:** "calm, horizontal, photorealistic, soft curves, gentle, natural water, peaceful, realistic lava"
- **Tags:** abstract, art, italian futurism, speed, dynamic, volcano
- **Style / Reference:** Italian Futurism art movement, Umberto Boccioni inspired
- **Composition:** dynamic diagonals, fragmented planes, tilted angle
- **Color palette:** steel greys, harsh rusted reds, fiery oranges, stark black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261231_futurism-volcano.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to apply the aggressive, dynamic abstraction of Italian Futurism to convey a cataclysmic natural event.

### Suggestion: Ashcan School Mother of Pearl Beehive
- **Date:** 2026-12-31
- **Prompt:** "A bustling, gritty early 20th-century street scene depicted in the Ashcan School art style, but the central focus is a massive, shimmering Mother of Pearl beehive attached to a brick tenement building. The subject features working-class pedestrians ignoring the fantastical structure. The lighting is overcast and realistic, casting soft, murky shadows that highlight the dirt and texture of the urban environment, contrasting with the iridescent, pearlescent glow of the nacre beehive. The mood is authentic, raw, and surreal. Captured with an eye-level, documentary-style perspective, emphasizing the unglamorous reality of the city juxtaposed with the ethereal hive."
- **Negative prompt:** "modern, bright, cheerful, clean, sci-fi, highly saturated, glossy, 3d render, anime, natural forest"
- **Tags:** art, city, historical, ashcan school, gritty, surreal, mother of pearl
- **Style / Reference:** Ashcan School painting, George Bellows inspired, thick brushstrokes, surrealism
- **Composition:** eye-level, crowded street, naturalistic framing, off-center subject
- **Color palette:** muted browns, dark greys, dull reds, pearlescent whites, soft pinks and baby blues
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261231_ashcan-nacre-beehive.jpg`
- **License / Attribution:** CC0
- **Notes:** Good for testing gritty, unidealized urban scenes blended with highly iridescent, surreal organic structures.

### Suggestion: Graphene Bioluminescent Reef
- **Date:** 2026-12-31
- **Prompt:** "A breathtaking, ultra-wide underwater landscape showcasing a sprawling coral reef constructed entirely from light-absorbing, matte black graphene. The dark, geometric graphene structures are heavily populated by intensely glowing, bioluminescent flora in vivid neon cyan and magenta. The lighting is entirely diegetic, radiating from the luminescent plants and reflecting off tiny, silver-scaled fish, while the graphene remains pitch black. The mood is alien, beautiful, and deeply mysterious. Captured with a 14mm ultra-wide lens to emphasize the vast, sweeping scale of the dark, glowing ecosystem."
- **Negative prompt:** "sunlight, daylight, bright surface, natural coral, sand, murky water, low resolution"
- **Tags:** underwater, sci-fi, landscape, graphene, bioluminescent
- **Style / Reference:** cinematic deep-sea exploration, high-contrast digital art
- **Composition:** wide landscape, deep perspective, rule of thirds
- **Color palette:** matte pitch black, neon cyan, vibrant magenta, bright silver
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261231_graphene-reef-2.jpg`
- **License / Attribution:** CC0
- **Notes:** Challenges the model to contrast intensely bright emissive materials against completely light-absorbing, matte geometric structures.

### Suggestion: Cinematic Aerogel Tsunami
- **Date:** 2026-12-31
- **Prompt:** "A massive, towering tsunami wave frozen in time, constructed entirely from weightless, translucent blue aerogel. The delicate, porous subject curves gracefully, catching bright, ethereal sunlight that scatters inside the low-density aerogel to create a mesmerizing internal glow and millions of soft refractions. The ocean below is dark and moody, contrasting with the luminous, ghost-like wave. The sky is clear and bright, providing stark, cinematic lighting. The mood is surreal, majestic, and terrifying. Captured with a low camera angle and wide lens to emphasize the towering height of the ghostly wave."
- **Negative prompt:** "water, liquid, splash, foam, ordinary, realistic ocean, dark sky, heavy, solid ice"
- **Tags:** fantasy, nature, surreal, ethereal, aerogel, tsunami
- **Style / Reference:** surrealism, 3D abstract render, photorealistic lighting
- **Composition:** imposing, low angle, wave dominating the frame
- **Color palette:** translucent ghostly blue, pale cyan, stark white sunlight, deep ocean blue
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20261231_aerogel-tsunami.jpg`
- **License / Attribution:** CC0
- **Notes:** Useful for generating smooth, massive organic shapes with subsurface scattering and highly translucent, low-density materials.

### Suggestion: Damascus Steel Exoplanet Core
- **Date:** 2026-12-31
- **Prompt:** "A colossal, surreal visualization deep within the core of a massive exoplanet, where the crushing pressure has formed an ocean of rippling, liquid Damascus steel. The subject features immense, flowing metallic waves showcasing intricate, woodgrain-like patterns of dark and light silver. The lighting is terrifyingly intense and internal, erupting from deep, glowing fissures of molten amber and white-hot energy that cast sharp, glaring highlights across the complex metallic ridges. The mood is oppressive, alien, and awe-inspiring. Captured with an extreme wide-angle 14mm lens to encompass the vast, churning scale of the planetary core."
- **Negative prompt:** "soft, organic, earth-like, calm, daylight, water, blurry, low resolution, solid rock"
- **Tags:** sci-fi, space, landscape, damascus steel, exoplanet
- **Style / Reference:** cinematic sci-fi environment design, photorealistic material rendering
- **Composition:** wide expansive view, chaotic flowing lines, deep perspective
- **Color palette:** dark metallic grays, polished silver, blinding white-hot core, glowing amber
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20261231_damascus-core.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating the complex, flowing texture generation of Damascus steel mapped onto massive, churning fluid dynamics under extreme lighting.

### Suggestion: Quantum Glass Bonsai Tree
- **Date:** 2024-05-18
- **Prompt:** "A serene, hyper-dimensional bonsai tree woven entirely from shimmering quantum hard-light and refractive quantum glass. The bonsai rests on a floating pedestal of dark obsidian in a volumetric dark-matter void. The lighting is soft, ethereal, and internally glowing, highlighting the branching structures that continuously fracture and self-assemble. The mood is tranquil, probabilistic, and magical. Captured with a 50mm portrait lens, featuring a shallow depth of field and beautiful glowing bokeh."
- **Negative prompt:** "organic, wood, leaves, soil, dirt, bright sunlight, harsh shadows, low resolution, blurry"
- **Tags:** sci-fi, surreal, bonsai, quantum, ethereal
- **Style / Reference:** hyper-detailed 3D render, holographic projection, magical realism
- **Composition:** centered subject, eye-level, shallow depth of field
- **Color palette:** glowing cyan, iridescent pink, deep obsidian black, ethereal white
- **Aspect ratio:** 4:5
- **Reference images:** `public/images/suggestions/20240518_quantum-bonsai.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating glass refraction, internal glow, and complex branching structures.

### Suggestion: Neon-Plasma Biomechanical Scarab
- **Date:** 2024-05-18
- **Prompt:** "A hyper-organic, biomechanical scarab beetle constructed from sleek, interlocking plates of liquid obsidian and glowing quantum circuitry. The scarab is perched on a massive, glowing neon-pink lotus flower. The lighting features intense neon pink and toxic green rim lights against a dark metallic environment, showcasing the pulsating plasma-spores emitting from the beetle's joints. The mood is intense, alien, and cybernetic. Captured with a macro 90mm lens focusing on the intricate glowing nodes and creeping metallic tendrils."
- **Negative prompt:** "natural beetle, organic, daytime, sunlight, flat lighting, lowres, soft, simple"
- **Tags:** cyberpunk, biomechanical, scarab, macro, glowing
- **Style / Reference:** dark sci-fi, photorealistic macro photography, biopunk concept art
- **Composition:** macro close-up, shallow depth of field, rule of thirds
- **Color palette:** neon pink, toxic green, glossy pitch black, glowing amber
- **Aspect ratio:** 1:1
- **Reference images:** `public/images/suggestions/20240518_neon-scarab.jpg`
- **License / Attribution:** CC0
- **Notes:** Excellent for testing complex normal maps, emissive textures, and high contrast lighting.

### Suggestion: Holographic Art Nouveau Library
- **Date:** 2024-05-18
- **Prompt:** "An exquisite, wide-angle interior shot of a majestic Art Nouveau library where the sweeping curves, whiplash lines, and elegant arches are formed entirely from glowing, translucent holographic data streams. The floating bookshelves are filled with luminescent, floating data-crystals. The lighting is magical and completely diegetic, emitting soft neon blues and pulsing gold from the holograms against the dark void. The mood is romantic, intellectual, and cyber-ethereal. Captured with a 14mm wide-angle lens, utilizing deep focus to capture the immense scale and elegant organic curves."
- **Negative prompt:** "wood, stone, straight lines, brutalist, daylight, bright, messy, modern"
- **Tags:** cyberpunk, architecture, interior, holographic, art nouveau
- **Style / Reference:** holographic architectural visualization, cyber-ethereal concept art
- **Composition:** sweeping curves leading the eye, symmetrical balance, wide expansive view
- **Color palette:** ethereal glowing blue, rich warm gold, deep cosmic black
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240518_holographic-library.jpg`
- **License / Attribution:** CC0
- **Notes:** Tests the AI's ability to naturally form specific architectural styles (Art Nouveau curves) out of glowing, non-solid holographic materials.

### Suggestion: Bioluminescent Deep-Sea Train
- **Date:** 2024-05-18
- **Prompt:** "A majestic, heavily armored steampunk train traveling along tracks laid across the deep ocean floor. The train is covered in overgrown, glowing bioluminescent coral and glowing anemones in vivid neon cyan and magenta. The lighting is entirely diegetic, radiating from the train's intense amber headlights cutting through the murky water and the luminescent marine life growing on its hull. The mood is mysterious, adventurous, and alien. Captured with a wide-angle perspective from the ocean floor, showcasing the crushing depth and scale of the dark, glowing machine."
- **Negative prompt:** "surface, daylight, sky, modern train, clean metal, realistic fish, dry"
- **Tags:** underwater, steampunk, vehicle, bioluminescent, deep-sea
- **Style / Reference:** cinematic deep-sea exploration, steampunk concept art
- **Composition:** dynamic angled profile, leading lines from tracks, wide shot
- **Color palette:** deep ocean black, glowing amber, neon cyan, vibrant magenta
- **Aspect ratio:** 21:9
- **Reference images:** `public/images/suggestions/20240518_bioluminescent-train.jpg`
- **License / Attribution:** CC0
- **Notes:** Great for evaluating the combination of heavy, rusty steampunk machinery with intense, colorful bioluminescent organic growth.

### Suggestion: Ethereal Chrono-Crystal Cavern
- **Date:** 2024-05-18
- **Prompt:** "A vast subterranean cavern filled with colossal, floating geometric crystals made of refractive chrono-glass. Inside the giant transparent crystals, frozen moments of time are visible—like suspended water droplets and frozen lightning. A glowing underground river weaves through the geometric structures, reflecting their faceted colors. The lighting is ethereal and internal, emanating from the glowing crystals and the liquid silver river. The mood is magical, untouched, and serene. Captured with a deep depth of field to capture the endless frozen reflections and the dynamic flow of the cavern."
- **Negative prompt:** "ordinary rock, daylight, sunlight, dirt, organic plants, people, blurry, flat lighting"
- **Tags:** fantasy, landscape, crystal, ethereal, subterranean
- **Style / Reference:** fantasy environment design, photorealistic 3D render, surreal landscape
- **Composition:** wide landscape, deep perspective, river creating a leading line
- **Color palette:** iridescent purple and green, glowing cyan, liquid silver, dark cavern shadows
- **Aspect ratio:** 16:9
- **Reference images:** `public/images/suggestions/20240518_chrono-crystal-cavern.jpg`
- **License / Attribution:** CC0
- **Notes:** Ideal for evaluating sharp geometric rendering, complex refractions, and floating, gravity-defying structures.

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
- **Styles:** Ashcan School
- **Materials:** Brass, Bismuth, Mother of Pearl. Graphene.
- **Subjects:** Tsunami, Exoplanet Core, Beehive, Beaver Dam, Orbital Ring
- **Styles:** Ashcan School.
- **Materials:** Brass, Bismuth, Mother of Pearl.
- **Subjects:** Supernova, Exoplanet Core, Fireworks, Volcanic Eruption, Tsunami, Beehive, Beaver Dam, Orbital Ring
- **Styles:** Italian Futurism.
- **Materials:** Brass, Bismuth, Mother of Pearl, Tweed, Aerogel, Damascus Steel. Graphene.
- **Subjects:** Tsunami, Bioluminescent Reef, Orbital Ring,
- **Styles:** Italian Futurism.
- **Materials:** Brass, Bismuth, Mother of Pearl, Tweed.
- **Subjects:** Supernova, Bioluminescent Reef, Fireworks, Volcanic Eruption, Tsunami, Orbital Ring,

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
