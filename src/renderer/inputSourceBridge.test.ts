import { loadImage, setInputSource, getInputSource } from './inputSourceBridge';

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
});
