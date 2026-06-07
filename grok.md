# grok.md — Grok AI Assistant Guide for image_video_effects

> Read this first.

## Project Overview
**image_video_effects** is a growing collection of real-time image and video effects powered by WebGPU compute shaders. It’s an experimental playground for creative GPU-accelerated visuals.

- **Live Demo**: https://go.1ink.us/pixelocity/index.html
- **Focus**: Mouse-reactive effects, compute shaders, bloom, color manipulation, and video processing.

## Technology Stack
- TypeScript + Vite
- WebGPU (WGSL compute + fragment shaders)
- Likely HTML5 video + canvas for input

## Grok Guidelines
- **Compute Shader First**: Leverage WebGPU compute for performance-heavy effects.
- **Interactivity**: Mouse position, time, audio, or other inputs should drive the effects.
- **Visual Wow Factor**: Prioritize beautiful, surprising, or hypnotic results.
- **Modularity**: Make it easy to add new effects or chain them.
- **Performance**: Keep effects running smoothly at 60fps even on mid-range GPUs.

## Common Tasks
- Add new effects (glitch, kaleidoscope, displacement, color grading, etc.)
- Improve video handling and real-time processing
- Add UI controls for parameters
- Optimize shaders and reduce GPU load
- Experiment with post-processing pipelines

This is a fantastic creative sandbox. Let’s keep expanding the library of mind-bending effects! 🌈✨