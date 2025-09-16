import { describe, expect, it, beforeEach, afterEach, mock, spyOn } from 'bun:test';
import { BenchmarkReporter } from '../reporter';
import type { BenchmarkConfig, TestResult } from '../../config/types';

describe('BenchmarkReporter', () => {
    let reporter: BenchmarkReporter;
    let mockConfig: BenchmarkConfig;
    let mockResults: TestResult[];

    beforeEach(() => {
        reporter = new BenchmarkReporter();
        
        mockConfig = {
            agent: 'claude',
            model: 'sonnet-3.5',
            provider: 'anthropic',
            testCommand: 'bun test',
            verbose: false
        };

        mockResults = [
            {
                exercise: 'hello-world',
                agentSuccess: true,
                testSuccess: true,
                overallSuccess: true,
                agentDuration: 5000,
                testDuration: 2000,
                totalDuration: 7000,
                agentError: undefined,
                testError: undefined
            },
            {
                exercise: 'two-fer',
                agentSuccess: false,
                testSuccess: false,
                overallSuccess: false,
                agentDuration: 3000,
                testDuration: 1000,
                totalDuration: 4000,
                agentError: 'Syntax error in generated code',
                testError: 'Tests failed with compilation error'
            }
        ];
    });

    afterEach(() => {
        mock.restore();
    });

    describe('printResults', () => {
        it('calculates correct statistics', () => {
            const consoleSpy = spyOn(console, 'log').mockImplementation(() => {});
            
            reporter.printResults(mockResults);
            
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Success Rate: 50.0% (1/2)'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Total Duration: 11.0s'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Average Duration: 5.5s'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Agent Success: 1'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Test Success: 1'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Test Failed: 1'));
            
            consoleSpy.mockRestore();
        });

        it('displays detailed results', () => {
            const consoleSpy = spyOn(console, 'log').mockImplementation(() => {});
            
            reporter.printResults(mockResults);
            
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('hello-world'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('two-fer'));
            
            consoleSpy.mockRestore();
        });

        it('displays errors for failed tests', () => {
            const consoleSpy = spyOn(console, 'log').mockImplementation(() => {});
            
            reporter.printResults(mockResults);
            
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Syntax error in generated code'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('Tests failed with compilation error'));
            
            consoleSpy.mockRestore();
        });
    });

    describe('exportToJSON', () => {
        it('generates basic JSON data structure', async () => {
            const privateReporter = reporter as any;
            const jsonData = await privateReporter.generateBasicJSONData(mockResults, mockConfig);
            
            expect(jsonData.metadata.agent).toBe('claude');
            expect(jsonData.metadata.model).toBe('sonnet-3.5');
            expect(jsonData.summary.successRate).toBe(50.0);
            expect(jsonData.summary.totalCount).toBe(2);
            expect(jsonData.summary.totalDuration).toBe(11000);
            expect(jsonData.summary.avgDuration).toBe(5500);
            expect(jsonData.summary.agentSuccessCount).toBe(1);
            expect(jsonData.summary.testSuccessCount).toBe(1);
            expect(jsonData.summary.testFailedCount).toBe(1);
            expect(jsonData.results).toHaveLength(2);
        });
    });

    describe('printLeaderboard', () => {
        it('displays leaderboard format', () => {
            const consoleSpy = spyOn(console, 'log').mockImplementation(() => {});
            
            reporter.printLeaderboard(mockResults, mockConfig);
            
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('LEADERBOARD'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('claude'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('sonnet-3.5'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('anthropic'));
            expect(consoleSpy).toHaveBeenCalledWith(expect.stringContaining('50.0%'));
            
            consoleSpy.mockRestore();
        });
    });

});
