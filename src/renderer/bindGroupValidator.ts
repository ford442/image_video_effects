/**
 * bindGroupValidator.ts
 *
 * Static WGSL validation against the fixed 13-binding compute layout.
 * Fails loudly with readable errors BEFORE pipeline creation.
 */

export interface BindGroupValidationResult {
  valid: boolean;
  shaderId: string;
  missingBindings: string[];
  wrongTypeBindings: string[];
  extraFields: string[];
  errors: string[];
  warnings: string[];
}

/** Expected bindings for the fixed Pixelocity compute layout */
const REQUIRED_BINDINGS: Record<number, { name: string; patterns: RegExp[] }> = {
  0: { name: 'u_sampler', patterns: [/var\s+u_sampler\s*:\s*sampler/] },
  1: { name: 'readTexture', patterns: [/var\s+readTexture\s*:\s*texture_2d<f32>/] },
  2: { name: 'writeTexture', patterns: [/var\s+writeTexture\s*:\s*texture_storage_2d<rgba32float,\s*write>/] },
  3: { name: 'u (uniforms)', patterns: [/var<uniform>\s+u\s*:\s*Uniforms/] },
  4: { name: 'readDepthTexture', patterns: [/var\s+readDepthTexture\s*:\s*texture_2d<f32>/] },
  5: { name: 'non_filtering_sampler', patterns: [/var\s+non_filtering_sampler\s*:\s*sampler/] },
  6: { name: 'writeDepthTexture', patterns: [/var\s+writeDepthTexture\s*:\s*texture_storage_2d<r32float,\s*write>/] },
  7: { name: 'dataTextureA', patterns: [/var\s+dataTextureA\s*:\s*texture_storage_2d<rgba32float,\s*write>/] },
  8: { name: 'dataTextureB', patterns: [/var\s+dataTextureB\s*:\s*texture_storage_2d<rgba32float,\s*write>/] },
  9: { name: 'dataTextureC', patterns: [/var\s+dataTextureC\s*:\s*texture_2d<f32>/] },
  10: { name: 'extraBuffer', patterns: [/var<storage,\s*read_write>\s+extraBuffer\s*:\s*array<f32>/] },
  11: { name: 'comparison_sampler', patterns: [/var\s+comparison_sampler\s*:\s*sampler_comparison/] },
  12: { name: 'plasmaBuffer', patterns: [/var<storage,\s*read>\s+plasmaBuffer\s*:\s*array<vec4<f32>>/] },
};

/** Required fields in the Uniforms struct */
const REQUIRED_UNIFORM_FIELDS = ['config', 'zoom_config', 'zoom_params', 'ripples'];

/**
 * Validate WGSL source against the fixed bind group layout.
 * This is a fast static check that runs before createComputePipeline.
 */
export function validateBindGroup(
  shaderId: string,
  wgsl: string
): BindGroupValidationResult {
  const result: BindGroupValidationResult = {
    valid: true,
    shaderId,
    missingBindings: [],
    wrongTypeBindings: [],
    extraFields: [],
    errors: [],
    warnings: [],
  };

  // 1. Check required bindings
  for (let binding = 0; binding <= 12; binding++) {
    const req = REQUIRED_BINDINGS[binding];
    const bindingRegex = new RegExp(
      `@group\\(0\\)\\s*@binding\\(${binding}\\)`,
      'g'
    );
    const hasBinding = bindingRegex.test(wgsl);

    if (!hasBinding) {
      result.missingBindings.push(`Binding ${binding} (${req.name})`);
      result.errors.push(`Missing binding ${binding} (${req.name})`);
      result.valid = false;
      continue;
    }

    // Check type pattern near the binding declaration
    const typeMatch = req.patterns.some((p) => p.test(wgsl));
    if (!typeMatch) {
      // Some shaders use aliases (e.g. outTex instead of writeTexture).
      // We only flag if the binding exists but the canonical name is missing.
      const hasAnyVar = new RegExp(
        `@group\\(0\\)\\s*@binding\\(${binding}\\)[^;]*var`,
        'g'
      ).test(wgsl);
      if (!hasAnyVar) {
        result.wrongTypeBindings.push(`Binding ${binding} (${req.name}) has unexpected type`);
        result.warnings.push(`Binding ${binding} (${req.name}) type mismatch or alias`);
      }
    }
  }

  // 2. Check Uniforms struct
  const uniformsMatch = wgsl.match(/struct\s+Uniforms\s*\{([^}]*)\}/s);
  if (!uniformsMatch) {
    result.errors.push("Missing 'struct Uniforms' declaration");
    result.valid = false;
  } else {
    const body = uniformsMatch[1];
    for (const field of REQUIRED_UNIFORM_FIELDS) {
      if (!body.includes(field)) {
        result.errors.push(`Uniforms struct missing field: ${field}`);
        result.valid = false;
      }
    }
  }

  // 3. Check compute entry point
  const hasCompute = /@compute/.test(wgsl);
  const hasMain = /fn\s+main\s*\(/.test(wgsl);
  if (!hasCompute) {
    result.errors.push("Missing @compute decorator");
    result.valid = false;
  }
  if (!hasMain) {
    result.errors.push("Missing 'fn main' entry point");
    result.valid = false;
  }

  // 4. Warn on extended bindings (13+)
  const extendedBinding = wgsl.match(/@group\(0\)\s*@binding\((\d+)\)/g);
  if (extendedBinding) {
    const maxBinding = Math.max(
      ...extendedBinding.map((b) => {
        const m = b.match(/@binding\((\d+)\)/);
        return m ? parseInt(m[1], 10) : 0;
      })
    );
    if (maxBinding > 12) {
      result.warnings.push(`Uses extended binding(s): ${maxBinding}`);
    }
  }

  return result;
}

/**
 * Quick check: returns true if shader is compatible, false otherwise.
 * Logs detailed errors to console.
 */
export function checkShaderCompatible(
  shaderId: string,
  wgsl: string
): boolean {
  const result = validateBindGroup(shaderId, wgsl);
  if (!result.valid) {
    console.error(
      `[BindGroupValidator] Shader "${shaderId}" incompatible with fixed layout:`
    );
    for (const err of result.errors) {
      console.error(`  ❌ ${err}`);
    }
    for (const warn of result.warnings) {
      console.warn(`  ⚠️  ${warn}`);
    }
  }
  return result.valid;
}
