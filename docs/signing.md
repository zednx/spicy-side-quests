# Setting up code signing (SignPath Foundation)

The release workflow already contains the signing steps. They switch on once the secret and variables below exist. Until then, releases ship unsigned exactly as before.

## 1. Apply

1. Turn on MFA for your GitHub account (Settings → Password and authentication).
2. Apply at <https://signpath.org> for the open-source program:
   - Project: Spicy Side Quests, <https://github.com/zednx/spicy-side-quests>
   - License: MIT
   - What's signed: one PowerShell script (`SpicySideQuests.ps1`), built and released by GitHub Actions
   - Code signing policy: <https://github.com/zednx/spicy-side-quests/blob/main/CODE_SIGNING_POLICY.md>

## 2. Once approved: set up SignPath

In the SignPath web app:
1. **Trusted build systems:** add the predefined **GitHub.com** system and link it to the project. Install the **SignPath GitHub App** on the repository when asked.
2. **Project:** slug `spicy-side-quests` (or set the repo variable `SIGNPATH_PROJECT_SLUG` to yours).
3. **Artifact configuration:** paste [`.signpath/artifact-configuration.xml`](../.signpath/artifact-configuration.xml) as the default configuration.
4. **Signing policy:** slug `release-signing` (or set `SIGNPATH_POLICY_SLUG`), with yourself as approver.
5. **CI user:** create one with *submitter* permission on that policy, and generate an **API token** for it.

## 3. Connect GitHub

Repo → **Settings → Secrets and variables → Actions**:

| Kind | Name | Value |
|---|---|---|
| Secret | `SIGNPATH_API_TOKEN` | the CI user's API token |
| Variable | `SIGNPATH_ORGANIZATION_ID` | your SignPath organization ID |
| Variable | `SIGNPATH_PROJECT_SLUG` | only if not `spicy-side-quests` |
| Variable | `SIGNPATH_POLICY_SLUG` | only if not `release-signing` |

## 4. Release

1. Bump the version (`scripts/bump-version.sh addon patch`), fill in the CHANGELOG, commit, and push the tag.
2. The release workflow pauses at **Sign with SignPath**. Approve the request in SignPath; it waits up to 24 hours.
3. Check it: on Windows, download the companion zip **without unblocking it**, extract it and run:
   ```powershell
   Get-AuthenticodeSignature .\powershell\SpicySideQuests.ps1
   ```
   `Status` should be `Valid`. Then test with Smart App Control on: right-click `powershell\SpicySideQuests.ps1` → **Run with PowerShell**.
4. Update `CODE_SIGNING_POLICY.md` (remove the "not signed yet" status) and the README's "Blocked by Windows?" section.
