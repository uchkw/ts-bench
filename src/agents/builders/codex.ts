import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';
import { requireEnv } from '../../utils/env';

export class CodexAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        const provider = this.config.provider ?? 'openai';
        const env: Record<string, string> = {};

        switch (provider) {
            case 'openrouter':
                env.OPENROUTER_API_KEY = requireEnv('OPENROUTER_API_KEY', 'Missing OPENROUTER_API_KEY for Codex (OpenRouter) provider');
                break;
            case 'openai':
            case 'local':
                env.OPENAI_API_KEY = requireEnv('OPENAI_API_KEY', 'Missing OPENAI_API_KEY for Codex (OpenAI) provider');
                break;
            default:
                throw new Error(`Unsupported provider for Codex: ${provider}`);
        }

        const sandboxHome = process.env.CODEX_SANDBOX_HOME;
        if (sandboxHome) {
            env.HOME = sandboxHome;
            env.CODEX_HOME = sandboxHome;
        }

        const sandboxConfig = process.env.CODEX_SANDBOX_XDG_CONFIG;
        if (sandboxConfig) {
            env.XDG_CONFIG_HOME = sandboxConfig;
        }

        const sandboxData = process.env.CODEX_SANDBOX_XDG_DATA;
        if (sandboxData) {
            env.XDG_DATA_HOME = sandboxData;
        }

        return env;
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
