import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { ControlsContainer as Controls } from './ControlsContainer';
import { findEffects, matchesQuery } from './sidebarFilter';
import { usePersistedToggle } from '../../hooks/usePersistedToggle';
import type { ShaderEntry, SlotParams } from '../../renderer/types';

beforeAll(() => {
    Object.defineProperty(window, 'matchMedia', {
        writable: true,
        value: vi.fn().mockImplementation(query => ({
            matches: false, media: query, onchange: null,
            addListener: vi.fn(), removeListener: vi.fn(),
            addEventListener: vi.fn(), removeEventListener: vi.fn(), dispatchEvent: vi.fn(),
        })),
    });
});

beforeEach(() => localStorage.clear());

const availableModes: ShaderEntry[] = [
    { id: 'rain', name: 'Rain', url: 'shaders/rain.wgsl', category: 'image', tags: ['weather'],
      params: [{ id: 'speed', name: 'Rain Speed', default: 0.5, min: 0, max: 1 }] },
    { id: 'liquid', name: 'Liquid', url: 'shaders/liquid.wgsl', category: 'image' },
    { id: 'rainbow-wave', name: 'Rainbow Wave', url: 'shaders/rainbow-wave.wgsl', category: 'image' },
];

const params: SlotParams = {
    zoomParam1: 0.5, zoomParam2: 0.5, zoomParam3: 0.5, zoomParam4: 0.5,
    lightStrength: 1, ambient: 0.2, normalStrength: 0.1, fogFalloff: 4, depthThreshold: 0.5,
};

const setMode = vi.fn();

const renderControls = () => render(
    <Controls
        modes={['rain', 'none', 'none']} setMode={setMode}
        activeSlot={0} setActiveSlot={() => {}}
        slotParams={[params, params, params]} updateSlotParam={() => {}}
        shaderCategory="image" setShaderCategory={() => {}}
        onNewImage={() => {}}
        autoChangeEnabled={false} setAutoChangeEnabled={() => {}}
        autoChangeDelay={10} setAutoChangeDelay={() => {}}
        onLoadModel={() => {}} isModelLoaded={false}
        availableModes={availableModes}
        inputSource="image" setInputSource={() => {}}
        videoList={[]} selectedVideo="" setSelectedVideo={() => {}}
        isMuted={false} setIsMuted={() => {}}
        onUploadImageTrigger={() => {}} onUploadVideoTrigger={() => {}}
        isAiVjMode={false} onToggleAiVj={() => {}} aiVjStatus="idle"
    />,
);

describe('sidebar groups', () => {
    test('renders the four top-level groups, open by default', () => {
        renderControls();
        for (const name of [/Source & Media/, /Effects & Slots/, /Output/, /Studio, MIDI & Tools/]) {
            expect(screen.getByRole('button', { name })).toHaveAttribute('aria-expanded', 'true');
        }
    });

    test('collapsing a group hides its panels and the state survives a remount', () => {
        const { unmount } = renderControls();
        expect(screen.getByText('Shader Slots')).toBeInTheDocument();
        fireEvent.click(screen.getByRole('button', { name: /Effects & Slots/ }));
        expect(screen.queryByText('Shader Slots')).not.toBeInTheDocument();
        unmount();

        renderControls();
        expect(screen.getByRole('button', { name: /Effects & Slots/ })).toHaveAttribute('aria-expanded', 'false');
        expect(screen.queryByText('Shader Slots')).not.toBeInTheDocument();
        expect(screen.getByRole('button', { name: /Output/ })).toHaveAttribute('aria-expanded', 'true');
    });
});

describe('sidebar filter', () => {
    const filter = () => screen.getByLabelText('Filter controls and effects');

    test('hides non-matching sections and empty groups, and expands collapsed matches', () => {
        renderControls();
        fireEvent.click(screen.getByRole('button', { name: /Output/ }));
        fireEvent.change(filter(), { target: { value: 'record' } });
        expect(screen.getByText(/Capture . share your creation/)).toBeInTheDocument();
        expect(screen.queryByText('Shader Slots')).not.toBeInTheDocument();
        expect(screen.queryByRole('button', { name: /Source & Media/ })).not.toBeInTheDocument();

        fireEvent.change(filter(), { target: { value: '' } });
        expect(screen.getByText('Shader Slots')).toBeInTheDocument();
    });

    test('matches the active shader\'s parameter names', () => {
        renderControls();
        fireEvent.change(filter(), { target: { value: 'rain speed' } });
        expect(screen.getByText(/Shader Parameters/)).toBeInTheDocument();
    });

    test('lists matching effects and applies the pick to the active slot', () => {
        renderControls();
        fireEvent.change(filter(), { target: { value: 'liq' } });
        fireEvent.click(screen.getByRole('option', { name: 'Liquid' }));
        expect(setMode).toHaveBeenCalledWith(0, 'liquid');
    });

    test('shows an empty state when nothing matches', () => {
        renderControls();
        fireEvent.change(filter(), { target: { value: 'zzzzqq' } });
        expect(screen.getByText(/No controls or effects match/)).toBeInTheDocument();
    });
});

describe('sidebarFilter helpers', () => {
    test('matchesQuery needs every token', () => {
        expect(matchesQuery('rain spe', 'Rain Speed')).toBe(true);
        expect(matchesQuery('rain xyz', 'Rain Speed')).toBe(false);
        expect(matchesQuery('  ', 'anything')).toBe(true);
    });

    test('findEffects ranks name-prefix hits first and searches tags', () => {
        expect(findEffects(availableModes, 'rain').map(e => e.id)).toEqual(['rain', 'rainbow-wave']);
        expect(findEffects(availableModes, 'weather').map(e => e.id)).toEqual(['rain']);
        expect(findEffects(availableModes, '')).toEqual([]);
    });
});

describe('usePersistedToggle', () => {
    const Probe: React.FC = () => {
        const [on, setOn] = usePersistedToggle('test.probe', true);
        return <button onClick={() => setOn(o => !o)}>{on ? 'on' : 'off'}</button>;
    };

    test('uses the default, then the stored value', () => {
        const { unmount } = render(<Probe />);
        fireEvent.click(screen.getByText('on'));
        expect(localStorage.getItem('pixelocity.ui.test.probe')).toBe('0');
        unmount();
        render(<Probe />);
        expect(screen.getByText('off')).toBeInTheDocument();
    });

    test('survives a throwing localStorage', () => {
        const spy = vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('blocked'); });
        render(<Probe />);
        expect(screen.getByText('on')).toBeInTheDocument();
        spy.mockRestore();
    });
});
