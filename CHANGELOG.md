# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2025-09-20
### Added
- On-demand CLI installation script (`scripts/run-agent.sh`) with shared cache to avoid repeated downloads.
- Environment variable validation helpers that abort execution when required API keys are missing.
- Smoke test script (`scripts/smoke-agents.sh`) to verify agent CLI availability inside Docker.

### Changed
- Docker image now uses `oven/bun:1.2.22-slim`, installs Node.js 20 via NodeSource, and mounts a persistent CLI cache.
- All agent builders route execution through the new script and share consistent environment handling.
- Documentation updated to describe the new installation flow and required environment variables.

[1.1.0]: https://github.com/laiso/ts-bench/releases/tag/v1.1.0

## [1.0.0] - 2024-09-15-06
- Initial release of TS-Bench: A reproducible benchmark for evaluating AI coding agents in TypeScript.

[1.0.0]: https://medium.com/@laiso/introducing-ts-bench-a-reproducible-benchmark-for-evaluating-ai-coding-agents-typescript-19bcf960cb7c