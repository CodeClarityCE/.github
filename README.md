# .github

Central reusable GitHub Actions workflows for CodeClarityCE repos. Callers reference them at the moving `v1` tag; breaking changes go out as `v2`. Third-party actions and images are pinned by SHA or digest. See ADR 0009 in `codeclarity-dev`.

| Workflow | For | What it runs |
|---|---|---|
| `go-library.yml` | Go utilities | version check, Go checks, workflow lint, release, `ci` |
| `version-check.yml` | other workflows | on PRs to `main`, fails unless the version file is bumped |
| `workflow-lint.yml` | other workflows | actionlint and zizmor over the caller's `.github/` |

## Caller

The required check is a job named `ci` in the caller, because jobs of a called workflow show as `<caller job> / <job>`. Concurrency is set in the caller so a newer PR push cancels the whole older run.

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [main, develop]

permissions: {}

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

jobs:
  go:
    uses: CodeClarityCE/.github/.github/workflows/go-library.yml@v1
    permissions:
      contents: write # release job only; it runs on main when CI_RELEASE is true

  ci:
    needs: [go]
    if: always()
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    permissions: {}
    steps:
      - env:
          RESULT: ${{ needs.go.result }}
        run: '[[ "$RESULT" == success ]] || { echo "::error::go did not succeed: $RESULT"; exit 1; }'
```

## Releases

Release jobs run on pushes to `main` only when the repo variable `CI_RELEASE` is `true`. They create the tag and release only if the tag does not exist yet, pinned to the built commit, as a prerelease for alpha or beta versions.

## Testing

`ci.yml` runs `go-library.yml` against `fixtures/go-library`, which also lints this repo's workflows. Move `v1` only after it is green.
