import { spawn } from "bun";
import { resolve, dirname, join } from "path";
import { existsSync } from "fs";
import type { Logger } from "./logger";

export interface ProgressMonitorOptions {
    exercisePath: string;
    exerciseName: string;
    intervalMs?: number;
    verbose?: boolean;
}

export class ProgressMonitor {
    private intervalId: Timer | null = null;
    private lastDiffOutput: string = '';
    private isRunning: boolean = false;
    private resolvedPath: string;
    private repoRoot: string | null = null;

    constructor(
        private logger: Logger,
        private options: ProgressMonitorOptions
    ) {
        // Resolve and normalize the exercise path
        this.resolvedPath = resolve(this.options.exercisePath);
        this.repoRoot = this.findGitRoot(this.resolvedPath);
        
        if (this.options.verbose) {
            this.logger.info(`🔍 Debug: ProgressMonitor created for path: ${this.resolvedPath}`);
            if (this.repoRoot) {
                this.logger.info(`🔍 Debug: Detected git root: ${this.repoRoot}`);
            } else {
                this.logger.info(`🔍 Debug: No git root found (falling back to exercise dir)`);
            }
        }
    }

    start(): void {
        if (this.isRunning) {
            return;
        }

        this.isRunning = true;
        const intervalMs = this.options.intervalMs || 8000; // 8s   

        this.logger.info(`🔍 Progress monitoring started: ${this.options.exerciseName}`);
        
        // Initial check
        this.checkProgress();

        // Periodic check
        this.intervalId = setInterval(() => {
            this.checkProgress();
        }, intervalMs);
    }

    stop(): void {
        if (!this.isRunning) {
            return;
        }

        this.isRunning = false;
        if (this.intervalId) {
            clearInterval(this.intervalId);
            this.intervalId = null;
        }

        this.logger.info(`✅ Progress monitoring stopped: ${this.options.exerciseName}`);
    }

    private async checkProgress(): Promise<void> {
        try {
            const diffOutput = await this.getDiffOutput();
            
            if (diffOutput && diffOutput !== this.lastDiffOutput) {
                this.displayProgress(diffOutput);
                this.lastDiffOutput = diffOutput;
            } else if (!diffOutput && this.lastDiffOutput) {
                // Changes were reset
                this.logger.info(`📝 ${this.options.exerciseName}: Changes have been reset`);
                this.lastDiffOutput = '';
            } else if (this.options.verbose) {
                this.logger.info(`🔍 Debug: No changes detected or same as last check`);
            }
        } catch (error) {
            if (this.options.verbose) {
                const errorMsg = error instanceof Error ? error.message : String(error);
                this.logger.info(`🔍 Debug: Error in checkProgress: ${errorMsg}`);
            }
        }
    }

    private async getDiffOutput(): Promise<string> {
        if (this.options.verbose) {
            this.logger.info(`🔍 Debug: Checking progress in ${this.resolvedPath}`);
        }

        const cwd = this.repoRoot ?? this.resolvedPath;

        // First, check for changed files with git status
        const statusProc = spawn(['git', 'status', '--porcelain'], {
            cwd,
            stdout: 'pipe',
            stderr: 'pipe'
        });

        await statusProc.exited;
        
        if (statusProc.exitCode !== 0) {
            const stderr = await new Response(statusProc.stderr).text();
            if (this.options.verbose) {
                this.logger.info(`🔍 Debug: git status failed: ${stderr}`);
            }
            return '';
        }

        const statusOutput = await new Response(statusProc.stdout).text();
        
        if (this.options.verbose) {
            this.logger.info(`🔍 Debug: git status output:\n${statusOutput}`);
        }

        // Parse git status output correctly
        const allChangedFiles = statusOutput
            .split('\n')
            .filter(line => line.trim())
            .map(line => line.substring(3).trim()); // Remove status characters
        
        // Filter for TypeScript files (but not test files for now)
        const changedFiles = allChangedFiles.filter(file => 
            file.endsWith('.ts') && !file.includes('.test.') && !file.includes('.spec.')
        );

        if (this.options.verbose) {
            this.logger.info(`🔍 Debug: All changed files: [${allChangedFiles.join(', ')}]`);
            this.logger.info(`🔍 Debug: TypeScript files: [${changedFiles.join(', ')}]`);
        }

        if (changedFiles.length === 0) {
            if (this.options.verbose) {
                this.logger.info(`🔍 Debug: No TypeScript files changed`);
            }
            return '';
        }

        // Get diff for changed TypeScript files
        // Use `--` to ensure paths are treated as pathspecs, not revisions
        const diffProc = spawn(['git', 'diff', '--color=never', '--', ...changedFiles], {
            cwd,
            stdout: 'pipe',
            stderr: 'pipe'
        });

        await diffProc.exited;
        
        if (diffProc.exitCode === 0 || diffProc.exitCode === 1) {
            const stdout = await new Response(diffProc.stdout).text();
            if (this.options.verbose) {
                this.logger.info(`🔍 Debug: git diff exit code: ${diffProc.exitCode}, output length: ${stdout.length}`);
            }
            return stdout.trim();
        } else {
            const stderr = await new Response(diffProc.stderr).text();
            if (this.options.verbose) {
                this.logger.info(`🔍 Debug: git diff failed with code ${diffProc.exitCode}: ${stderr}`);
            }
        }

        return '';
    }

    private findGitRoot(startPath: string): string | null {
        let cur = startPath;
        for (let i = 0; i < 8; i++) {
            if (existsSync(join(cur, '.git'))) return cur;
            const next = dirname(cur);
            if (next === cur) break;
            cur = next;
        }
        return null;
    }


    private displayProgress(diffOutput: string): void {
        const timestamp = new Date().toLocaleTimeString('en-US');
        const lines = diffOutput.split('\n');
        
        // Create a summary of the diff
        const addedLines = lines.filter(line => line.startsWith('+')).length;
        const removedLines = lines.filter(line => line.startsWith('-')).length;
        
        this.logger.info(`🔄 [${timestamp}] ${this.options.exerciseName}: +${addedLines} -${removedLines} lines changed`);
        
        // Show only important changes (omit long diffs)
        if (lines.length <= 50) {
            console.log('--- Latest changes ---');
            console.log(diffOutput);
            console.log('--- End of changes ---\n');
        } else {
            console.log('--- Changes omitted due to length ---');
            console.log(`Total changed lines: ${lines.length}`);
            console.log('--- End of changes ---\n');
        }
    }
}
