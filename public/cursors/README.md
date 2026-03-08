# Custom Cursor Setup

## Option 1: Using your .cur file (recommended)

1. Place your `cursor.cur` file in this directory: `public/cursors/cursor.cur`
2. The app will automatically use it on the canvas hover

**Note:** The CSS expects a 32x32 pixel cursor with the hotspot at the center (16, 16).

## Option 2: Using the SVG crosshair (included)

An SVG crosshair is already available at `crosshair.svg` and works in all modern browsers.
The CSS has been configured to try the .cur file first, then fall back to the SVG.

## Option 3: Creating a .cur file

If you need to create a .cur file from the SVG:

1. Use online converters like:
   - https://convertio.co/svg-cur/
   - https://cloudconvert.com/svg-to-cur

2. Or use tools like:
   - RealWorld Cursor Editor (Windows)
   - cursor.cc (online editor)

## Cursor Specifications

- **Size:** 32x32 pixels (recommended)
- **Hotspot:** Center (16, 16)
- **Format:** .cur (Windows cursor) or .svg (modern browsers)
- **Style:** Reduced crosshair (minimal, precise)
