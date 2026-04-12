# Shader Scanner Enhancements

## Overview
Enhanced the "🔍 Scan Shaders for Errors" button functionality to test each shader and validate parameter slider values.

## Changes Made

### 1. Enhanced `src/components/ShaderScanner.tsx`

#### New Features:

**Three Scan Modes:**
- `Compile + Params` (default) - Tests both compilation and parameters
- `Compilation Only` - Tests WGSL compilation only
- `Parameters Only` - Tests parameter definitions only

**Parameter Validation:**
- Checks all shader parameters from JSON definitions
- Validates:
  - Required fields (id, name, default, min, max)
  - Default value within min/max range
  - Step value合理性
  - Uniform mapping correctness
- Shows parameter count per shader
- Color-coded status:
  - 🟢 Valid params (default in range)
  - 🔴 Invalid params (errors detected)
  - 🟡 Not checked

**Expandable Parameter Details:**
- Click any shader row to expand parameter details
- Shows:
  - Parameter ID, name, default value
  - Valid range (min-max)
  - Step size
  - WGSL uniform mapping
  - Validation errors (if any)

**Enhanced Export:**
- JSON report now includes:
  - Parameter statistics (with/without params, valid/invalid counts)
  - Per-shader parameter details
  - Parameter validation errors
  - Full results array with all metadata

### 2. Updated `src/App.tsx`

Added `onTestShader` callback:
- Actually loads each shader during testing
- Sets parameters to test values (60% of range)
- Verifies runtime parameter application
- Reports success/failure

## How to Use

1. **Open the Scanner:**
   - Click "🔍 Scan Shaders for Errors" button in the UI
   - Or access via Developer Tools menu

2. **Select Scan Mode:**
   - Use dropdown to choose: Compile + Params / Compilation Only / Parameters Only

3. **Start Scan:**
   - Click "▶️ Start Scan"
   - Scanner processes shaders in batches of 3
   - Progress bar shows completion percentage

4. **View Results:**
   - Status column shows: ⏳/🔄/✅/❌/⏭️
   - Params column shows count + validation status
   - Click any row with params to expand details

5. **Export Report:**
   - Click "💾 Export Report" to download JSON
   - Report includes all results and parameter stats

## Parameter Validation Rules

The scanner validates each parameter against these rules:

```typescript
interface ShaderParam {
  id: string;        // Required
  name: string;      // Required
  default: number;   // Must be between min and max
  min: number;       // Required
  max: number;       // Required, must be > min
  step?: number;     // Optional
  mapping?: string;  // WGSL uniform mapping (e.g., "zoom_params.x")
}
```

**Validation Errors Detected:**
- Missing required fields
- Default value outside min/max range
- Invalid range (min >= max)
- Missing uniform mapping

## Example Output

### Table View:
```
Status | Params | ID               | Name              | Category
-------|--------|------------------|-------------------|------------
✅     | 4 ✓    | liquid           | Liquid Ripple     | image
✅     | 4 ✓    | crt-tv           | CRT TV            | retro-glitch
❌     | 4 ✗    | broken-shader    | Broken Shader     | generative
⏭️     | -      | texture          | Texture Pass      | internal
```

### Expanded Parameter Details:
```
Parameter Details:
┌─────────────┬──────────────┬─────────┬───────────┬──────┬─────────────────┐
│ ID          │ Name         │ Default │ Range     │ Step │ Mapping         │
├─────────────┼──────────────┼─────────┼───────────┼──────┼─────────────────┤
│ viscosity   │ Viscosity    │ 0.5     │ [0 - 1]   │ 0.01 │ zoom_params.x   │
│ turbulence  │ Turbulence   │ 0.4     │ [0 - 1]   │ 0.01 │ zoom_params.y   │
│ speed       │ Flow Speed   │ 0.5     │ [0 - 1]   │ 0.01 │ zoom_params.z   │
│ damping     │ Damping      │ 0.3     │ [0 - 1]   │ 0.01 │ zoom_params.w   │
└─────────────┴──────────────┴─────────┴───────────┴──────┴─────────────────┘
```

## Files Modified

1. `src/components/ShaderScanner.tsx` - Enhanced scanner component
2. `src/App.tsx` - Added `onTestShader` callback

## Build Status

✅ Build successful with all TypeScript errors resolved.

## Deployment

To deploy the enhanced scanner:
```bash
npm run build
# Deploy build/ folder to server
```

## Browser Requirements

- **Full functionality**: Chrome 113+, Edge 113+, Firefox Nightly (WebGPU required)
- **Parameter-only mode**: Any modern browser (JSON validation only, no compilation test)

## Future Enhancements

Potential future improvements:
1. **Slider Live Test** - Actually move sliders and verify visual feedback
2. **Audio Param Test** - Test audio-reactive parameter behavior
3. **Mouse Interaction Test** - Verify mouse-driven shaders respond to input
4. **Performance Metrics** - Track compilation time per shader
5. **Batch Export** - Export failed shaders list for fixing
