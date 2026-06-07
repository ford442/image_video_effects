import React from 'react';
import ReactDOM from 'react-dom/client';
import MainApp from './App';
import RemoteApp from './RemoteApp';
import ShaderValidator from './components/ShaderValidator';

// Check URL parameters to determine which app to render
const urlParams = new URLSearchParams(window.location.search);
const mode = urlParams.get('mode');
const isValidator = urlParams.has('validator');

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

root.render(
  <React.StrictMode>
    {isValidator ? <ShaderValidator /> : mode === 'remote' ? <RemoteApp /> : <MainApp />}
  </React.StrictMode>
);
