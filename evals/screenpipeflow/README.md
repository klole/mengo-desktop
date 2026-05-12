# ScreenpipeFlow synthesis evals

Regression eval for the bootstrap synthesis prompt at `Resources/synthesis-prompt.md`.

## Usage

```bash
./run-evals.sh
```

Prints PASS/FAIL per fixture and a final tally.

## Adding a fixture

1. Record a short demonstration via ScreenpipeFlow normally; let it synthesize.
2. Copy the manifest from `~/Library/Application Support/ScreenpipeFlow/manifests/<uuid>.json`
   to `fixtures/<name>/manifest.json`.
3. Note the time range so it can be re-fetched against a running screenpipe.
   (V1 of the harness expects screenpipe to be running with the fixture's data
   already in its DB. A fully hermetic eval requires injecting fixture data
   into screenpipe's MCP — deferred.)
4. Write `fixtures/<name>/expected.md` listing properties the synthesis output must have:

   ```
   - SKILL.md MUST mention "slack channel" as a parameter
   - flow.json MUST contain a step of type=browser with intent containing "dashboard"
   - The "Open dashboard" step MUST be tagged inferred: true
   ```

5. Run `./run-evals.sh` to confirm it passes today. Commit the fixture.

## Iterating on the prompt

When changing `Resources/synthesis-prompt.md`:
1. Run evals before the change. Note the pass count.
2. Make your change.
3. Run evals again. Pass count must not drop.

## V1 Limitations

- Expects a live screenpipe instance with fixture-time-range data in its DB.
- Token must be available (run `screenpipe auth token` to verify).
- Hermetic fixture injection into screenpipe MCP is a future improvement.
