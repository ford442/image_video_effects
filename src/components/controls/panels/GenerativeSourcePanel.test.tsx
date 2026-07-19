import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { GenerativeSourcePanel } from './GenerativeSourcePanel';

const generativeMenuOptions = [
    { id: 'gen-orb', name: 'Gen Orb', coordinate: 101, category: 'generative' },
    { id: 'gen-wave', name: 'Gen Wave', coordinate: 102, category: 'generative' },
];

test('renders generative picker and calls setActiveGenerativeShader', () => {
    const setActiveGenerativeShader = jest.fn();

    render(
        <GenerativeSourcePanel
            activeGenerativeShader="gen-orb"
            setActiveGenerativeShader={setActiveGenerativeShader}
            generativeMenuOptions={generativeMenuOptions}
        />
    );

    expect(screen.getByText('Generative Shader')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /gen orb/i }));
    fireEvent.mouseDown(screen.getByText('Gen Wave'));

    expect(setActiveGenerativeShader).toHaveBeenCalledWith('gen-wave');
});
