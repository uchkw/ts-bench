import type { ProviderType } from '../../config/types';
import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';
import { requireAnyEnv, requireEnv } from '../../utils/env';

export class OpenCodeAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    private static readonly LOCAL_PROVIDERS = new Set(['lmstudio', 'ollama']);

    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        const provider = this.config.provider ?? 'openai';

        if (provider === 'local' || OpenCodeAgentBuilder.LOCAL_PROVIDERS.has(provider)) {
            return {
                OC_PROVIDER: provider,
                OPENAI_BASE_URL: process.env.OPENAI_BASE_URL || '',
                OPENAI_API_KEY: process.env.OPENAI_API_KEY || '',
                OPENAI_MODEL: process.env.OPENAI_MODEL || this.config.model
            };
        }

        switch (provider as ProviderType) {
            case 'openai':
                return {
                    OC_PROVIDER: provider,
                    OPENAI_API_KEY: requireEnv('OPENAI_API_KEY', 'Missing OPENAI_API_KEY for OpenCode (OpenAI) provider')
                };
            case 'anthropic':
                return {
                    OC_PROVIDER: provider,
                    ANTHROPIC_API_KEY: requireEnv('ANTHROPIC_API_KEY', 'Missing ANTHROPIC_API_KEY for OpenCode (Anthropic) provider')
                };
            case 'google': {
                const { key, value } = requireAnyEnv(
                    ['GOOGLE_GENERATIVE_AI_API_KEY', 'GOOGLE_API_KEY', 'GEMINI_API_KEY'],
                    'Missing API key for OpenCode (Google) provider'
                );
                const env: Record<string, string> = {
                    OC_PROVIDER: provider,
                    GOOGLE_GENERATIVE_AI_API_KEY: value
                };
                env[key] = value;
                return env;
            }
            case 'openrouter':
                return {
                    OC_PROVIDER: provider,
                    OPENROUTER_API_KEY: requireEnv('OPENROUTER_API_KEY', 'Missing OPENROUTER_API_KEY for OpenCode (OpenRouter) provider')
                };
            case 'dashscope':
                return {
                    OC_PROVIDER: provider,
                    DASHSCOPE_API_KEY: requireEnv('DASHSCOPE_API_KEY', 'Missing DASHSCOPE_API_KEY for OpenCode (DashScope) provider')
                };
            case 'xai':
                return {
                    OC_PROVIDER: provider,
                    XAI_API_KEY: requireEnv('XAI_API_KEY', 'Missing XAI_API_KEY for OpenCode (xAI) provider')
                };
            case 'deepseek':
                return {
                    OC_PROVIDER: provider,
                    DEEPSEEK_API_KEY: requireEnv('DEEPSEEK_API_KEY', 'Missing DEEPSEEK_API_KEY for OpenCode (DeepSeek) provider')
                };
            default:
                throw new Error(`Unsupported provider for OpenCode: ${provider}`);
        }
    }

    protected getCoreArgs(instructions: string): string[] {
        const provider = this.config.provider;
        const shouldPrefix = provider
            && OpenCodeAgentBuilder.LOCAL_PROVIDERS.has(provider)
            && !this.config.model.startsWith(`${provider}/`);
        const model = shouldPrefix
            ? `${provider}/${this.config.model}`
            : this.config.model;

        return [
            'bash',
            this.config.agentScriptPath,
            'opencode',
            'run',
            '-m',
            model,
            instructions
        ];
    }
}
