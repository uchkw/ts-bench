import { join } from 'path';

export function getAgentScriptPath(useDocker: boolean): string {
    if (useDocker) {
        return '/app/scripts/run-agent.sh';
    }

    return join(process.cwd(), 'scripts', 'run-agent.sh');
}
