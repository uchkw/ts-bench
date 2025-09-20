import { mkdirSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';

export const DOCKER_BASE_ARGS = ["docker", "run", "--rm", "-i"] as const;
const CLI_CACHE_ENV = 'TS_BENCH_CLI_CACHE';
export const CLI_CACHE_CONTAINER_PATH = '/root/.local';

export interface DockerWorkspaceOptions {
  workspacePath: string;
  workingDir?: string;
}

export function createWorkspaceArgs(options: DockerWorkspaceOptions): string[] {
  const { workspacePath, workingDir = "/workspace" } = options;
  return [
    "-v", `${workspacePath}:${workingDir}`,
    "-w", workingDir
  ];
}

export function createEnvironmentArgs(envVars: Record<string, string>): string[] {
    return Object.entries(envVars)
        // Security hardening: only pass variables that have explicit values set
        // Avoid implicit host env pass-through with `-e KEY` which can leak secrets unexpectedly
        .filter(([, value]) => typeof value === 'string' && value.length > 0)
        .flatMap(([key, value]) => ["-e", `${key}=${value}`]);
}

export function createCliCacheArgs(): string[] {
  const hostPath = resolveCliCachePath();
  return ['-v', `${hostPath}:${CLI_CACHE_CONTAINER_PATH}`];
}

function resolveCliCachePath(): string {
  const explicit = process.env[CLI_CACHE_ENV];
  const base = explicit && explicit.trim().length > 0
    ? explicit
    : join(homedir(), '.cache', 'ts-bench', 'cli');
  mkdirSync(base, { recursive: true });
  return base;
}
