# commitshow/audit-action

Run a commit.show audit against a GitHub repo and post the score as a sticky comment on the pull request.

The action shells out to [`commitshow`](https://www.npmjs.com/package/commitshow) on npm, asks for `--json`, and renders a short Markdown summary. Re-running on the same PR updates the existing comment instead of stacking new ones.

## Quick start

Drop this into `.github/workflows/audit.yml`:

```yaml
name: audit
on:
  pull_request:

permissions:
  pull-requests: write   # so the action can post the sticky comment

jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: commitshow/audit-action@v1
```

That's it. By default the action audits the current repo and writes a comment that looks like:

```
### commit.show audit  ·  82 / 100

Audit  42/50  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱
Scout  26/30  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱
Comm.  14/20  ▰▰▰▰▰▰▰▰▰▰▰▰▰▰▱▱▱▱▱▱

Top concerns
- Accessibility 72: buttons missing aria-labels
- No API rate limiting on /auth endpoints
- Three packages with known high-severity advisories

Full report on commit.show
```

## Inputs

| Input          | Default                | Description                                                                              |
|----------------|------------------------|------------------------------------------------------------------------------------------|
| `target`       | current repo           | Repo to audit. Accepts `owner/repo` or `github.com/owner/repo`.                          |
| `refresh`      | `false`                | Bypass the 7-day cache and trigger a fresh audit. Counts against the IP rate cap.        |
| `comment`      | `true`                 | Post or update the sticky comment on the pull request.                                   |
| `fail-below`   | _unset_                | Fail the check when the total score is below this number.                                |
| `github-token` | `${{ github.token }}`  | Token used to post the comment. Needs `pull-requests: write`.                            |

## Outputs

| Output  | Description                                              |
|---------|----------------------------------------------------------|
| `score` | Total score out of 100.                                  |
| `band`  | Score band (e.g. `rookie`, `building`, `strong`).        |
| `url`   | URL of the report on commit.show.                        |

## Examples

### Quality gate

Block PRs that drop below 70:

```yaml
- uses: commitshow/audit-action@v1
  with:
    fail-below: 70
```

### Skip the comment, just record the score

```yaml
- id: audit
  uses: commitshow/audit-action@v1
  with:
    comment: false
- run: echo "Score was ${{ steps.audit.outputs.score }} / 100"
```

### Audit a different repo than the one running the workflow

```yaml
- uses: commitshow/audit-action@v1
  with:
    target: github.com/some-org/some-other-repo
```

### Force a fresh audit

By default the action returns a cached snapshot if one was taken in the last 7 days. To re-run from scratch:

```yaml
- uses: commitshow/audit-action@v1
  with:
    refresh: true
```

## How it works

1. Runs `npx commitshow@latest audit <target> --json` on the runner.
2. Parses the stable v1 JSON schema (`score.total`, `score.audit`, `concerns[]`, etc.).
3. Renders a Markdown summary and writes it to the action job summary.
4. If the workflow was triggered by a pull request and `comment: true`, posts or updates a sticky comment marked with an HTML comment token.

The CLI handles every network call to commit.show. This repository is glue: a YAML action descriptor, a Bash entry script, and a small Python block that turns the JSON into a comment.

## Rate limits

Anonymous audits are capped at 20 per IP per day, and 5 per repo URL per day. A cached audit (under 7 days old) is returned at no rate cost — most workflow runs hit the cache. If you need every PR to trigger a fresh audit, set `refresh: true` and budget for the cap.

## Privacy

The action sends the target URL to commit.show. It does not send your repo contents — commit.show fetches the public repository on its own end via the GitHub REST API. No tokens or secrets from your runner are forwarded.

## Related

- CLI: [`commitshow` on npm](https://www.npmjs.com/package/commitshow)
- Site: [commit.show](https://commit.show)
- Issues for this action: [`commitshow/audit-action/issues`](https://github.com/commitshow/audit-action/issues)

## License

MIT.
