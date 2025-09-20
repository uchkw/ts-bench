import type { AgentResult, BenchmarkConfig } from '../config/types';
import { AgentFactory } from '../agents/factory';
import { AgentLoggerFactory } from '../utils/agent-logger';
import { ExerciseReader } from '../exercises/reader';
import type { CommandExecutor } from '../utils/shell';
import type { Logger } from '../utils/logger';
import { ProgressMonitor } from '../utils/progress-monitor';
import { join } from 'path';
import { LocalExecutionStrategy } from '../execution/local-strategy';
import { DockerExecutionStrategy } from '../execution/docker-strategy';
import { getAgentScriptPath } from '../config/paths';

export class AgentRunner {
    constructor(
        private executor: CommandExecutor,
        private exerciseReader: ExerciseReader,
        private logger: Logger,
        private containerName: string,
        private baseInstruction: string,
        private customInstruction?: string
    ) {}

    async run(config: BenchmarkConfig, exercise: string, exercisePath: string, useDocker: boolean = true): Promise<AgentResult> {
        const startTime = Date.now();

        let progressMonitor: ProgressMonitor | null = null;
        if (config.showProgress) {
            progressMonitor = new ProgressMonitor(this.logger, {
                exercisePath: join(process.cwd(), exercisePath),
                exerciseName: exercise,
                intervalMs: 8000,
                verbose: config.verbose
            });
        }

        try {
            const agentScriptPath = getAgentScriptPath(useDocker);
            const agentBuilder = AgentFactory.create(config, this.containerName, agentScriptPath);
            const instructions = await this.exerciseReader.getInstructions(exercise, this.baseInstruction, this.customInstruction);
            const fileList = await this.exerciseReader.getFileList(exercise);
            const coreCommand = await agentBuilder.buildCommand(instructions, fileList);

            const strategy = useDocker
                ? new DockerExecutionStrategy(this.containerName)
                : new LocalExecutionStrategy();
            const prepared = strategy.prepare(coreCommand, { exercisePath, testFiles: fileList.testFiles });

            if (config.verbose) {
                this.logger.logAgentCommand(prepared.command);
            }

            if (progressMonitor) {
                progressMonitor.start();
            }

            const execOptions = { ...prepared.options, timeout: config.timeout };
            const result = await this.executor.execute(prepared.command, execOptions);

            const logCollector = AgentLoggerFactory.create(config.agent);
            await logCollector.collect(config, exercise, exercisePath, result);

            const duration = Date.now() - startTime;

            if (progressMonitor) {
                progressMonitor.stop();
            }

            if (result.exitCode === 0) {
                this.logger.logAgentSuccess(exercise, duration, config.verbose, result);
                return { exercise, success: true, duration, output: result.stdout };
            } else {
                this.logger.logAgentFailure(exercise, duration, config.verbose, result);

                // Agent failed - exit immediately
                console.error(`❌ Agent failed for ${exercise}. Exiting immediately.`);
                return { exercise, success: false, duration, error: result.stderr, output: result.stdout };
            }
        } catch (error) {
            if (progressMonitor) {
                progressMonitor.stop();
            }

            const duration = Date.now() - startTime;
            const errorMsg = error instanceof Error ? error.message : String(error);
            this.logger.logAgentError(exercise, duration, errorMsg);

            // Agent error - exit immediately
            console.error(`❌ Agent error for ${exercise}: ${errorMsg}. Exiting immediately.`);
            return { exercise, success: false, duration, error: errorMsg };
        }
    }

    async getTestFiles(exercise: string): Promise<string[]> {
        return await this.exerciseReader.getTestFiles(exercise);
    }

    
}
