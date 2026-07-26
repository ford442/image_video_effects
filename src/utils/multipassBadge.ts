import { countGraphPasses } from '../renderer/multipassGraph';
import {
  MULTIPASS_REGISTRY,
  hasGraph,
  resolveGraphForShader,
} from '../renderer/multipassRegistry';

/** Pass-count label for shader browser cards (Tier C graph or Tier B linear). */
export function getMultipassBadgeLabel(shaderId: string): string | null {
  if (hasGraph(shaderId)) {
    const graph = resolveGraphForShader(shaderId);
    if (!graph) return null;
    const passes = countGraphPasses(graph);
    return `graph · ${passes} passes`;
  }
  const info = MULTIPASS_REGISTRY[shaderId];
  if (info && info.totalPasses > 1 && info.pass === 1) {
    return `${info.totalPasses}-pass`;
  }
  return null;
}
