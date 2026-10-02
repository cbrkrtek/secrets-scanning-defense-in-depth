
### experiment A, baseline ( no protection):
```
commit 2d885bffaf4ce988a5a27e04fc358b942872a313 (HEAD -> main)
Author: cbrkrtek <253804507+cbrkrtek@users.noreply.github.com>
Date:   Mon Sep 28 19:07:20 2026 +0300

    feat: add aws config (experiment A - no protection)

 config/aws-credentials.txt | 2 ++
 1 file changed, 2 insertions(+)
```
### experiment B, pre-commit hook active:
```
Detect hardcoded secrets.................................................Failed
- hook id: gitleaks
- exit code: 1

○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

Finding:     AWS_ACCESS_KEY_ID=REDACTED
Secret:      REDACTED
RuleID:      fake-hardcoded-aws-key
Entropy:     3.921928
Tags:        [aws access-key]
File:        config/aws-credentials-2.txt
Line:        1
Fingerprint: config/aws-credentials-2.txt:fake-hardcoded-aws-key:1

8:05PM INF 1 commits scanned.
8:05PM INF scan completed in 5.67ms
8:05PM WRN leaks found: 1
```

## Experiment C — Pre-commit bypass via --no-verify
- Date/time: 2026-09-28 20:09 +0300
- Command: git commit --no-verify -m "feat: add 3rd aws config (experiment C - bypassed with --no-verify)"
- Result: commit succeeded locally, pre-commit hook never invoked (no gitleaks output at all)
- Commit hash: d5c7def5763a2f04ec588ea7ffb4ed04934e041d
- Screenshot: screenshots/6-no-verify-bypass.png

## Experiment D — Pre-commit bypass via GitHub REST API (direct commit)
- Method: PUT /repos/{owner}/{repo}/contents/{path} (GitHub Contents API), bypassing local
  git client and .git/hooks entirely
- Token: fine-grained PAT, scope: Contents (Read and write), single repository
- Attempt 1 (protections enabled):
  - Result: BLOCKED — HTTP 409 "Repository rule violations found / Secret detected in content"
  - Root cause (after investigation): NOT a repository ruleset (Settings  ->  Rules -> Rulesets
    was empty), NOT a repo-level Code security toggle checked at the time — the first
    control found was an ACCOUNT-WIDE setting: Settings (profile) → Code security →
    "Push protection for yourself", described as "Block commits that contain supported
    secrets across all public repositories on GitHub"
  - Authorized bypass attempt via `push_protection_bypasses` + returned `placeholder_id`
    was rejected with the same 409 — this bypass mechanism is designed for
    organization/repository rulesets with an explicit Bypass list, not for this
    account-wide control; there was no Bypass list to grant access through
  - Screenshot: screenshots/7-push-protection-blocked.png
- Attempt 2 (after disabling "Push protection for yourself" in account settings):
  - Result: SUCCEEDED — HTTP 200/201
  - Commit SHA: 5086feb733ed98b54697f65b6044a198c62b0570
  - File URL: https://github.com/cbrkrtek/secrets-scanning-defense-in-depth/blob/main/config/aws-credentials-4.txt
  - Screenshots: screenshots/8-api-commit-success.png, screenshots/9-api-commit-on-github.png

## Experiment D (continued) — standard git push hit a SECOND, repo-level toggle
- Context: after merging the API-made commit into the local branch (git pull --no-rebase),
  a standard `git push origin main` was attempted to sync the merge commit back to GitHub
- Result: BLOCKED with `GH013: Repository rule violations found` / `GITHUB PUSH PROTECTION`,
  even though the ACCOUNT-LEVEL "Push protection for yourself" toggle was already disabled
- Blocked secrets spanned MULTIPLE historical commits in the push range, not just HEAD:
  2d885bf (Day 1 baseline), d5c7def (Experiment C) -  these commits were created locally
  days earlier but had never been sent through a standard git push before this point
- Finding: GitHub Push Protection scans the ENTIRE set of commits being transmitted in a
  single push, not only the tip commit - a secret committed locally long ago surfaces the
  first time it is actually pushed, regardless of its commit age
- Root cause of continued blocking: a THIRD, independent toggle exists — repo-level
  Settings → Code security and analysis -> "Secret scanning" -> "Push protection" (distinct
  from the "Protection rules" section on the same page, which governs Code Scanning/CodeQL,
  not secrets). This toggle is independent of both the account-level toggle and the
  (empty) repository ruleset.
- Resolution: disabled the repo-level Push protection toggle specifically; git push
  then succeeded
- Both toggles (account-level and repo-level) were re-enabled immediately after

## Side note — API commits diverge from local git history
Committing via the GitHub REST API advances the remote main branch independently of any
local clone. A subsequent git push from a local clone that doesn't know about the
API-made commit is rejected ("! [rejected] main -> main (fetch first)"), requiring an
explicit git fetch + git pull --no-rebase (merge) before pushing again. This is a small
but real operational cost of the API-bypass path: it doesn't just skip local hooks, it also
leaves the local working copy out of sync until manually reconciled.

## Day 2 final summary — five points
1. Pre-commit hook (Gitleaks) — client-side, trivially bypassed (--no-verify, API commit)
2. GitHub Push Protection exists on at least THREE independent levels simultaneously:
   account-level, repository-level, and repository ruleset (empty in this project, but a
   theoretically available fourth layer)
3. Fully disabling push protection required toggling off BOTH the account-level AND the
   repo-level controls separately — disabling only one was not sufficient
4. Push Protection scans the FULL range of commits in a push, not just the diff tip -
   old, previously-unpushed secrets surface the first time they are actually pushed, even
   if the local commit is days old
5. The authorized API bypass (push_protection_bypasses) only applies to ruleset Bypass
   lists; it has no effect on either the account-level or the repo-level toggle - the only
   way past those two is explicit, manual disablement by an account owner / repo admin
