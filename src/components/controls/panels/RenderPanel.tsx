import React, { useState } from 'react';
import type { UseOfflineRenderReturn } from '../../../hooks/useOfflineRender';
import type { UseSetRecorderReturn } from '../../../hooks/useSetRecorder';
import { formatBytes, OFFLINE_FPS_CHOICES, RESOLUTION_PRESETS } from '../../../recording/offlineExportPlan';
import { KEYFRAME_EASES, TIMELINE_PARAM_KEYS, type KeyframeEase, type TimelineParamKey } from '../../../services/vjSetExport';

/**
 * VJ Studio → Render (#1401): render the recorded set to a file at a size and frame rate
 * the GPU need not sustain live, plus keyframes on a param (add / remove).
 */
export interface RenderPanelProps {
    offline: UseOfflineRenderReturn;
    recorder: UseSetRecorderReturn;
    slotCount: number;
}

const CODEC_LABELS: Record<string, string> = { auto: 'Auto', h264: 'H.264', hevc: 'HEVC', av1: 'AV1', vp9: 'VP9', vp8: 'VP8' };

function formatClock(ms: number): string {
    const total = Math.max(0, Math.round(ms / 1000));
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}

const rowStyle: React.CSSProperties = { display: 'flex', gap: '6px', alignItems: 'center', fontSize: '11px' };
const labelStyle: React.CSSProperties = { width: '74px', color: '#a0a0b0', flexShrink: 0 };

