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

## Inputs

| Input | Default | What it does |
|---|---|---|
| `max-to-fix` | `0` | Fail when more than this many packages are affected. `-1` reports without failing. |
| `path` | `.` | The directory to check. |
| `site` | `https://pwned.coffee` | The instance to ask. |

## Outputs

`to-fix`, `upgrades`, `no-fix`, `to-check` (the receipt's counts) and `report` (the path to the JSON
response of `/api/check`).

## What leaves the runner

The Action reads these files, outside `node_modules`, `vendor`, `target`, `.venv` and `.git`:
`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `requirements*.txt`, `poetry.lock`, `uv.lock`,
`Pipfile.lock`, `composer.lock`, `go.mod`, `go.sum`, `Cargo.lock`, `Gemfile.lock`, `Dockerfile*`,
`.nvmrc`, `.node-version` and `.github/workflows/*.yml`. It sends them (at most 40 files, 6 MB) to
`<site>/api/check`, which matches them and answers; pwned.coffee doesn't store them. Nothing else
is sent: no source code, no secrets, no environment.

It needs `bash`, `curl` and `jq` 1.6 or newer, which GitHub's hosted runners have.

Not security advice. Confirm against the vendor advisory on each ticket.

## License

MIT. The checker itself runs at pwned.coffee; this repository holds the Action only.
