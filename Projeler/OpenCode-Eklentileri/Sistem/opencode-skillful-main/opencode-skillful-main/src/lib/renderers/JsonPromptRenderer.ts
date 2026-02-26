/**
 * JsonPromptRenderer - Format objects as JSON
 *
 * WHY: Some LLM models (especially GPT family) have strong JSON parsing
 * and prefer structured JSON data over XML for reliability and clarity.
 */

import type { PromptRenderer } from '../../types';

export const createJsonPromptRenderer = (): PromptRenderer => {
  const renderer: PromptRenderer = {
    format: 'json' as const,
    render(args) {
      return JSON.stringify({ [args.type]: args.data }, null, 2);
    },
  };

  return renderer;
};
