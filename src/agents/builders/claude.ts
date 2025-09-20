import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';
import { requireAnyEnv, requireEnv } from '../../utils/env';

export class ClaudeAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        const provider = this.config.provider ?? 'anthropic';
        const env: Record<string, string> = {};

        switch (provider) {
            case 'dashscope': {
                const value = requireEnv('DASHSCOPE_API_KEY', 'Missing DASHSCOPE_API_KEY for Claude (DashScope) provider');
                env.ANTHROPIC_API_KEY = value;
                env.ANTHROPIC_AUTH_TOKEN = value;
                env.ANTHROPIC_BASE_URL = process.env.ANTHROPIC_BASE_URL || 'https://dashscope-intl.aliyuncs.com/api/v2/apps/claude-code-proxy';
                break;
            }
            case 'deepseek': {
                const value = requireEnv('DEEPSEEK_API_KEY', 'Missing DEEPSEEK_API_KEY for Claude (DeepSeek) provider');
                env.ANTHROPIC_API_KEY = value;
                env.ANTHROPIC_AUTH_TOKEN = value;
                env.ANTHROPIC_BASE_URL = 'https://api.deepseek.com/anthropic';
                break;
            }
            case 'moonshot': {
                const value = requireEnv('MOONSHOT_API_KEY', 'Missing MOONSHOT_API_KEY for Claude (Moonshot) provider');
                env.ANTHROPIC_API_KEY = value;
                env.ANTHROPIC_AUTH_TOKEN = value;
                env.ANTHROPIC_BASE_URL = 'https://api.moonshot.ai/anthropic';
                break;
            }
            case 'zai': {
                const value = requireEnv('ZAI_API_KEY', 'Missing ZAI_API_KEY for Claude (ZAI) provider');
                env.ANTHROPIC_API_KEY = value;
                env.ANTHROPIC_AUTH_TOKEN = value;
                env.ANTHROPIC_BASE_URL = 'https://api.z.ai/api/anthropic';
                break;
            }
            default: {
                const { value } = requireAnyEnv(
                    ['ANTHROPIC_API_KEY', 'DASHSCOPE_API_KEY'],
                    'Missing ANTHROPIC_API_KEY or DASHSCOPE_API_KEY for Claude'
                );
                env.ANTHROPIC_API_KEY = value;
            }
        }

        return env;
    }

    protected getCoreArgs(instructions: string): string[] {
        return [
            'bash',
            this.config.agentScriptPath,
            'claude',
            '--debug',
            '--verbose',
            '--dangerously-skip-permissions',
            '--model', this.config.model,
            '-p', instructions
        ];
    }
}
