import {
  av1CodecString,
  estimateOfflineBytes,
  evenDimension,
  frameCountFor,
  h264CodecString,
  hevcCodecString,
  offlineBitrate,
  offlineCodecCandidates,
  resolvePresetSize,
  vp9CodecString,
} from './offlineExportPlan';

describe('offline export plan (#1401)', () => {
  it('picks the lowest H.264 High level that fits the macroblock rate', () => {
    expect(h264CodecString(1280, 720, 30)).toBe('avc1.64001F'); // 3.1
    expect(h264CodecString(1920, 1080, 30)).toBe('avc1.640028'); // 4.0
    expect(h264CodecString(1920, 1080, 60)).toBe('avc1.64002A'); // 4.2
    expect(h264CodecString(3840, 2160, 30)).toBe('avc1.640033'); // 5.1
    expect(h264CodecString(3840, 2160, 60)).toBe('avc1.640034'); // 5.2
    expect(h264CodecString(7680, 4320, 60)).toBe('avc1.64003D'); // 6.1
  });

  it('levels for HEVC, AV1 and VP9 follow the picture size and sample rate', () => {
    expect(hevcCodecString(1920, 1080, 30)).toBe('hvc1.1.6.L120.B0');
    expect(hevcCodecString(3840, 2160, 60)).toBe('hvc1.1.6.L153.B0');
    expect(av1CodecString(1920, 1080, 30)).toBe('av01.0.08M.08');
    expect(av1CodecString(3840, 2160, 60)).toBe('av01.0.13M.08');
    expect(av1CodecString(3840, 2160, 120)).toBe('av01.0.14M.08');
    expect(vp9CodecString(3840, 2160, 60)).toBe('vp09.00.51.08');
    expect(vp9CodecString(640, 360, 30)).toBe('vp09.00.21.08');
  });

  it('offers only codecs the container can hold, best first', () => {
    expect(offlineCodecCandidates('mp4', 'auto', 1920, 1080, 60).map((c) => [c.id, c.muxCodec])).toEqual([
      ['h264', 'avc'], ['hevc', 'hevc'], ['av1', 'av1'], ['vp9', 'vp9'],
    ]);
    expect(offlineCodecCandidates('webm', 'auto', 1920, 1080, 60).map((c) => c.muxCodec)).toEqual(['V_VP9', 'V_AV1', 'V_VP8']);
    expect(offlineCodecCandidates('webm', 'h264', 1920, 1080, 60)).toEqual([]);
    expect(offlineCodecCandidates('mp4', 'av1', 3840, 2160, 60)).toEqual([
      { id: 'av1', container: 'mp4', codec: 'av01.0.13M.08', muxCodec: 'av1' },
    ]);
  });

  it('bitrate ladder: rises with size and rate, falls with codec efficiency, scales with quality', () => {
    expect(offlineBitrate(1920, 1080, 30, 'h264', 'high')).toBe(12_000_000);
    const uhd60 = offlineBitrate(3840, 2160, 60, 'h264', 'high');
    expect(uhd60).toBeGreaterThan(70_000_000);
    expect(uhd60).toBeLessThan(80_000_000);
    expect(offlineBitrate(3840, 2160, 60, 'av1', 'high')).toBeLessThan(uhd60);
    expect(offlineBitrate(1920, 1080, 30, 'h264', 'master')).toBe(24_000_000);
    expect(offlineBitrate(2560, 1440, 30, 'h264')).toBe(24_000_000);
    const mid = offlineBitrate(2240, 1260, 30, 'h264');
    expect(mid).toBeGreaterThan(12_000_000);
    expect(mid).toBeLessThan(24_000_000);
    expect(offlineBitrate(16, 16, 1, 'vp9', 'standard')).toBe(500_000);
  });

  it('frame count is exactly duration × fps; size estimate follows the bitrate', () => {
    expect(frameCountFor(10_000, 60)).toBe(600);
    expect(frameCountFor(10_000, 24)).toBe(240);
    expect(frameCountFor(1001, 30)).toBe(30);
    expect(frameCountFor(0, 30)).toBe(1);
    expect(estimateOfflineBytes(8_000_000, 10)).toBe(10_100_000);
  });

  it('resolves presets against the canvas and the device limit, with even sizes', () => {
    const canvas = { width: 1919, height: 1081 };
    const custom = { width: 5000, height: 3001 };
    expect(resolvePresetSize('match', canvas, custom, 8192)).toEqual({ width: 1918, height: 1080 });
    expect(resolvePresetSize('2160p', canvas, custom, 8192)).toEqual({ width: 3840, height: 2160 });
    expect(resolvePresetSize('4320p', canvas, custom, 4096)).toEqual({ width: 4096, height: 2304 });
    expect(resolvePresetSize('custom', canvas, custom, 8192)).toEqual({ width: 5000, height: 3000 });
    expect(evenDimension(1)).toBe(2);
  });
});
