---
name: pr-review-skill-generator
description: Generate a repo-specific PR-review skill by mining recently merged PRs — review comments, enforced corrections, accepted patterns, domain vocabulary, and post-merge fixes — into a distilled reviewer skill with provenance and a measured backtest score. Use when asked to generate, train, build, regenerate, or update a PR review skill from a repository's history.
---

# PR-review-skill generator

You will mine a repository's merged PRs for the knowledge a senior reviewer
carries in their head — what the team actually enforces, what it has
deliberately accepted, its domain vocabulary and invariants — and distill it
into a `pr-review` skill for that repo. The pipeline:

```
fetch (script) → select holdouts → mine (parallel subagents) → distill → write skill → backtest → report
```

Run phases in order. Each phase names the reference doc to read **when you
reach it** — don't read them all upfront.

## Phase 0 — preflight

1. Check `gh auth status` succeeds and you're inside the target repo (or the
   user named one). This tool requires GitHub; if the repo is on GitLab or
   Bitbucket, say v1 doesn't support it and stop.
2. Detect an existing generated skill at `.claude/skills/pr-review/SKILL.md`.
   If present, read its `trained-range` metadata and switch to
   **incremental mode** (see below).
3. Ask the user (one round of questions, then proceed without further asking):
   - How many merged PRs to mine? Default **100** (cost scales linearly).
   - **Full run or preview first?** A preview mines ~15 PRs, shows the top
     candidate rules and the would-be decisions.md entries, then stops and
     asks before the full run (no skill written, no backtest). Recommend the
     preview to first-time users.
   - Output location? Default `.claude/skills/pr-review/` in the target repo.
   - Monorepo scoping — restrict to a subdirectory, or mine everything?
   Before proceeding, state the estimated cost: ~`ceil(N/10)` miner subagents
   + one blind reviewer per holdout + 1 judge (so ~17 agent runs for N=100,
   H=5; a preview is ~2).
4. Sanity-check scale: `gh pr list --state merged --limit <N> --json number --jq length`.
   - Fewer than 30 merged PRs: proceed, but warn that the skill will be thin.
   - Fewer than 15: skip holdouts/backtest (note it in metadata).

## Phase 1 — fetch

Run `scripts/fetch-pr-data.sh` from this skill's directory:

```bash
scripts/fetch-pr-data.sh --count <N> --out <workdir>
```

Use a work directory outside the repo (a scratch/tmp path) so nothing lands in
the user's git status. The script is resumable — on partial failure, re-run
it. If more than ~10% of PRs land in `failed.txt`, stop and show the user the
errors (usually auth scope or rate limiting) instead of mining a biased
sample. If `truncated.txt` exists, tell the user which PRs have incomplete
thread data (miners are instructed to handle it).

## Phase 2 — select holdouts

Read `references/backtest-guide.md` §1 now. Select the holdout PRs **before
any mining** and set them aside — they must not appear in any miner's batch.

## Phase 3 — mine (map)

Read `references/mining-guide.md` now — it defines the signal taxonomy, bot
filtering, and the exact candidate JSON format.

1. Partition the non-holdout PRs into batches of ~10 (fewer if the repo's PRs
   are discussion-heavy). Skip PRs authored by automation bots when batching —
   but keep their numbers for file-stats if humans commented.
2. Spawn one subagent per batch, **in parallel**. Each gets: the batch's file
   paths in the workdir, the full text of `mining-guide.md` (or the path, and
   instruct it to read it first), and the instruction to return ONLY the JSON
   candidate array. If parallel subagents aren't available, process batches
   sequentially yourself with fresh attention per batch.
3. Write each batch's output to `<workdir>/candidates/batch-<K>.json` as it
   completes (a crash then costs one batch, not all). Validate each batch
   against the contract in mining-guide.md Step 4 — quickest check:
   `python3 -c "import json,sys; [c['type'] and c['prs' if 'prs' in c else 'pr'] for c in json.load(open(sys.argv[1]))]" <file>`
   (if python3 is unavailable, inspect the file yourself). A batch that fails
   to parse or violates the contract gets one retry with the error quoted;
   after that its PRs are logged as unmined in the final report — don't
   silently drop them. Then concatenate all batches into
   `<workdir>/candidates.json`.
