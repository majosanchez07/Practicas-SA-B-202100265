---
name: optimise-claude-context
description: Audit and optimise Claude Code context loading for any repository. Use when you want to reduce token usage, speed up Claude sessions, or check if a repo follows Claude context best practices.
triggers: optimise context, claude context, token usage, slow claude, CLAUDE.md, .claudeignore, context loading, context audit, quick ref, session hook, reduce tokens
---

## What this skill does

Runs a structured audit of the current Claude Code setup, identifies what's wasting tokens or missing, then applies fixes. Based on the three-tier context architecture: only essentials are preloaded, everything else is on-demand.

---

## Step 1 — Audit current state

Read and check each of the following. Do not skip any — the report depends on all of them.

### 1a. CLAUDE.md
- Read `CLAUDE.md` (if it exists)
- Count lines and estimate tokens (words × 1.3 is a good approximation)
- Identify sections that duplicate content already in other files (e.g. config files, README, inline code comments)
- Flag any section over 50 lines that could be summarised or moved to `docs/`
- Flag if total estimated tokens exceed 800

### 1b. .claudeignore
- Check if `.claudeignore` exists
- If it exists, check whether common high-noise paths are covered: `node_modules/`, `dist/`, `*.lock`, `coverage/`, build artefacts
- If it does not exist, flag as missing — this is the highest-impact quick win

### 1c. docs/QUICK_REF.md
- Check if `docs/QUICK_REF.md` exists
- If it does not, flag as missing — essential commands and never-do/always-do rules should live here, not inline in CLAUDE.md

### 1d. Session-start hook
- Check if `.claude/hooks/session-start.sh` exists and is executable
- If it does not exist, flag as missing — saves Claude running orientation commands manually every session

### 1e. Slash commands
- List files in `.claude/commands/`
- Note any obvious gaps for the repo's workflow

### 1f. MEMORY.md (auto-memory)
- Run `git rev-parse --show-toplevel` to get the absolute project root path
- Construct the MEMORY.md path: take the absolute path, replace every `/` with `-`, then prepend `~/.claude/projects/` and append `/memory/MEMORY.md`
  - Example: `/Users/alice/workspace/my-project` → `~/.claude/projects/-Users-alice-workspace-my-project/memory/MEMORY.md`
- Check if the file exists at that path
- If it does **not** exist: note "not found / clean" and skip the remaining checks for this step
- If it **does** exist:
  - Read the file contents
  - Estimate token count: count all words in the file and multiply by 1.3
  - Scan every line for keywords that commonly duplicate plugin or hook managed context: `OpenSpec`, `SDD`, `sdd-planner`, `INDEX.md`, `proposal`, `design.md`, `tasks.md`
  - Flag the full text of any line or bullet that contains one or more of those keywords as a candidate for removal
  - If no lines match: note "exists / no overlap detected"
  - If lines match: collect and record each flagged line so it can be shown in the report and fix steps

### 1g. openspec/INDEX.md
- Check if the directory `openspec/specs/` exists in the repo root. If it does not exist, skip this step entirely — make no mention of it in the report.
- If `openspec/specs/` exists:
  - Check whether `openspec/INDEX.md` exists
  - If it does **not** exist: flag as **HIGH impact** — every exploratory session in this repo loads all spec files (~9,458 tokens wasted per session). Record status as "missing".
  - If it **does** exist:
    - Run `find openspec/specs -name "spec.md" -newer openspec/INDEX.md` to check whether any spec file has been modified more recently than INDEX.md
    - If the command returns one or more files: flag INDEX.md as **stale** — list the files that are newer. Record status as "stale".
    - If the command returns no output: INDEX.md is up to date. Record status as "present / up to date".

---

## Step 2 — Present the audit report

Show a concise report before making any changes:

```
## Claude context audit — <repo name>

### CLAUDE.md
- Lines: <n> (target: ≤ 100)
- Estimated tokens: <n> (target: ≤ 800)
- Status: ✅ lean / ⚠️ oversized
- Sections to trim: [list if any]

### .claudeignore
- Status: ✅ exists / ❌ missing
- Missing patterns (if exists): [list]

### docs/QUICK_REF.md
- Status: ✅ exists / ❌ missing

### .claude/hooks/session-start.sh
- Status: ✅ exists / ❌ missing

### .claude/commands/
- Found: [list]
- Missing: [list if applicable]

### MEMORY.md (auto-memory)
- Status: ✅ not found / ✅ clean / ⚠️ overlapping entries found
- Estimated tokens: <n> (or N/A if not found)
- Overlapping entries: [list of flagged lines, or "none"]

### openspec/INDEX.md
- Status: ✅ present / ⚠️ stale / ❌ missing / ➖ no openspec (skipped)
- Stale specs (if stale): [list]
- Estimated saving if fixed: ~9,458 tokens per exploratory session

### Estimated token saving from fixes: ~<n> tokens per session
```

