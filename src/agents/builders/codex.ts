import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';

export class CodexAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        return {
            OPENAI_API_KEY: process.env.OPENAI_API_KEY || "",
            OPENROUTER_API_KEY: process.env.OPENROUTER_API_KEY || ""
        };
    }

    protected getCoreArgs(instructions: string): string[] {
        const isLocal = (this.config.provider === 'local');
        const baseArgs = [
            'codex', 'exec',
            '-c', 'model_reasoning_effort=high',
            '--full-auto',
            '--skip-git-repo-check',
            '-m', this.config.model,
        ];

        if (isLocal) {
            // Use Codex OSS mode; endpoint is controlled via CODEX_OSS_BASE_URL/CODEX_OSS_PORT
            return [...baseArgs, '--oss', instructions];
        } else {
            // Cloud / OpenAI-compatible provider
            return [...baseArgs, '-c', `model_provider=${this.config.provider || 'openai'}`, instructions];
        }
    }
}
