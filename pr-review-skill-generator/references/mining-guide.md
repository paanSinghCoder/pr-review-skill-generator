# Mining guide — extracting signals from raw PR data

This guide is for the **miner subagents** (and the orchestrator when running
sequentially). Input: a batch of fetched PR files. Output: a JSON list of
candidate signals. Miners extract and quote evidence; they do NOT decide what
makes it into the final skill — that happens at the distillation stage.

## Input files

For each PR `N` in the work directory:

- `prs/N.meta.json` — fields: `number`, `title`, `body`, `author`, `mergedAt`,
  `baseRefName`, `files` (path + additions/deletions), `commits` (oid,
  committedDate, messageHeadline, messageBody), `reviews` (author, state:
  APPROVED/CHANGES_REQUESTED/COMMENTED, body), `comments` (issue-level
  comments: author, body, createdAt), `labels`.
- `prs/N.threads.json` — `{truncated, nodes}` where `nodes` is the list of
  inline review threads: `isResolved`, `isOutdated`, `path`, `line`, and
  `comments.nodes` (author.login, body, createdAt, diffHunk). If `truncated`
  is true (also listed in `truncated.txt`), the PR had more threads/comments
  than one fetch window — mine what's there, but never treat absence of a
  comment in a truncated PR as evidence of anything.

## Step 1: classify authors, then filter

Classify every comment author into: **human**, **automation bot**, or **AI reviewer**.

- **Automation bots** — discard all their comments entirely: login starts with
  `app/`, ends with `[bot]`, or is one of `dependabot`, `renovate`,
  `github-actions`, `codecov`, `sonarcloud`, `vercel`, `netlify`, `snyk-bot`.
  Also discard entire PRs *authored* by automation bots (dependency bumps) —
  but do count their files toward hot-zone stats if humans left review
  comments on them.
- **AI reviewers** — logins like `copilot-pull-request-reviewer`, `copilot`,
  `coderabbitai`, `cursor`, `greptile-apps`, `ellipsis-dev`, `sweep-ai`, or any
  login the repo's PRs show posting templated review summaries. Keep their
  comments ONLY under the rule in Step 3d.
- **Humans** — everything else. When unsure, treat as human.

Then drop noise comments from any author: bare approvals ("LGTM", "+1", "nice",
emoji-only), CI status chatter, and thread replies that only say "done"/"fixed"
(but note that a "done" reply CONFIRMS the thread was enforced — see below).

## Step 2: know the enforcement signals

The single most important judgment per thread: **was this comment acted on?**
Evidence sufficient for `confidence: validated`, strongest first:

1. A commit in `commits` with `committedDate` AFTER the comment's `createdAt`
   whose message references the concern (fix-commit evidence).