Ask the developer: **"Should I apply all recommended fixes, or do you want to review each one first?"**

Wait for their answer before proceeding.

---

## Step 3 — Apply fixes

Apply only what was flagged. Do not change things that are already correct.

### Fix: CLAUDE.md is oversized

The goal is a CLAUDE.md that loads fast and stays cached. It should contain:
- **What this service does** — 2–3 sentences max
- **Essential commands** — just the most-used ones, or a pointer to `docs/QUICK_REF.md`
- **Critical rules** — the 3–5 things that must always apply
- **Architecture pointer** — one line pointing to where the deep detail lives

Move any section over these bounds to `docs/` and replace it with a one-line reference.

**Never delete content — move it.** If a section is being removed from CLAUDE.md, it must land somewhere (docs/QUICK_REF.md, a new docs/*.md file, or the relevant spec file).

### Fix: .claudeignore missing or incomplete

Create or update `.claudeignore` with patterns appropriate to this repo's tech stack. Always include:
```
node_modules/
dist/
*.lock
*.log
coverage/
```

For any repo, check `.gitignore` — anything in `.gitignore` that's also a large directory should be in `.claudeignore` too.

### Fix: docs/QUICK_REF.md missing

Create `docs/QUICK_REF.md` containing:
- Top 10 commands for copy-paste
- Never-do list (repo-specific rules that Claude must never break)
- Always-do list (conventions Claude must always follow)
- Key files table (the 5–8 most-referenced files in this repo)

Extract this content from CLAUDE.md if it exists there — don't duplicate it.

### Fix: Session-start hook missing

Create `.claude/hooks/session-start.sh` that displays:
- Current git branch and last commit
- Any active in-progress state (e.g. open feature branches, active work items)
- Contextual tips based on recently changed files

Make it executable with `chmod +x`.

### Fix: MEMORY.md has redundant content

Only apply this fix if step 1f flagged one or more overlapping entries.

Show the engineer the exact lines that will be removed:

```
The following lines in MEMORY.md were flagged as overlapping with context already managed by hooks or plugins:

1. <exact text of flagged line 1>
2. <exact text of flagged line 2>
   ...
```

Ask: **"Should I remove these entries from MEMORY.md?"**

Wait for the engineer's answer before making any changes.

- **If confirmed:** Remove only the flagged lines. Leave all other content exactly as it is.
- **If declined:** Leave MEMORY.md unchanged. Note in the Step 4 summary that the engineer chose to keep the overlapping entries.

### Fix: openspec/INDEX.md missing or stale

Only apply this fix if step 1g flagged INDEX.md as missing or stale.

1. Find all spec files: `find openspec/specs -name "spec.md" | sort`
2. For each spec file found, read it and extract the text of the first `### Requirement:` heading line (strip the `### Requirement: ` prefix to get just the heading text).
3. Derive the capability name from the spec file path: it is the directory name immediately under `openspec/specs/` (e.g. `openspec/specs/my-capability/spec.md` → capability name is `my-capability`).
4. Build the index entries — one line per capability:
   `- **<capability-name>**: <first requirement heading> — \`openspec/specs/<capability-name>/spec.md\``
5. Write `openspec/INDEX.md` with the following structure:
   ```
   # OpenSpec Index

   <!-- Auto-generated by optimise-claude-context skill. Do not edit manually. -->

   <one entry per capability, in sorted order>
   ```
6. If `openspec/specs/` is empty or contains no `spec.md` files, write `openspec/INDEX.md` with the header comment and a note that no specs were found, and report zero entries generated.
7. Never delete an existing `openspec/INDEX.md` without immediately replacing it in the same operation.

---

## Step 4 — Show before/after summary

After applying all fixes:

```
## Optimisation complete

| Item | Before | After |
|---|---|---|
| CLAUDE.md lines | <n> | <n> |
| CLAUDE.md est. tokens | <n> | <n> |
| .claudeignore | ❌ | ✅ |
| docs/QUICK_REF.md | ❌ | ✅ |
| session-start hook | ❌ | ✅ |
| MEMORY.md overlapping entries | <n> tokens / <n> entries | <n> tokens / "none" (or "kept — engineer declined") |
| openspec/INDEX.md | ❌ missing / ⚠️ stale | ✅ present (~9,458 tokens saved per exploratory session) |

Estimated saving: ~<n> tokens per session (~<n>% reduction)

Content moved (not deleted):
- [section] → [destination file]
```

Suggested commit message:
```
chore(.claude): optimise context loading — trim CLAUDE.md, add .claudeignore, QUICK_REF and session hook
```
