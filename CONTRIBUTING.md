# Contributing to Mengo Desktop

Thanks for helping make private, local-first workflow memory accessible to
everyone.

## Development setup

You need macOS 15 or later and Xcode 16 or later.

```bash
git clone https://github.com/klole/mengo-desktop.git
cd mengo-desktop
swift test
./build-mengo.sh
open MengoDesktop.app
```

`bootstrap-cert.sh` can create a stable local signing identity so macOS does
not request capture permissions after every rebuild. It is optional and never
requires `sudo`.

## Pull requests

- Keep changes focused and explain the user-visible result.
- Add or update tests for behavior changes.
- Run `swift test`, `git diff --check`, and `bash -n` on changed shell scripts.
- Do not commit recordings, transcripts, screenshots, logs, model files,
  credentials, or generated app/ZIP artifacts.
- Preserve the account-free local runtime and do not introduce paid gates.
- Pin executable dependencies and GitHub Actions to exact versions or commits.
- Clearly disclose any feature that can send recording context off-device.

## Architecture

- `Sources/MengoDesktop`: the only shipping app target.
- `Tests/MengoDesktopTests`: unit and integration tests.
- `Resources`: app metadata, icons, and the synthesis prompt.
- `build-mengo.sh`: repeatable local development package build.
- `scripts/release-mengo.sh`: Developer ID signing and Apple notarization.

Historical plans under `docs/superpowers` are not the source of truth. Current
behavior is defined by the app source, tests, README, and active smoke test.
