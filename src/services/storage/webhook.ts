/**
 * HMAC-signed webhook writes to the VPS storage manager.
 */

import { assertOk, generateHmacSignature, resolveStaticUrl } from './http';
import type {
  EffectConfigPayload,
  ShaderItem,
  StorageClientConfig,
  StorageSaveOptions,
  StorageSaveResponse,
  VideoConfigPayload,
} from './types';

export async function webhookSave(
  config: StorageClientConfig,
  options: StorageSaveOptions
): Promise<StorageSaveResponse> {
  const payload = JSON.stringify({
    action: options.action,
    name: options.name,
    data: options.data,
    timestamp: new Date().toISOString(),
  });

  const signature = await generateHmacSignature(payload, config.secret);

  const response = await fetch(`${config.webhookUrl}/image-effects`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Hub-Signature-256': signature,
    },
    body: payload,
  });

  await assertOk(response);
  const result = (await response.json()) as StorageSaveResponse;

  if (result.files && result.files.length > 0) {
    result.url = resolveStaticUrl(config.staticUrl, result.files[0]);
  }

  return result;
}

export function saveShaderPayload(
  name: string,
  wgslCode: string,
  metadata: Partial<ShaderItem> = {}
): StorageSaveOptions {
  return {
    action: 'save_shader',
    name,
    data: {
      name,
      wgsl_code: wgslCode,
      ...metadata,
      saved_at: new Date().toISOString(),
    },
  };
}

export function saveEffectConfigPayload(
  name: string,
  config: EffectConfigPayload
): StorageSaveOptions {
  return {
    action: 'save_metadata',
    name,
    data: {
      type: 'effect_config',
      name,
      ...config,
      saved_at: new Date().toISOString(),
    },
  };
}

export function saveOutputPayload(
  name: string,
  imageData: string,
  metadata: Record<string, unknown> = {}
): StorageSaveOptions {
  return {
    action: 'save_output',
    name,
    data: {
      image_data: imageData,
      ...metadata,
      saved_at: new Date().toISOString(),
    },
  };
}

export function saveVideoConfigPayload(
  name: string,
  config: VideoConfigPayload
): StorageSaveOptions {
  return {
    action: 'save_video_config',
    name,
    data: {
      type: 'video_config',
      ...config,
      saved_at: new Date().toISOString(),
    },
  };
}

export function uploadTexturePayload(
  name: string,
  textureData: string,
  metadata: Record<string, unknown> = {}
): StorageSaveOptions {
  return {
    action: 'upload_texture',
    name,
    data: {
      texture_data: textureData,
      ...metadata,
      saved_at: new Date().toISOString(),
    },
  };
}

export type UploadFileType = 'image' | 'video' | 'audio' | 'shader';

const UPLOAD_ACTION: Record<UploadFileType, StorageSaveOptions['action'] | 'upload_audio'> = {
  image: 'upload_texture',
  video: 'save_video_config',
  audio: 'upload_audio',
  shader: 'save_shader',
};

export function fileUploadPayload(
  file: File,
  base64Data: string,
  type: UploadFileType
): StorageSaveOptions {
  const action = UPLOAD_ACTION[type];
  if (!action) {
    throw new Error(`Unsupported file type: ${type}`);
  }

  return {
    action,
    name: file.name,
    data: {
      file_data: base64Data,
      file_name: file.name,
      file_type: file.type,
      file_size: file.size,
      upload_type: type,
      saved_at: new Date().toISOString(),
    },
  };
}

export function readFileAsBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      resolve(result.split(',')[1]);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
