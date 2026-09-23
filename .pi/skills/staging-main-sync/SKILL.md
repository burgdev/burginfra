---
name: staging-main-sync
description: Two-way staging/main branch sync for burginfra. Use when asked to promote or merge staging into main via PR, update or realign staging from main, or when staging and main histories diverge after a squash merge (e.g. after FluxCD wodore image-tag bumps on staging were promoted). Triggers "sync staging", "promote staging", "merge staging into main", "update staging from main".
---

# Staging ↔ main sync (burginfra)

## Repo facts
- GitHub repo `burgdev/burginfra` allows **squash merges only** — no merge/rebase via PR.
- Neither branch is protected. Direct pushes to `staging` are normal (the FluxCD image-policy bot commits tag bumps there).
- Squash merges make the branches' histories diverge even when their trees are identical — realign after every promote.
- CI is GitGuardian Security Checks only (~30–60 s).
- Sync PRs (#64–#67) carry **no labels**; the repo has no BUILD label.
- Branch references: `4b68add` / `cfe857f` are old local merge commits; #63 is the main→staging PR precedent.

## Workflow A — promote staging → main

1. Preflight — working tree must be clean:
   ```bash
   git fetch origin --prune
   git status --porcelain                     # must print nothing
   git checkout staging && git pull --ff-only
   ```
2. Review what ships:
   ```bash
   git log --oneline origin/main..origin/staging
   git diff origin/main...origin/staging
   ```
3. Create the PR. Follow the `pr-conventions` skill: changelog-ready imperative title (e.g. `Update wodore staging backend and frontend images`), confirm title + labels with the user before creating, no labels unless the user asks:
   ```bash
   gh pr create --base main --head staging --title "<title>" --body "<what & why / changes / testing / risks>"
   ```
4. Wait for GitGuardian (bounded, ~2 min): `gh pr checks <N> --watch --interval 10`
5. Merge: `gh pr merge <N> --squash`
6. `git checkout main && git pull --ff-only && git checkout staging`
7. Immediately run Workflow B to realign staging.

## Workflow B — update staging from main (realign)

⚠️ **Safety gate — run first, every time:**
```bash
git fetch origin
git diff origin/main origin/staging    # must print NOTHING
```
- Empty → safe to proceed (staging holds nothing main lacks).
- Non-empty (fresh unpromoted bot bumps or other staging-only work) → **STOP**. Promote first (Workflow A). Resetting now would destroy staging-only work.

### B1. Reset staging onto main — preferred, matches repo practice
```bash
git push --force-with-lease origin origin/main:staging
git checkout staging && git reset --hard origin/staging
```
Branches become identical; the next promote PR diffs cleanly. Granular bot commits vanish from staging's history — their content lives in main's squash commit, which is fine.

### B2. PR fallback — no force push, keeps an audit trail (precedent #63)
```bash
gh pr create --base staging --head main --title "<imperative title>"
gh pr checks <N> --watch --interval 10
gh pr merge <N> --squash
```
Caveat: histories stay diverged; future promote PRs' "Files changed" may re-list already-merged changes — cosmetic, merges still resolve correctly.

### B3. Merge-commit alternative (precedent `cfe857f`) — keeps granular history
```bash
git checkout staging && git pull --ff-only
git merge origin/main && git push origin staging
```
Repairs the merge-base without discarding bot commits, but introduces merge commits (off-pattern for the PR habit). Only use if B1 is unwanted.

## Verify after any workflow
```bash
git log --oneline origin/main..origin/staging   # empty right after B1
git diff origin/main origin/staging             # empty
gh pr list --state open                         # none expected
```
