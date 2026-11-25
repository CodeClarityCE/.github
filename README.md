# .github

Central reusable GitHub Actions workflows for CodeClarityCE repos. Callers reference them at the moving `v1` tag; breaking changes go out as `v2`. Third-party actions and images are pinned by SHA or digest. See ADR 0009 in `codeclarity-dev`.

| Workflow            | For                        | What it runs                                                                                                                          |
| ------------------- | -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `go-library.yml`    | Go utilities               | version check, Go checks, workflow lint, release, `ci`                                                                                |
| `go-image.yml`      | Go plugins and services    | version check, Go checks (`GOWORK=off`, recursive submodules), workflow lint, image build or release, `ci`                            |
| `node-image.yml`    | api, frontend              | version check, Node checks in the Dockerfile's `toolchain` target, opt-in Playwright e2e, workflow lint, image build or release, `ci` |
| `go-checks.yml`     | other workflows, backend   | download, tidy, gofmt, vet, opt-in golangci-lint, test, govulncheck in the pinned Go image                                            |
| `image.yml`         | other workflows            | image build, or the native multi-arch release with provenance and GitHub release                                                      |
| `version-check.yml` | other workflows            | on PRs to `main`, fails unless the version file is bumped                                                                             |
| `workflow-lint.yml` | other workflows            | actionlint and zizmor over the caller's `.github/`, the release callers check, and the gitleaks secret scan                           |
| `ci-report.yml`     | every caller               | on pushes to `main` or `develop`, keeps one `ci-failure` tracking issue per branch                                                    |
| `codeql.yml`        | every caller               | CodeQL for Actions, and Go or JavaScript/TypeScript when asked, on every PR and push                                                  |
| `go-fuzz.yml`       | Go repos with fuzz targets | nightly Go native fuzzing of every `Fuzz` target, with a `ci-failure` issue per crash                                                 |

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

  # Its own job, outside ci's needs: the only job with security-events: write. See CodeQL below.
  codeql:
    uses: CodeClarityCE/.github/.github/workflows/codeql.yml@v1
    permissions:
      contents: read
      security-events: write
    with:
      go-directory: . # omit for a repo without Go
      # javascript: true

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

