import { GRAPH_LAB_STORAGE_KEY, graphLabFlagFromSearch, readGraphLabEnabled } from './graphLabFlags';

beforeEach(() => window.localStorage.clear());

describe('graphLabFlagFromSearch', () => {
  it.each([
    ['?graphlab', true],
    ['?graphlab=1', true],
    ['?graphlab=true', true],
    ['?graphlab=0', false],
    ['?graphlab=false', false],
    ['?graphlab=OFF', false],
    ['?other=1', null],
    ['', null],
  ])('%p → %p', (search, expected) => {
    expect(graphLabFlagFromSearch(search)).toBe(expected);
  });
});

describe('readGraphLabEnabled', () => {
  it('is off by default', () => {
    expect(readGraphLabEnabled('')).toBe(false);
  });

  it('turns on from the URL and remembers it', () => {
    expect(readGraphLabEnabled('?graphlab')).toBe(true);
    expect(window.localStorage.getItem(GRAPH_LAB_STORAGE_KEY)).toBe('1');
    expect(readGraphLabEnabled('')).toBe(true);
  });

  it('turns off from the URL and forgets it', () => {
    window.localStorage.setItem(GRAPH_LAB_STORAGE_KEY, '1');
    expect(readGraphLabEnabled('?graphlab=0')).toBe(false);
    expect(readGraphLabEnabled('')).toBe(false);
  });

  it('still honours the URL when storage is blocked', () => {
    const get = jest.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    const set = jest.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new Error('blocked');
    });
    expect(readGraphLabEnabled('?graphlab=1')).toBe(true);
    expect(readGraphLabEnabled('')).toBe(false);
    get.mockRestore();
    set.mockRestore();
  });
});
