import { act, fireEvent, render, renderHook, screen } from '@testing-library/react';
import { LocalMediaLoader, useLocalMediaLoader, useLocalMediaUpload } from './useLocalMediaUpload';

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

describe('useLocalMediaUpload input events', () => {
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

describe('useLocalMediaLoader', () => {
    it('creates blob URLs, revokes replaced URLs, and releases live URLs on unmount', async () => {
        const createObjectURL = vi.fn((file: Blob) => `blob:test/${(file as File).name}`);
        const revokeObjectURL = vi.fn();
        Object.assign(URL, { createObjectURL, revokeObjectURL });
        const onImage = vi.fn();
        const onVideo = vi.fn();
        const { result, unmount } = renderHook(() => useLocalMediaLoader({ onImage, onVideo }));
        const first = new File(['a'], 'first.png');
        const second = new File(['b'], 'second.png');
        const video = new File(['c'], 'clip.mp4');

        await act(async () => {
            await result.current(first, 'image');
            await result.current(second, 'image');
            await result.current(video, 'video');
        });

        expect(onImage).toHaveBeenLastCalledWith('blob:test/second.png');
        expect(onVideo).toHaveBeenCalledWith('blob:test/clip.mp4');
        expect(revokeObjectURL).toHaveBeenCalledWith('blob:test/first.png');
        unmount();
        expect(revokeObjectURL).toHaveBeenCalledWith('blob:test/second.png');
        expect(revokeObjectURL).toHaveBeenCalledWith('blob:test/clip.mp4');
    });
});
