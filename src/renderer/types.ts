export type RenderMode = string;

export type ShaderCategory = 'shader' | 'image' | 'video';

export type InputSource = 'image' | 'video';

export interface ShaderParam {
    id: string;
    name: string;
    default: number;
    min: number;
    max: number;
    step?: number;
    labels?: string[];
}

export interface ShaderEntry {
    id: string;
    name: string;
    url: string;
    category: ShaderCategory;
    description?: string;
    params?: ShaderParam[];
    advanced_params?: ShaderParam[];
    features?: string[];
}
