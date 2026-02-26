/**
 * MdPromptRenderer Tests
 *
 * Test coverage for real use cases:
 * - Rendering Skill objects with metadata, references, scripts, assets
 * - Rendering SkillResource objects (file content)
 * - Rendering SkillSearchResults objects
 * - HTML character escaping for security
 * - Special values handling (null, undefined)
 */

import { describe, it, expect } from 'vitest';
import { createMdPromptRenderer } from './MdPromptRenderer';
import type { Skill } from '../../types';

describe('MdPromptRenderer', () => {
  const renderer = createMdPromptRenderer();

  it('should have md format identifier', () => {
    expect(renderer.format).toBe('md');
  });

  it('should render Skill object with metadata and resources', () => {
    const skill: Skill = {
      name: 'git-workflows',
      fullPath: '/home/user/.opencode/skills/git-workflows',
      toolName: 'skill_git_workflows',
      description: 'Git workflow patterns and best practices',
      content: '# Git Workflows\n\n## Feature Branch Workflow\n\nStandard approach...',
      path: '/home/user/.opencode/skills/git-workflows/SKILL.md',
      scripts: new Map(),
      references: new Map(),
      assets: new Map(),
      metadata: { version: '1.0.0', author: 'Team' },
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    expect(result).toContain('# git-workflows');
    expect(result).toContain('Git Workflows');
    expect(result).toContain('## Metadata');
    expect(result).toContain('## References');
    expect(result).toContain('## Scripts');
    expect(result).toContain('## Assets');
  });

  it('should render SkillResource object (file content)', () => {
    const data = {
      skill_name: 'api-design',
      resource_path: 'references/rest-guidelines.md',
      resource_mimetype: 'text/markdown',
      content: 'REST Guidelines content here',
    };

    const result = renderer.render({ data, type: 'SkillResource' });

    expect(result).toContain('skill_name');
    expect(result).toContain('api-design');
    expect(result).toContain('rest-guidelines.md');
    expect(result).toContain('REST Guidelines content here');
  });

  it('should render SkillSearchResults object', () => {
    const data = {
      query: 'authentication',
      skills: [
        { name: 'oauth-setup', description: 'OAuth implementation guide' },
        { name: 'jwt-patterns', description: 'JWT patterns and best practices' },
      ],
      summary: {
        total: 15,
        matches: 2,
        feedback: 'Found 2 skills matching "authentication"',
      },
    };

    const result = renderer.render({ data, type: 'SkillSearchResults' });

    expect(result).toContain('oauth-setup');
    expect(result).toContain('jwt-patterns');
    expect(result).toContain('2');
    expect(result).toContain('authentication');
  });

  it('should HTML-escape special characters for security', () => {
    const data = {
      skill_name: 'xss-test',
      resource_path: 'test.md',
      resource_mimetype: 'text/markdown',
      content: '<script>alert("xss")</script> & dangerous',
    };

    const result = renderer.render({ data, type: 'SkillResource' });

    expect(result).toContain('&lt;script&gt;');
    expect(result).toContain('&amp;');
    expect(result).not.toContain('<script>');
  });

  it('should skip null and undefined values in search results', () => {
    const data = {
      query: 'test',
      skills: [{ name: 'skill1', description: 'Test skill' }],
      summary: {
        total: 10,
        matches: 1,
        feedback: 'Found 1 skill',
      },
      debug: undefined,
    };

    const result = renderer.render({ data, type: 'SkillSearchResults' });

    expect(result).toContain('skill1');
    expect(result).toContain('Found 1 skill');
    expect(result).not.toContain('debug');
  });

  it('should handle Skill with optional metadata', () => {
    const skill: Skill = {
      name: 'minimal-skill',
      fullPath: '/path/to/skill',
      toolName: 'minimal_skill',
      description: 'Minimal skill without metadata',
      content: '# Content',
      path: '/path/to/skill/SKILL.md',
      scripts: new Map(),
      references: new Map(),
      assets: new Map(),
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    expect(result).toContain('minimal-skill');
    expect(result).toContain('# Content');
    expect(result).toContain('## Metadata');
  });

  it('should render Skill with resource maps', () => {
    const references = new Map([
      [
        'guide.md',
        {
          absolutePath: '/skills/git/references/guide.md',
          mimeType: 'text/markdown',
        },
      ],
    ]);

    const skill: Skill = {
      name: 'git-skill',
      fullPath: '/skills/git',
      toolName: 'skill_git',
      description: 'Git patterns',
      content: '# Git',
      path: '/skills/git/SKILL.md',
      scripts: new Map(),
      references,
      assets: new Map(),
    };

    const result = renderer.render({ data: skill, type: 'Skill' });

    expect(result).toContain('git-skill');
    expect(result).toContain('References');
  });
});
