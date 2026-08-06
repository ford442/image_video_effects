import { RenderMode, ShaderCategory, InputSource, SlotParams, ShaderEntry } from './renderer/types';

export type SyncMessageType =
    | 'HELLO' // Remote -> Main (Request initial state)
    | 'HEARTBEAT' // Main -> Remote (Keepalive)
    | 'STATE_FULL' // Main -> Remote (Full state dump)
    | 'STATE_UPDATE' // Main -> Remote (Partial update)
    // Commands (Remote -> Main)
    | 'CMD_SET_MODE'
    | 'CMD_SET_ACTIVE_SLOT'
    | 'CMD_UPDATE_SLOT_PARAM'
    | 'CMD_SET_SHADER_CATEGORY'
    | 'CMD_SET_ZOOM'
    | 'CMD_SET_PAN_X'
    | 'CMD_SET_PAN_Y'
    | 'CMD_SET_INPUT_SOURCE'
    | 'CMD_SET_AUTO_CHANGE'
    | 'CMD_SET_AUTO_CHANGE_DELAY'
    | 'CMD_LOAD_RANDOM_IMAGE'
    | 'CMD_LOAD_MODEL'
    | 'CMD_UPLOAD_FILE' // Payload: { name: string, type: 'image' | 'video', data: ArrayBuffer }
    | 'CMD_SELECT_VIDEO'
    | 'CMD_SET_MUTED'
    /** Randomize one slot (shader + params). Payload: slot index 0–2. */
    | 'CMD_RANDOMIZE_SLOT'
    /** Randomize all non-empty/empty slots like main Roulette "Randomize All". */
    | 'CMD_RANDOMIZE_ALL_SLOTS'
    /** Roulette on the main app's active slot (same as R / Randomize Slot N button). */
    | 'CMD_ROULETTE'

export interface SyncMessage {
    type: SyncMessageType;
    payload?: any;
}

export interface VideoRecord {
    id?: string;
    url: string;
    title?: string;
    description?: string;
    tags?: string[];
    duration?: number;
}

export interface FullState {
    modes: RenderMode[];
    activeSlot: number;
    slotParams: SlotParams[];
    shaderCategory: ShaderCategory;

    inputSource: InputSource;
    autoChangeEnabled: boolean;
    autoChangeDelay: number;
    isModelLoaded: boolean;
    availableModes: ShaderEntry[];
    videoList: VideoRecord[];
    selectedVideo: string;
    isMuted: boolean;
}

export const SYNC_CHANNEL_NAME = 'webgpu_remote_control_channel';
