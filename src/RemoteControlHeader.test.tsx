import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { RemoteControlHeader } from './RemoteControlHeader';

describe('RemoteControlHeader', () => {
  it('calls onLoadRandom when Random Image is clicked', () => {
    const onLoadRandom = jest.fn();
    render(<RemoteControlHeader inputSource="image" onLoadRandom={onLoadRandom} />);
    fireEvent.click(screen.getByRole('button', { name: /random image/i }));
    expect(onLoadRandom).toHaveBeenCalled();
  });

  it('disables Random Image when the source is not image', () => {
    render(<RemoteControlHeader inputSource="video" onLoadRandom={jest.fn()} />);
    expect(screen.getByRole('button', { name: /random image/i })).toBeDisabled();
  });
});
