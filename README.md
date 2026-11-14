# .github

Central reusable GitHub Actions workflows for CodeClarityCE repos. Callers reference them at the moving `v1` tag; breaking changes go out as `v2`. Third-party actions and images are pinned by SHA or digest. See ADR 0009 in `codeclarity-dev`.

| Workflow | For | What it runs |
|---|---|---|
| `go-library.yml` | Go utilities | version check, Go checks, workflow lint, release, `ci` |
| `go-image.yml` | Go plugins and services | version check, Go checks (`GOWORK=off`, recursive submodules), workflow lint, image build or release, `ci` |
| `go-checks.yml` | other workflows | download, tidy, gofmt, vet, test, govulncheck in the pinned Go image |
| `image.yml` | other workflows | image build, or the native multi-arch release with provenance and GitHub release |
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

### Go image repos

Same as above with `go-image.yml`. Image name and version come from `config.json` (`image_name`, `version`). The release jobs also need `id-token` and `attestations`:

```yaml
  go:
    uses: CodeClarityCE/.github/.github/workflows/go-image.yml@v1
    permissions:
      contents: write
      id-token: write
      attestations: write
    # with:
    #   target: plugin   # Dockerfile target, the default
```

## image.yml

| Input | Default | |
|---|---|---|
| `image` | required | Docker Hub repository, such as `codeclarityce/plugin-js-sbom` |
| `version` | required | version and git tag; the Docker tag drops a leading `v` |
| `target` | `plugin` | Dockerfile build target |
| `context` | `.` | build context, relative to the repo root |
| `dockerfile` | `.cloud/docker/Dockerfile` | relative to the context |
| `submodules` | `"false"` | checkout `submodules` value |
| `release` | `false` | push and release instead of a local build |

Outputs: `tag` (such as `codeclarityce/plugin-js-sbom:0.0.26-alpha`), `released` (`true` when this run released), `digest` (manifest list digest when released).

With `release: false` it builds linux/amd64 without pushing, using the GitHub Actions layer cache. With `release: true`, on a push to `main` with `CI_RELEASE` set to `true`, it skips with a summary note if the tag exists; otherwise it builds amd64 on `ubuntu-24.04` and arm64 on `ubuntu-24.04-arm` without cache, pushes each by digest, merges them into a manifest list tagged with the version and `latest`, attests build provenance on the manifest digest, and only then creates the GitHub release. The push, merge and release jobs run in the `release` environment and read `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` from it; callers pass no secrets. The caller job must grant `contents: write`, `id-token: write` and `attestations: write` even for the build-only call, since GitHub checks the skipped release jobs' permissions too.

## Releases

Release jobs run on pushes to `main` only when the repo variable `CI_RELEASE` is `true`. They create the tag and release only if the tag does not exist yet, pinned to the built commit, as a prerelease for alpha or beta versions.

## Testing

`ci.yml` runs `go-library.yml` against `fixtures/go-library` and `go-image.yml` against `fixtures/go-image` (amd64 build, not pushed), which also lints this repo's workflows. Move `v1` only after it is green.
