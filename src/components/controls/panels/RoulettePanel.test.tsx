import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { RoulettePanel } from './RoulettePanel';

test('renders randomize slot button and fires onRoulette', () => {
    const onRoulette = jest.fn();

    render(
        <RoulettePanel
            activeSlot={1}
            onRoulette={onRoulette}
        />
    );

    expect(screen.getByText(/Randomize Slot 2/)).toBeInTheDocument();

    fireEvent.click(screen.getByText(/Randomize Slot 2/));
    expect(onRoulette).toHaveBeenCalledTimes(1);
});
