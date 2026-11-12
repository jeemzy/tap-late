# Issue tracker: GitHub

Issues and specs for this repo live in [jeemzy/tap-late](https://github.com/jeemzy/tap-late/issues). Use the `gh` CLI.

## Target repository

The expected repository is `jeemzy/tap-late`, owned by `jeemzy`. Before the first issue write in a session, verify the target with `gh repo view --json nameWithOwner` and check it against `git remote -v`. Resolve a mismatch before writing. Pass `--repo jeemzy/tap-late` when the command cannot infer the repository from this directory.

## Conventions

- **Create an issue:** `gh issue create --title "..." --body-file <file>`.
- **Read an issue:** `gh issue view <number> --json number,title,body,labels,comments`.
- **List issues:** `gh issue list --state open --json number,title,body,labels,comments`, with appropriate label and state filters.
- **Comment:** `gh issue comment <number> --body-file <file>`.
- **Labels:** `gh issue edit <number> --add-label "..."` or `--remove-label "..."`. Use the vocabulary in `triage-labels.md`.
- **Close:** post the explanation with `gh issue comment`, then run `gh issue close <number>`. Post the explanation separately even when the issue is already closed.

For multiline bodies and comments, write the exact text to a temporary file and pass `--body-file`; preserve actual newlines.

## Parent issues and dependencies

- **Sub-issues:** with `gh` 2.94+, use `gh issue create --parent <parent> ...` or `gh issue edit <parent> --add-sub-issue <child>`. With older CLI versions, use `gh api --method POST repos/jeemzy/tap-late/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`.
- **Blocking:** use GitHub's native issue dependencies. With `gh` 2.94+, use `gh issue create --blocked-by <n>,<n> ...` or `gh issue edit <child> --add-blocked-by <blocker>`. With older CLI versions, use `gh api --method POST repos/jeemzy/tap-late/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`.
- Obtain a numeric database ID with `gh api repos/jeemzy/tap-late/issues/<number> --jq .id`; a database ID differs from the issue number and node ID.
- If sub-issues are unavailable, put `Part of #<parent>` at the top of the child and link it in the parent's task list. If dependencies are unavailable, add `Blocked by: #<n>, #<n>` near the top of the child body.
- A ticket is unblocked when every blocker is closed. To count open native blockers, use `gh api repos/jeemzy/tap-late/issues/<number> --jq .issue_dependencies_summary.blocked_by`; check fallback body links when native dependencies are unavailable.

## Pull requests as a triage surface

**PRs as a request surface: no.** Set to `yes` if external PRs should enter the feature-request triage queue.

When enabled, use `gh pr view`, `gh pr diff`, `gh pr comment --body-file <file>`, `gh pr edit --add-label`, and `gh pr close` for external PRs. GitHub shares issue and PR numbers; resolve the object type before acting on a bare number.

## Publishing and fetching

When a skill says **publish to the issue tracker**, create a GitHub issue. When it says **fetch the relevant ticket**, read the referenced issue with its labels and comments.

## Wayfinding operations

Used by the wayfinder skill when invoked:

- **Map:** one issue labelled `wayfinder:map`, holding Notes, Decisions-so-far, and Fog.
- **Child:** one issue per ticket, linked to the map as a sub-issue or through the parent/child fallback above. Use `wayfinder:research`, `wayfinder:prototype`, `wayfinder:grilling`, or `wayfinder:task` for its type. Create a missing wayfinder label when that workflow needs it.
- **Frontier:** inspect the map's open children, exclude blocked or assigned issues, and take the first remaining ticket in map order.
- **Claim:** assign the ticket to the driving developer with `gh issue edit <number> --add-assignee @me` before working on it.
- **Resolve:** comment with the answer, close the child, and append a short answer and link to the map's Decisions-so-far.
