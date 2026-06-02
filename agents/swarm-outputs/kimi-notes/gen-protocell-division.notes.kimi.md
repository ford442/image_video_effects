# gen-protocell-division Notes

- **Surprising behavior:** When two protocells drift close together, the smin blending causes them to merge into a single organic peanut shape before snapping apart during division — the membrane surface tension parameter controls whether they stretch like amoebas or hold rigid spherical form.
- **Audio reactivity:** Bass triggers sudden division events (blobs split apart on hits), mids control surface tension roundness via domain-warped fBm amplitude, and treble injects high-frequency membrane vibration ripples that make cells appear electrically excited.
- **Alpha semantics:** `alpha = membrane_thickness * fresnel` — thick membrane centers are opaque, thin edges and internal fluid are translucent, creating the characteristic look of oil droplets in water with a visible but semi-transparent core glow.
