import type { BenchmarkConfig } from '../config/types';
import type { AgentBuilder } from './types';
import { ClaudeAgentBuilder } from './builders/claude';
import { GooseAgentBuilder } from './builders/goose';
import { AiderAgentBuilder } from './builders/aider';
import { CodexAgentBuilder } from './builders/codex';
import { GeminiAgentBuilder } from './builders/gemini';
import { OpenCodeAgentBuilder } from './builders/opencode';
import { QwenAgentBuilder } from './builders/qwen';
import { CursorAgentBuilder } from './builders/cursor';

export class AgentFactory {
    static create(config: BenchmarkConfig, containerName: string, agentScriptPath: string): AgentBuilder {
        const agentConfig = {
            model: config.model,
            provider: config.provider,
            containerName,
            agentScriptPath
        };

        switch (config.agent) {
            case 'claude':
                return new ClaudeAgentBuilder(agentConfig);
            case 'goose':
                return new GooseAgentBuilder(agentConfig);
            case 'aider':
                return new AiderAgentBuilder(agentConfig);
            case 'codex':
                return new CodexAgentBuilder(agentConfig);
            case 'gemini':
                return new GeminiAgentBuilder(agentConfig);
            case 'opencode':
                return new OpenCodeAgentBuilder(agentConfig);
            case 'qwen':
                return new QwenAgentBuilder(agentConfig);
            case 'cursor':
                return new CursorAgentBuilder(agentConfig);
            default:
                throw new Error(`Unknown agent: ${config.agent}`);
        }
    }
}
