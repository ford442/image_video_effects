import React from 'react';
import ReactDOM from 'react-dom/client';
import MainApp from './App';
import RemoteApp from './RemoteApp';
import ShaderValidator from './components/ShaderValidator';
import { shouldMountRemoteApp } from './utils/publicHost';

// Check URL parameters to determine which app to render
const urlParams = new URLSearchParams(window.location.search);
const isValidator = urlParams.has('validator');
const mountRemote = shouldMountRemoteApp(window.location.search, window.location.hostname);

const root = ReactDOM.createRoot(
  document.getElementById('root') as HTMLElement
);

root.render(
  <React.StrictMode>
    {isValidator ? <ShaderValidator /> : mountRemote ? <RemoteApp /> : <MainApp />}
  </React.StrictMode>
);
