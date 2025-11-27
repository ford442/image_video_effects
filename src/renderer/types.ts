export type RenderMode = string;

export type ShaderCategory = 'shader' | 'image' | 'video';

export interface ShaderEntry {
    id: string;
    name: string;
    url: string;
    category: ShaderCategory;
}
