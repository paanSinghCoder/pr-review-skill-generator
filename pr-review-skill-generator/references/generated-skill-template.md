# Generated-skill template

The exact structure to write into the target repo (default
`.claude/skills/pr-review/`). Replace `{{PLACEHOLDERS}}`; keep everything else
as close to this template as the repo's content allows. Sections marked
`<!-- HUMAN-CURATED -->` must survive every regeneration verbatim.

## Folder layout

```
.claude/skills/pr-review/
├── SKILL.md            # procedure + routing (≤ 150 lines)
├── decisions.md        # deliberate patterns — do NOT flag these
├── glossary.md         # domain terms + invariants
├── hot-zones.md        # risk-weighted attention map
├── context-wanted.md   # unresolved links & open questions for the team
└── rules/
    ├── general.md      # cross-cutting rules
    └── <domain>.md     # one per mined domain
```

## SKILL.md

````markdown
---
name: pr-review
description: Repo-specific PR review for {{OWNER/REPO}} using mined team conventions, business rules, and past review decisions. Use when asked to review a PR, branch, or diff in this repository.
---

<!-- generated-by: pr-review-skill-generator v1 -->
<!-- repo: {{OWNER/REPO}} -->
<!-- generated-on: {{YYYY-MM-DD}} -->
<!-- trained-range: PR #{{FIRST}} -> #{{LAST}} ({{N}} PRs mined, {{H}} held out) -->
<!-- backtest: {{ONE-LINE SUMMARY OR "skipped — <reason>"}} -->

# PR review — {{OWNER/REPO}}

You are reviewing as this team's most senior reviewer would: fluent in the
business logic, aware of past decisions, focused on the few things that
matter. Follow the steps in order.

## Step 0 — staleness check

Run `gh pr list --state merged --limit 1 --json number,mergedAt`. If the
latest merged PR number exceeds {{LAST}} + 150, or today is more than 6 months
past {{GENERATED-ON}}, tell the user:

> This review skill was trained through PR #{{LAST}} ({{GENERATED-ON}}) and is
> now <gap> PRs / <months> behind. Consider regenerating it with
> pr-review-skill-generator.

Then continue with the review regardless.

## Step 1 — get the change under review

- Given a PR number: `gh pr diff <N>` and `gh pr view <N> --json title,body,files`.
- Otherwise review the working branch: `git diff $(git merge-base HEAD {{DEFAULT_BRANCH}})...HEAD`
  plus uncommitted changes if the user asks.
- Read the PR description — it often states intent the diff alone doesn't.

## Step 2 — load context (only what the diff needs)

1. ALWAYS read [decisions.md](decisions.md) — patterns this team has
   deliberately accepted. Never flag anything listed there.
2. Match every changed file path against the routing table; read each matched
   rules file once:

   | Path pattern | Rules file |
   |---|---|
{{ROUTING_ROWS — e.g. | `src/billing/**` | rules/payments.md | }}
   | `**` (always) | rules/general.md |

3. Read [hot-zones.md](hot-zones.md). If changed paths overlap a hot zone,
   apply its extra checks and raise your scrutiny; if all paths are cold
   zones, keep the review brief.
4. If the diff touches domain logic, read [glossary.md](glossary.md) —
   especially the Invariants section.

## Step 3 — review

Priority order — spend attention accordingly:
1. **Business-logic and invariant violations** (glossary invariants, domain
   rules). These are the misses that cost the most.
2. **Correctness** — bugs, edge cases, concurrency, migrations, missed call
   sites. Think about what the diff does NOT touch but should.
3. **Repo conventions** — only those in the loaded rules files.

Ground rules:
- Every finding based on a mined rule cites it: `(rule: <file>, PR #x)`.
- Findings from your own judgment (not a mined rule) are allowed — mark them
  `(judgment)` and check them against decisions.md before reporting.
- Do not flag style that linters/formatters cover. Do not restate the diff.
- If the PR description references an internal doc you can't read, note it
  once under a "Context I lacked" line rather than guessing.

## Step 4 — report

Maximum 5 findings, ordered by severity. If nothing significant: say the
change looks good, name what you checked (one line), and stop — do NOT
manufacture findings to seem thorough.

