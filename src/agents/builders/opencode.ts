import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';

export class OpenCodeAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    // LLMプロバイダーの文字列集合を定義
    private static readonly LOCAL_PROVIDERS = new Set(['lmstudio', 'ollama']);

    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        const baseEnv = {
            OPENAI_API_KEY: process.env.OPENAI_API_KEY || "",
            ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || "",
            GOOGLE_API_KEY: process.env.GOOGLE_API_KEY || "",
            GEMINI_API_KEY: process.env.GOOGLE_API_KEY || ""
        } as Record<string, string>;

        if (this.config.provider && OpenCodeAgentBuilder.LOCAL_PROVIDERS.has(this.config.provider)) {
                return {
                ...baseEnv,
                OPENAI_BASE_URL: process.env.OPENAI_BASE_URL || '',
                OPENAI_MODEL: process.env.OPENAI_MODEL || this.config.model
            };
        }

        if (this.config.provider === 'xai') {
            return {
                ...baseEnv,
                XAI_API_KEY: process.env.XAI_API_KEY || ""
            };
        }

        return baseEnv;
    }

    protected getCoreArgs(instructions: string): string[] {
        return [
            'opencode', 'run',
            '-m', this.config.model,
            instructions
        ];
    }
} 
