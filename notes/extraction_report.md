# Shader Parameters Extraction Report

## Summary Statistics

| Metric | Value |
|--------|-------|
| Total JSON files found | 688 |
| Total shaders extracted | 693 |
| Shaders with params | 588 |
| Categories covered | 14 |

## Categories

- **artistic**: 20 shaders (20 with params)\n- **distortion**: 32 shaders (31 with params)\n- **generative**: 105 shaders (78 with params)\n- **geometric**: 9 shaders (8 with params)\n- **image**: 405 shaders (348 with params)\n- **interactive**: 38 shaders (36 with params)\n- **interactive-mouse**: 1 shaders (1 with params)\n- **lighting-effects**: 9 shaders (5 with params)\n- **liquid**: 3 shaders (2 with params)\n- **liquid-effects**: 4 shaders (4 with params)\n- **post-processing**: 6 shaders (6 with params)\n- **retro-glitch**: 13 shaders (12 with params)\n- **simulation**: 30 shaders (21 with params)\n- **visual-effects**: 18 shaders (16 with params)\n
## Sample Extracted Data

```json
{
  "audio-voronoi-displacement": {
    "category": "distortion",
    "params": [
    {
        "id": "cell_count",
        "name": "Cell Count",
        "default": 0.3,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.x",
        "description": "Number of Voronoi cells"
    },
    {
        "id": "audio_reactivity",
        "name": "Audio Reactivity",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.y",
        "description": "How much audio affects the cells"
    },
    {
        "id": "displacement",
        "name": "Displacement Strength",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.z",
        "description": "Strength of displacement effect"
    },
    {
        "id": "color_intensity",
        "name": "Color Intensity",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.w",
        "description": "Intensity of frequency-based coloring"
    }
]
  },
  "cellular-automata-3d": {
    "category": "generative",
    "params": [
    {
        "id": "evolution_speed",
        "name": "Evolution Speed",
        "default": 0.3,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.x",
        "description": "Speed of CA evolution"
    },
    {
        "id": "initial_density",
        "name": "Initial Density",
        "default": 0.3,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.y",
        "description": "Initial cell density"
    },
    {
        "id": "color_cycling",
        "name": "Color Cycling",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.z",
        "description": "Speed of color cycling"
    },
    {
        "id": "camera_rotation",
        "name": "Camera Rotation",
        "default": 0.0,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.w",
        "description": "Camera rotation speed"
    }
]
  },
  "chromatic-reaction-diffusion": {
    "category": "artistic",
    "params": [
    {
        "id": "red_feed",
        "name": "Red Feed Rate",
        "default": 0.4,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.x",
        "description": "Feed rate for red channel"
    },
    {
        "id": "green_feed",
        "name": "Green Feed Rate",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.y",
        "description": "Feed rate for green channel"
    },
    {
        "id": "blue_feed",
        "name": "Blue Feed Rate",
        "default": 0.6,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.z",
        "description": "Feed rate for blue channel"
    },
    {
        "id": "chromatic_sep",
        "name": "Chromatic Separation",
        "default": 0.5,
        "min": 0.0,
        "max": 1.0,
        "step": 0.01,
        "mapping": "zoom_params.w",
        "description": "Amount of chromatic aberration"
    }
]
  }
}
```

## Parameter Schema

Each parameter object contains:
- `id`: Parameter identifier (string)
- `name`: Display name (string)
- `default`: Default value (number)
- `min`: Minimum value (number)
- `max`: Maximum value (number)
- `step`: Step increment (number, optional)
- `mapping`: WGSL uniform mapping (string, optional)
- `description`: Parameter description (string, optional)

## Output File

Extracted data saved to: `shader_params_extracted.json`
