import { isPublicPixelocityHost, shouldMountRemoteApp } from './publicHost';

describe('publicHost', () => {
  it('treats go.1ink.us as public', () => {
    expect(isPublicPixelocityHost('go.1ink.us')).toBe(true);
    expect(isPublicPixelocityHost('www.go.1ink.us')).toBe(true);
  });

  it('keeps test, localhost, and other hosts non-public', () => {
    expect(isPublicPixelocityHost('test.1ink.us')).toBe(false);
    expect(isPublicPixelocityHost('localhost')).toBe(false);
    expect(isPublicPixelocityHost('127.0.0.1')).toBe(false);
  });

  it('mounts remote only when mode=remote and host is not public', () => {
    expect(shouldMountRemoteApp('?mode=remote', 'test.1ink.us')).toBe(true);
    expect(shouldMountRemoteApp('mode=remote', 'localhost')).toBe(true);
    expect(shouldMountRemoteApp('?mode=remote', 'go.1ink.us')).toBe(false);
    expect(shouldMountRemoteApp('', 'test.1ink.us')).toBe(false);
    expect(shouldMountRemoteApp('?mode=main', 'test.1ink.us')).toBe(false);
  });
});
