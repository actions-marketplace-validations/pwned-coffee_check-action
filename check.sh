#!/usr/bin/env bash
# The pwned.coffee GitHub Action: sends the repo's lockfiles, Dockerfiles, .nvmrc and workflow files
# to /api/check, writes the receipt to the job summary, and fails when more packages are affected
# than INPUT_MAX_TO_FIX allows. Needs bash, curl and jq 1.6+ (all on GitHub's runners).
set -euo pipefail

site="${INPUT_SITE:-https://pwned.coffee}"
site="${site%/}"
root="${INPUT_PATH:-.}"
max="${INPUT_MAX_TO_FIX:-0}"
fail_previously="${INPUT_FAIL_ON_PREVIOUSLY:-false}"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
output="${GITHUB_OUTPUT:-/dev/null}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The files the checker reads (its READERS in src/repo.ts), outside dependency and VCS folders; the
# server takes 40 files, 6 MB.
(cd "$root" && find . \( -name node_modules -o -name .git -o -name vendor -o -name target -o -name .venv \) -prune -o -type f \( \
  -name package-lock.json -o -name npm-shrinkwrap.json -o -name yarn.lock -o -name pnpm-lock.yaml -o -name pnpm-lock.yml \
  -o -name 'requirements*.txt' -o -name poetry.lock -o -name uv.lock -o -name Pipfile.lock -o -name composer.lock \
  -o -name go.sum -o -name go.mod -o -name Cargo.lock -o -name Gemfile.lock -o -name 'Dockerfile*' -o -name 'Containerfile*' \
  -o -name '*.dockerfile' -o -name .nvmrc -o -name .node-version -o -name action.yml -o -name action.yaml \
  -o -path './.github/workflows/*.yml' -o -path './.github/workflows/*.yaml' \) -print) | sed 's|^\./||' | LC_ALL=C sort | head -n 40 > "$work/files"

if [ ! -s "$work/files" ]; then
  echo "pwned.coffee: no lockfiles, Dockerfiles, .nvmrc or workflows found under $root."
  printf '## pwned.coffee\n\nNo lockfiles, Dockerfiles, `.nvmrc` or workflows found under `%s`.\n' "$root" >> "$summary"
  echo "to-fix=0" >> "$output"
  exit 0
fi

while IFS= read -r f; do
  jq -n --arg path "$f" --rawfile content "$root/$f" '{path: $path, content: $content}'
done < "$work/files" | jq -s '{files: .}' > "$work/body.json"

code="$(curl -sS -o "$work/report.json" -w '%{http_code}' -X POST -H 'content-type: application/json' -H 'accept: application/json' -H 'user-agent: pwned-coffee-check-action' --data-binary @"$work/body.json" "$site/api/check")" || {
  echo "::error title=pwned.coffee::Could not reach $site/api/check."
  exit 2
}
if [ "$code" != 200 ]; then
  echo "::error title=pwned.coffee::$site/api/check answered $code: $(head -c 300 "$work/report.json")"
  exit 2
fi

report="$work/report.json"
to_fix="$(jq '.counts.affected' "$report")"
upgrades="$(jq '.counts.upgrades' "$report")"
no_fix="$(jq '.counts.no_fix' "$report")"
to_check="$(jq '.counts.check' "$report")"
previous="$(jq '.counts.previously // 0' "$report")"
kept="${RUNNER_TEMP:-$work}/pwned-coffee-report.json"
[ "$kept" = "$report" ] || cp "$report" "$kept"
{
  echo "to-fix=$to_fix"
  echo "upgrades=$upgrades"
  echo "no-fix=$no_fix"
  echo "to-check=$to_check"
  echo "previously=$previous"
  echo "report=$kept"
} >> "$output"

packages() { if [ "$1" = 1 ]; then echo "1 package"; else echo "$1 packages"; fi; }
headline="$(packages "$to_fix") to fix"
[ "$to_fix" = 0 ] && headline="nothing to fix"

# The job summary: every affected package with its fix and ticket, then what to check by hand.
{
  echo "## pwned.coffee: $headline"
  echo
  jq -r --arg site "$site" '"Read \(.files_read | length) file\(if (.files_read | length) == 1 then "" else "s" end), \(.packages_checked) package\(if .packages_checked == 1 then "" else "s" end) checked against the live tickets at \($site)."' "$report"
  echo
  if [ "$to_fix" != 0 ]; then
    echo "| Package | Version | File | Fix | Ticket |"
    echo "|---|---|---|---|---|"
    jq -r 'def md: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
      .matches[] | select(.status == "affected")
      | "| \(.package | md) | \(.version | md) | \(.file | md) | \(if .command then "`\(.command | md)`" else (.action | md) end) | [\(.title | md)](\(.url)) |"' "$report"
    echo
  fi
  if [ "$to_check" != 0 ]; then
    echo "### To check by hand"
    echo
    echo "| Package | Version | File | Why | Ticket |"
    echo "|---|---|---|---|---|"
    jq -r 'def md: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
      .matches[] | select(.status == "check")
      | "| \(.package | md) | \(.version | md) | \(.file | md) | \((.note // .action) | md) | [\(.title | md)](\(.url)) |"' "$report"
    echo
  fi
  if [ "$previous" != 0 ]; then
    echo "### Previously on the board"
    echo
    echo "No longer live, so not a verdict: history for these versions."
    echo
    jq -r 'def md: tostring | gsub("\\|"; "\\|"); .previously[] | "- \(.package | md) \(.version | md): [\(.title | md)](\(.url))"' "$report"
    echo
  fi
  echo "Not security advice. Confirm against the vendor advisory on each ticket."
} >> "$summary"

# One annotation per affected package, on the file it was found in.
prefix=""
[ "$root" = "." ] || prefix="${root%/}/"
jq -r --arg p "$prefix" '.matches[] | select(.status == "affected") | "::warning file=\($p)\(.file),title=\(.package) \(.version)::\(.action) (\(.url))"' "$report"

echo "pwned.coffee: $headline ($upgrades with an upgrade, $no_fix with no fix yet, $to_check to check, $previous previously on the board)."
if [ "$max" -ge 0 ] && [ "$to_fix" -gt "$max" ]; then
  echo "::error title=pwned.coffee::$(packages "$to_fix") to fix (allowed: $max)."
  exit 1
fi
if [ "$fail_previously" = true ] && [ "$previous" != 0 ]; then
  echo "::error title=pwned.coffee::$(packages "$previous") previously on the board (fail-on-previously)."
  exit 1
fi
