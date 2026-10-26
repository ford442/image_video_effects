import { renderHook, act } from '@testing-library/react';
import type { ChangeEvent } from 'react';
import { useLocalMediaLoader, useLocalMediaUpload } from './useLocalMediaUpload';

function changeEvent(files: File[]): ChangeEvent<HTMLInputElement> {
  const input = document.createElement('input');
  input.type = 'file';
  Object.defineProperty(input, 'files', { value: files, configurable: true });
  return { target: input } as unknown as ChangeEvent<HTMLInputElement>;
}

describe('useLocalMediaUpload', () => {
  it('passes the first picked file and its kind on', async () => {
    const onFile = vi.fn();
    const { result } = renderHook(() => useLocalMediaUpload(onFile));
    const file = new File(['x'], 'a.png', { type: 'image/png' });
    await act(async () => {
      result.current.handleFileChange(changeEvent([file]), 'image');
    });
    expect(onFile).toHaveBeenCalledWith(file, 'image');
  });

  it('does nothing when the picker is cancelled', async () => {
    const onFile = vi.fn();
    const { result } = renderHook(() => useLocalMediaUpload(onFile));
    await act(async () => {
      result.current.handleFileChange(changeEvent([]), 'video');
    });
    expect(onFile).not.toHaveBeenCalled();
  });
});

describe('useLocalMediaLoader', () => {
  let created: string[];
  let revoked: string[];
  beforeEach(() => {
    created = [];
    revoked = [];
    let n = 0;
    vi.stubGlobal('URL', Object.assign(Object.create(URL), {
      createObjectURL: () => {
        const url = `blob:test/${++n}`;
        created.push(url);
        return url;
      },
      revokeObjectURL: (url: string) => { revoked.push(url); },
    }));
  });
  afterEach(() => vi.unstubAllGlobals());

  it('loads images and plays videos from blob URLs, revoking each replaced URL', async () => {
    const onImage = vi.fn(async () => {});
    const onVideo = vi.fn();
    const { result, unmount } = renderHook(() => useLocalMediaLoader({ onImage, onVideo }));

    await act(async () => { await result.current(new Blob(['a']), 'image'); });
    expect(onImage).toHaveBeenCalledWith('blob:test/1');
    expect(revoked).toEqual([]);

    await act(async () => { await result.current(new Blob(['v']), 'video'); });
    expect(onVideo).toHaveBeenCalledWith('blob:test/2');

    await act(async () => { await result.current(new Blob(['b']), 'image'); });
    expect(onImage).toHaveBeenLastCalledWith('blob:test/3');
    expect(revoked).toEqual(['blob:test/1']);

    unmount();
    expect(revoked.sort()).toEqual(['blob:test/1', 'blob:test/2', 'blob:test/3']);
  });
});
