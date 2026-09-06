import { isRemoteChromeHidden, writeRemoteChromeParam } from './remoteChrome';

describe('isRemoteChromeHidden', () => {
  it('is true only for chrome=hide', () => {
    expect(isRemoteChromeHidden('?mode=remote&chrome=hide')).toBe(true);
    expect(isRemoteChromeHidden('mode=remote&chrome=hide')).toBe(true);
  });

  it('fails visible for missing or unrecognised values', () => {
    expect(isRemoteChromeHidden('?mode=remote')).toBe(false);
    expect(isRemoteChromeHidden('?mode=remote&chrome=0')).toBe(false);
    expect(isRemoteChromeHidden('?mode=remote&chrome=false')).toBe(false);
    expect(isRemoteChromeHidden('?mode=remote&chrome=hidden')).toBe(false);
    expect(isRemoteChromeHidden('?mode=remote&chrome=HIDE')).toBe(false);
    expect(isRemoteChromeHidden('')).toBe(false);
  });
});

describe('writeRemoteChromeParam', () => {
  const original = window.location;
  let replaceState: jest.SpyInstance;

  beforeEach(() => {
    Object.defineProperty(window, 'location', {
      value: {
        ...original,
        pathname: '/',
        search: '?mode=remote',
        hash: '',
      },
      configurable: true,
    });
    replaceState = jest.spyOn(window.history, 'replaceState').mockImplementation(() => {});
  });

  afterEach(() => {
    replaceState.mockRestore();
    Object.defineProperty(window, 'location', { value: original, configurable: true });
  });

  it('sets chrome=hide and keeps mode=remote', () => {
    writeRemoteChromeParam(true);
    expect(replaceState).toHaveBeenCalledWith(null, '', '/?mode=remote&chrome=hide');
  });

  it('removes chrome and keeps mode=remote', () => {
    Object.defineProperty(window, 'location', {
      value: {
        ...original,
        pathname: '/',
        search: '?mode=remote&chrome=hide',
        hash: '#x',
      },
      configurable: true,
    });
    writeRemoteChromeParam(false);
    expect(replaceState).toHaveBeenCalledWith(null, '', '/?mode=remote#x');
  });
});
