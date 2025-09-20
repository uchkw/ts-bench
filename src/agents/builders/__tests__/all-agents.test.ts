import { describe, expect, it } from 'bun:test';
import { AiderAgentBuilder } from '../aider';
import { CodexAgentBuilder } from '../codex';
import { GeminiAgentBuilder } from '../gemini';
import { GooseAgentBuilder } from '../goose';
import { CursorAgentBuilder } from '../cursor';
import type { AgentBuilder } from '../../types';

const SCRIPT_PATH = '/tmp/scripts/run-agent.sh';
const BASE_CONFIG = {
    containerName: 'test-container',
    agentScriptPath: SCRIPT_PATH,
    model: 'test-model'
};

describe('Agent builders invoke run-agent script', () => {
    type TestCase = {
        cli: string;
        builder: AgentBuilder;
        env: ReadonlyArray<readonly [string, string]>;
        fileList?: { sourceFiles: string[]; testFiles: string[] };
    };

    const cases: TestCase[] = [
        {
            cli: 'aider',
            builder: new AiderAgentBuilder(BASE_CONFIG),
            env: [['OPENAI_API_KEY', 'test-oa-key'] as const],
            fileList: { sourceFiles: ['app.ts'], testFiles: ['app.test.ts'] }
        },
        {
            cli: 'codex',
            builder: new CodexAgentBuilder(BASE_CONFIG),
            env: [['OPENAI_API_KEY', 'test-oa-key'] as const]
        },
        {
            cli: 'gemini',
            builder: new GeminiAgentBuilder(BASE_CONFIG),
            env: [['GEMINI_API_KEY', 'test-gemini-key'] as const]
        },
        {
            cli: 'goose',
            builder: new GooseAgentBuilder(BASE_CONFIG),
            env: [['ANTHROPIC_API_KEY', 'test-anthropic-key'] as const]
        },
        {
            cli: 'cursor-agent',
            builder: new CursorAgentBuilder(BASE_CONFIG),
            env: [['CURSOR_API_KEY', 'test-cursor-key'] as const]
        }
    ] as const;

    for (const { cli, builder, env, fileList } of cases) {
        it(`ensures ${cli} passes through run-agent`, async () => {
            const originals: Record<string, string | undefined> = {};
            for (const [key, value] of env) {
                originals[key] = process.env[key];
                process.env[key] = value;
            }

            try {
                const command = await builder.buildCommand('instructions', fileList as any);

                expect(command.args[0]).toBe('bash');
                expect(command.args[1]).toBe(SCRIPT_PATH);
                expect(command.args[2]).toBe(cli);
            } finally {
                for (const [key] of env) {
                    const previous = originals[key];
                    if (previous === undefined) {
                        delete process.env[key];
                    } else {
                        process.env[key] = previous;
                    }
                }
            }
        });
    }
});
