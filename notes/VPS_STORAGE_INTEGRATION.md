# VPS Storage Integration Guide

This document describes the integration between the Pixelocity image_video_effects frontend and the Contabo VPS Storage API.

## Overview

The VPS Storage integration provides:
- **Secure Saving**: Save shaders, effect configurations, and outputs to your VPS with HMAC SHA256 signature verification
- **Easy Loading**: Load saved files from the static Nginx server
- **Visual Browser**: Browse shaders, images, and videos with star ratings
- **Real-time Feedback**: Toast notifications and operation tracking
- **Modular Design**: Clean service architecture for easy extension

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Pixelocity Frontend                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │
│  │  App.tsx    │  │StorageBrowser│  │   Controls  │  │   Hooks     │   │
│  │             │  │   Component │  │             │  │             │   │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘   │
│         │                │                │                │          │
│         └────────────────┴────────────────┴────────────────┘          │
│                                    │                                   │
│                           useStorage Hook                             │
│                                    │                                   │
│                         StorageService.ts                             │
│                                    │                                   │
└────────────────────────────────────┼───────────────────────────────────┘
                                     │
                     ┌───────────────┴───────────────┐
                     │                               │
                     ▼                               ▼
        ┌──────────────────────┐        ┌──────────────────────┐
        │   VPS Webhook API    │        │  Static Nginx Server │
        │  173.249.14.134:8000 │        │  storage.1ink.us     │
        │                      │        │                      │
        │  POST /webhook/      │        │  GET /files/         │
        │  X-Hub-Signature-256 │        │                      │
        └──────────────────────┘        └──────────────────────┘
```

## Configuration

### Environment Variables

Create a `.env` file in your project root:

```bash
# VPS Storage Configuration
REACT_APP_STORAGE_VPS_HOST=173.249.14.134
REACT_APP_STORAGE_VPS_PORT=8000
REACT_APP_STORAGE_VPS_URL=http://173.249.14.134:8000/webhook
REACT_APP_STORAGE_API_URL=http://173.249.14.134:8000
REACT_APP_STATIC_NGINX_URL=https://storage.1ink.us
REACT_APP_WEBHOOK_SECRET=your-webhook-secret-here
```

### Config File

The configuration is centralized in `src/config/appConfig.ts`:

```typescript
// VPS Storage Manager (Contabo) - PRIMARY STORAGE
export const STORAGE_VPS_HOST = process.env.REACT_APP_STORAGE_VPS_HOST || '173.249.14.134';
export const STORAGE_VPS_PORT = process.env.REACT_APP_STORAGE_VPS_PORT || '8000';
export const STORAGE_VPS_URL = process.env.REACT_APP_STORAGE_VPS_URL || `http://${STORAGE_VPS_HOST}:${STORAGE_VPS_PORT}/webhook`;
export const STORAGE_API_URL = process.env.REACT_APP_STORAGE_API_URL || `http://${STORAGE_VPS_HOST}:${STORAGE_VPS_PORT}`;

// Static Nginx file server
export const STATIC_NGINX_URL = process.env.REACT_APP_STATIC_NGINX_URL || 'https://storage.1ink.us';

// Webhook Secret for HMAC SHA256 signatures
export const STORAGE_WEBHOOK_SECRET = process.env.REACT_APP_WEBHOOK_SECRET || 'your-webhook-secret-here';
```

## Usage

### 1. Using the Storage Browser Component

```tsx
import { StorageBrowser } from './components/StorageBrowser';

function MyComponent() {
  const handleSelectShader = (shader) => {
    console.log('Selected shader:', shader);
    // Load the shader into your app
  };

  const handleSelectImage = (image) => {
    console.log('Selected image:', image);
    // Use the image URL
  };

  return (
    <StorageBrowser
      onSelectShader={handleSelectShader}
      onSelectImage={handleSelectImage}
      onSelectVideo={(video) => console.log(video)}
      initialTab="shaders"
    />
  );
}
```

### 2. Using the useStorage Hook

```tsx
import { useStorage } from './hooks/useStorage';