Same as above, `ci` and `report` jobs included, with `go-image.yml`. Image name and version come from `config.json` (`image_name`, `version`). The release jobs also need `id-token` and `attestations`, and the Docker Hub secrets passed by name; workflow lint fails the caller without them (see [Release callers check](#release-callers-check)):

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

#### Go lint (opt-in)

Set `golangci-lint: true` on a `go-library.yml` or `go-image.yml` call to add a `golangci-lint` step to `go checks`, after `go vet`. A caller that leaves it at `false`, the default, gets no new step.

```yaml
with:
  golangci-lint: true
```

- It runs golangci-lint `v2.15.0` (`go run`, built with the pinned Go image) with this repo's `.golangci.yml`: only `unused`, `staticcheck` and `gosec`, every finding reported. The config is read at the commit of the workflow itself (`job.workflow_sha`), so a caller on `v1` gets `v1`'s config.
- Any finding fails the step, and so `ci`, with one annotation per finding.
- `golangci-lint-gowork-off: true` (on `go-checks.yml`) lints with `GOWORK=off` while every other step keeps the workspace, for a module such as the backend CLI that sits in a `go.work` but imports none of its modules.
- Run it locally from the module directory, as CI does: `GOWORK=off go run github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.15.0 run --config <path to this repo>/.golangci.yml ./...` (drop `GOWORK=off` for a Go library).
- A finding that is a false positive gets a `//nolint:<linter> // <why>` comment on its line, not a change to the shared config.

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

#### E2E (opt-in)

Set `e2e-image` to add an `e2e` job beside `node checks`. A caller that leaves it empty, the default, gets a skipped `e2e` job and nothing else changes.

| Input         | Default                     |                                                                                                     |
| ------------- | --------------------------- | --------------------------------------------------------------------------------------------------- |
| `e2e-image`   | `""`                        | Playwright image as `<image>:<tag>@sha256:<digest>`, matching the repo's `@playwright/test` version |
| `e2e-command` | `pnpm exec playwright test` | run in the package directory after `pnpm install --frozen-lockfile`                                 |

```yaml
with:
  e2e-image: mcr.microsoft.com/playwright:v1.65.1-noble@sha256:1507cbfc550a63a6b7396791ca4f00df17beb56342d2447b3f106c306f525579
  e2e-command: pnpm exec playwright test --workers=4
```

- The image stays in the caller, since it must move with the repo's `@playwright/test`; the job fails unless it is pinned by digest.
- The job runs the command in that image with `CI=true` and its own pnpm store cache. Which projects run is the repo's Playwright config.
- When it fails, it uploads `playwright-report/` and `test-results/` (screenshots, videos and traces, as the config records them) as the `e2e-report` artifact, kept 14 days.
- `ci` and the release need it, so a failing suite fails `ci` and blocks the release; skipped counts as success.

## Go test services

The `go checks` job in `go-checks.yml`, so every `go-library.yml` and `go-image.yml` caller, starts Postgres and RabbitMQ as service containers, with the same images as the dev stack. The `go test` step gets their address and credentials in the variables the backend already reads, and `CI=true`:

| Variable                                               | Value                          |
| ------------------------------------------------------ | ------------------------------ |
| `PG_DB_HOST`, `PG_DB_PORT`                             | `postgres`, `5432`             |
| `PG_DB_USER`, `PG_DB_PASSWORD`                         | `postgres`, `postgres`         |
| `AMQP_HOST`, `AMQP_PORT`, `AMQP_USER`, `AMQP_PASSWORD` | `rabbitmq`, `5672`, `ci`, `ci` |

- Postgres starts with only the `postgres` database. A test creates what it needs, for instance a throwaway database per test.
- Go tests get them through `github.com/CodeClarityCE/utility-boilerplates/testdeps`: `testdeps.Postgres(t)` returns a new empty database and drops it after the test, and `testdeps.RabbitMQ(t)` returns the AMQP URL. When the dependency is unreachable, the test fails if `CI` is set and skips otherwise, so a local run without the stack still passes and a green `ci` means the tests ran.
- `fixtures/go-library` has a test that fails in this repo's CI when either service is unreachable.

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

## CodeQL

`codeql.yml` runs CodeQL on every pull request and push the caller runs on, `develop` included, and uploads the results to code scanning. Each caller calls it as its own `codeql` job, as in the template above, so `security-events: write` goes to that job only and never to the release jobs.

| Input          | Default |                                                      |
| -------------- | ------- | ---------------------------------------------------- |
| `go-directory` | `""`    | directory of the `go.mod` to analyze; empty skips Go |
| `javascript`   | `false` | analyze JavaScript and TypeScript                    |

- Actions is always analyzed, with no build. JavaScript/TypeScript needs no build either.
- Go builds with `go build ./...` in the same pinned Go image as `go-checks.yml`, with `GOWORK=off` and no submodules, so a `go.work` pointing at sibling checkouts does not break it.
- The job is not in `ci`'s `needs`: findings show as code scanning alerts and PR annotations, and never fail `ci`.
- Pull requests from forks skip it, since their token cannot upload results.
- GitHub rejects these uploads while CodeQL default setup is on, so repos that call it must have default setup off (the org's code security configuration keeps it off).

## Go fuzz

`go-fuzz.yml` runs Go native fuzzing outside the PR gate. A Go repo with `Fuzz` targets calls it from its own scheduled workflow, `.github/workflows/fuzz.yml`, beside `ci.yml`:

```yaml
# Nightly Go fuzzing from the central workflows; see CodeClarityCE/.github.
name: Fuzz

on:
  schedule:
    - cron: "23 2 * * *"
  workflow_dispatch:

permissions: {}

concurrency:
  group: ${{ github.workflow }}
  cancel-in-progress: false

jobs:
  fuzz:
    uses: CodeClarityCE/.github/.github/workflows/go-fuzz.yml@v1
    permissions:
      contents: read
      issues: write # the report job only
    # with:
    #   fuzz-time: 10m      # per target, the default
    #   gowork-off: true    # for plugins and services, as in go-image.yml
```

| Input               | Default   |                                                                       |
| ------------------- | --------- | --------------------------------------------------------------------- |
| `working-directory` | `.`       | directory of the `go.mod`                                             |
| `gowork-off`        | `false`   | set `GOWORK=off`                                                      |
| `submodules`        | `"false"` | checkout `submodules` value                                           |
| `fuzz-time`         | `10m`     | `go test -fuzztime` per target, such as `30s`, `10m`, `1h` or `5000x` |

- The `fuzz targets` job lists every `Fuzz` function in every package of the module with `go test -list`, so a new target is fuzzed from the next night on with no change to the caller. Each target then runs as its own `fuzz <target>` job, in the same pinned Go image as `go-checks.yml`. Both jobs set `GOFLAGS=-buildvcs=false`: the container user does not own the checkout, so git refuses it and `go list` on a main package would fail with `error obtaining VCS status`.
- When a target fails, its job uploads the `fuzz-crash-<n>` artifact: the target, the log tail and the input `go test` wrote under `testdata/fuzz/<target>/`.
- On a scheduled or manual run, the `report` job then opens one issue per target, titled `Fuzz crash in <target> (<package>)` and labelled `ci-failure` and `needs-triage`, or comments on the open one. The body holds the failing input and how to reproduce it. A failed run with no crash input, such as a build failure, opens `Fuzz run failing` instead. Runs on other events, such as this repo's own CI, never open issues.
- To fix a crash, commit the input file at `testdata/fuzz/<target>/<name>` in the package with the fix. Plain `go test`, which `go-checks.yml` runs on every PR, runs every file there, so the crash stays fixed. Close the issue by hand once the fix is in.
- Schedules run only on the default branch, so a new caller fuzzes once it reaches `main`; until then run it with `workflow_dispatch`.

## Release callers check

The `workflow lint` job's `release callers` step runs `scripts/release-callers.sh`, read at the commit of the workflow itself (`job.workflow_sha`), over the caller's `.github/workflows/`. Every job that calls `go-image.yml` or `node-image.yml` must:

- pass `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` by name under `secrets:` (`secrets: inherit` does not count), and
- grant `contents: write`, `id-token: write` and `attestations: write` on that job (`write-all` counts; the workflow-level `permissions:` does not).

Otherwise the step fails, and so `ci`, with one annotation per job naming what is missing, such as `Job go calls go-image.yml without secrets: DOCKERHUB_TOKEN`. Without this check the gap shows only at the first real release on `main`. The step parses the workflows with yq from the digest-pinned `YQ_IMAGE`. Run it locally from a repo root with Docker: `YQ_IMAGE=<image from workflow-lint.yml> bash <path to this repo>/scripts/release-callers.sh`.

## Secret scan

`workflow-lint.yml` has a `secret scan` job, so every caller gets it with no change to its `ci.yml`. It runs gitleaks from the digest-pinned `GITLEAKS_IMAGE` with the rules in this repo's `.gitleaks.toml`, read at the commit of the workflow itself (`job.workflow_sha`), so a caller on `v1` gets `v1`'s rules.

- A pull request scans its commits (base to head); a push to `main` or `develop` scans the commits pushed. With no usable range, such as a new branch, it scans the working tree.
- A finding fails the job and so the caller's `ci`. The log names the rule, file, line and fingerprint; the value is redacted.
- `.gitleaks.toml` extends gitleaks' default rules with GitLab, GitHub and Slack token rules that have no entropy floor, matching what GitHub push protection rejects: `glpat-` followed by 20 x's fails, `glpat-test-token` passes. A test that needs a token-shaped value builds it at run time, such as a prefix joined to repeated characters.
- A known dev key or test fixture is recorded in the repo's own `.gitleaksignore`, one fingerprint per line from the job's output, under a `#` comment saying why. A fingerprint from a commit scan is `<commit>:<file>:<rule>:<line>`; a working-tree one drops the commit.
- The umbrella's pre-commit hook (`codeclarity-dev`'s `.githooks/`) runs the same version with a copy of `.gitleaks.toml`; its tests fail if the copy differs from this one at `v1`. Change the version here, in that hook and in the devcontainer together.

## Community health files

GitHub uses the files here for every org repo that has none of its own: `SECURITY.md` and the pull request template in `.github/pull_request_template.md`. They take effect from `main`, so a change reaches other repos only after `develop` merges to `main`. Code owners are not inherited: each repo keeps its own `.github/CODEOWNERS`.

## Releases

Release jobs run on pushes to `main` only when the repo variable `CI_RELEASE` is `true`. They create the tag and release only if the tag does not exist yet, pinned to the built commit, as a prerelease for alpha or beta versions.

## Testing

`ci.yml` runs `go-library.yml` against `fixtures/go-library`, `go-fuzz.yml` over the same fixture's `FuzzHello` and over `fixtures/go-image`'s `FuzzGreeting` (a main package, as in plugins) for 10 seconds each, `go-image.yml` against `fixtures/go-image` with `golangci-lint: true` (so both the on and off paths run), and `node-image.yml` against `fixtures/node-image` twice, without and with `e2e-image` (amd64 builds, not pushed), which also lints this repo's workflows. Its `release-callers` job runs the release callers check over `fixtures/release-callers/good`, which must pass, and `fixtures/release-callers/broken`, which must fail with exactly the errors in `fixtures/release-callers/broken.expected`. Its `codeql` job runs `codeql.yml` over `fixtures/go-image`, the JavaScript fixture and the workflows. It passes `version-check: false`, since the fixtures never release: a `develop` -> `main` PR here needs no fixture version bump. Callers leave the input at its default, so their PRs to `main` must still bump the version.

## Moving `v1`

Changes reach callers only when `v1` moves, in this order:

1. Work lands on `develop` through PRs, with `ci` green.
2. `develop` merges to `main` through a PR, with `ci` green.
3. Only then `v1` moves, always to a commit on `main` (usually the merge commit): `git tag -f v1 origin/main && git push -f origin v1`.

Never point `v1` at a commit that is only on `develop` or a feature branch: `main` falls behind what callers run, and the next `develop` -> `main` PR carries changes callers already have. A breaking change goes out as `v2` instead.
