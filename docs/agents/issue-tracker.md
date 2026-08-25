# Issue tracker: GitHub

Issues and specifications for this repository live in GitHub Issues:

- Repository: `Nicoeevee/SSSubtitle`
- Issues: <https://github.com/Nicoeevee/SSSubtitle/issues>
- CLI repository argument: `--repo Nicoeevee/SSSubtitle`

## Publishing

When an engineering skill says "publish to the issue tracker", create or update a GitHub Issue in this repository. Prefer non-interactive commands that preserve Markdown formatting, for example:

```powershell
gh issue create --repo Nicoeevee/SSSubtitle --title "<title>" --body-file "<body-file>"
```

Use the repository's issue templates when they exist. Include acceptance criteria and validation evidence in the issue body rather than relying on chat history.

## Fetching

When a skill says "fetch the relevant ticket", read the referenced GitHub Issue before planning or editing:

```powershell
gh issue view <number> --repo Nicoeevee/SSSubtitle --comments
```

Treat the Issue body and maintainer comments as the acceptance surface. Do not infer that a focused passing test closes the entire Issue unless every acceptance criterion has been verified.

## Pull requests as a request surface

External pull requests are not part of the triage request queue by default. Do not treat a pull request as a new implementation request unless the user or a maintainer explicitly asks for review or follow-up work.

PRs as request surface: **off**.