export const RenderPanel: React.FC<RenderPanelProps> = ({ offline, recorder, slotCount }) => {
    const { settings, updateSettings, estimate, output, progress, status, busy } = offline;
    const timeline = recorder.timeline;
    const keyframes = timeline?.keyframes ?? [];
    const [kfSlot, setKfSlot] = useState(0);
    const [kfKey, setKfKey] = useState<TimelineParamKey>('zoomParam1');
    const [kfTime, setKfTime] = useState(0);
    const [kfValue, setKfValue] = useState(0.5);
    const [kfEase, setKfEase] = useState<KeyframeEase>('linear');
    const audioInputRef = React.useRef<HTMLInputElement>(null);

    const canRender = offline.supported && !!timeline && !busy && recorder.recorderState !== 'recording';
    const pct = progress && progress.totalFrames > 0 ? Math.round((progress.frame / progress.totalFrames) * 100) : 0;

    return (
        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', marginTop: '8px' }} data-testid="vj-render-panel">
            <div style={{ fontSize: '10px', color: '#a0a0b0' }}>
                {timeline
                    ? `Source: recorded set · ${formatClock(timeline.durationMs)} · ${timeline.events.length} events${keyframes.length ? ` · ${keyframes.length} keyframes` : ''}`
                    : 'Record a set (Share & export → ● Record set) or import one, then render it here.'}
            </div>
            {!offline.supported && offline.unsupportedReason && (
                <div style={{ fontSize: '10px', color: '#ff9a7a' }}>{offline.unsupportedReason}</div>
            )}

            <label style={rowStyle}>
                <span style={labelStyle}>Resolution</span>
                <select className="glass-select" value={settings.preset} disabled={busy}
                    onChange={(e) => updateSettings({ preset: e.target.value as typeof settings.preset })}>
                    {RESOLUTION_PRESETS.map((p) => <option key={p.id} value={p.id}>{p.label}</option>)}
                </select>
                <span style={{ color: '#a0a0b0' }}>{output.width}×{output.height}</span>
            </label>
            {settings.preset === 'custom' && (
                <div style={rowStyle}>
                    <span style={labelStyle}>Custom</span>
                    <input type="number" className="glass-input" aria-label="Custom width" min={16} max={offline.maxDimension} step={2}
                        value={settings.customWidth} disabled={busy} style={{ width: '70px' }}
                        onChange={(e) => updateSettings({ customWidth: Number(e.target.value) || 16 })} />
                    ×
                    <input type="number" className="glass-input" aria-label="Custom height" min={16} max={offline.maxDimension} step={2}
                        value={settings.customHeight} disabled={busy} style={{ width: '70px' }}
                        onChange={(e) => updateSettings({ customHeight: Number(e.target.value) || 16 })} />
                    <span style={{ color: '#a0a0b0' }}>≤ {offline.maxDimension}</span>
                </div>
            )}
            <label style={rowStyle}>
                <span style={labelStyle}>Frame rate</span>
                <select className="glass-select" value={settings.fps} disabled={busy}
                    onChange={(e) => updateSettings({ fps: Number(e.target.value) })}>
                    {OFFLINE_FPS_CHOICES.map((fps) => <option key={fps} value={fps}>{fps} fps</option>)}
                </select>
            </label>
            <div style={rowStyle}>
                <span style={labelStyle}>Format</span>
                <select className="glass-select" aria-label="Container" value={settings.container} disabled={busy}
                    onChange={(e) => updateSettings({ container: e.target.value as typeof settings.container })}>
                    <option value="mp4">MP4</option>
                    <option value="webm">WebM</option>
                </select>
                <select className="glass-select" aria-label="Codec" value={settings.codec} disabled={busy}
                    onChange={(e) => updateSettings({ codec: e.target.value as typeof settings.codec })}>
                    {offline.codecChoices.map((c) => <option key={c} value={c}>{CODEC_LABELS[c] ?? c}</option>)}
                </select>
                <select className="glass-select" aria-label="Quality" value={settings.quality} disabled={busy}
                    onChange={(e) => updateSettings({ quality: e.target.value as typeof settings.quality })}>
                    <option value="standard">Standard</option>
                    <option value="high">High</option>
                    <option value="master">Master</option>
                </select>
            </div>
            <div style={rowStyle}>
                <span style={labelStyle}>Audio</span>
                {offline.audio ? (
                    <>
                        <span style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis' }} title={offline.audio.name}>
                            {offline.audio.name} ({formatClock(offline.audio.durationSec * 1000)})
                        </span>
                        <button type="button" className="gold-outline-btn" style={{ fontSize: '10px', padding: '2px 6px' }} disabled={busy}
                            onClick={offline.clearAudio}>✕</button>
                    </>
                ) : (
                    <button type="button" className="gold-outline-btn" style={{ fontSize: '10px', padding: '2px 6px' }} disabled={busy}
                        onClick={() => audioInputRef.current?.click()}>Soundtrack for audio-reactive shaders…</button>
                )}
                <input ref={audioInputRef} type="file" accept="audio/*,video/*" style={{ display: 'none' }} onChange={(e) => {
                    const f = e.target.files?.[0];
                    if (f) void offline.loadAudio(f);
                    e.target.value = '';
                }} />
            </div>
            <div style={{ fontSize: '10px', color: '#a0a0b0' }} data-testid="vj-render-estimate">
                {estimate.frames} frames · {(estimate.bitrate / 1e6).toFixed(1)} Mbps · ≈ {formatBytes(estimate.bytes)}
                {' '}(video only; the soundtrack drives shaders, it is not muxed)
            </div>

            <div style={{ display: 'flex', gap: '6px' }}>
                {busy ? (
                    <button type="button" className="gold-outline-btn gold-active" style={{ flex: 1, fontSize: '11px' }} onClick={offline.cancel}>
                        ■ Cancel render
                    </button>
                ) : (
                    <button type="button" className="gold-outline-btn" style={{ flex: 1, fontSize: '11px' }} disabled={!canRender}
                        onClick={() => void offline.start()}>
                        🎞 Render {output.width}×{output.height} @ {settings.fps}
                    </button>
                )}
            </div>
            {(busy || progress) && status !== 'done' && (
                <div>
                    <div style={{ height: '6px', background: 'rgba(255,255,255,0.08)', borderRadius: '3px', overflow: 'hidden' }}>
                        <div style={{ width: `${pct}%`, height: '100%', background: '#ffd700', transition: 'width 0.1s' }} />
                    </div>
                    <div style={{ fontSize: '10px', color: '#a0a0b0', marginTop: '4px' }} data-testid="vj-render-progress">
                        {status === 'preparing' && 'Compiling shaders…'}
                        {status === 'rendering' && progress && `Frame ${progress.frame} / ${progress.totalFrames} · ${progress.renderFps.toFixed(1)} fps${progress.etaMs !== null ? ` · ETA ${formatClock(progress.etaMs)}` : ''}`}
                        {status === 'finalizing' && 'Finishing the file…'}
                        {status === 'cancelled' && 'Render cancelled.'}
                    </div>
                </div>
            )}
            {status === 'done' && offline.outcome && (
                <div style={{ fontSize: '10px', color: '#a0ffa0' }}>
                    {offline.outcome.downloadUrl
                        ? <a href={offline.outcome.downloadUrl} download={offline.outcome.fileName} style={{ color: '#ffd700' }}>{offline.outcome.fileName}</a>
                        : `Saved ${offline.outcome.fileName}`}
                    {` · ${offline.outcome.frames} frames · ${offline.outcome.codec}`}
                    {offline.outcome.failedShaders.length > 0 && ` · did not compile: ${offline.outcome.failedShaders.join(', ')}`}
                </div>
            )}
            {offline.error && <div style={{ fontSize: '10px', color: '#ff9a7a' }}>{offline.error}</div>}

            {/* Keyframes: hand-placed values that override the recording from their first key on. */}
            <div style={{ borderTop: '1px solid rgba(255,215,0,0.15)', paddingTop: '6px' }}>
                <div style={{ fontSize: '11px', color: '#ffd700', marginBottom: '4px' }}>Keyframes</div>
                <div style={{ ...rowStyle, flexWrap: 'wrap' }}>
                    <select className="glass-select" aria-label="Keyframe slot" value={kfSlot} onChange={(e) => setKfSlot(Number(e.target.value))}>
                        {Array.from({ length: slotCount }, (_, i) => <option key={i} value={i}>Slot {i + 1}</option>)}
                    </select>
                    <select className="glass-select" aria-label="Keyframe param" value={kfKey} onChange={(e) => setKfKey(e.target.value as TimelineParamKey)}>
                        {TIMELINE_PARAM_KEYS.map((k) => <option key={k} value={k}>{k}</option>)}
                    </select>
                    <input type="number" className="glass-input" aria-label="Keyframe time (s)" min={0} step={0.1} value={kfTime}
                        style={{ width: '56px' }} onChange={(e) => setKfTime(Math.max(0, Number(e.target.value) || 0))} />
                    s =
                    <input type="number" className="glass-input" aria-label="Keyframe value" step={0.01} value={kfValue}
                        style={{ width: '56px' }} onChange={(e) => setKfValue(Number(e.target.value) || 0)} />
                    <select className="glass-select" aria-label="Keyframe ease" value={kfEase} onChange={(e) => setKfEase(e.target.value as KeyframeEase)}>
                        {KEYFRAME_EASES.map((ease) => <option key={ease} value={ease}>{ease}</option>)}
                    </select>
                    <button type="button" className="gold-outline-btn" style={{ fontSize: '10px', padding: '2px 6px' }} disabled={busy}
                        onClick={() => recorder.addKeyframe({ t: Math.round(kfTime * 1000), slot: kfSlot, key: kfKey, value: kfValue, ease: kfEase })}>
                        ◆ Add
                    </button>
                </div>
                {keyframes.length > 0 && (
                    <div style={{ maxHeight: '110px', overflowY: 'auto', marginTop: '4px' }}>
                        {keyframes.map((k, i) => (
                            <div key={`${k.slot}-${k.key}-${k.t}-${i}`} style={{ ...rowStyle, justifyContent: 'space-between' }}>
                                <span>{formatClock(k.t)}.{String(Math.round(k.t % 1000)).padStart(3, '0')} · slot {k.slot + 1} · {k.key} = {k.value} ({k.ease})</span>
                                <button type="button" className="gold-outline-btn" aria-label={`Remove keyframe ${i + 1}`}
                                    style={{ fontSize: '10px', padding: '0 6px' }} disabled={busy} onClick={() => recorder.removeKeyframe(i)}>✕</button>
                            </div>
                        ))}
                    </div>
                )}
            </div>
        </div>
    );
};

export default RenderPanel;
