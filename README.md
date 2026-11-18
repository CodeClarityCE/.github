# .github

Central reusable GitHub Actions workflows for CodeClarityCE repos. Callers reference them at the moving `v1` tag; breaking changes go out as `v2`. Third-party actions and images are pinned by SHA or digest. See ADR 0009 in `codeclarity-dev`.

| Workflow            | For                     | What it runs                                                                                                   |
| ------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------- |
| `go-library.yml`    | Go utilities            | version check, Go checks, workflow lint, release, `ci`                                                         |
| `go-image.yml`      | Go plugins and services | version check, Go checks (`GOWORK=off`, recursive submodules), workflow lint, image build or release, `ci`     |
| `node-image.yml`    | api, frontend           | version check, Node checks in the Dockerfile's `toolchain` target, workflow lint, image build or release, `ci` |
| `go-checks.yml`     | other workflows         | download, tidy, gofmt, vet, test, govulncheck in the pinned Go image                                           |
| `image.yml`         | other workflows         | image build, or the native multi-arch release with provenance and GitHub release                               |
| `version-check.yml` | other workflows         | on PRs to `main`, fails unless the version file is bumped                                                      |
| `workflow-lint.yml` | other workflows         | actionlint and zizmor over the caller's `.github/`                                                             |
| `ci-report.yml`     | every caller            | on pushes to `main` or `develop`, keeps one `ci-failure` tracking issue per branch                             |

## Caller

The required check is a job named `ci` in the caller, because jobs of a called workflow show as `<caller job> / <job>`. Concurrency is set in the caller so a newer PR push cancels the whole older run.

```yaml
name: CI

on:
  pull_request:
    branches: [main, develop]
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
      - name: Check job results
        env:
          RESULTS: ${{ join(needs.*.result, ' ') }}
        run: |
          echo "results: $RESULTS"
          if [[ " $RESULTS " == *" failure "* || " $RESULTS " == *" cancelled "* ]]; then
            echo "::error::A needed job failed or was cancelled: $RESULTS"
            exit 1
          fi

  # Tracks a failing ci on pushes to main and develop in one issue per branch; not the required check.
  report:
    needs: [ci]
    if: ${{ !cancelled() && github.event_name == 'push' && (needs.ci.result == 'success' || needs.ci.result == 'failure') }}
    uses: CodeClarityCE/.github/.github/workflows/ci-report.yml@v1
    permissions:
      issues: write
      actions: read
    with:
      ci-result: ${{ needs.ci.result }}
```

The `Check job results` step is the one gate rule, used unchanged in every caller and in the central workflows' own `ci` jobs: it fails if any needed job failed or was cancelled, and skipped counts as success.

### CI report

Every caller ends with the `report` job above, after `ci`. It never runs for pull requests or a cancelled run, and it is not the required check, so its own failure leaves `ci` as it was. Do not name it `ci` or put it in `ci`'s `needs`.

- When `ci` fails, it opens an issue titled `CI failing on <branch>`, labelled `ci-failure` and `needs-triage`, or comments on the open one. It never opens a second. The issue names the commit, the run and every job that failed or was cancelled, nested ones as `<caller job> / <job>`. Missing labels are created first.
- When `ci` is green and the run's commit is still the branch head, it comments on the open issue and closes it. A green re-run of an older commit leaves the issue open.
- The job grants `issues: write` and `actions: read` (to list the run's jobs); the workflow top level stays `permissions: {}`.

Find the open ones across the org with `gh search issues --owner CodeClarityCE label:ci-failure state:open`.

### Go image repos

Same as above, `ci` and `report` jobs included, with `go-image.yml`. Image name and version come from `config.json` (`image_name`, `version`). The release jobs also need `id-token` and `attestations`, and the Docker Hub secrets passed by name:

```yaml
go:
  uses: CodeClarityCE/.github/.github/workflows/go-image.yml@v1
  permissions:
    contents: write
    id-token: write
    attestations: write
  secrets:
    DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
    DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
  # with:
  #   target: plugin   # Dockerfile target, the default
```

### Node image repos

Image `codeclarityce/<name>` and version come from `package.json` (`name`, `version`); the git tag is `v<version>`. The job stages `.cloud/docker/pnpm-workspace.yaml` at the package root, builds the Dockerfile's `toolchain` target and runs each step in it with the pnpm store cached: `pnpm install --frozen-lockfile`, `pnpm lint:check`, `pnpm type-check`, the test command, the extra test command if set, and `pnpm exec prettier src --check`. Same permissions and secrets as the Go image call, and the same `ci` and `report` jobs after it:

```yaml
node:
  uses: CodeClarityCE/.github/.github/workflows/node-image.yml@v1
  permissions:
    contents: write
    id-token: write
    attestations: write
  secrets:
    DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
    DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
  with:
    test-command: pnpm test # the default
    extra-test-command: pnpm test:e2e test/integration/*contract*.e2e-spec.ts
  #   target: ""        # Dockerfile target; empty builds the last stage, the default
```

## image.yml

| Input        | Default                    |                                                               |
| ------------ | -------------------------- | ------------------------------------------------------------- |
| `image`      | required                   | Docker Hub repository, such as `codeclarityce/plugin-js-sbom` |
| `version`    | required                   | version and git tag; the Docker tag drops a leading `v`       |
| `target`     | `plugin`                   | Dockerfile build target                                       |
| `context`    | `.`                        | build context, relative to the repo root                      |
| `dockerfile` | `.cloud/docker/Dockerfile` | relative to the context                                       |
| `submodules` | `"false"`                  | checkout `submodules` value                                   |
| `release`    | `false`                    | push and release instead of a local build                     |

Secrets, both optional and needed only for `release: true`: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.

Outputs: `tag` (such as `codeclarityce/plugin-js-sbom:0.0.26-alpha`), `released` (`true` when this run released), `digest` (manifest list digest when released).

With `release: false` it builds linux/amd64 without pushing, using the GitHub Actions layer cache. With `release: true`, on a push to `main` with `CI_RELEASE` set to `true`, it skips with a summary note if the tag exists; otherwise it builds amd64 on `ubuntu-24.04` and arm64 on `ubuntu-24.04-arm` without cache, pushes each by digest, merges them into a manifest list tagged with the version and `latest`, attests build provenance on the manifest digest, and only then creates the GitHub release. The push, merge and release jobs run in the `release` environment, where `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` are stored. A reusable workflow only gets the secrets its caller passes, even environment secrets, so every workflow in the chain passes both by name: the repo's `ci.yml` to `go-image.yml` or `node-image.yml`, and that to `image.yml`. A secret that is not passed resolves to an empty string. Both are optional, so the build-only call to `image.yml` passes none. We pass them by name rather than with `secrets: inherit`, which zizmor flags. The caller job must grant `contents: write`, `id-token: write` and `attestations: write` even for the build-only call, since GitHub checks the skipped release jobs' permissions too.

## Releases

Release jobs run on pushes to `main` only when the repo variable `CI_RELEASE` is `true`. They create the tag and release only if the tag does not exist yet, pinned to the built commit, as a prerelease for alpha or beta versions.

## Testing

`ci.yml` runs `go-library.yml` against `fixtures/go-library`, `go-image.yml` against `fixtures/go-image`, and `node-image.yml` against `fixtures/node-image` (amd64 builds, not pushed), which also lints this repo's workflows. Move `v1` only after it is green.
