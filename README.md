# pwned.coffee check

A GitHub Action that checks a repository's lockfiles, Dockerfiles, `.nvmrc` and workflow files against
the live incidents on [pwned.coffee](https://pwned.coffee), writes the receipt to the job summary, and
fails the job when packages need fixing.

```yaml
name: pwned.coffee
on:
  push:
  schedule:
    - cron: '17 7 * * *'
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pwned-coffee/check-action@v1
```

Pin it by commit SHA rather than the tag, as you should every action (tags can be moved):

```yaml
      - uses: pwned-coffee/check-action@<full commit SHA> # v1
```

## Inputs

| Input | Default | What it does |
|---|---|---|
| `max-to-fix` | `0` | Fail when more than this many packages are affected. `-1` reports without failing. |
| `fail-on-previously` | `false` | Also fail when only a past ticket (no longer live) held an installed version. |
| `path` | `.` | The directory to check. |
| `site` | `https://pwned.coffee` | The instance to ask. |

## Outputs

`to-fix`, `upgrades`, `no-fix`, `to-check`, `previously` (the receipt's counts) and `report` (the path
to the JSON response of `/api/check`).

## Exit codes

| Exit | When |
|---|---|
| `0` | No more than `max-to-fix` packages affected (and, with `fail-on-previously`, none previously on the board). |
| `1` | More than `max-to-fix` packages affected. `to-fix` counts every affected package: the ones with an upgrade (`upgrades`) and the ones with no fix yet (`no-fix`). Or `fail-on-previously` is on and a past ticket held a version. |
| `2` | The checker couldn't be reached or answered with an error. |

Packages to check by hand (`to-check`) never fail the job: they go in the summary. Matches only a past
ticket holds (`previously`) are history, not a verdict, so they fail the job only with
`fail-on-previously`. `/api/check?fail=1` follows the same rule: 422 when something is affected, 200
when matches are only previously on the board.

## What leaves the runner

The Action reads these files, outside `node_modules`, `vendor`, `target`, `.venv` and `.git`:
`package-lock.json`, `npm-shrinkwrap.json`, `yarn.lock`, `pnpm-lock.yaml`, `requirements*.txt`,
`poetry.lock`, `uv.lock`, `Pipfile.lock`, `composer.lock`, `go.mod`, `go.sum`, `Cargo.lock`,
`Gemfile.lock`, `Dockerfile*`, `Containerfile*`, `*.dockerfile`, `.nvmrc`, `.node-version`,
`action.yml` and `.github/workflows/*.yml`: the files the checker has a reader for. It sends them (at most 40 files, 6 MB) to
`<site>/api/check`, which matches them and answers; pwned.coffee doesn't store them. Nothing else
is sent: no source code, no secrets, no environment.

It needs `bash`, `curl` and `jq` 1.6 or newer, which GitHub's hosted runners have.

Not security advice. Confirm against the vendor advisory on each ticket.

## License

MIT. The checker itself runs at pwned.coffee; this repository holds the Action only.
