import { DOCKER_BASE_ARGS, createEnvironmentArgs, createWorkspaceArgs } from '../utils/docker';
import type { ExecutionStrategy, Command, PrepareContext, PreparedCommand } from './types';
import { basename, dirname, join } from 'path';
import { mkdirSync } from 'fs';

export class DockerExecutionStrategy implements ExecutionStrategy {
  constructor(private containerName: string) {}

  prepare(core: Command, ctx: PrepareContext): PreparedCommand {
    const workspacePath = join(process.cwd(), ctx.exercisePath);

    // Bind-mount a host directory to capture OpenCode logs from the container.
    // Target in container: /root/.local/share/opencode/log
    // Host path strategy:
    // - If the workspace follows the pattern .benchwork/<RUN_ID>-exercism-typescript,
    //   place logs under .benchwork/<RUN_ID>/logs/opencode
    // - Otherwise, fall back to .benchwork/opencode-logs
    let hostLogsDir = join(process.cwd(), '.benchwork', 'opencode-logs');
    try {
      // workspacePath points to: .benchwork/<RUN_ID>-exercism-typescript/exercises/practice/<exercise>
      const exerciseDir = workspacePath;
      const practiceDir = dirname(exerciseDir); // .../exercises/practice
      const exercisesDir = dirname(practiceDir); // .../exercises
      const wsRoot = dirname(exercisesDir); // .benchwork/<RUN_ID>-exercism-typescript
      const benchworkDir = dirname(wsRoot); // .benchwork
      if (basename(benchworkDir) === '.benchwork') {
        const runId = basename(wsRoot).replace(/-exercism-typescript$/, '');
        hostLogsDir = join(benchworkDir, runId, 'logs', 'opencode');
      }
    } catch (_) {
      // Keep default hostLogsDir
    }
    try {
      mkdirSync(hostLogsDir, { recursive: true });
    } catch (_) {
      // If we fail to create, Docker will still attempt the bind; ignore here
    }

    // Build read-only mounts for test files to prevent modification
    const testMountArgs: string[] = [];
    if (ctx.testFiles && ctx.testFiles.length > 0) {
      for (const testFile of ctx.testFiles) {
        const hostPath = join(workspacePath, testFile);
        const containerPath = `/workspace/${testFile}`;
        testMountArgs.push('-v', `${hostPath}:${containerPath}:ro`);
      }
    }

    const command = [
      ...DOCKER_BASE_ARGS,
      ...createEnvironmentArgs(core.env || {}),
      ...createWorkspaceArgs({ workspacePath }),
      '-v', `${hostLogsDir}:/root/.local/share/opencode/log`,
      ...testMountArgs,
      this.containerName,
      ...core.args
    ];

    return {
      command,
      options: {}
    };
  }
}
