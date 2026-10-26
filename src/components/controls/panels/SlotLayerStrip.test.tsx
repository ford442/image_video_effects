import { fireEvent, render, screen } from '@testing-library/react';
import { DEFAULT_SLOT_OUTPUT, type SlotOutput } from '../../../renderer/slotOutput';
import { SlotLayerStrip, type SlotLayerStripProps } from './SlotLayerStrip';

function setup(overrides: Partial<SlotLayerStripProps> = {}) {
  const props: SlotLayerStripProps = {
    slotIndex: 1,
    maskSlots: [0, 2],
    mode: 'parallel',
    output: { ...DEFAULT_SLOT_OUTPUT },
    opacityAudio: null,
    onModeChange: vi.fn(),
    onOutputChange: vi.fn(),
    onOpacityAudioChange: vi.fn(),
    ...overrides,
  };
  render(<SlotLayerStrip {...props} />);
  return props;
}

const blended = (patch: Partial<SlotOutput> = {}): SlotOutput => ({ ...DEFAULT_SLOT_OUTPUT, mode: 'blend', ...patch });

describe('SlotLayerStrip', () => {
  it('toggles chained / parallel', () => {
    const props = setup({ mode: 'chained' });
    fireEvent.click(screen.getByRole('button', { name: 'Slot 2: chained' }));
    expect(props.onModeChange).toHaveBeenCalledWith('parallel');
  });

  it('picks a blend mode, mask-only or replace from one dropdown', () => {
    const props = setup();
    const layer = screen.getByLabelText('Slot 2 layer');
    fireEvent.change(layer, { target: { value: 'screen' } });
    fireEvent.change(layer, { target: { value: 'mask' } });
    fireEvent.change(layer, { target: { value: 'replace' } });
    expect(props.onOutputChange).toHaveBeenNthCalledWith(1, { mode: 'blend', blend: 'screen' });
    expect(props.onOutputChange).toHaveBeenNthCalledWith(2, { mode: 'mask' });
    expect(props.onOutputChange).toHaveBeenNthCalledWith(3, { mode: 'replace' });
  });

  it('sets opacity and an inverted slot mask, then shows the feather', () => {
    const props = setup({ output: blended({ blend: 'screen' }) });
    fireEvent.change(screen.getByLabelText('Slot 2 opacity'), { target: { value: '0.5' } });
    fireEvent.change(screen.getByLabelText('Slot 2 mask'), { target: { value: '~slot2' } });
    expect(props.onOutputChange).toHaveBeenCalledWith({ opacity: 0.5 });
    expect(props.onOutputChange).toHaveBeenCalledWith({ mask: 'slot2', maskInvert: true });
    expect(screen.queryByLabelText('Slot 2 mask feather')).toBeNull();
  });

  it('offers only other slots as mask sources and shows feather / key controls when relevant', () => {
    setup({ output: blended({ blend: 'luma-key', mask: 'depth' }) });
    const options = Array.from((screen.getByLabelText('Slot 2 mask') as HTMLSelectElement).options).map((o) => o.value);
    expect(options).toEqual(['none', 'luma', '~luma', 'depth', '~depth', 'slot0', '~slot0', 'slot2', '~slot2']);
    expect(screen.getByLabelText('Slot 2 mask feather')).toBeTruthy();
    expect(screen.getByLabelText('Slot 2 key threshold')).toBeTruthy();
  });

  it('disables the blend controls on a chained slot', () => {
    setup({ mode: 'chained', output: blended() });
    expect((screen.getByLabelText('Slot 2 layer') as HTMLSelectElement).disabled).toBe(true);
    expect((screen.getByLabelText('Slot 2 opacity') as HTMLInputElement).disabled).toBe(true);
  });

  it('routes the audio band selector', () => {
    const props = setup({ output: blended() });
    fireEvent.change(screen.getByLabelText('Slot 2 opacity audio'), { target: { value: 'bass' } });
    fireEvent.change(screen.getByLabelText('Slot 2 opacity audio'), { target: { value: 'off' } });
    expect(props.onOpacityAudioChange).toHaveBeenNthCalledWith(1, 'bass');
    expect(props.onOpacityAudioChange).toHaveBeenNthCalledWith(2, null);
  });
});
