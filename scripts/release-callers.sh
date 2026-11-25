#!/usr/bin/env bash
# Fails when a job calling go-image.yml or node-image.yml cannot release: it must pass both Docker Hub
# secrets by name and grant contents, id-token and attestations write. Usage: release-callers.sh [dir]
set -euo pipefail

dir=${1:-.github/workflows}
# YAML_TO_JSON is a command reading YAML on stdin and writing JSON; by default yq from YQ_IMAGE.
to_json() {
  if [[ -n "${YAML_TO_JSON:-}" ]]; then
    # shellcheck disable=SC2086 # a command line, split on purpose
    $YAML_TO_JSON
  else
    docker run --rm -i "${YQ_IMAGE:?YQ_IMAGE or YAML_TO_JSON must be set}" -p=yaml -o=json '.'
  fi
}

# One line per caller job that misses something: job, called file, what is missing.
# shellcheck disable=SC2016 # jq program, not shell
missing='
  def need($ok; $what): if $ok then empty else $what end;
  (.jobs // {}) | to_entries[]
  | (.value.uses // "") as $uses
  | ($uses | capture("(^|/)\\.github/workflows/(?<file>(go|node)-image\\.ya?ml)(@|$)") // empty) as $m
  | .value as $j
  | (if ($j.secrets | type) == "object" then $j.secrets else {} end) as $s
  | (if ($j.permissions | type) == "object" then $j.permissions else {} end) as $p
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
  while IFS=$'\t' read -r job called what; do
    line=$(grep -n -m1 -E "^[[:space:]]+[\"']?${job}[\"']?:[[:space:]]*(#.*)?$" "$file" | cut -d: -f1 || true)
    echo "::error file=${file#./},line=${line:-1}::Job $job calls $called without $what"
    status=1
  done < <(jq -r "$missing" <<<"$json")
done
exit "$status"
