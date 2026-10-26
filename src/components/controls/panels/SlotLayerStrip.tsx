import React from 'react';
import type { SlotMode } from '../../../renderer/types';
import {
    BLEND_MODES,
    BLEND_MODE_LABELS,
    type MaskSource,
    type SlotOutput,
} from '../../../renderer/slotOutput';
import type { AudioBandSource } from '../../../utils/audioParamMapping';

/**
 * One row under a slot (#1512): chained / parallel, how the layer joins the frame
 * (replace, a blend mode, or a mask for other slots), opacity, mask source and the
 * audio band that may drive the opacity. Lazy chunk "layer-strip" (SlotStackPanel).
 */
export interface SlotLayerStripProps {
    slotIndex: number;
    /** Other slots that hold a shader, offered as mask sources. */
    maskSlots: number[];
    mode: SlotMode;
    output: SlotOutput;
    opacityAudio: AudioBandSource | null;
    onModeChange: (mode: SlotMode) => void;
    onOutputChange: (patch: Partial<SlotOutput>) => void;
    onOpacityAudioChange: (band: AudioBandSource | null) => void;
}

const AUDIO_BANDS: AudioBandSource[] = ['bass', 'mid', 'treble', 'overall'];

const stop = (e: React.SyntheticEvent) => e.stopPropagation();

const rowStyle: React.CSSProperties = {
    display: 'flex',
    flexWrap: 'wrap',
    gap: '6px',
    alignItems: 'center',
    marginTop: '6px',
    fontSize: '11px',
};

const selectStyle: React.CSSProperties = { fontSize: '11px', padding: '2px 4px', width: 'auto', maxWidth: '6.5rem' };

function layerValue(output: SlotOutput): string {
    if (output.mode === 'replace') return 'replace';
    if (output.mode === 'mask') return 'mask';
    return output.blend;
}

function maskValue(output: SlotOutput): string {
    if (output.mask === 'none') return 'none';
    return `${output.maskInvert ? '~' : ''}${output.mask}`;
}

export const SlotLayerStrip: React.FC<SlotLayerStripProps> = ({
    slotIndex,
    maskSlots,
    mode,
    output,
    opacityAudio,
    onModeChange,
    onOutputChange,
    onOpacityAudioChange,
}) => {
    const parallel = mode === 'parallel';
    const blending = output.mode === 'blend';
    const label = `Slot ${slotIndex + 1}`;
    const keyed = blending && (output.blend === 'luma-key' || output.blend === 'depth-key');

    return (
        <div style={rowStyle} onClick={stop} data-testid={`layer-strip-${slotIndex}`}>
            <button
                type="button"
                className="gold-badge"
                aria-label={`${label}: ${parallel ? 'parallel' : 'chained'}`}
                aria-pressed={parallel}
                title={parallel
                    ? 'Parallel: reads the stack input; its layer composites with the other parallel slots'
                    : 'Chained: feeds the next slot (blend and masks apply to parallel slots)'}
                onClick={() => onModeChange(parallel ? 'chained' : 'parallel')}
                style={{ cursor: 'pointer', fontSize: '11px', padding: '2px 6px' }}
            >
                {parallel ? '⚡ Parallel' : '⛓ Chained'}
            </button>

            <select
                className="glass-select"
                aria-label={`${label} layer`}
                style={selectStyle}
                value={layerValue(output)}
                disabled={!parallel}
                title={parallel ? 'How this layer joins the parallel group' : 'Switch to parallel to blend this slot'}
                onChange={(e) => {
                    const v = e.target.value;
                    if (v === 'replace' || v === 'mask') onOutputChange({ mode: v });
                    else onOutputChange({ mode: 'blend', blend: v as SlotOutput['blend'] });
                }}
            >
                <option value="replace">Replace</option>
                {BLEND_MODES.map((b) => (
                    <option key={b} value={b}>{BLEND_MODE_LABELS[b]}</option>
                ))}
                <option value="mask">Mask (matte)</option>
            </select>

            <input
                type="range"
                min={0}
                max={1}
                step={0.01}
                aria-label={`${label} opacity`}
                title={`Opacity ${Math.round(output.opacity * 100)}% (MIDI / OSC: slot opacity)`}
                value={output.opacity}
                disabled={!parallel || !blending}
                onChange={(e) => onOutputChange({ opacity: Number(e.target.value) })}
                style={{ width: '4rem' }}
            />

            <select
                className="glass-select"
                aria-label={`${label} mask`}
                style={selectStyle}
                value={maskValue(output)}
                disabled={!parallel || !blending}
                onChange={(e) => {
                    const v = e.target.value;
                    const invert = v.startsWith('~');
                    const source = (invert ? v.slice(1) : v) as MaskSource;
                    onOutputChange({ mask: source, maskInvert: invert });
                }}
            >
                <option value="none">No mask</option>
                <option value="luma">Luma</option>
                <option value="~luma">Luma (inv)</option>
                <option value="depth">Depth</option>
                <option value="~depth">Depth (inv)</option>
                {maskSlots.map((s) => (
                    <React.Fragment key={s}>
                        <option value={`slot${s}`}>Slot {s + 1}</option>
                        <option value={`~slot${s}`}>Slot {s + 1} (inv)</option>
                    </React.Fragment>
                ))}
            </select>

            {blending && parallel && output.mask !== 'none' && (
                <input
                    type="range"
                    min={0}
                    max={1}
                    step={0.05}
                    aria-label={`${label} mask feather`}
                    title={`Mask feather ${Math.round(output.feather * 100)}%`}
                    value={output.feather}
                    onChange={(e) => onOutputChange({ feather: Number(e.target.value) })}
                    style={{ width: '3rem' }}
                />
            )}

            {keyed && parallel && (
                <input
                    type="range"
                    min={0}
                    max={1}
                    step={0.01}
                    aria-label={`${label} key threshold`}
                    title={`Key threshold ${Math.round(output.keyThreshold * 100)}%`}
                    value={output.keyThreshold}
                    onChange={(e) => onOutputChange({ keyThreshold: Number(e.target.value) })}
                    style={{ width: '3rem' }}
                />
            )}

            {blending && parallel && (
                <select
                    className="glass-select"
                    aria-label={`${label} opacity audio`}
                    title="Audio band that gates the opacity while audio reactivity is on"
                    style={{ ...selectStyle, maxWidth: '4.5rem' }}
                    value={opacityAudio ?? 'off'}
                    onChange={(e) => onOpacityAudioChange(e.target.value === 'off' ? null : (e.target.value as AudioBandSource))}
                >
                    <option value="off">♪ off</option>
                    {AUDIO_BANDS.map((b) => (
                        <option key={b} value={b}>♪ {b}</option>
                    ))}
                </select>
            )}
        </div>
    );
};

export default SlotLayerStrip;
