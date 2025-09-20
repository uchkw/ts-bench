import type { AgentBuilder, AgentConfig } from '../types';
import { BaseAgentBuilder } from '../base';
import { requireAnyEnv } from '../../utils/env';

export class GeminiAgentBuilder extends BaseAgentBuilder implements AgentBuilder {
    constructor(agentConfig: AgentConfig) {
        super(agentConfig);
    }

    protected getEnvironmentVariables(): Record<string, string> {
        const { key, value } = requireAnyEnv(
            ['GEMINI_API_KEY', 'GOOGLE_API_KEY'],
            'Missing API key for Gemini provider'
        );

        const env: Record<string, string> = {
            GEMINI_API_KEY: value
        };

        if (key !== 'GEMINI_API_KEY') {
            env[key] = value;
        }

        return env;
    }

    protected getCoreArgs(instructions: string): string[] {
        return [
            'bash',
            this.config.agentScriptPath,
            'gemini',
            '--model', this.config.model,
            '-y',
            '-p', instructions
        ];
    }
}
