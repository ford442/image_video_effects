# Remote Control Implementation Summary

## Overview
Fixed the remote control feature to work as intended: RemoteApp provides a control-only interface that communicates with MainApp via BroadcastChannel, without any rendering/image loading of its own.

## Changes Made

### 1. src/index.tsx
**Purpose**: Add URL-based routing to conditionally render MainApp vs RemoteApp

**Changes**:
- Import both MainApp and RemoteApp
- Check URL parameter `?mode=remote`
- Render RemoteApp if mode=remote, otherwise render MainApp

### 2. src/App.tsx
**Purpose**: Fix pre-existing linting errors that blocked CI builds

**Changes**:
- Changed `setVideoList` to unused: `const [videoList] = useState<string[]>([]);`
- Wrapped `loadModel` in `useCallback` to fix dependency array issues
- Added `loadModel` to useEffect dependency array

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         MainApp                              │
│  (http://localhost:3000/)                                   │
│                                                              │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────┐ │
│  │  Controls    │  │ WebGPUCanvas  │  │  BroadcastChan  │ │
│  │  Component   │  │  + Renderer   │  │  (sends state)  │ │
│  └──────────────┘  └───────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              ↕
                    BroadcastChannel
                              ↕
┌─────────────────────────────────────────────────────────────┐
│                       RemoteApp                              │
│  (http://localhost:3000/?mode=remote)                       │
│                                                              │
│  ┌──────────────┐  ┌─────────────────┐                     │
│  │  Controls    │  │  BroadcastChan  │  NO CANVAS          │
│  │  Component   │  │  (sends cmds)   │  NO RENDERER        │
│  └──────────────┘  └─────────────────┘  NO IMAGE LOADING   │
└─────────────────────────────────────────────────────────────┘
```

## Communication Protocol

### Message Types

**Remote → Main (Commands)**:
- `CMD_SET_MODE`: Change shader in a slot
- `CMD_SET_ACTIVE_SLOT`: Switch active slot
- `CMD_UPDATE_SLOT_PARAM`: Update shader parameters
- `CMD_SET_ZOOM`, `CMD_SET_PAN_X`, `CMD_SET_PAN_Y`: View controls
- `CMD_SET_INPUT_SOURCE`: Switch between image/video/webcam
- `CMD_LOAD_RANDOM_IMAGE`: Load new random image in MainApp
- `CMD_LOAD_MODEL`: Load AI depth model in MainApp
- `CMD_UPLOAD_FILE`: Upload image/video to MainApp
- `CMD_SELECT_VIDEO`, `CMD_SET_MUTED`: Video controls
- `CMD_SET_AUTO_CHANGE`, `CMD_SET_AUTO_CHANGE_DELAY`: Auto-change settings
- `CMD_SET_SHADER_CATEGORY`: Filter effects by category

**Main → Remote (State)**:
- `HEARTBEAT`: Sent every 1s to keep connection alive
- `STATE_FULL`: Complete state snapshot sent on connection and changes
- Response to `HELLO`: RemoteApp sends HELLO on mount to request initial state

### State Synchronization

RemoteApp uses **optimistic UI updates**:
1. User adjusts slider in RemoteApp
2. RemoteApp immediately updates its local state (instant feedback)
3. RemoteApp sends CMD message to MainApp
4. MainApp receives CMD, updates its state, renders changes
5. MainApp broadcasts STATE_FULL back
6. RemoteApp receives STATE_FULL, overwrites local state (keeps in sync)

This approach provides smooth UX while maintaining consistency.

## Key Features

### What RemoteApp Does
✅ Displays all UI controls (sliders, buttons, dropdowns)
✅ Sends commands to MainApp via BroadcastChannel
✅ Receives state updates from MainApp
✅ Shows connection status ("LOST CONNECTION" when disconnected)
✅ Handles file uploads by reading files and sending buffer to MainApp

### What RemoteApp Does NOT Do
❌ NO WebGPU rendering
❌ NO canvas element
❌ NO Renderer instantiation
❌ NO direct image/video loading
❌ NO shader compilation
❌ NO depth map processing

## Usage

### Opening Remote Control
1. **From UI**: Click "Open Remote" button in MainApp header
2. **Manually**: Navigate to `http://localhost:3000/?mode=remote`
3. **New Window**: `window.open('http://localhost:3000/?mode=remote', '_blank')`

### Testing
```bash
# Terminal 1: Start dev server
npm start

# Browser 1: Open main app
http://localhost:3000/

# Browser 2: Open remote control
http://localhost:3000/?mode=remote
```

Both windows will stay in sync through BroadcastChannel.

## Benefits

1. **Separation of Concerns**: Rendering logic stays in MainApp, controls are reusable
2. **Multi-Window Control**: Control from tablet, phone, or second monitor
3. **No Redundant Resources**: RemoteApp doesn't duplicate GPU/image resources
4. **Flexible Deployment**: Can easily add authentication or network-based control
5. **Maintainability**: Single Controls component used in both apps

## Future Enhancements

Possible improvements:
- Add WebSocket support for cross-network control
- Add mobile-optimized RemoteApp layout
- Add keyboard shortcuts in RemoteApp
- Add preset saving/loading
- Add animation timeline controls
- Add multi-user control with conflict resolution

## Technical Notes

### Why BroadcastChannel?
- Same-origin restriction (security)
- Works across tabs/windows in same browser
- Structured clone algorithm (supports ArrayBuffer, etc.)
- Automatic garbage collection
- No server required

### Why Not window.postMessage?
- Requires window reference (harder with window.open)
- More complex message routing
- BroadcastChannel simpler for 1:N communication

### Performance
- State updates are throttled by React's setState batching
- BroadcastChannel uses structured clone (fast for small objects)
- Optimistic UI prevents perceived lag
- Heartbeat at 1Hz has negligible overhead

## Compatibility

- **Requires**: Chrome 54+, Firefox 38+, Safari 15.4+, Edge 79+
- **BroadcastChannel**: Widely supported (can't use in IE11)
- **WebGPU**: Chrome 113+, Edge 113+ (experimental in Firefox/Safari)

## Security Considerations

- BroadcastChannel is same-origin only (secure by default)
- File uploads send ArrayBuffer (no path exposure)
- No external network communication
- All processing happens client-side
