/**
 * XmlPromptRenderer - Format objects as XML (current default)
 *
 * WHY: Claude models are trained extensively on XML and prefer structured
 * XML injection for skill metadata and search results. This maintains the
 * current behavior as the default and recommended format for Claude models.
 */

import type { PromptRenderer, Skill, SkillResource, SkillSearchResult } from '../../types';
import { jsonToXml } from '../xml';
import { resourceMapToArray } from './resourceMapToArray';

export const createXmlPromptRenderer = () => {
  /**
   * Skills need special preparation before rendering
   * 1. resource maps need to be converted to arrays
   */
  const prepareSkill = (skill: Skill): object => {
    // Add any skill-specific preparation logic here if needed

    return {
      ...skill,
      references: resourceMapToArray(skill.references),
      scripts: resourceMapToArray(skill.scripts),
      assets: resourceMapToArray(skill.assets),
    };
  };

  const prepareResource = (resource: SkillResource): object => {
    // Add any resource-specific preparation logic here if needed
    return resource;
  };

  const prepareSearchResult = (result: SkillSearchResult): object => {
    // Add any search result-specific preparation logic here if needed
    return result;
  };

  const renderer: PromptRenderer = {
    format: 'xml' as const,

    render(args) {
      const rootElement = args.type || 'root';

      if (args.type === 'Skill') {
        return jsonToXml(prepareSkill(args.data), rootElement);
      }
      if (args.type === 'SkillResource') {
        return jsonToXml(prepareResource(args.data), rootElement);
      }
      if (args.type === 'SkillSearchResults') {
        return jsonToXml(prepareSearchResult(args.data), rootElement);
      }

      return jsonToXml({}, rootElement);
    },
  };

  return renderer;
};
