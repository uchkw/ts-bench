import { spawn } from "bun";

export function escapeShellArg(str: string): string {
    return str.replace(/'/g, "'\"'\"'");
}

export function escapeForDoubleQuotes(str: string): string {
    return str.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
}

export interface ExecuteOptions {
    cwd?: string;
    env?: Record<string, string>;
    timeout?: number; // seconds
}

export interface CommandExecutor {
    execute(args: string[], options?: ExecuteOptions): Promise<CommandResult>;
}

export interface CommandResult {
    exitCode: number | null;
    stdout: string;
    stderr: string;
}

export class BunCommandExecutor implements CommandExecutor {
    async execute(args: string[], options?: ExecuteOptions): Promise<CommandResult> {
        const spawnOptions: any = {};
        
        if (options?.cwd) {
            spawnOptions.cwd = options.cwd;
        }
        
        if (options?.env) {
            spawnOptions.env = { ...process.env, ...options.env };
        }

        // Ensure pipes so we can consume output without blocking
        spawnOptions.stdout = 'pipe';
        spawnOptions.stderr = 'pipe';
        spawnOptions.stdin = 'ignore';

        const proc = spawn(args, spawnOptions);

        // Prepare concurrent, cancellable readers for stdout/stderr
        const stdoutChunks: string[] = [];
        const stderrChunks: string[] = [];
        const dec = new TextDecoder();

        const stdoutReader = proc.stdout?.getReader ? proc.stdout.getReader() : undefined;
        const stderrReader = proc.stderr?.getReader ? proc.stderr.getReader() : undefined;

        let reading = true;
        const readStream = async (reader: ReadableStreamDefaultReader<Uint8Array> | undefined, sink: string[]) => {
            try {
                if (!reader) return; // No stream available
                while (reading) {
                    const { value, done } = await reader.read();
                    if (done) break;
                    if (value) sink.push(dec.decode(value));
                }
            } catch (_) {
                // Reader cancelled or stream errored; best effort collection only
            } finally {
                try { reader?.releaseLock?.(); } catch (_) {}
            }
        };

        const stdoutDone = readStream(stdoutReader, stdoutChunks);
        const stderrDone = readStream(stderrReader, stderrChunks);

        let timeoutId: ReturnType<typeof setTimeout> | undefined;
        let timedOut = false;

        // Helper: attempt to terminate the process, escalating if needed
        const forceKillAfter = async (ms: number) => {
            await new Promise(res => setTimeout(res, ms));
            try { proc.kill(9); } catch (_) {}
        };

        // Helper: if this is a docker run with a named container, also kill the container
        const tryDockerCleanup = async () => {
            try {
                if (args.length >= 2 && args[0] === 'docker' && args[1] === 'run') {
                    const nameIdx = args.indexOf('--name');
                    if (nameIdx !== -1 && nameIdx + 1 < args.length) {
                        const cname = args[nameIdx + 1]!;
                        const killProc = spawn(['docker', 'kill', cname], { stdout: 'ignore', stderr: 'ignore' });
                        await Promise.race([killProc.exited, new Promise(res => setTimeout(res, 1500))]);
                        const rmProc = spawn(['docker', 'rm', '-f', cname], { stdout: 'ignore', stderr: 'ignore' });
                        await Promise.race([rmProc.exited, new Promise(res => setTimeout(res, 1500))]);
                    }
                }
            } catch (_) {
                // Best-effort cleanup; ignore failures
            }
        };

        try {
            if (options?.timeout && options.timeout > 0) {
                await Promise.race([
                    proc.exited,
                    new Promise<void>((resolve) => {
                        timeoutId = setTimeout(async () => {
                            timedOut = true;
                            try { proc.kill(); } catch (_) {}
                            // Escalate to SIGKILL shortly after
                            forceKillAfter(1200);
                            // Best-effort docker cleanup when applicable
                            tryDockerCleanup();
                            resolve();
                        }, options.timeout! * 1000);
                    })
                ]);
            } else {
                await proc.exited;
            }
        } finally {
            if (timeoutId) clearTimeout(timeoutId);
        }

        // Stop readers; if timed out, allow a small grace period then abandon
        if (timedOut) {
            reading = false;
            try { await Promise.race([stdoutDone, new Promise(res => setTimeout(res, 1500))]); } catch (_) {}
            try { await Promise.race([stderrDone, new Promise(res => setTimeout(res, 1500))]); } catch (_) {}
            try { await stdoutReader?.cancel?.(); } catch (_) {}
            try { await stderrReader?.cancel?.(); } catch (_) {}
        } else {
            reading = false;
            try { await stdoutDone; } catch (_) {}
            try { await stderrDone; } catch (_) {}
        }

        const stdoutRaw = stdoutChunks.join('');
        const stderrRaw = stderrChunks.join('');

        const stdout = this.filterYarnNoise(stdoutRaw);
        let stderr = this.filterYarnNoise(stderrRaw);
        let exitCode: number | null = proc.exitCode;

        if (timedOut) {
            exitCode = 124;
            const msg = `Execution timed out after ${options?.timeout} seconds`;
            stderr = stderr ? `${stderr}\n${msg}` : msg;
        }
        
        return {
            exitCode,
            stdout,
            stderr
        };
    }

    private filterYarnNoise(text: string): string {
        return text.replace(/YN0000.*\n/g, '');
    }
}
