# Backtest guide — measuring the generated skill before anyone trusts it

The backtest answers one question honestly: *if this skill had reviewed PRs it
was never trained on, would it have caught what human reviewers caught?* It
runs AFTER the skill is written, on held-out PRs selected BEFORE mining.

## Step 1: select holdouts (before mining!)

From `index.json` + thread files, find qualifying PRs: authored by a human,
with ≥ 3 human review comments. Pick **5 at random** from qualifying PRs (not
the top 5 most-discussed — that would skew both the test and the training cut).
Use a deterministic spread (e.g. every k-th qualifying PR) rather than true
randomness so reruns are reproducible.

- Remove holdouts from the mining set BEFORE any miner runs.
- If fewer than 3 PRs qualify, skip the backtest entirely and write
  `backtest: skipped — insufficient review activity` into the metadata. Never
  fake a score.

## Step 2: reconstruct the pre-review state

Reviewers commented on code that later changed; testing against the merged
diff would erase exactly the problems the skill should catch. For each holdout:

1. First human review timestamp = earliest human comment `createdAt` across
   `threads.json` and `reviews` in `meta.json`.
2. Pre-review head = the latest commit in `commits` with
   `committedDate` < that timestamp. Fallback: the first commit.
3. Fetch the diff the reviewer saw:
   ```bash
   BASE=$(gh api repos/OWNER/REPO/pulls/N --jq .base.sha)
   gh api "repos/OWNER/REPO/compare/${BASE}...${PRE_REVIEW_HEAD}" \
     -H "Accept: application/vnd.github.v3.diff" > holdout-N.diff
   ```
4. If the diff exceeds ~3000 lines, truncate to the files that human review
   comments touched plus the 10 largest remaining files, and note the
   truncation in the report.

## Step 3: run blind reviews

For each holdout, spawn a **fresh subagent** that receives ONLY:

- the generated skill files (instructed to follow the skill's own procedure), 
- the pre-review diff, PR title, and PR body.

It must NOT see the human comments, the merged state, or this guide, and must
not fetch the PR (a leaked comment invalidates the test — instruct it to work
offline from the provided diff only). It outputs findings in the skill's own
format. Run holdouts in parallel.

## Step 4: judge the comparison

A separate judge subagent gets, per holdout: the skill's findings and the
actual human review comments (bot/AI comments excluded, noise comments
excluded). It classifies:

- **caught** — a finding matches a human comment's underlying concern (same
  issue; file/line may differ slightly). Judge the concern, not the wording.
- **missed** — a substantive human concern with no matching finding. Ignore
  pure style nits and questions that led to no change.
- **novel** — a finding no human raised. The judge marks each novel finding
  `plausible` or `dubious` from the diff alone (dubious ⇒ likely false
  positive; a high dubious count means the rules are too aggressive).

## Step 5: report and record

Aggregate into `backtest-report.md` in the work directory:

```
Backtest: 5 held-out PRs (#812 #845 #871 #890 #902)
Caught 7 / 11 human-flagged concerns (64%)
Missed: 4 — of which 3 relate to zones with no mined rules (list them)
Novel findings: 3 (2 plausible, 1 dubious)
Per-PR detail: ...
```

Write the one-line summary into the generated SKILL.md metadata block, e.g.
`backtest: caught 7/11 human concerns on 5 held-out PRs; 1/3 novel findings dubious`.

## Interpreting results (tell the user this, honestly)

- **Catch rate ≥ 60%** with few dubious novels: healthy for v1.
- **30–60%**: usable but look at the misses — if they cluster in one domain,
  the repo's docs for that domain belong in `context-wanted.md`.
- **< 30%**: the mined rules are weak — usually a repo with thin review
  culture (rubber-stamp approvals). Say so plainly and recommend leaning on
  the human-curated section instead of regenerating with more PRs.
- Misses are more informative than catches: each one is a candidate rule the
  distillation dropped or never saw. List them explicitly so the dev can
  hand-promote them into the human-curated section.

The backtest costs a handful of subagent runs and is the difference between
"trust me" and a measured claim. Do not skip it to save time unless the user
explicitly asks.
