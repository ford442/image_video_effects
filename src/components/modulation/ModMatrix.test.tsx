import { act, fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { ModMatrixHost } from './ModMatrixHost';
import { ParamSlidersPanel } from '../controls/panels/ParamSlidersPanel';
import { modulationStore } from '../../modulation/store';
import { resetModulationRuntime } from '../../modulation/runtime';
import type { ShaderEntry, SlotParams } from '../../renderer/types';

const entry = {
    id: 'liquid', name: 'Liquid', url: 'x', category: 'image',
    params: [{ id: 'amt', name: 'Amount', default: 2, min: 0, max: 4 }],
} as unknown as ShaderEntry;

const params: SlotParams = { zoomParam1: 2, zoomParam2: 0.5, zoomParam3: 0.5, zoomParam4: 0.5 } as SlotParams;

afterEach(() => { modulationStore.reset(); resetModulationRuntime(); });

describe('mod matrix', () => {
    it('stays unloaded until opened, then opens pre-targeted from "Modulate…"', async () => {
        render(
            <>
                <ModMatrixHost modes={['liquid']} availableModes={[entry]} />
                <ParamSlidersPanel activeSlot={0} currentShaderEntry={entry} currentParams={params} updateSlotParam={() => {}} />
            </>,
        );
        expect(screen.queryByRole('dialog', { name: 'Modulation matrix' })).toBeNull();
        fireEvent.click(screen.getByRole('button', { name: 'Modulate Amount' }));
        expect(await screen.findByRole('dialog', { name: 'Modulation matrix' })).toBeInTheDocument();
        expect(modulationStore.getPanel().target).toEqual({ slot: 0, param: 'p1' });
        expect(modulationStore.getRange({ slot: 0, param: 'p1' })).toEqual({ min: 0, max: 4 });

        // Add a source row and route it to the pre-targeted param.
        fireEvent.click(screen.getByRole('button', { name: '+ Source' }));
        const cell = screen.getByRole('checkbox', { name: /LFO sine 4 beats → S1 Liquid Amount/ });
        fireEvent.click(cell);
        const [route] = modulationStore.getSnapshot().routes;
        expect(route).toMatchObject({ target: { slot: 0, param: 'p1' }, depth: 2, curve: 'linear', min: 0, max: 4 });

        fireEvent.change(screen.getByRole('combobox', { name: 'Curve' }), { target: { value: 'smooth' } });
        fireEvent.change(screen.getByRole('slider', { name: 'Depth' }), { target: { value: '-1' } });
        expect(modulationStore.getSnapshot().routes[0]).toMatchObject({ curve: 'smooth', depth: -1 });

        // Editing the source row rewrites its routes; unticking removes the route.
        fireEvent.change(screen.getByRole('combobox', { name: 'LFO shape' }), { target: { value: 'square' } });
        expect(modulationStore.getSnapshot().routes[0]!.source).toMatchObject({ shape: 'square' });
        fireEvent.click(screen.getByRole('checkbox', { name: /LFO square 4 beats → S1 Liquid Amount/ }));
        expect(modulationStore.getSnapshot().routes).toHaveLength(0);

        fireEvent.click(screen.getByRole('button', { name: 'Close modulation matrix' }));
        expect(screen.queryByRole('dialog', { name: 'Modulation matrix' })).toBeNull();
    });

    it('lists opacity targets and closes on Escape', async () => {
        render(<ModMatrixHost modes={['liquid', 'none']} availableModes={[entry]} />);
        act(() => modulationStore.openPanel());
        await screen.findByRole('dialog', { name: 'Modulation matrix' });
        fireEvent.click(screen.getByRole('button', { name: '+ Source' }));
        fireEvent.click(screen.getByRole('checkbox', { name: /→ S1 Liquid opacity/ }));
        expect(modulationStore.getSnapshot().routes[0]).toMatchObject({ target: { slot: 0, param: 'opacity' }, min: 0, max: 1, depth: 0.5 });
        fireEvent.keyDown(window, { key: 'Escape' });
        expect(screen.queryByRole('dialog', { name: 'Modulation matrix' })).toBeNull();
    });
});
