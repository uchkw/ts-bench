import type { ProviderType } from '../../config/types';
import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';

const setIfDefined = (env: Record<string, string>, key: string, value: string | undefined = process.env[key]): void => {
    if (value !== undefined) {
        env[key] = value;
    }
};

const providerSpecificEnv: Partial<Record<ProviderType, (env: Record<string, string>) => void>> = {
    openai: (env) => {
        setIfDefined(env, 'OPENAI_API_KEY');
    },
    anthropic: (env) => {
        setIfDefined(env, 'ANTHROPIC_API_KEY');
    },
    google: (env) => {
        const direct = process.env.GOOGLE_GENERATIVE_AI_API_KEY;

        if (direct !== undefined) {
            env.GOOGLE_GENERATIVE_AI_API_KEY = direct;
        } else {
            for (const fallbackKey of ['GOOGLE_API_KEY', 'GEMINI_API_KEY']) {
                const fallback = process.env[fallbackKey];
                if (fallback !== undefined) {
                    env.GOOGLE_GENERATIVE_AI_API_KEY = fallback;
                    break;
                }
            }
        }

        setIfDefined(env, 'GOOGLE_API_KEY');
        setIfDefined(env, 'GEMINI_API_KEY');
    },
    openrouter: (env) => {
        setIfDefined(env, 'OPENROUTER_API_KEY');
    },
    dashscope: (env) => {
        setIfDefined(env, 'DASHSCOPE_API_KEY');
    },
    xai: (env) => {
        setIfDefined(env, 'XAI_API_KEY');
    },
    deepseek: (env) => {
        setIfDefined(env, 'DEEPSEEK_API_KEY');
    }
};

export class OpenCodeAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        const env: Record<string, string> = {};
        const provider = (this.config.provider ?? 'openai') as ProviderType;
        providerSpecificEnv[provider]?.(env);

        return env;
    }

    protected getCoreArgs(instructions: string): string[] {
        const model = this.config.provider && !this.config.model.includes('/')
            ? `${this.config.provider}/${this.config.model}`
            : this.config.model;

        return [
            'opencode', 'run',
            '-m', model,
            instructions
        ];
    }
}
