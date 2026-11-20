/**
 * offlineExportPlan.ts — pure planning helpers for offline export (#1401).
 *
 * Main-bundle safe (no muxer, no WebCodecs calls): resolution presets, codec strings with a
 * level that fits the frame size and rate, the bitrate ladder and the size estimate the
 * Render tab shows. The encoder and muxers live in the lazy "gpu-encode" chunk
 * (offlineEncoder.ts).
 */

export type OfflineContainer = 'mp4' | 'webm';
export type OfflineCodecId = 'h264' | 'hevc' | 'av1' | 'vp9' | 'vp8';
export type OfflineCodecChoice = OfflineCodecId | 'auto';
export type OfflineQuality = 'standard' | 'high' | 'master';

export interface OfflineCodecCandidate {
  id: OfflineCodecId;
  container: OfflineContainer;
  /** WebCodecs codec string, level chosen for the frame size and rate. */
  codec: string;
  /** The muxer's codec name (mp4-muxer `avc | hevc | vp9 | av1`, webm-muxer `V_*`). */
  muxCodec: string;
}

export interface ResolutionPreset {
  id: 'match' | '720p' | '1080p' | '1440p' | '2160p' | '4320p' | 'custom';
  label: string;
  width?: number;
  height?: number;
}

export const RESOLUTION_PRESETS: readonly ResolutionPreset[] = [
  { id: 'match', label: 'Match canvas' },
  { id: '720p', label: '720p', width: 1280, height: 720 },
  { id: '1080p', label: '1080p', width: 1920, height: 1080 },
  { id: '1440p', label: '1440p', width: 2560, height: 1440 },
  { id: '2160p', label: '4K', width: 3840, height: 2160 },
  { id: '4320p', label: '8K', width: 7680, height: 4320 },
  { id: 'custom', label: 'Custom' },
];

export const OFFLINE_FPS_CHOICES = [24, 30, 60, 120] as const;

/** Codecs in preference order per container (`auto`). */
export const CONTAINER_CODECS: Record<OfflineContainer, readonly OfflineCodecId[]> = {
  mp4: ['h264', 'hevc', 'av1', 'vp9'],
  webm: ['vp9', 'av1', 'vp8'],
};

/** Encoders want even dimensions (4:2:0 chroma). */
export function evenDimension(v: number): number {
  const n = Math.max(2, Math.round(v));
  return n % 2 === 0 ? n : n - 1;
}

// ── Levels ──────────────────────────────────────────────────────────────────────

/** H.264 Table A-1: [level_idc, MaxMBPS, MaxFS]. */
const H264_LEVELS: ReadonlyArray<[number, number, number]> = [
  [30, 40_500, 1_620],
  [31, 108_000, 3_600],
  [32, 216_000, 5_120],
  [40, 245_760, 8_192],
  [42, 522_240, 8_704],
  [50, 589_824, 22_080],
  [51, 983_040, 36_864],
  [52, 2_073_600, 36_864],
  [60, 4_177_920, 139_264],
  [61, 8_355_840, 139_264],
  [62, 16_711_680, 139_264],
];

/** H.264 High profile, the lowest level whose macroblock limits fit `w × h @ fps`. */
export function h264CodecString(width: number, height: number, fps: number): string {
  const mbs = Math.ceil(width / 16) * Math.ceil(height / 16);
  const level = H264_LEVELS.find(([, maxMbps, maxFs]) => mbs <= maxFs && mbs * fps <= maxMbps)?.[0] ?? 62;
  return `avc1.6400${level.toString(16).padStart(2, '0').toUpperCase()}`;
}

/** [level × 30 (general_level_idc), MaxLumaPs, MaxLumaSr] — HEVC Table A.8 (Main tier). */
const HEVC_LEVELS: ReadonlyArray<[number, number, number]> = [
  [90, 552_960, 16_588_800],
  [93, 983_040, 33_177_600],
  [120, 2_228_224, 66_846_720],
  [123, 2_228_224, 133_693_440],
  [150, 8_912_896, 267_386_880],
  [153, 8_912_896, 534_773_760],
  [156, 8_912_896, 1_069_547_520],
  [180, 35_651_584, 1_069_547_520],
  [183, 35_651_584, 2_139_095_040],
  [186, 35_651_584, 4_278_190_080],
];

