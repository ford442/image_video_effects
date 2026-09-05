import aliasManifest from './shader-id-aliases.json';

const ALIASES: Record<string, string> = (aliasManifest as { aliases?: Record<string, string> }).aliases ?? {};

/**
 * Resolve legacy hyphen share URLs to canonical catalog ids (22 underscore ids).
 * Unknown ids pass through unchanged.
 */
export function resolveShaderId(shaderId: string): string {
  if (!shaderId) return shaderId;
  return ALIASES[shaderId] ?? shaderId;
}

export function getShaderIdAliases(): Readonly<Record<string, string>> {
  return ALIASES;
}
