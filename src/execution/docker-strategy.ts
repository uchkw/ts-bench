import { DOCKER_BASE_ARGS, createCliCacheArgs, createEnvironmentArgs, createWorkspaceArgs } from '../utils/docker';
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
      const exerciseDir = workspacePath;
      const practiceDir = dirname(exerciseDir);
      const exercisesDir = dirname(practiceDir);
      const wsRoot = dirname(exercisesDir);
      const benchworkDir = dirname(wsRoot);
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
      // Ignore errors; Docker will attempt bind mount regardless
    }

    const testMountArgs: string[] = [];
    if (ctx.testFiles && ctx.testFiles.length > 0) {
      for (const testFile of ctx.testFiles) {
        const hostPath = join(workspacePath, testFile);
        const containerPath = `/workspace/${testFile}`;
        testMountArgs.push('-v', `${hostPath}:${containerPath}:ro`);
      }
    }

    const exName = basename(workspacePath).replace(/[^a-zA-Z0-9_.-]/g, '_');
    const runtimeName = `ocbench_${exName}_${Date.now().toString(36)}`;

    const command = [
      ...DOCKER_BASE_ARGS,
      '--name', runtimeName,
      '--init',
      ...createCliCacheArgs(),
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
