import React from 'react';
import { ShaderCategory, InputSource } from '../../../renderer/types';

export interface InputSourcePanelProps {
    inputSource: InputSource;
    setInputSource: (source: InputSource) => void;
    setShaderCategory: (category: ShaderCategory) => void;
}

export const InputSourcePanel: React.FC<InputSourcePanelProps> = ({
    inputSource,
    setInputSource,
    setShaderCategory,
}) => (
    <div className="control-group">
        <label className="gold-section-header">Input Source</label>
        <div className="gold-radio-group">
            <label>
                <input
                    type="radio"
                    value="image"
                    checked={inputSource === 'image'}
                    onChange={() => {
                        setInputSource('image');
                        setShaderCategory('image');
                    }}
                /> Image
            </label>
            <label>
                <input
                    type="radio"
                    value="video"
                    checked={inputSource === 'video'}
                    onChange={() => {
                        setInputSource('video');
                        setShaderCategory('image');
                    }}
                /> Video
            </label>
            <label>
                <input
                    type="radio"
                    value="webcam"
                    checked={inputSource === 'webcam'}
                    onChange={() => {
                        setInputSource('webcam');
                        setShaderCategory('image');
                    }}
                /> Webcam
            </label>
            <label>
                <input
                    type="radio"
                    value="generative"
                    checked={inputSource === 'generative'}
                    onChange={() => setInputSource('generative')}
                /> Generative
            </label>
            <label>
                <input
                    type="radio"
                    value="live"
                    checked={inputSource === 'live'}
                    onChange={() => setInputSource('live')}
                /> 🔴 Live
            </label>
        </div>
    </div>
);

export default InputSourcePanel;