export function hevcCodecString(width: number, height: number, fps: number): string {
  const ps = width * height;
  const level = HEVC_LEVELS.find(([, maxPs, maxSr]) => ps <= maxPs && ps * fps <= maxSr)?.[0] ?? 186;
  return `hvc1.1.6.L${level}.B0`;
}

/** [seq_level_idx, MaxPicSize, MaxDisplayRate] — AV1 Annex A.3. */
const AV1_LEVELS: ReadonlyArray<[number, number, number]> = [
  [0, 147_456, 4_423_680],
  [1, 278_784, 8_363_520],
  [4, 665_856, 19_975_680],
  [5, 1_065_024, 31_950_720],
  [8, 2_359_296, 70_778_880],
  [9, 2_359_296, 141_557_760],
  [12, 8_912_896, 267_386_880],
  [13, 8_912_896, 534_773_760],
  [14, 8_912_896, 1_069_547_520],
  [16, 35_651_584, 1_069_547_520],
  [17, 35_651_584, 2_139_095_040],
  [18, 35_651_584, 4_278_190_080],
];

export function av1CodecString(width: number, height: number, fps: number): string {
  const ps = width * height;
  const level = AV1_LEVELS.find(([, maxPs, maxRate]) => ps <= maxPs && ps * fps <= maxRate)?.[0] ?? 18;
  return `av01.0.${String(level).padStart(2, '0')}M.08`;
}

/** [level × 10, MaxLumaPictureSize, MaxLumaSampleRate] — VP9 levels. */
const VP9_LEVELS: ReadonlyArray<[number, number, number]> = [
  [10, 36_864, 829_440],
  [11, 73_728, 2_764_800],
  [20, 122_880, 4_608_000],
  [21, 245_760, 9_216_000],
  [30, 552_960, 20_736_000],
  [31, 983_040, 36_864_000],
  [40, 2_228_224, 83_558_400],
  [41, 2_228_224, 160_432_128],
  [50, 8_912_896, 311_951_360],
  [51, 8_912_896, 588_251_136],
  [52, 8_912_896, 1_176_502_272],
  [60, 35_651_584, 1_176_502_272],
  [61, 35_651_584, 2_353_004_544],
  [62, 35_651_584, 4_706_009_088],
];

export function vp9CodecString(width: number, height: number, fps: number): string {
  const ps = width * height;
  const level = VP9_LEVELS.find(([, maxPs, maxSr]) => ps <= maxPs && ps * fps <= maxSr)?.[0] ?? 62;
  return `vp09.00.${level}.08`;
}

const MUX_CODECS: Record<OfflineContainer, Partial<Record<OfflineCodecId, string>>> = {
  mp4: { h264: 'avc', hevc: 'hevc', av1: 'av1', vp9: 'vp9' },
  webm: { vp9: 'V_VP9', av1: 'V_AV1', vp8: 'V_VP8' },
};

export function codecString(id: OfflineCodecId, width: number, height: number, fps: number): string {
  switch (id) {
    case 'h264': return h264CodecString(width, height, fps);
    case 'hevc': return hevcCodecString(width, height, fps);
    case 'av1': return av1CodecString(width, height, fps);
    case 'vp9': return vp9CodecString(width, height, fps);
    default: return 'vp8';
  }
}

/** Candidates to try, best first. A codec the container cannot hold is never offered. */
export function offlineCodecCandidates(
  container: OfflineContainer,
  choice: OfflineCodecChoice,
  width: number,
  height: number,
  fps: number,
): OfflineCodecCandidate[] {
  const order = CONTAINER_CODECS[container];
  const ids = choice === 'auto' ? order : order.includes(choice) ? [choice] : [];
  return ids.flatMap((id) => {
    const muxCodec = MUX_CODECS[container][id];
    return muxCodec ? [{ id, container, codec: codecString(id, width, height, fps), muxCodec }] : [];
  });
}

