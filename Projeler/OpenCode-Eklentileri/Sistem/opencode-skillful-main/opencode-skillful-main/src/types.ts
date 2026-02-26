/**
 * Type definitions for OpenCode Skills Plugin
 */

import { ReadyStateMachine } from './lib/ReadyStateMachine';

/**
 * PromptRenderer Interface - Provider Pattern for Prompt Injection Formatting
 *
 * WHY: Different LLM models have different strengths and preferences for structured data:
 * - Claude models: trained extensively on XML, prefer structured XML injection
 * - GPT models: strong JSON parsing, prefer JSON-formatted data
 * - Other models: may benefit from markdown readability for better context
 *
 * The provider pattern allows selecting the appropriate renderer at runtime based on:
 * - Model preference (configured in modelRenderers)
 * - Global default (promptRenderer)
 * - Model detection via client.session.message()
 *
 * This abstraction decouples rendering format from tool execution logic,
 * enabling easy format additions without changing plugin code.
 */

type SkillInjectionResult = {
  skill_name: string;
  resource_path: string;
  resource_mimetype: string;
  content: string;
};

type SkillSearchResultInjection = {
  query: string | string[];
  skills: Array<{ name: string; description: string }>;
  summary: { total: number; matches: number; feedback: string };
  debug?: SkillRegistryDebugInfo;
};

type Args =
  | { data: Skill; type: 'Skill' }
  | { data: SkillInjectionResult; type: 'SkillResource' }
  | { data: SkillSearchResultInjection; type: 'SkillSearchResults' };

export interface PromptRenderer {
  /**
   * Render an object to a string using the preferred format
   *
   * @param data The object to render (typically skill metadata or search results)
   * @param rootElement Optional element name (used for XML rendering as root tag)
   * @returns Formatted string ready for prompt injection
   */
  render(args: Args): string;

  /**
   * The format identifier for this renderer
   * Used for logging, debugging, and format selection
   */
  readonly format: 'json' | 'xml' | 'md';
}

/**
 * Skill resource map type for indexing skill resources
 *
 * A Map of relative paths to resource metadata. Used to securely resolve
 * and access skill resources without allowing path traversal attacks.
 *
 * Key: relative path to the resource (e.g., "scripts/build.sh", "references/README.md")
 * Value: resource metadata
 *   - absolutePath: absolute filesystem path (pre-validated during skill initialization)
 *   - mimeType: detected MIME type for proper content handling
 *
 * Example:
 *   Map {
 *     "scripts/build.sh" => { absolutePath: "/skills/cli/scripts/build.sh", mimeType: "application/x-sh" },
 *     "references/api.md" => { absolutePath: "/skills/cli/references/api.md", mimeType: "text/markdown" }
 *   }
 */
export type SkillResource = {
  relativePath: string;
  absolutePath: string;
  mimeType: string;
};
export type SkillResourceMap = Map<string, Omit<SkillResource, 'relativePath'>>;

const ResourceTypes = ['script', 'asset', 'reference'] as const;
type ResourceType = (typeof ResourceTypes)[number];

/**
 * Asserts that the provided type is a valid ResourceType
 */
export const assertIsValidResourceType: (type: string) => asserts type is ResourceType = (type) => {
  if (!ResourceTypes.includes(type as ResourceType)) {
    throw new Error(`Invalid resource type: ${type}`);
  }
};
export type MapValue<T> = T extends Map<unknown, infer V> ? V : never;
export type MapKey<T> = T extends Map<infer K, unknown> ? K : never;

/**
 * Skill definition parsed from SKILL.md
 *
 * Represents a complete skill including metadata and indexed resources.
 * Resources are pre-indexed at skill initialization to enable:
 * - Safe path traversal prevention (all paths are pre-validated)
 * - Fast lookup by relative path
 * - MIME type detection for proper content handling
 */
export type Skill = {
  name: string; // From frontmatter (e.g., "brand-guidelines")
  fullPath: string; // Full directory path to skill
  toolName: string; // Generated tool name (e.g., "skills_brand_guidelines")
  description: string; // From frontmatter
  allowedTools?: string[]; // Parsed but not enforced (agent-level restrictions instead)
  metadata?: Record<string, string>;
  license?: string;
  content: string; // Markdown body
  path: string; // Full path to SKILL.md
  scripts: SkillResourceMap; // Indexed script resources (e.g., build.sh, test.sh)
  references: SkillResourceMap; // Indexed reference resources (e.g., documentation, guides)
  assets: SkillResourceMap; // Indexed asset resources (e.g., images, icons)
};

/**
 * Text segment from parsed search query
 */
export type TextSegment = {
  text: string;
  negated: boolean;
};

/**
 * Parsed query structure from search-string
 */
export type ParsedSkillQuery = {
  include: string[]; // Positive search terms
  exclude: string[]; // Negative search terms (-term)
  originalQuery: string[]; // Original query string
  hasExclusions: boolean; // Flag for user feedback
  termCount: number; // Total number of terms
};

/**
 * Search result with ranking and feedback
 */
export type SkillSearchResult = {
  matches: Skill[]; // Ranked skill matches
  totalMatches: number; // Total count before exclusions
  totalSkills: number; // Total skills in registry
  feedback: string; // User-friendly interpretation message
  query: ParsedSkillQuery; // Parsed query structure
};

/**
 * Ranking metrics for a skill match
 */
export type SkillRank = {
  skill: Skill;
  nameMatches: number; // How many terms matched the skill name
  descMatches: number; // How many terms matched the description
  totalScore: number; // Composite rank score
};

/**
 * Plugin configuration
 */
export type PluginConfig = {
  debug: boolean;
  basePaths: string[];
  promptRenderer: 'json' | 'xml' | 'md';
  modelRenderers?: Record<string, 'json' | 'xml' | 'md'>;
};

export type LogType = 'log' | 'debug' | 'error' | 'warn';
export type PluginLogger = Record<LogType, (...message: unknown[]) => void>;

/**
 * Skill searcher function type
 */
export type SkillSearcher = (_query: string | string[]) => SkillSearchResult;

/**
 * Skill registry controller interface
 */
export type SkillRegistryController = {
  ready: ReadyStateMachine;
  skills: Skill[];
  ids: string[];
  clear: () => void;
  delete: (_key: string) => void;
  has: (_key: string) => boolean;
  get: (_key: string) => Skill | undefined;
  set: (_key: string, _skill: Skill) => void;
};

export type SkillRegistryDebugInfo = {
  discovered: number;
  parsed: number;
  rejected: number;
  errors: string[];
};

export type SkillRegistry = {
  initialise: () => Promise<void>;
  config: PluginConfig;
  register: (...skillPaths: string[]) => Promise<SkillRegistryDebugInfo>;
  controller: SkillRegistryController;
  isSkillPath: (_path: string) => boolean;
  getToolnameFromSkillPath: (_path: string) => string | null;
  search: SkillSearcher;
  debug?: SkillRegistryDebugInfo;
  logger: PluginLogger;
};
