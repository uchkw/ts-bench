# Fix: Reliable timeout enforcement and stream handling (Bun + Docker)

Context
- Benchmarks sometimes ran far beyond the configured timeout. Logs showed messages like "Execution timed out after ..." but the overall run continued (e.g. ProgressMonitor never stopped for binary-search-tree; bank-account only finished much later).
- After the first attempt to harden timeouts, another issue appeared in results: `undefined is not an object (evaluating 'proc.stderr.getReader')`, causing immediate failures and suspiciously short durations in the JSON summary.

Root Causes
1) Post-timeout hang due to stdout/stderr reads:
   - The code used `await new Response(proc.stdout).text()` and `...stderr).text()` after attempting to kill the process on timeout.
   - If the child process (e.g., `docker run`) didn’t fully terminate or its pipes didn’t close, reading until EOF blocked indefinitely.

2) Docker child process not reliably terminated:
   - We were killing only the `docker run` CLI process. The container itself could remain running, keeping the pipes alive.
   - Without a named container, we had no reliable way to `docker kill` it by name.

3) Streams not configured or guarded:
   - In Bun, `proc.stdout`/`proc.stderr` may not be readable streams unless `stdout: 'pipe'` / `stderr: 'pipe'` are set when spawning.
   - Unconditionally calling `getReader()` on `undefined` led to the error seen in JSON results and very short measured durations (early failures).

What Changed
1) src/utils/shell.ts (BunCommandExecutor)
   - Force pipes for IO and ignore stdin to avoid interactive TTY edge cases:
     ```ts
     spawnOptions.stdout = 'pipe';
     spawnOptions.stderr = 'pipe';
     spawnOptions.stdin  = 'ignore';
     ```
   - Read stdout/stderr concurrently with cancellable readers, rather than `Response(...).text()`:
     ```ts
     const stdoutReader = proc.stdout?.getReader ? proc.stdout.getReader() : undefined;
     const stderrReader = proc.stderr?.getReader ? proc.stderr.getReader() : undefined;
     // readStream() loops while a shared `reading` flag is true and appends decoded chunks.
     // On timeout, we stop reading, wait briefly, and then cancel readers to avoid hang.
     ```
   - Robust timeout path:
     - Race `proc.exited` vs a `setTimeout` timer.
     - On timeout: send `proc.kill()` (SIGTERM), schedule SIGKILL escalation after ~1.2s, and attempt best-effort Docker cleanup (see below).
     - Do not block forever on output collection; apply small grace periods then cancel readers.
   - Preserve exit status and append a standardized timeout message with exitCode = 124 for consumers.

2) src/execution/docker-strategy.ts
   - Assign a unique container name and add `--init` for better signal handling:
     ```ts
     const runtimeName = `ocbench_${exName}_${Date.now().toString(36)}`;
     const command = [
       ...DOCKER_BASE_ARGS,
       '--name', runtimeName,
       '--init',
       // ...
     ];
     ```
   - With a known name, the executor can `docker kill` / `docker rm -f` the container during timeout cleanup, ensuring it does not linger and hold pipes open.

Why durations looked “too short” in one run
- The short per-exercise durations in the JSON came from early exceptions (`getReader` on `undefined`) causing fast failures. The measurement logic itself still uses wall-clock deltas around each exercise phase; but if the phase aborts immediately with an exception, the recorded duration is small.
- Also note: the reported `summary.totalDuration` is the sum of per-exercise durations and does not include initial workspace preparation overhead. The overall wall-clock time can be larger than the JSON sum even when everything is correct.

Expected Effects
- After this fix, timeouts deterministically stop the process and its Docker container. Output streams stop cleanly, so `execute()` returns promptly.
- ProgressMonitor is stopped reliably since the agent phase now returns on timeout.
- No more `getReader` exceptions; stdout/stderr pipes are explicitly enabled and guarded.

Future Hardening (optional)
- Add a global wall-clock timer to record the entire benchmark duration in metadata for easier correlation with filesystem timestamps.
- Consider using a watchdog around output reads with AbortController or a tighter read deadline.

Files touched
- src/utils/shell.ts: concurrent, cancellable IO + kill escalation + docker cleanup + pipe config.
- src/execution/docker-strategy.ts: `--name` and `--init` to enable reliable container termination.

References
- Bun Subprocess streams: ensure `stdout: 'pipe'` / `stderr: 'pipe'` when you need `getReader()`.
- Docker signal/cleanup: using a named container enables reliable `docker kill` / `docker rm -f` on timeout.