// ── Bitrate ladder ──────────────────────────────────────────────────────────────

/**
 * H.264 bitrates at 30 fps by frame height, the top of the usual upload recommendations
 * for SDR (an offline render has the time to spend the bits). Interpolated by pixel count.
 */
const H264_LADDER_30FPS: ReadonlyArray<[pixels: number, bps: number]> = [
  [640 * 360, 1_500_000],
  [1280 * 720, 6_500_000],
  [1920 * 1080, 12_000_000],
  [2560 * 1440, 24_000_000],
  [3840 * 2160, 50_000_000],
  [7680 * 4320, 150_000_000],
];

/** Relative to H.264 for the same quality. */
const CODEC_EFFICIENCY: Record<OfflineCodecId, number> = { h264: 1, hevc: 0.65, vp9: 0.7, av1: 0.55, vp8: 1.2 };
const QUALITY_SCALE: Record<OfflineQuality, number> = { standard: 0.6, high: 1, master: 2 };
const MIN_BITRATE = 500_000;
const MAX_BITRATE = 400_000_000;

/** H.264 bps at 30 fps for `pixels`: linear between rungs, proportional outside them. */
function ladderBitrate30(pixels: number): number {
  let lower: readonly [number, number] = [0, 0];
  for (const rung of H264_LADDER_30FPS) {
    const [p, b] = rung;
    if (pixels <= p) {
      // Below the first rung: proportional to the pixel count.
      if (lower[0] === 0) return b * (pixels / p);
      return lower[1] + (b - lower[1]) * ((pixels - lower[0]) / (p - lower[0]));
    }
    lower = rung;
  }
  // Above the last rung: proportional to the pixel count.
  return lower[0] > 0 ? lower[1] * (pixels / lower[0]) : 0;
}

export function offlineBitrate(
  width: number,
  height: number,
  fps: number,
  codec: OfflineCodecId,
  quality: OfflineQuality = 'high',
): number {
  const bps30 = ladderBitrate30(width * height);
  // Doubling the frame rate costs ~1.5× the bits (temporal redundancy), not 2×.
  const fpsScale = Math.pow(Math.max(1, fps) / 30, 0.6);
  const bps = bps30 * fpsScale * CODEC_EFFICIENCY[codec] * QUALITY_SCALE[quality];
  return Math.round(Math.min(MAX_BITRATE, Math.max(MIN_BITRATE, bps)));
}

/** Bytes of a `durationSec` render (muxing overhead ~1%). */
export function estimateOfflineBytes(bitrate: number, durationSec: number): number {
  return Math.round((bitrate * Math.max(0, durationSec)) / 8 * 1.01);
}

export function frameCountFor(durationMs: number, fps: number): number {
  return Math.max(1, Math.round((Math.max(0, durationMs) / 1000) * fps));
}

export function formatBytes(bytes: number): string {
  if (bytes >= 1024 ** 3) return `${(bytes / 1024 ** 3).toFixed(2)} GiB`;
  if (bytes >= 1024 ** 2) return `${(bytes / 1024 ** 2).toFixed(1)} MiB`;
  return `${Math.max(1, Math.round(bytes / 1024))} KiB`;
}

/** Output size for a preset: `match` uses the live canvas, `custom` the typed size; both clamped to the device. */
export function resolvePresetSize(
  preset: ResolutionPreset['id'],
  canvas: { width: number; height: number },
  custom: { width: number; height: number },
  maxDimension: number,
): { width: number; height: number } {
  const found = RESOLUTION_PRESETS.find((p) => p.id === preset);
  const raw = preset === 'match'
    ? canvas
    : preset === 'custom' || !found?.width || !found.height
      ? custom
      : { width: found.width, height: found.height };
  const max = maxDimension > 0 ? maxDimension : 8192;
  const scale = Math.min(1, max / Math.max(raw.width, raw.height, 1));
  return { width: evenDimension(raw.width * scale), height: evenDimension(raw.height * scale) };
}