function MyComponent() {
  const storage = useStorage();

  // Save a shader
  const handleSaveShader = async () => {
    try {
      const result = await storage.saveShader(
        'my-effect',
        wgslCode,
        { author: 'Me', tags: ['cool', 'neon'] }
      );
      console.log('Saved to:', result.url);
    } catch (error) {
      console.error('Save failed:', error);
    }
  };

  // Save current effect configuration
  const handleSaveConfig = async () => {
    await storage.saveEffectConfig('my-preset', {
      modes: ['liquid', 'neon-pulse', 'none'],
      slotParams: [...],
      inputSource: 'image',
      // ... other config
    });
  };

  // Rate a shader
  const handleRate = async (shaderId, rating) => {
    await storage.rateShader(shaderId, rating, 'Great shader!');
  };

  // Connection status
  if (storage.isCheckingConnection) {
    return <div>Checking VPS connection...</div>;
  }

  if (!storage.isConnected) {
    return (
      <div>
        Not connected: {storage.connectionError}
        <button onClick={storage.checkConnection}>Retry</button>
      </div>
    );
  }

  return (
    <div>
      {/* Toast notifications are automatic */}
      
      {/* Show loading state */}
      {storage.isLoadingShaders && <div>Loading shaders...</div>}
      
      {/* Display shaders with ratings */}
      {storage.shaders.map(shader => (
        <div key={shader.id}>
          <h3>{shader.name}</h3>
          <StarRating 
            rating={shader.rating}
            onRate={(r) => handleRate(shader.id, r)}
          />
        </div>
      ))}
    </div>
  );
}
```

### 3. Using the StorageService Directly

```tsx
import { 
  getStorageService, 
  createStorageService 
} from './services/StorageService';

// Use the default singleton instance
const storage = getStorageService();

// Or create a custom instance
const customStorage = createStorageService(
  'http://custom-webhook-url',
  'https://custom-static-url',
  'custom-secret',
  'http://custom-api-url'
);

// Save with signature
const result = await storage.save({
  action: 'save_shader',
  name: 'my-shader',
  data: { wgsl_code: '...', metadata: {} }
});

// List shaders with ratings
const shaders = await storage.listShaders();

// Load a file from static server
const config = await storage.loadJson('image-effects/metadata/my-config.json');
```

## HMAC SHA256 Signature Generation

The Web Crypto API is used for browser-native HMAC SHA256 signature generation:

```typescript
async function generateSignature(payload: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  
  // Import the secret key
  const keyData = encoder.encode(secret);
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    keyData,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  
  // Sign the payload
  const payloadData = encoder.encode(payload);
  const signatureBuffer = await crypto.subtle.sign('HMAC', cryptoKey, payloadData);
  
  // Convert to hex string
  const signatureArray = new Uint8Array(signatureBuffer);
  const signatureHex = Array.from(signatureArray)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
  
  return `sha256=${signatureHex}`;
}
```

The signature is included in the request header:

```typescript
const response = await fetch(`${webhookUrl}/image-effects`, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'X-Hub-Signature-256': signature,
  },
  body: payload,
});
```

## API Reference

### StorageService Methods

| Method | Description | Parameters | Returns |
|--------|-------------|------------|---------|
| `save()` | Generic save with signature | `StorageSaveOptions` | `StorageSaveResponse` |
| `saveShader()` | Save WGSL shader | `name, wgslCode, metadata` | `StorageSaveResponse` |
| `saveEffectConfig()` | Save effect configuration | `name, config` | `StorageSaveResponse` |
| `saveOutput()` | Save rendered output | `name, imageData, metadata` | `StorageSaveResponse` |
| `saveVideoConfig()` | Save video configuration | `name, config` | `StorageSaveResponse` |
| `uploadTexture()` | Upload texture file | `name, textureData, metadata` | `StorageSaveResponse` |
| `loadJson()` | Load JSON from static server | `path` | `T` |
| `loadShader()` | Load shader by filename | `filename` | `ShaderData` |
| `loadEffectConfig()` | Load effect config | `filename` | `any` |
| `listShaders()` | List all shaders | - | `ShaderItem[]` |
| `listShadersWithErrors()` | List shaders with 0 rating | - | `ShaderItem[]` |
| `listImages()` | List all images | - | `ImageItem[]` |
| `listSongs()` | List media files | `type?` | `(VideoItem \| ImageItem)[]` |
| `rateShader()` | Rate a shader | `shaderId, rating, notes?` | `RatingResult` |
| `getShaderRating()` | Get shader rating | `shaderId` | `RatingData` |
| `checkHealth()` | Check VPS health | - | `HealthResponse` |
| `getStatus()` | Get full status | - | `StorageStatus` |
| `subscribeToOperations()` | Subscribe to ops | `callback` | `unsubscribe` |

### useStorage Hook Return Values

| Property | Type | Description |
|----------|------|-------------|
| `isConnected` | `boolean` | VPS connection status |
| `isCheckingConnection` | `boolean` | Checking connection state |
| `connectionError` | `string?` | Connection error message |
| `shaders` | `ShaderItem[]` | List of shaders |
| `images` | `ImageItem[]` | List of images |
| `videos` | `VideoItem[]` | List of videos |
| `audio` | `VideoItem[]` | List of audio files |
| `isLoadingShaders` | `boolean` | Loading shaders state |
| `isLoadingImages` | `boolean` | Loading images state |
| `isLoadingVideos` | `boolean` | Loading videos state |
| `operations` | `StorageOperation[]` | All operations |
| `activeOperations` | `StorageOperation[]` | Pending/in-progress ops |
| `lastError` | `string?` | Last error message |
| `toasts` | `ToastNotification[]` | Active toast notifications |

### useStorage Hook Methods

| Method | Description |
|--------|-------------|
| `refreshShaders()` | Reload shader list |
| `refreshImages()` | Reload image list |
| `refreshVideos()` | Reload video list |
| `refreshAll()` | Reload all data |
| `saveShader(name, code, meta)` | Save a shader |
| `saveEffectConfig(name, config)` | Save configuration |
| `saveOutput(name, data, meta)` | Save output image |
| `loadShader(filename)` | Load shader data |
| `loadEffectConfig(filename)` | Load configuration |
| `rateShader(id, rating, notes)` | Rate a shader |
| `checkConnection()` | Verify VPS connection |
| `clearError()` | Clear error state |
| `dismissToast(id)` | Dismiss toast |
| `clearCompleted()` | Clear completed ops |

## StorageBrowser Component Props

| Prop | Type | Default | Description |
|------|------|---------|-------------|
| `onSelectShader` | `(shader) => void` | - | Called when shader selected |
| `onSelectImage` | `(image) => void` | - | Called when image selected |
| `onSelectVideo` | `(video) => void` | - | Called when video selected |
| `onLoadEffectConfig` | `(config) => void` | - | Called when config loaded |
| `initialTab` | `TabType` | 'shaders' | Initial active tab |

## File Structure

```
src/
├── services/
│   ├── StorageService.ts       # Core storage API service
│   ├── shaderApi.ts            # Legacy shader API
│   ├── ShaderRatingIntegration.ts
│   └── index.ts                # Service exports
├── hooks/
│   ├── useStorage.ts           # Storage state management hook
│   ├── useAudioAnalyzer.ts
│   └── usePerformanceMonitor.ts
├── components/
│   ├── StorageBrowser.tsx      # Visual browser component
│   ├── StorageBrowser.css      # Component styles
│   ├── ShaderStarRating.tsx
│   └── ...
├── config/
│   └── appConfig.ts            # Configuration
└── ...
```

## Error Handling

All errors are caught and displayed to users via:

1. **Toast Notifications**: Automatic toast popups for all operations
2. **Connection Status**: Visual indicator in the browser header
3. **Operation Tracking**: Full operation history with status
4. **Last Error**: Available in hook return values

Example error handling:

```tsx
const storage = useStorage();