2. An author reply like "done", "fixed", "good catch" AND the thread resolved.
3. `isOutdated: true` AND a later commit whose changed files (from the commit
   message or the PR's `files`) plausibly include the thread's `path`.

NOT sufficient on their own:

- `isOutdated` alone — rebases and force-pushes mark threads outdated without
  anything being addressed. If the PR looks rebased (every commit's
  `committedDate` is later than every comment, or all commits share one
  timestamp), treat `isOutdated` as noise entirely.
- `isResolved` alone — teams bulk-resolve threads at merge time.

A thread with real discussion but only weak evidence can still be a candidate —
emit it with `confidence: asserted`, never `validated`.

A thread where the author **pushed back** ("this is intentional because…",
"we decided X in #123", "won't fix — see ADR") and the reviewer accepted
(resolved without a fixing commit, then APPROVED) is the opposite signal — an
accepted pattern (Step 3c). These are gold: they suppress false positives.

## Step 3: extract candidate signals

Emit one candidate per distinct signal. Types, with base strength weights:

### a. `enforced-correction` (weight 3)
A human review comment that led to a code change. Extract the *generalizable
rule*, not the incident. "This variable name is confusing" is noise; "domain
events must be published after the transaction commits, not inside it" is a
rule. Use the `diffHunk` for code context. If the comment is inherently
one-off (typo, local naming), skip it.

### b. `post-merge-fix` (weight 5)
A PR whose title/body/commits indicate it fixes something a recent PR broke:
"fixes regression from #N", "follow-up to #N", "hotfix", reverts. These are
review MISSES — the most valuable rules of all. State the rule that would have
caught the bug. Link both PRs in provenance.

### c. `accepted-pattern` (weight 3)
A defended-and-accepted pattern per Step 2. Extract: the pattern, where it
applies, the team's stated reason, and the PR(s). These become the generated
skill's `decisions.md` ("do not flag") list.

### d. `ai-reviewer-validated` (weight 1)
An AI reviewer comment counts ONLY if a human then enforced it (fixing commit
or author "fixed" reply). An ignored or dismissed AI comment is at best noise —
and if a human explicitly dismissed it, that's an `accepted-pattern` candidate
instead. Never let unvalidated AI comments become rules: that would launder
generic AI advice into "team knowledge".

### e. `domain-knowledge` (weight 2)
Q&A threads where someone asks "why does X do Y?" and gets an explanation —
even with no code change, the explanation is business logic. Also: invariants
stated in PR bodies ("amounts are integer paise end-to-end"), constraints
("this table is written by service X too — never drop columns without a
2-phase migration").

### f. `domain-term` (weight 1)
Business vocabulary that isn't standard programming lexicon — product nouns,
internal service names, acronyms. Capture the term and the best inferable
definition. These feed `glossary.md`.

### g. `convention` (weight 1)
Repo-specific conventions stated or enforced in review: layering rules, error
handling idioms, naming schemes for specific concepts, "new endpoints need a
rate-limit annotation". EXCLUDE anything a linter/formatter config in the repo
already enforces, and exclude universal best practices ("add tests", "handle
errors") unless the comment shows a repo-specific twist.

### h. `doc-link` (weight n/a)
Any URL to internal docs (Notion, Confluence, Google Docs, internal wikis)
found in PR bodies or comments. Capture URL + surrounding context. Repo-local
paths (docs/, ADRs, CONTRIBUTING) — note them; the orchestrator mines those
directly. External links can't be fetched; they go to `context-wanted.md`.

### i. `file-stats` (mechanical, one per PR)
For hot-zone computation: PR number, list of changed paths, count of human
review comments per path (from threads' `path`), whether the PR was a
post-merge fix, whether any review was CHANGES_REQUESTED.

## Step 4: emit candidates

Output ONLY a JSON array (no prose), one object per candidate:

```json
{
  "type": "enforced-correction",
  "statement": "Refunds must check the ledger balance, not the order total — partial refunds may already exist.",
  "category": "payments",
  "paths": ["src/billing/refunds.ts"],
  "prs": [482],
  "evidence": "reviewer: 'this will double-refund if a partial refund happened' → fixed in commit a1b2c3",
  "confidence": "validated"
}
```

Contract (the orchestrator validates every batch against this before
distillation; a failing batch gets one retry):

- Output parses as a JSON array of objects.
- Regular candidates require: `type` (one of the nine types above), `statement`
  (non-empty string), `category` (string), `paths` (array of strings, may be
  empty), `prs` (non-empty array of integers), `evidence` (string),
  `confidence` (`validated` | `asserted` | `inferred`).
- `file-stats` candidates require: `type`, `pr` (integer), `paths`,
  `comment_counts` (object mapping path → integer), `post_merge_fix` (bool),
  `changes_requested` (bool).

- `statement`: imperative, generalized, self-contained (readable without the PR).
- `category`: a short domain bucket you infer from paths/labels (e.g.
  `payments`, `auth`, `api`, `infra`, `testing`). Distillation will merge these.
- `confidence`: `validated` (enforcement evidence per Step 2), `asserted`
  (stated by a human, not enforced), `inferred` (your generalization).
- `evidence`: ≤ 2 short quotes/paraphrases with attribution. Never include
  secrets, tokens, or personal contact info found in comments.
- For `file-stats`, use fields: `type`, `pr`, `paths`, `comment_counts`,
  `post_merge_fix` (bool), `changes_requested` (bool).

Quality bar: a typical PR with real discussion yields 0–5 candidates. A silent
rubber-stamp PR yields only `file-stats`. Do not pad — empty is a valid answer.
Err toward capturing anything plausibly repo-specific (distillation prunes);
err against generic software advice (distillation can't detect that it's
generic).
