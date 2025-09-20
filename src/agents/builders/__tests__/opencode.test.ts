import { afterEach, describe, expect, it, beforeEach } from 'bun:test';
import { OpenCodeAgentBuilder } from '../opencode';

type EnvSnapshot = Record<string, string | undefined>;

describe('OpenCodeAgentBuilder', () => {
    const baseConfig = {
        model: 'test-model',
        containerName: 'test-container'
    };

    const RELEVANT_KEYS = [
        'OPENAI_API_KEY',
        'ANTHROPIC_API_KEY',
        'GOOGLE_GENERATIVE_AI_API_KEY',
        'GOOGLE_API_KEY',
        'GEMINI_API_KEY',
        'OPENROUTER_API_KEY',
        'OPENAI_BASE_URL',
        'DASHSCOPE_API_KEY',
        'XAI_API_KEY',
        'DEEPSEEK_API_KEY'
    ];

    let originalEnv: EnvSnapshot;

    const overrideEnv = (key: string, value: string | undefined) => {
        if (!(key in originalEnv)) {
            originalEnv[key] = process.env[key];
        }

        if (value === undefined) {
            delete process.env[key];
        } else {
            process.env[key] = value;
        }
    };

    const resetRelevantEnv = () => {
        for (const key of RELEVANT_KEYS) {
            overrideEnv(key, undefined);
        }
    };

    beforeEach(() => {
        originalEnv = {};
        resetRelevantEnv();
    });

    afterEach(() => {
        for (const [key, value] of Object.entries(originalEnv)) {
            if (value === undefined) {
                delete process.env[key];
            } else {
                process.env[key] = value;
            }
        }
    });

    it('defaults to OPENAI_API_KEY when no provider is specified', async () => {
        overrideEnv('OPENAI_API_KEY', 'openai-key');

        const builder = new OpenCodeAgentBuilder(baseConfig);
        const command = await builder.buildCommand('instructions');

        expect(command.env).toEqual({ OPENAI_API_KEY: 'openai-key' });
    });

    it('sets OpenRouter specific environment variables', async () => {
        overrideEnv('OPENROUTER_API_KEY', 'router-key');
        
        const builder = new OpenCodeAgentBuilder({
            ...baseConfig,
            provider: 'openrouter'
        });

        const command = await builder.buildCommand('instructions');

        expect(command.env).toEqual({
            OPENROUTER_API_KEY: 'router-key',
        });
    });

    it('prefers GOOGLE_GENERATIVE_AI_API_KEY but falls back when needed', async () => {
        overrideEnv('GOOGLE_GENERATIVE_AI_API_KEY', 'gen-key');

        const builder = new OpenCodeAgentBuilder({
            ...baseConfig,
            provider: 'google'
        });

        const command = await builder.buildCommand('instructions');

        expect(command.env).toEqual({ GOOGLE_GENERATIVE_AI_API_KEY: 'gen-key' });
    });

    it('falls back to GOOGLE_API_KEY for Google provider', async () => {
        overrideEnv('GOOGLE_API_KEY', 'legacy-google');

        const builder = new OpenCodeAgentBuilder({
            ...baseConfig,
            provider: 'google'
        });

        const command = await builder.buildCommand('instructions');

        expect(command.env).toEqual({
            GOOGLE_GENERATIVE_AI_API_KEY: 'legacy-google',
            GOOGLE_API_KEY: 'legacy-google'
        });
    });

    it('exposes provider-specific keys for xai, dashscope and deepseek', async () => {
        overrideEnv('XAI_API_KEY', 'xai-key');
        overrideEnv('DASHSCOPE_API_KEY', 'dashscope-key');
        overrideEnv('DEEPSEEK_API_KEY', 'deepseek-key');

        const xaiEnv = await new OpenCodeAgentBuilder({
            ...baseConfig,
            provider: 'xai'
        }).buildCommand('instructions');

        const dashscopeEnv = await new OpenCodeAgentBuilder({
            ...baseConfig,
            provider: 'dashscope'
        }).buildCommand('instructions');

        const deepseekEnv = await new OpenCodeAgentBuilder({
            ...baseConfig,
            provider: 'deepseek'
        }).buildCommand('instructions');

        expect(xaiEnv.env).toEqual({ XAI_API_KEY: 'xai-key' });
        expect(dashscopeEnv.env).toEqual({ DASHSCOPE_API_KEY: 'dashscope-key' });
        expect(deepseekEnv.env).toEqual({ DEEPSEEK_API_KEY: 'deepseek-key' });
    });
});