// Errors are automatically shown as toasts
// You can also handle them manually:
useEffect(() => {
  if (storage.lastError) {
    console.error('Storage error:', storage.lastError);
    // Custom error handling
  }
}, [storage.lastError]);
```

## Security Notes

1. **Webhook Secret**: Store the webhook secret securely (environment variable)
2. **HTTPS**: Always use HTTPS in production for the static server
3. **CORS**: The VPS backend already has CORS configured
4. **Signatures**: All save operations include HMAC SHA256 signatures

## Extending the Service

To add new save actions:

1. Add the action type to `StorageSaveOptions['action']`:

```typescript
export interface StorageSaveOptions {
  action: 'save_shader' | 'save_metadata' | 'save_output' | 
          'save_video_config' | 'upload_texture' | 'my_new_action';
  name: string;
  data: Record<string, any>;
}
```

2. Add a convenience method to `StorageService`:

```typescript
async saveMyNewAction(
  name: string,
  data: any
): Promise<StorageSaveResponse> {
  return this.save({
    action: 'my_new_action',
    name,
    data: {
      ...data,
      saved_at: new Date().toISOString(),
    },
  });
}
```

3. Add a hook method in `useStorage.ts`:

```typescript
const saveMyNewAction = useCallback(async (name: string, data: any) => {
  setLastError(undefined);
  try {
    const result = await serviceRef.current.saveMyNewAction(name, data);
    addToast({
      id: `save-new-${Date.now()}`,
      type: 'success',
      message: `Saved ${name} successfully`,
      duration: 5000,
    });
    return result;
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Failed';
    setLastError(errorMessage);
    addToast({
      id: `save-new-error-${Date.now()}`,
      type: 'error',
      message: errorMessage,
      duration: 5000,
    });
    throw error;
  }
}, []);
```

## Troubleshooting

### Connection Failed
- Check VPS is running: `curl http://173.249.14.134:8000/health`
- Verify CORS is enabled on the VPS
- Check firewall settings

### Signature Invalid
- Verify `REACT_APP_WEBHOOK_SECRET` matches the VPS secret
- Check the payload is being sent as raw JSON

### Static Files Not Loading
- Verify the file exists on the VPS
- Check Nginx configuration
- Ensure CORS headers are present

### CORS Errors
- The VPS backend already handles CORS
- For development, you may need a proxy

## License

This integration is part of the Pixelocity project.
