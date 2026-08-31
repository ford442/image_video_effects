import { loadImage, setInputSource, getInputSource, rebindMediaAfterBackendSwitch, readRendererVideo } from './inputSourceBridge';

describe('inputSourceBridge', () => {
  it('forwards setInputSource and getInputSource', () => {
    const renderer = {
      setInputSource: jest.fn(),
      getInputSource: jest.fn().mockReturnValue('webcam'),
    };
    setInputSource(renderer as never, 'video');
    expect(renderer.setInputSource).toHaveBeenCalledWith('video');
    expect(getInputSource(renderer as never)).toBe('webcam');
  });

  it('prefers loadImage over loadImageFromURL (#887 duck-type)', async () => {
    const renderer = {
      loadImage: jest.fn().mockResolvedValue('https://cdn/a.png'),
      loadImageFromURL: jest.fn(),
    };
    const url = await loadImage(renderer as never, 'https://cdn/a.png');
    expect(renderer.loadImage).toHaveBeenCalledWith('https://cdn/a.png');
    expect(renderer.loadImageFromURL).not.toHaveBeenCalled();
    expect(url).toBe('https://cdn/a.png');
  });

  it('falls back to loadImageFromURL when loadImage is absent', async () => {
    const renderer = {
      loadImageFromURL: jest.fn().mockResolvedValue(undefined),
    };
    const url = await loadImage(renderer as never, 'https://cdn/b.png');
    expect(renderer.loadImageFromURL).toHaveBeenCalledWith('https://cdn/b.png');
    expect(url).toBe('https://cdn/b.png');
  });

  it('reads the video element from getVideo, mediaVideo, or video', () => {
    const el = document.createElement('video');
    expect(readRendererVideo({ getVideo: () => el } as never)).toBe(el);
    expect(readRendererVideo({ mediaVideo: el } as never)).toBe(el);
    expect(readRendererVideo({ video: el } as never)).toBe(el);
    expect(readRendererVideo({} as never)).toBeNull();
  });

  it('rebind uploads the current image URL after a backend switch', async () => {
    const loadImageFn = jest.fn().mockResolvedValue('https://cdn/photo.png');
    const setSource = jest.fn();
    const renderer = {
      setInputSource: setSource,
      loadImage: loadImageFn,
      updateVideoFrame: jest.fn(),
    };
    const result = await rebindMediaAfterBackendSwitch(renderer as never, {
      inputSource: 'image',
      imageUrl: 'https://cdn/photo.png',
    });
    expect(setSource).toHaveBeenCalledWith('image');
    expect(loadImageFn).toHaveBeenCalledWith('https://cdn/photo.png');
    expect(renderer.updateVideoFrame).not.toHaveBeenCalled();
    expect(result.uploaded).toBe(true);
  });

  it('rebind uploads a video frame and does not reload an image', async () => {
    const video = document.createElement('video');
    Object.defineProperty(video, 'videoWidth', { value: 1280 });
    Object.defineProperty(video, 'videoHeight', { value: 720 });
    const renderer = {
      setInputSource: jest.fn(),
      setVideo: jest.fn(),
      getVideo: () => video,
      updateVideoFrame: jest.fn(),
      loadImage: jest.fn(),
    };
    const result = await rebindMediaAfterBackendSwitch(renderer as never, {
      inputSource: 'video',
      imageUrl: 'https://cdn/photo.png',
    });
    expect(renderer.setInputSource).toHaveBeenCalledWith('video');
    expect(renderer.setVideo).toHaveBeenCalledWith(video);
    expect(renderer.updateVideoFrame).toHaveBeenCalled();
    expect(renderer.loadImage).not.toHaveBeenCalled();
    expect(result).toEqual({ uploaded: true, width: 1280, height: 720, source: 'video' });
  });

  it('rebind skips pixel upload for generative', async () => {
    const renderer = {
      setInputSource: jest.fn(),
      loadImage: jest.fn(),
      updateVideoFrame: jest.fn(),
    };
    const result = await rebindMediaAfterBackendSwitch(renderer as never, {
      inputSource: 'generative',
      imageUrl: 'https://cdn/photo.png',
    });
    expect(renderer.setInputSource).toHaveBeenCalledWith('generative');
    expect(renderer.loadImage).not.toHaveBeenCalled();
    expect(result.uploaded).toBe(false);
  });
});
