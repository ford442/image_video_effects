import type { ChangeEvent } from 'react';
import { renderHook, act } from '@testing-library/react';
import { isAcceptedLocalMedia, useLocalMediaLoader, useLocalMediaUpload } from './useLocalMediaUpload';

function changeEvent(files: File[]): { event: ChangeEvent<HTMLInputElement>; input: { value: string } } {
  const input = { files, value: 'C:\\fakepath\\x' };
  return { event: { target: input } as unknown as ChangeEvent<HTMLInputElement>, input };
}

describe('useLocalMediaUpload', () => {
  it('hands the picked file to onFile and resets the input', async () => {
    const onFile = vi.fn();
    const { result } = renderHook(() => useLocalMediaUpload(onFile));
    const file = new File(['x'], 'cat.png', { type: 'image/png' });
    const { event, input } = changeEvent([file]);

    await act(() => result.current.handleFileChange(event, 'image'));

    expect(onFile).toHaveBeenCalledWith(file, 'image');
    expect(input.value).toBe('');
  });

  it('ignores an empty selection and mismatched MIME types', async () => {
    const onFile = vi.fn();
    const { result } = renderHook(() => useLocalMediaUpload(onFile));

    await act(() => result.current.handleFileChange(changeEvent([]).event, 'image'));
    const wrong = new File(['x'], 'song.mp3', { type: 'audio/mpeg' });
    await act(() => result.current.handleFileChange(changeEvent([wrong]).event, 'video'));

    expect(onFile).not.toHaveBeenCalled();
  });

  it('accepts files with no MIME type', () => {
    expect(isAcceptedLocalMedia(new Blob(['x']), 'video')).toBe(true);
    expect(isAcceptedLocalMedia(new Blob(['x'], { type: 'image/jpeg' }), 'video')).toBe(false);
  });
});

describe('useLocalMediaLoader', () => {
  // jsdom has no object URLs; the stubs stay installed for the whole file so the
  // automatic unmount after each test can still revoke.
  let created: string[];
  let revoked: string[];

  beforeEach(() => {
    created = [];
    revoked = [];
    let n = 0;
    URL.createObjectURL = vi.fn(() => {
      const url = `blob:test/${++n}`;
      created.push(url);
      return url;
    });
    URL.revokeObjectURL = vi.fn((url: string) => { revoked.push(url); });
  });

  it('routes images and videos to their loaders via blob: URLs', async () => {
    const loadImage = vi.fn(async () => {});
    const loadVideo = vi.fn();
    const { result } = renderHook(() => useLocalMediaLoader({ loadImage, loadVideo }));

    await act(() => result.current.loadLocalMedia(new Blob(['i'], { type: 'image/png' }), 'image'));
    await act(() => result.current.loadLocalMedia(new Blob(['v'], { type: 'video/mp4' }), 'video'));

    expect(loadImage).toHaveBeenCalledWith('blob:test/1');
    expect(loadVideo).toHaveBeenCalledWith('blob:test/2');
    expect(revoked).toEqual([]);
  });

  it('revokes the previous URL of the same kind once replaced, and all on unmount', async () => {
    const loadImage = vi.fn();
    const loadVideo = vi.fn();
    const { result, unmount } = renderHook(() => useLocalMediaLoader({ loadImage, loadVideo }));

    await act(() => result.current.loadLocalMedia(new Blob(['a']), 'image'));
    await act(() => result.current.loadLocalMedia(new Blob(['b']), 'image'));
    expect(revoked).toEqual(['blob:test/1']);

    unmount();
    expect(revoked).toEqual(['blob:test/1', 'blob:test/2']);
  });

  it('wires end-to-end: a picked file reaches loadImage', async () => {
    const loadImage = vi.fn();
    const { result } = renderHook(() => {
      const { loadLocalMedia } = useLocalMediaLoader({ loadImage, loadVideo: vi.fn() });
      return useLocalMediaUpload(loadLocalMedia);
    });
    const { event } = changeEvent([new File(['x'], 'cat.png', { type: 'image/png' })]);

    await act(() => result.current.handleFileChange(event, 'image'));

    expect(created).toHaveLength(1);
    expect(loadImage).toHaveBeenCalledWith(created[0]);
  });
});
