import { describe, expect, it } from 'bun:test';
import { ClaudeAgentBuilder } from '../claude';

describe('ClaudeAgentBuilder', () => {
    const config = {
        model: 'claude-3-sonnet',
        containerName: 'test-container',
        agentScriptPath: '/tmp/scripts/run-agent.sh'
    };

    it('buildCommand should return core args and env', async () => {
        const prev = process.env.ANTHROPIC_API_KEY;
        process.env.ANTHROPIC_API_KEY = 'test-key';

        const builder = new ClaudeAgentBuilder(config);
        const cmd = await builder.buildCommand('Test instructions');

        expect(cmd.args.slice(0, 3)).toEqual(['bash', '/tmp/scripts/run-agent.sh', 'claude']);
        expect(cmd.args).toContain('--model');
        expect(cmd.args).toContain('claude-3-sonnet');
        expect(cmd.args).toContain('-p');
        expect(cmd.env?.ANTHROPIC_API_KEY).toBe('test-key');

        process.env.ANTHROPIC_API_KEY = prev;
    });
});
