#!/usr/bin/env bash
# Fails when a job calling go-image.yml or node-image.yml cannot release: it must pass both Docker Hub
# secrets by name and grant contents, id-token and attestations write. Usage: release-callers.sh [dir]
set -euo pipefail

dir=${1:-.github/workflows}
# Reads YAML on stdin and writes it as JSON, with yq from the pinned image.
to_json() {
  docker run --rm -i "${YQ_IMAGE:?YQ_IMAGE must be set}" -p=yaml -o=json '.'
}

# One line per caller job that misses something: job, called file, what is missing.
# shellcheck disable=SC2016 # jq program, not shell
missing_jq='
  def need($ok; $what): if $ok then empty else $what end;
  (.jobs // {}) | to_entries[]
  | (.value.uses // "") as $uses
  | ($uses | capture("(^|/)\\.github/workflows/(?<file>(go|node)-image\\.ya?ml)(@|$)") // empty) as $m
  | .value as $j
  | (if ($j.secrets | type) == "object" then $j.secrets else {} end) as $s
  | (if $j.permissions == "write-all" then {contents: "write", "id-token": "write", attestations: "write"}
     elif ($j.permissions | type) == "object" then $j.permissions else {} end) as $p
  | [need($s | has("DOCKERHUB_USERNAME"); "DOCKERHUB_USERNAME"), need($s | has("DOCKERHUB_TOKEN"); "DOCKERHUB_TOKEN")] as $sec
  | [need($p.contents == "write"; "contents: write"), need($p["id-token"] == "write"; "id-token: write"),
     need($p.attestations == "write"; "attestations: write")] as $perm
  | select(($sec + $perm) | length > 0)
  | [
      (if ($sec | length) > 0 then "secrets: " + ($sec | join(", "))
         + (if $j.secrets == "inherit" then " (pass both by name, not secrets: inherit)" else "" end) else empty end),
      (if ($perm | length) > 0 then "permissions: " + ($perm | join(", ")) else empty end)
    ] as $parts
  | [.key, $m.file, ($parts | join("; "))] | @tsv'

status=0
shopt -s nullglob
for file in "$dir"/*.yml "$dir"/*.yaml; do
  json=$(to_json <"$file")
  # Run jq first so a jq error fails the script instead of an empty loop.
  findings=$(jq -r "$missing_jq" <<<"$json")
  [[ -n "$findings" ]] || continue
  while IFS=$'\t' read -r job called what; do
    # The job's key line: the first "<job>:" after the top-level jobs: key.
    line=$(awk -v job="$job" '/^jobs:/ { in_jobs = 1; next }
      in_jobs && $0 ~ "^[[:space:]]+[\"\x27]?" job "[\"\x27]?:[[:space:]]*(#.*)?$" { print NR; exit }' "$file")
    echo "::error file=${file#./},line=${line:-1}::Job $job calls $called without $what"
    status=1
  done <<<"$findings"
done
exit "$status"
