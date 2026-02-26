/**
 * JsonPromptRenderer Tests
 *
 * Test coverage for real use cases:
 * - Rendering Skill objects for prompt injection
 * - Rendering SkillResource objects (file content)
 * - Rendering SkillSearchResults objects (search results)
 * - Proper JSON formatting with indentation
 */

import { describe, it, expect } from 'vitest';
import { createJsonPromptRenderer } from './JsonPromptRenderer';
import type { Skill } from '../../types';

describe('JsonPromptRenderer', () => {
  const renderer = createJsonPromptRenderer();

  it('should have json format identifier', () => {
    expect(renderer.format).toBe('json');
  });

  it('should render Skill object for prompt injection', () => {
    const skill: Skill = {
      name: 'auth-patterns',
      fullPath: '/home/user/.opencode/skills/auth-patterns',
      toolName: 'skill_auth_patterns',
      description: 'Common authentication patterns and best practices',
      content: '# Authentication Patterns\n\nStandard approaches...',
      path: '/home/user/.opencode/skills/auth-patterns/SKILL.md',
      scripts: new Map(),
      references: new Map(),
      assets: new Map(),
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    expect(result).toContain('"Skill"');
    expect(result).toContain('"name": "auth-patterns"');
    expect(result).toContain('"toolName": "skill_auth_patterns"');
    expect(result).toContain('"description"');
    expect(result).toMatch(/\n/); // Has newlines for readability
    expect(result).toMatch(/[ ]{2}/); // Has indentation
  });

  it('should render SkillResource object (file content)', () => {
    const data = {
      skill_name: 'api-design',
      resource_path: 'references/rest-guidelines.md',
      resource_mimetype: 'text/markdown',
      content: '# REST API Guidelines\n\n## Best Practices\n\n...',
    };

    const result = renderer.render({ data, type: 'SkillResource' });

    expect(result).toContain('"SkillResource"');
    expect(result).toContain('"skill_name": "api-design"');
    expect(result).toContain('"resource_path": "references/rest-guidelines.md"');
    expect(result).toContain('"resource_mimetype": "text/markdown"');
    expect(result).toContain('"content"');
  });

  it('should render SkillSearchResults object', () => {
    const data = {
      query: 'authentication',
      skills: [
        { name: 'auth-patterns', description: 'Common auth patterns' },
        { name: 'oauth-setup', description: 'OAuth implementation guide' },
      ],
      summary: {
        total: 25,
        matches: 2,
        feedback: 'Found 2 skills matching "authentication"',
      },
    };

    const result = renderer.render({ data, type: 'SkillSearchResults' });

    expect(result).toContain('"SkillSearchResults"');
    expect(result).toContain('"query": "authentication"');
    expect(result).toContain('"auth-patterns"');
    expect(result).toContain('"oauth-setup"');
    expect(result).toContain('"matches": 2');
    expect(result).toContain('"total": 25');
  });

  it('should properly format JSON with indentation', () => {
    const skill: Skill = {
      name: 'test-skill',
      fullPath: '/path/to/skill',
      toolName: 'test_skill',
      description: 'Test skill',
      content: 'Content',
      path: '/path/to/skill/SKILL.md',
      scripts: new Map(),
      references: new Map(),
      assets: new Map(),
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    // Verify it's valid JSON
    expect(() => JSON.parse(result)).not.toThrow();

    // Verify it has proper formatting
    expect(result).toMatch(/\n/); // Has newlines
    expect(result).toMatch(/ {2}"/); // Has 2-space indentation
  });

  it('should handle optional Skill properties', () => {
    const skill: Skill = {
      name: 'minimal-skill',
      fullPath: '/path/to/skill',
      toolName: 'minimal_skill',
      description: 'Minimal skill',
      content: 'Content',
      path: '/path/to/skill/SKILL.md',
      scripts: new Map(),
      references: new Map(),
      assets: new Map(),
      metadata: { version: '1.0.0' },
      license: 'MIT',
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    expect(() => JSON.parse(result)).not.toThrow();
    expect(result).toContain('"metadata"');
    expect(result).toContain('"license": "MIT"');
  });
});
