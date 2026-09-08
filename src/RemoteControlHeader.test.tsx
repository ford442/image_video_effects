import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { RemoteControlHeader } from './RemoteControlHeader';

describe('RemoteControlHeader', () => {
  it('calls onLoadRandom when Random Image is clicked', () => {
    const onLoadRandom = jest.fn();
    render(
      <RemoteControlHeader
        inputSource="image"
        onLoadRandom={onLoadRandom}
        hidden={false}
        onHide={jest.fn()}
      />
    );
    fireEvent.click(screen.getByRole('button', { name: /random image/i }));
    expect(onLoadRandom).toHaveBeenCalled();
  });

  it('disables Random Image when the source is not image', () => {
    render(
      <RemoteControlHeader
        inputSource="video"
        onLoadRandom={jest.fn()}
        hidden={false}
        onHide={jest.fn()}
      />
    );
    expect(screen.getByRole('button', { name: /random image/i })).toBeDisabled();
  });

  it('renders title, random image, and hide when shown', () => {
    render(
      <RemoteControlHeader
        inputSource="image"
        onLoadRandom={jest.fn()}
        hidden={false}
        onHide={jest.fn()}
      />
    );
    expect(screen.getByRole('heading', { name: /remote control/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /random image/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /hide controls/i })).toBeInTheDocument();
  });

  it('renders nothing when hidden', () => {
    const { container } = render(
      <RemoteControlHeader
        inputSource="image"
        onLoadRandom={jest.fn()}
        hidden
        onHide={jest.fn()}
      />
    );
    expect(container).toBeEmptyDOMElement();
    expect(screen.queryByRole('heading', { name: /remote control/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /random image/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /hide controls/i })).not.toBeInTheDocument();
  });

  it('calls onHide when Hide Controls is clicked', () => {
    const onHide = jest.fn();
    render(
      <RemoteControlHeader
        inputSource="image"
        onLoadRandom={jest.fn()}
        hidden={false}
        onHide={onHide}
      />
    );
    fireEvent.click(screen.getByRole('button', { name: /hide controls/i }));
    expect(onHide).toHaveBeenCalled();
  });
});
