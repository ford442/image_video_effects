import { fireEvent, render, screen } from '@testing-library/react';
import { LocalMediaLoader, useLocalMediaUpload } from './useLocalMediaUpload';

function Pickers({ loader }: { loader: LocalMediaLoader }) {
    const { onImageChange, onVideoChange } = useLocalMediaUpload(loader);
    return (
        <>
            <input type="file" data-testid="img" onChange={onImageChange} />
            <input type="file" data-testid="vid" onChange={onVideoChange} />
        </>
    );
}

/** Spy on the value setter so the reset is observable (jsdom file inputs always read ''). */
function trackValueResets(input: HTMLInputElement): string[] {
    const writes: string[] = [];
    Object.defineProperty(input, 'value', {
        configurable: true,
        get: () => '',
        set: (v: string) => { writes.push(v); },
    });
    return writes;
}

describe('useLocalMediaUpload (#1511 bug 1)', () => {
    it('hands each picked file to the loader with its kind and resets the input', () => {
        const loader = vi.fn();
        render(<Pickers loader={loader} />);
        const img = screen.getByTestId('img') as HTMLInputElement;
        const vid = screen.getByTestId('vid') as HTMLInputElement;
        const imgResets = trackValueResets(img);
        const vidResets = trackValueResets(vid);
        const png = new File(['x'], 'a.png', { type: 'image/png' });
        const mp4 = new File(['y'], 'b.mp4', { type: 'video/mp4' });

        fireEvent.change(img, { target: { files: [png] } });
        fireEvent.change(vid, { target: { files: [mp4] } });

        expect(loader).toHaveBeenNthCalledWith(1, png, 'image');
        expect(loader).toHaveBeenNthCalledWith(2, mp4, 'video');
        expect(imgResets).toEqual(['']);
        expect(vidResets).toEqual(['']);
    });

    it('ignores a change with no file and logs a rejecting loader instead of throwing', async () => {
        const error = vi.spyOn(console, 'error').mockImplementation(() => {});
        const loader = vi.fn().mockRejectedValue(new Error('decode failed'));
        render(<Pickers loader={loader} />);
        const img = screen.getByTestId('img');

        fireEvent.change(img, { target: { files: [] } });
        expect(loader).not.toHaveBeenCalled();

        fireEvent.change(img, { target: { files: [new File(['x'], 'a.png')] } });
        await vi.waitFor(() => expect(error).toHaveBeenCalled());
        error.mockRestore();
    });
});
