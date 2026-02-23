const API_BASE = process.env.REACT_APP_STORAGE_API || 'https://ford442-storage-manager.hf.space';

export interface ShaderMeta {
  id: string;
  name: string;
  author: string;
  date: string;
  description: string;
  tags: string[];
  filename: string;
  stars: number;
  rating_count: number;
  thumbnail?: string;
}

export interface ShaderUploadData {
  name: string;
  description?: string;
  tags?: string[];
  author?: string;
}

export interface ShaderListParams {
  category?: string;
  minStars?: number;
  sortBy?: 'date' | 'rating' | 'name' | 'last_played' | 'genre';
}

export const shaderApi = {
  async list(params: ShaderListParams = {}): Promise<ShaderMeta[]> {
    const query = new URLSearchParams();
    if (params.category) query.append('category', params.category);
    if (params.minStars !== undefined) query.append('min_stars', params.minStars.toString());
    if (params.sortBy) query.append('sort_by', params.sortBy);
    
    const response = await fetch(`${API_BASE}/api/shaders?${query}`);
    if (!response.ok) throw new Error('Failed to fetch shaders');
    return response.json();
  },

  async getMeta(shaderId: string): Promise<ShaderMeta> {
    const response = await fetch(`${API_BASE}/api/shaders/${shaderId}`);
    if (!response.ok) throw new Error('Failed to fetch shader meta');
    return response.json();
  },

  async getCode(shaderId: string): Promise<{ id: string; code: string; name: string }> {
    const response = await fetch(`${API_BASE}/api/shaders/${shaderId}/code`);
    if (!response.ok) throw new Error('Failed to fetch shader code');
    return response.json();
  },

  async upload(file: File, data: ShaderUploadData): Promise<{ success: boolean; id: string; meta: ShaderMeta }> {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('name', data.name);
    if (data.description) formData.append('description', data.description);
    if (data.tags) formData.append('tags', data.tags.join(','));
    if (data.author) formData.append('author', data.author);

    const response = await fetch(`${API_BASE}/api/shaders/upload`, {
      method: 'POST',
      body: formData,
    });
    if (!response.ok) throw new Error('Upload failed');
    return response.json();
  },

  async rate(shaderId: string, stars: number): Promise<ShaderMeta> {
    const formData = new FormData();
    formData.append('stars', stars.toString());
    
    const response = await fetch(`${API_BASE}/api/shaders/${shaderId}/rate`, {
      method: 'POST',
      body: formData,
    });
    if (!response.ok) throw new Error('Rating failed');
    return response.json();
  },

  async update(shaderId: string, data: { description?: string; tags?: string[] }): Promise<ShaderMeta> {
    const formData = new FormData();
    if (data.description) formData.append('description', data.description);
    if (data.tags) formData.append('tags', data.tags.join(','));
    
    const response = await fetch(`${API_BASE}/api/shaders/${shaderId}/update`, {
      method: 'POST',
      body: formData,
    });
    if (!response.ok) throw new Error('Update failed');
    return response.json();
  },
};
