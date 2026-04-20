# Organizing Shaders

The repository currently ships with over 500 shader effects and the UI presents them in a single HTML dropdown. As the library grows the list becomes unwieldy for users. This document proposes a high–level plan to improve shader organization as well as a more advanced shader panel that would coexist with (or eventually replace) the current dropdown.

## Goals

1. **Improve discoverability** – users should be able to browse by category and features.
2. **Reduce visual clutter** – long flat lists are hard to scan and navigate.
3. **Provide editing/test harness** – allow adjusting parameters and selecting shaders without leaving the canvas.
4. **Maintain backwards compatibility** – existing dropdown should still work until we transition fully.
5. **Enable future UI enhancements** – e.g. search, favorites, AI VJ tags, previews.

## Proposed Structure

### 1. Nested menu / sub‑menus

- **Top-level categories** match the JSON categories already defined (`liquid-effects`, `interactive-mouse`, etc.).
- Each category becomes a menu header or accordion section, opening to show its shaders.
- Optionally, secondary grouping based on tags/feature flags ("depth-aware", "mouse-driven", "glitch", etc.).
- Implement as a custom React component or use an existing UI library (the project currently uses plain HTML/React so a lightweight accordion is ideal). 

### 2. Shader panel alongside the canvas

- A side panel or overlay displaying:
  - **Shader selection tree** (reflecting nested menu structure).
  - **Parameter sliders** for the currently selected shader (up to 4, already supported by metadata). Sliders update `zoom_params` in `u` uniforms.
  - **Search/filter bar** to quickly find shaders by name, tag, or ID.
  - **Preview thumbnail** (optional, could be a small canvas rendering the effect).
  - **Depth/Toggles** for optional features (e.g. depth enable, multi-pass options).
- Panel should be responsive and hideable/collapsible.

### 3. Data changes

- No change to existing `shader_definitions` JSON schema, but include new `tags` and `features` consistently if not already.
- Consider generating a category index object in `scripts/generate_shader_lists.js` to support UI grouping, e.g.:
  ```js
  {
    "liquid-effects": ["ink-drop", "viscous-flow", ...],
    "interactive-mouse": [...],
    ...
  }
  ```
- Add metadata for each shader to help frontend sort into subgroups (e.g. `tags: ["depth-aware"]`).

### 4. Implementation steps

1. **Prototype menu component**
   - Create `src/components/ShaderMenu.tsx` (or similar) with nested lists/accordion.
   - Populate from combined shader list JSON (`public/shader-lists/*`) or new index.
   - Keep old dropdown in parallel while testing.
2. **Parameter UI**
   - Extend `Controls.tsx` or create a new `ShaderControls` panel.
   - Map `currentShader.params` to sliders, updating global state.
3. **Search/filter**
   - Add text input that filters the menu tree by name or tag.
   - Could be simple substring match initially.
4. **Styling and layout**
   - Create CSS rules in `src/style.css` for the panel.
   - Make panel togglable via a button (e.g. a gear icon or "Shaders" button). 
5. **Accessibility & keyboard navigation**
   - Ensure the menu can be navigated with arrow keys for accessibility.
6. **Gradual rollout**
   - Keep existing dropdown until panel is stable.
   - Provide a setting to toggle between dropdown and panel.

### 5. Future Enhancements

- **Shader thumbnails** generated offline or at runtime.
- **Favorites and history**.
- **AI‑driven suggestions** using existing tags and features.
- **Drag‑and‑drop stacking** to reorder multi‑slot shaders.
- **WebGPU inspector** for debugging shaders in the panel.

### 6. Technical Considerations

- The panel will rely on React state already used by `App.tsx` and `Controls.tsx`; avoid bloating global state.
- Existing `renderer/` files are immutable; all UI changes occur in `src/components` or top‑level app logic.
- Avoid adding heavy dependencies; leverage existing React/TypeScript and minimal CSS.
- Keep shader list generation script updated to produce any additional index files needed.

### 7. Migration Plan

1. Implement panel + nested menu while keeping dropdown.
2. Deploy to dev environment, test with 500+ shaders.
3. Remove dropdown or hide it behind an option once panel is stable.
4. Document new workflow in README and update `AGENTS.md` for future shader authors.

## Appendix: Example UI Sketch

```
[Shader Panel Toggle]   [Search ▾]________________________________
| liquid-effects ▾                                                   |
|   - ink-drop                                                       |
|   - viscous-flow                                                  |
| interactive-mouse ▾                                                |
|   - ripple-sphere                                                 |
|   - heat-distort                                                  |
| ...                                                                |
| tags: depth-aware, mouse-driven, glitch, ...                       |
|                                                                   |
| Selected shader: ink-drop                                          |
| Param1 [----o------] 0.5                                           |
| Param2 [---o-------] 0.2                                           |
| ...                                                               |
```

## Conclusion

Organizing the shaders into categories and providing an integrated panel will make the application more scalable and user-friendly as the effect library continues to expand. This plan outlines the structure, data changes, UI components, and rollout strategy needed to achieve that improvement.
