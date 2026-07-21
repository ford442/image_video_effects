import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import '@testing-library/jest-dom';
import { VideoSourcePanel } from './VideoSourcePanel';

const videoList = [
    { url: 'https://example.com/a.mp4', title: 'Clip A', duration: 42 },
    { url: 'https://example.com/b.mp4', title: 'Clip B' },
];

test('renders video select and fires selection callbacks', () => {
    const setSelectedVideo = jest.fn();
    const setInputSource = jest.fn();

    render(
        <VideoSourcePanel
            selectedVideo=""
            setSelectedVideo={setSelectedVideo}
            setInputSource={setInputSource}
            videoList={videoList}
            onUploadVideoTrigger={() => {}}
            isMuted={false}
            setIsMuted={() => {}}
        />
    );

    const select = screen.getByRole('combobox');
    expect(select).toBeInTheDocument();
    expect(screen.getByText('Clip A (42s)')).toBeInTheDocument();

    fireEvent.change(select, { target: { value: 'https://example.com/a.mp4' } });

    expect(setSelectedVideo).toHaveBeenCalledWith('https://example.com/a.mp4');
    expect(setInputSource).toHaveBeenCalledWith('video');
});