```
## Review: <one-line verdict>

### 🔴 Blocker — <title>
`path/file.ts:42` — <what is wrong and the consequence>.
Why: <business/correctness reason> (rule: rules/payments.md, PR #482)
Suggestion:
```diff
- current
+ proposed
```

### 🟡 Should fix — <title> …
### 🔵 Consider — <title> …

Checked and fine: <one line — invariants/zones checked that passed>
Context I lacked: <only if applicable>
```

Severity: **Blocker** = violates an invariant/decision or breaks correctness;
**Should fix** = real defect or rule violation, ship-blocking at reviewer's
discretion; **Consider** = improvement, take or leave. Suggestions must be
concrete diffs whenever the fix is local.

## Human-curated rules

<!-- HUMAN-CURATED: the generator must preserve this section verbatim -->
<!-- Team: add rules the miner can't infer — tribal knowledge, upcoming
     migrations, "always page X before touching Y". These are loaded on every
     review, so keep them tight. -->

<!-- END HUMAN-CURATED -->
````

## decisions.md

````markdown
# Deliberate decisions — do NOT flag these

Each entry is a pattern this team has consciously accepted. A reviewer (human
or AI) flagging these wastes everyone's time. If the diff *changes* one of
these patterns, that IS worth flagging — link the entry.

- **{{Pattern, stated concretely}}** — where: `{{paths/scope}}`.
  Why accepted: {{team's stated reason, or "reason not stated in PR — confirm
  with team"}}. (PR #{{x}})

<!-- HUMAN-CURATED -->
<!-- END HUMAN-CURATED -->
````

## rules/<domain>.md

````markdown
# {{Domain}} rules

<!-- Ordered by mined confidence. Every rule cites the PRs it was learned from. -->

- **{{Imperative, checkable rule statement.}}**
  Why: {{one line — the consequence of violating it}}. (PR #{{x}}, #{{y}})

- **{{Rule with example.}}**
  Why: {{…}}. (PR #{{x}})
  ```diff
  - {{anti-pattern from a real diff hunk, trimmed}}
  + {{corrected form}}
  ```

<!-- HUMAN-CURATED -->
<!-- END HUMAN-CURATED -->
````

## glossary.md

````markdown
# Domain glossary — {{OWNER/REPO}}

## Terms
- **{{Term}}** — {{meaning}}. Code: `{{path or package, if known}}`.

## Invariants
<!-- The highest-value lines in this skill. A diff that could violate one of
     these deserves a Blocker. -->
- {{Invariant, stated testably}} (PR #{{x}})

<!-- HUMAN-CURATED -->
<!-- END HUMAN-CURATED -->
````

## hot-zones.md

````markdown
# Hot zones — where review attention pays off

| Path | Why it's hot | Extra checks |
|---|---|---|
| `{{dir}}` | {{e.g. "3 post-merge fixes in last 100 PRs"}} | {{e.g. "rules/payments.md; check migration ordering"}} |

Cold zones (keep review brief): {{e.g. `docs/`, `**/generated/**`}}

<!-- HUMAN-CURATED -->
<!-- END HUMAN-CURATED -->
````

## context-wanted.md

````markdown
# Context wanted — help make this skill smarter

The miner found references it couldn't read. If you can, paste a short summary
under each item, then move durable knowledge into the HUMAN-CURATED section of
the relevant file (this file is a queue — content here is NOT loaded during
reviews).

## Unreadable internal docs
- {{URL}} — referenced in PR #{{x}} ({{context — what it likely covers}})
  > (paste summary here)

## Open questions from mining
- {{e.g. "PR #512 and #587 handle retry backoff differently — which is canonical?"}}
````

## Writing-quality bar (applies to every file)

- Rules are **checkable against a diff**: a reviewer can point to a line and
  say "this violates it". Rewrite vague mined statements into checks.
- Self-contained: readable without opening the source PR. Provenance is for
  verification, not comprehension.
- No secrets, tokens, internal URLs with auth params, or personal contact
  info — scrub anything the miners quoted.
- The generated skill contains distilled business logic. Add this line at the
  top of the generated repo's skill folder in a `README.md` one-liner if the
  repo is public-facing: "Internal knowledge — do not copy this folder to
  public repositories."
