import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';

export class QwenAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        if (this.config.provider === 'openrouter') {
            return {
                OPENAI_BASE_URL: 'https://openrouter.ai/api/v1',
                OPENAI_API_KEY: process.env.OPENROUTER_API_KEY || '',
                OPENAI_MODEL: this.config.model
            };
        }
        if (this.config.provider === 'lmstudio') {
            return {
                OPENAI_BASE_URL: process.env.OPENAI_BASE_URL || '',
                OPENAI_API_KEY: process.env.OPENAI_API_KEY || '',
                OPENAI_MODEL: process.env.OPENAI_MODEL || this.config.model
            };
        }
        return {
            OPENAI_BASE_URL: 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
            OPENAI_API_KEY: process.env.DASHSCOPE_API_KEY || '',
            OPENAI_MODEL: this.config.model
        };
    }

    protected getCoreArgs(instructions: string): string[] {
        return [
            'qwen',
            '-y',
            '-m', this.config.model,
            '-p', instructions
        ];
    }
} 
