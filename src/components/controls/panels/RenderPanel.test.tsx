import { fireEvent, render, screen } from '@testing-library/react';
import { RenderPanel } from './RenderPanel';
import type { UseOfflineRenderReturn } from '../../../hooks/useOfflineRender';
import type { UseSetRecorderReturn } from '../../../hooks/useSetRecorder';

function offline(patch: Partial<UseOfflineRenderReturn> = {}): UseOfflineRenderReturn {
  return {
    settings: { preset: '2160p', customWidth: 1920, customHeight: 1080, fps: 60, container: 'mp4', codec: 'auto', quality: 'high' },
    updateSettings: vi.fn(),
    codecChoices: ['auto', 'h264', 'hevc', 'av1', 'vp9'],
    supported: true,
    unsupportedReason: null,
    maxDimension: 8192,
    output: { width: 3840, height: 2160 },
    estimate: { frames: 600, durationSec: 10, bitrate: 75_800_000, bytes: 95_000_000 },
    status: 'idle',
    progress: null,
    error: null,
    outcome: null,
    audio: null,
    loadAudio: vi.fn(async () => {}),
    clearAudio: vi.fn(),
    start: vi.fn(async () => {}),
    cancel: vi.fn(),
    busy: false,
    ...patch,
  };
}

function recorder(patch: Partial<UseSetRecorderReturn> = {}): UseSetRecorderReturn {
  return {
    recorderState: 'idle',
    timeline: { hz: 20, durationMs: 10_000, events: [{ t: 0, slot: 0, kind: 'shader', value: 'liquid' }] },
    setTimeline: vi.fn(),
    elapsedMs: 0,
    startRecording: vi.fn(),
    stopRecording: vi.fn(),
    startPlayback: vi.fn(),
    stopPlayback: vi.fn(),
    hitCap: false,
    addKeyframe: vi.fn(),
    removeKeyframe: vi.fn(),
    ...patch,
  };
}

describe('RenderPanel (#1401)', () => {
  it('shows the set, the output size and the estimate, and starts a render', () => {
    const o = offline();
    render(<RenderPanel offline={o} recorder={recorder()} slotCount={6} />);
    expect(screen.getByText(/recorded set · 0:10 · 1 events/)).toBeTruthy();
    expect(screen.getByTestId('vj-render-estimate').textContent).toMatch(/600 frames · 75\.8 Mbps · ≈ 90\.6 MiB/);
    fireEvent.click(screen.getByText('🎞 Render 3840×2160 @ 60'));
    expect(o.start).toHaveBeenCalled();
  });

  it('cannot render without a set or a capable renderer, and explains why', () => {
    const { rerender } = render(<RenderPanel offline={offline()} recorder={recorder({ timeline: null })} slotCount={6} />);
    expect((screen.getByText(/🎞 Render/) as HTMLButtonElement).disabled).toBe(true);
    rerender(<RenderPanel offline={offline({ supported: false, unsupportedReason: 'needs WebGPU' })} recorder={recorder()} slotCount={6} />);
    expect(screen.getByText('needs WebGPU')).toBeTruthy();
    expect((screen.getByText(/🎞 Render/) as HTMLButtonElement).disabled).toBe(true);
  });

  it('shows progress with ETA and a cancel button while rendering', () => {
    const o = offline({
      busy: true,
      status: 'rendering',
      progress: { phase: 'rendering', frame: 120, totalFrames: 600, elapsedMs: 30_000, etaMs: 120_000, renderFps: 4 },
    });
    render(<RenderPanel offline={o} recorder={recorder()} slotCount={6} />);
    expect(screen.getByTestId('vj-render-progress').textContent).toBe('Frame 120 / 600 · 4.0 fps · ETA 2:00');
    fireEvent.click(screen.getByText('■ Cancel render'));
    expect(o.cancel).toHaveBeenCalled();
  });

  it('adds and removes keyframes on a param', () => {
    const r = recorder({
      timeline: {
        hz: 20,
        durationMs: 2000,
        events: [],
        keyframes: [{ t: 1500, slot: 1, key: 'zoomParam2', value: 0.75, ease: 'easeOut' }],
      },
    });
    render(<RenderPanel offline={offline()} recorder={r} slotCount={6} />);
    fireEvent.change(screen.getByLabelText('Keyframe slot'), { target: { value: '2' } });
    fireEvent.change(screen.getByLabelText('Keyframe param'), { target: { value: 'lightStrength' } });
    fireEvent.change(screen.getByLabelText('Keyframe time (s)'), { target: { value: '2.5' } });
    fireEvent.change(screen.getByLabelText('Keyframe value'), { target: { value: '1.2' } });
    fireEvent.change(screen.getByLabelText('Keyframe ease'), { target: { value: 'easeInOut' } });
    fireEvent.click(screen.getByText('◆ Add'));
    expect(r.addKeyframe).toHaveBeenCalledWith({ t: 2500, slot: 2, key: 'lightStrength', value: 1.2, ease: 'easeInOut' });
    expect(screen.getByText(/slot 2 · zoomParam2 = 0.75 \(easeOut\)/)).toBeTruthy();
    fireEvent.click(screen.getByLabelText('Remove keyframe 1'));
    expect(r.removeKeyframe).toHaveBeenCalledWith(0);
  });
});
