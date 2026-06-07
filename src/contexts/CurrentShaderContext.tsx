import React, { createContext, useContext, useState, ReactNode } from 'react';

interface CurrentShaderContextValue {
  currentWgsl: string;
  setCurrentWgsl: (wgsl: string) => void;
}

const CurrentShaderContext = createContext<CurrentShaderContextValue | undefined>(undefined);

interface CurrentShaderProviderProps {
  children: ReactNode;
}

export function CurrentShaderProvider({ children }: CurrentShaderProviderProps) {
  const [currentWgsl, setCurrentWgsl] = useState('');

  return (
    <CurrentShaderContext.Provider value={{ currentWgsl, setCurrentWgsl }}>
      {children}
    </CurrentShaderContext.Provider>
  );
}

export function useCurrentShader() {
  const context = useContext(CurrentShaderContext);
  if (context === undefined) {
    throw new Error('useCurrentShader must be used within a CurrentShaderProvider');
  }
  return context;
}
