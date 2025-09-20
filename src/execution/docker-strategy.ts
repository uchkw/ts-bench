import { DOCKER_BASE_ARGS, createCliCacheArgs, createEnvironmentArgs, createWorkspaceArgs } from '../utils/docker';
import type { ExecutionStrategy, Command, PrepareContext, PreparedCommand } from './types';
import { join } from 'path';

export class DockerExecutionStrategy implements ExecutionStrategy {
  constructor(private containerName: string) {}

  prepare(core: Command, ctx: PrepareContext): PreparedCommand {
    const workspacePath = join(process.cwd(), ctx.exercisePath);

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
      ...createCliCacheArgs(),
      ...createEnvironmentArgs(core.env || {}),
      ...createWorkspaceArgs({ workspacePath }),
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
