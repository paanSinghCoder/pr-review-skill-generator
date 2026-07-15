# Distillation guide — from candidate signals to a review skill

Input: the concatenated JSON candidate lists from all miner batches, plus
repo-local docs identified during mining. Output: the content of every file in
the generated skill (see `generated-skill-template.md` for exact formats).
This stage is where quality is won: be ruthless — a 40-rule skill that is 90%
right beats a 200-rule skill that is 60% right.

## Step 1: cluster duplicates

Group candidates that express the **same underlying rule** even when worded
differently or found in different files. For each cluster:

- Merge into the single best statement (rewrite for clarity; imperative voice).
- Union the provenance PR lists and paths.
- `occurrences` = number of distinct PRs in the union.
- Confidence = the highest in the cluster (any `validated` member ⇒ validated).

Do NOT cluster rules that share a topic but differ in substance ("validate
webhook signatures" ≠ "webhook handlers must be idempotent").

## Step 2: score and cut

Score each cluster: `score = weight × occurrences × confidence-multiplier`
(validated ×2, asserted ×1, inferred ×0.5). Weights come from the mining
guide's signal types (post-merge-fix 5, enforced-correction 3, …).

Keep a cluster if ANY of:
- score ≥ 6 (e.g. one validated enforced-correction, or two asserted conventions)
- it appears in ≥ 2 distinct PRs
- it is a `post-merge-fix` (always keep — these were expensive)
- it is an `accepted-pattern` (always keep — these kill false positives)

Then drop, regardless of score:
- Generic best practices with no repo-specific twist ("add tests", "handle nil").
- Anything enforced by the repo's linter/formatter/CI config — check for
  configs (.eslintrc*, ruff/flake8, golangci, .editorconfig, CI workflows)
  before finalizing, and drop rules those tools already catch.
- Incident-specific one-offs that don't generalize.
- Rules you cannot attach at least one PR number to.

## Step 3: organize into domains

Derive 3–8 domain buckets from the clusters' `category` fields, the repo's
top-level structure, and its labels. Merge sparse categories into their nearest
neighbor; split any bucket that would exceed ~25 rules. Each bucket becomes
`rules/<domain>.md`. Cross-cutting rules (error handling, API design) get a
`rules/general.md`.

Within a file, order rules by score, highest first. Format per rule (see
template): bold imperative statement, one-line *why*, provenance `(PR #x, #y)`,
and — only when a mined `diffHunk` provides a crisp one — a minimal good/bad
example. Rules must be checkable against a diff; "be careful with X" is not a
rule. Rewrite as the check a reviewer would actually perform.

## Step 4: build decisions.md (the suppression list)

From `accepted-pattern` clusters. Each entry: the pattern, where it applies,
the team's stated reason, provenance. This file is loaded on EVERY review, so
keep entries tight. If the reason was never stated, write "reason not stated
in PR — confirm with team" rather than inventing one.

## Step 5: build glossary.md

Consolidate `domain-term` and `domain-knowledge` candidates. One line per
term: **Term** — meaning — where it lives in code (if known). Include stated
invariants here too, under an "Invariants" heading — these are the highest-value
lines in the whole skill for business-logic review. Cap ~40 entries, prefer
terms that appeared in ≥ 2 PRs or in an invariant statement.

## Step 6: build hot-zones.md

From `file-stats` candidates, compute per directory (aggregate to the deepest
directory with ≥ 3 PRs touching it):

- `review_density` = human review comments / PRs touching it
- `fix_count` = post-merge fixes touching it
- `cr_count` = CHANGES_REQUESTED reviews on PRs touching it

List the top ~10 zones where `fix_count ≥ 1` or `review_density` is clearly
above the repo median. For each: path, why it's hot (one line, from the data),
and what extra checks apply (link the relevant rules file). Also list notable
COLD zones (generated code, vendored deps, docs) where review effort is wasted.

## Step 7: build the routing table

Map path globs → rules files for the generated SKILL.md. Derive globs from the
`paths` of each rules file's clusters, generalized to directories. Every rules
file must be reachable by at least one glob; add a catch-all `**` → 
`rules/general.md`. Keep ≤ 15 rows; a reviewer loads files whose globs match
any changed path.

## Step 8: build context-wanted.md

- All external `doc-link` URLs, each with: URL, the PR/context it came from,
  and what the doc likely covers. The dev is asked to paste in the relevant
  content or a summary — anything they add here should later be moved by them
  into the human-curated section or a rules file.
- Open questions the mining raised (contradictory rules, unstated reasons in
  decisions.md, suspected invariants that no PR confirmed).

## Step 9: size budgets (hard limits)

- Generated `SKILL.md` ≤ 150 lines — it is procedure + routing, not content.
- Each `rules/<domain>.md` ≤ 120 lines. Over budget ⇒ cut lowest scores, don't
  compress wording into mush.
- `decisions.md` ≤ 80 lines; `glossary.md` ≤ 60; `hot-zones.md` ≤ 50.
- Every rule carries provenance. No exceptions — an uncited rule is unverifiable
  and gets deleted on the next regeneration.

## Incremental regeneration

When updating an existing generated skill (new PRs only):

1. Parse existing rules + provenance from the current skill files.
2. Cluster NEW candidates against existing rules first: a match extends the
   existing rule's provenance (and may sharpen its wording); no match ⇒ new
   cluster, scored as usual.
3. A new `accepted-pattern` that contradicts an existing rule ⇒ move the rule
   to decisions.md with both provenances and flag it in the final report —
   the team changed its mind; the dev should confirm.
4. NEVER edit anything between `<!-- HUMAN-CURATED -->` markers, in any file.
5. Update metadata: extend trained-range, refresh generated-on, re-run backtest.