4. Additionally, mine repo-local docs yourself (no subagent needed):
   CONTRIBUTING, docs/, ADRs, architecture notes — anything `doc-link`
   candidates or PR bodies pointed at inside the repo. Emit candidates in the
   same format, type `convention`/`domain-knowledge`, provenance = file path.

## Phase 4 — distill (reduce)

Read `references/distillation-guide.md` now and follow it end to end:
cluster → score → cut → organize into domains → decisions.md → glossary →
hot-zones → routing table → context-wanted. Check the repo for linter/CI
configs at the "cut" step, as the guide requires.

**Preview mode stops here.** Show the top ~15 rules by score (with
provenance), the decisions.md entries, and the hot zones, then ask: proceed
to the full run, or stop? On proceed, fetch and mine the remaining PRs
(preview batches are already done) and select holdouts from PRs the preview
did NOT mine, then continue normally.

## Phase 5 — write the generated skill

Read `references/generated-skill-template.md` now. Write every file exactly in
that structure to the output location, filling placeholders:

- `trained-range`: lowest → highest PR number actually mined, plus the
  highest PR's **merge date** (incremental runs fetch by this date); count
  mined and held out.
- `generated-on`: today's date. Get it from the system, don't guess.
- `backtest`: leave as `pending` — Phase 6 fills it.
- Respect every size budget. Every rule carries provenance.

Before writing, run a scrub pass over every file you are about to write:

```bash
grep -rnE 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY|xox[baprs]-|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' <output-dir>
```

Any hit: replace the value with `[scrubbed]` (emails: keep GitHub handles
instead). Mined comment text can contain leaked credentials — the generated
skill must not republish them.

## Phase 6 — backtest

Follow `references/backtest-guide.md` §2–5: reconstruct each holdout's
pre-review diff, run blind reviewer subagents in parallel (they get only the
generated skill + the diff — never the human comments), judge caught / missed
/ novel, write `backtest-report.md` to the workdir, and update the `backtest`
metadata line in the generated SKILL.md with the one-line summary.

## Phase 7 — report to the user

End with a report containing, in this order:

1. **What was written** — file list with line counts.
2. **Backtest results** — the honest numbers, including the misses (each miss
   is a candidate rule the team can hand-add), interpreted per the guide.
3. **Top 5 mined rules** — a taste of what it learned, with provenance.
4. **context-wanted.md contents** — ask the dev to fill what they can.
5. **Next steps** — review the generated files like any PR (they're the
   team's knowledge, the team should sanity-check them); add tribal knowledge
   to the HUMAN-CURATED sections; commit the folder to the repo; try it with
   "review PR #<recent>".
6. **Privacy note** — the generated skill distills internal business logic;
   it belongs in the private repo, never in public ones.

## Incremental mode (existing skill found)

Goal: extend, don't rebuild — and never touch human content.

1. Read the existing skill's `trained-range` (…→ #LAST, merged through DATE)
   and all its files.
2. Fetch only newer PRs by merge date:
   `scripts/fetch-pr-data.sh --since <DATE> --count 300 --out <workdir>`
   then drop any fetched PR ≤ #LAST (boundary-day overlap). If the metadata
   predates the DATE field, fall back to the merge date of #LAST
   (`gh pr view <LAST> --json mergedAt`). If more than 300 PRs come back,
   recommend a full regeneration instead.
3. Mine the new PRs (Phases 2–3, holdouts from new PRs only if ≥ 15).
4. Merge per `distillation-guide.md` § "Incremental regeneration": new
   evidence extends existing rules' provenance; contradictions move rules to
   decisions.md and are flagged in the report; `<!-- HUMAN-CURATED -->`
   sections are preserved byte-for-byte in every file.
5. Update metadata (extend trained-range, refresh generated-on), re-run the
   backtest, report as in Phase 7 with a "what changed" section.

## Failure honesty

- Thin review culture (mostly rubber-stamps) ⇒ say the mined skill is weak and
  the HUMAN-CURATED sections will have to carry it. Don't inflate.
- Never invent a rule, a reason, or a provenance PR number. Every claim in the
  generated skill must trace to fetched data or a repo file.
- If a phase fails midway, tell the user what completed and how to resume
  (the fetch script resumes; mining can rerun per batch; distillation restarts
  from `candidates.json`).
