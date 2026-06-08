import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import { PresetPackGallery, PresetPack } from './PresetPackGallery';

const samplePacks: { version: number; packs: PresetPack[] } = {
    version: 1,
    packs: [
        {
            id: 'pack-a',
            name: 'Pack A',
            description: 'First test pack',
            chain: { v: 1, slots: [{ shaderId: 'liquid-metal' }, { shaderId: 'cosmic-flow' }] },
        },
        {
            id: 'pack-b',
            name: 'Pack B',
            description: 'Second test pack',
            chain: { v: 1, slots: [{ shaderId: 'crystal-facets' }] },
        },
    ],
};

describe('PresetPackGallery', () => {
    beforeEach(() => {
        global.fetch = jest.fn(() =>
            Promise.resolve({
                ok: true,
                json: () => Promise.resolve(samplePacks),
            } as Response)
        ) as jest.Mock;
    });

    afterEach(() => {
        jest.restoreAllMocks();
    });

    it('does not fetch packs while collapsed', () => {
        render(<PresetPackGallery open={false} onToggle={jest.fn()} onApplyPack={jest.fn()} />);
        expect(global.fetch).not.toHaveBeenCalled();
        expect(screen.getByText('Preset Packs')).toBeInTheDocument();
    });

    it('fetches and lists packs when opened', async () => {
        render(<PresetPackGallery open={true} onToggle={jest.fn()} onApplyPack={jest.fn()} />);

        expect(global.fetch).toHaveBeenCalledWith('/preset_packs.json');
        await waitFor(() => expect(screen.getByText('Pack A')).toBeInTheDocument());
        expect(screen.getByText('Pack B')).toBeInTheDocument();
        expect(screen.getByText('First test pack')).toBeInTheDocument();
    });

    it('invokes onApplyPack with the chain when "Load Pack" is clicked', async () => {
        const onApplyPack = jest.fn();
        render(<PresetPackGallery open={true} onToggle={jest.fn()} onApplyPack={onApplyPack} />);

        await waitFor(() => expect(screen.getByText('Pack A')).toBeInTheDocument());
        const loadButtons = screen.getAllByText('Load Pack');
        fireEvent.click(loadButtons[0]);

        expect(onApplyPack).toHaveBeenCalledWith(samplePacks.packs[0].chain);
    });

    it('shows an error state when the fetch fails', async () => {
        (global.fetch as jest.Mock).mockImplementationOnce(() => Promise.resolve({ ok: false, status: 500, json: () => Promise.resolve({}) } as Response));

        render(<PresetPackGallery open={true} onToggle={jest.fn()} onApplyPack={jest.fn()} />);

        await waitFor(() => expect(screen.getByText(/Couldn't load preset packs/)).toBeInTheDocument());
    });

    it('calls onToggle when the header is clicked', () => {
        const onToggle = jest.fn();
        render(<PresetPackGallery open={false} onToggle={onToggle} onApplyPack={jest.fn()} />);

        fireEvent.click(screen.getByText('Preset Packs'));
        expect(onToggle).toHaveBeenCalled();
    });
});
