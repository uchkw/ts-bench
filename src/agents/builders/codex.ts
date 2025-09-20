import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';
import { requireEnv } from '../../utils/env';

export class CodexAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        const provider = this.config.provider ?? 'openai';

        switch (provider) {
            case 'openrouter':
                return {
                    OPENROUTER_API_KEY: requireEnv('OPENROUTER_API_KEY', 'Missing OPENROUTER_API_KEY for Codex (OpenRouter) provider')
                };
            case 'openai':
            case 'local':
                return {
                    OPENAI_API_KEY: requireEnv('OPENAI_API_KEY', 'Missing OPENAI_API_KEY for Codex (OpenAI) provider')
                };
            default:
                throw new Error(`Unsupported provider for Codex: ${provider}`);
        }
    }

    protected getCoreArgs(instructions: string): string[] {
        const provider = this.config.provider ?? 'openai';
        const isLocal = provider === 'local';
        const baseArgs = [
            'bash',
            this.config.agentScriptPath,
            'codex', 'exec',
            '-c', 'model_reasoning_effort=high',
            '--full-auto',
            '--skip-git-repo-check',
            '-m', this.config.model
        ];

        if (isLocal) {
            return [...baseArgs, '--oss', instructions];
        }

        return [...baseArgs, '-c', `model_provider=${provider}`, instructions];
    }
}
