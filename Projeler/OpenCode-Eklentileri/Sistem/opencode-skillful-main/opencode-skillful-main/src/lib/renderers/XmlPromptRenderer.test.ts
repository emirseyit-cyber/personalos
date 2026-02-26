/**
 * XmlPromptRenderer Tests
 *
 * Test coverage for real use cases:
 * - Rendering Skill objects as XML with resource maps converted to arrays
 * - Rendering SkillResource objects (file content)
 * - Rendering SkillSearchResults objects
 * - XML character escaping for security
 * - Resource map serialization
 */

import { describe, it, expect } from 'vitest';
import { createXmlPromptRenderer } from './XmlPromptRenderer';
import type { Skill } from '../../types';

describe('XmlPromptRenderer', () => {
  const renderer = createXmlPromptRenderer();

  it('should have xml format identifier', () => {
    expect(renderer.format).toBe('xml');
  });

  it('should render Skill object as XML with resource maps', () => {
    const references = new Map([
      [
        'api-guide.md',
        {
          absolutePath: '/skills/api/references/api-guide.md',
          mimeType: 'text/markdown',
        },
      ],
    ]);

    const skill: Skill = {
      name: 'rest-api',
      fullPath: '/skills/rest-api',
      toolName: 'skill_rest_api',
      description: 'REST API design patterns',
      content: 'REST API patterns content',
      path: '/skills/rest-api/SKILL.md',
      scripts: new Map(),
      references,
      assets: new Map(),
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    expect(result).toContain('<Skill>');
    expect(result).toContain('</Skill>');
    expect(result).toContain('<name>rest-api</name>');
    expect(result).toContain('<description>REST API design patterns</description>');
    expect(result).toContain('<references>');
    expect(result).toContain('api-guide.md');
  });

  it('should render SkillResource object (file content)', () => {
    const data = {
      skill_name: 'security-patterns',
      resource_path: 'references/owasp-guidelines.md',
      resource_mimetype: 'text/markdown',
      content: 'OWASP Top 10 security guidelines...',
    };

    const result = renderer.render({ data, type: 'SkillResource' });

    expect(result).toContain('<SkillResource>');
    expect(result).toContain('</SkillResource>');
    expect(result).toContain('<skill_name>security-patterns</skill_name>');
    expect(result).toContain('<resource_path>references/owasp-guidelines.md</resource_path>');
    expect(result).toContain('<content>OWASP Top 10 security guidelines...</content>');
  });

  it('should render SkillSearchResults object', () => {
    const data = {
      query: 'testing',
      skills: [
        { name: 'unit-testing', description: 'Unit testing best practices' },
        { name: 'integration-testing', description: 'Integration test patterns' },
      ],
      summary: {
        total: 20,
        matches: 2,
        feedback: 'Found 2 skills matching "testing"',
      },
    };

    const result = renderer.render({ data, type: 'SkillSearchResults' });

    expect(result).toContain('<SkillSearchResults>');
    expect(result).toContain('</SkillSearchResults>');
    expect(result).toContain('<query>testing</query>');
    expect(result).toContain('<skills>');
    expect(result).toContain('<name>unit-testing</name>');
    expect(result).toContain('<name>integration-testing</name>');
    expect(result).toContain('<matches>2</matches>');
  });

  it('should escape special XML characters for security', () => {
    const data = {
      skill_name: 'dangerous-content',
      resource_path: 'test.md',
      resource_mimetype: 'text/markdown',
      content: 'Content with <tags> & ampersands "quoted"',
    };

    const result = renderer.render({ data, type: 'SkillResource' });

    expect(result).toContain('&lt;tags&gt;');
    expect(result).toContain('&amp;');
    expect(result).toContain('&quot;');
    expect(result).not.toContain('<tags>');
  });

  it('should handle Skill with multiple resource types', () => {
    const references = new Map([
      ['guide.md', { absolutePath: '/skills/test/references/guide.md', mimeType: 'text/markdown' }],
    ]);

    const scripts = new Map([
      ['setup.sh', { absolutePath: '/skills/test/scripts/setup.sh', mimeType: 'application/x-sh' }],
    ]);

    const skill: Skill = {
      name: 'complex-skill',
      fullPath: '/skills/complex-skill',
      toolName: 'skill_complex',
      description: 'Skill with multiple resources',
      content: 'Content',
      path: '/skills/complex-skill/SKILL.md',
      scripts,
      references,
      assets: new Map(),
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    expect(result).toContain('<Skill>');
    expect(result).toContain('<references>');
    expect(result).toContain('<scripts>');
    expect(result).toContain('guide.md');
    expect(result).toContain('setup.sh');
  });

  it('should handle Skill with empty resource maps', () => {
    const skill: Skill = {
      name: 'minimal-skill',
      fullPath: '/skills/minimal',
      toolName: 'skill_minimal',
      description: 'Skill without resources',
      content: 'Content',
      path: '/skills/minimal/SKILL.md',
      scripts: new Map(),
      references: new Map(),
      assets: new Map(),
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    expect(result).toContain('<Skill>');
    expect(result).toContain('<name>minimal-skill</name>');
    expect(() => {
      // Verify it's valid XML by checking structure
      expect(result).toMatch(/<Skill>[\s\S]*<\/Skill>/);
    }).not.toThrow();
  });
});
