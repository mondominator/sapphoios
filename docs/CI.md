# CI, versioning and TestFlight

This setup mirrors Sashimi's (`bitstorm-labs/sashimi-apple`): fastlane runs the
build and tests on pull requests, and a `v*` tag builds, signs with match and
uploads to TestFlight.

| Workflow | Trigger | Secrets |
|---|---|---|
| `.github/workflows/ci.yml` | PRs to `main`, pushes to `main` | none |
| `.github/workflows/testflight.yml` | tag `v*`, manual dispatch | the six below, in the `testflight` environment |

## Versioning

- `MARKETING_VERSION` in `project.yml` is the user-visible version. It is bumped
  by hand for each release (1.0.0 shipped as build 45; the next release is 1.0.1).
- `CURRENT_PROJECT_VERSION` is the build number. CI sets it to the Unix epoch
  seconds at upload time, so every upload is unique and increasing. The value
  in `project.yml` only applies to local builds.
- `Info.plist` reads both values (`$(MARKETING_VERSION)`, `$(CURRENT_PROJECT_VERSION)`),
  so `project.yml` is the only place a version is set.
- Export uses `manageAppVersionAndBuildNumber = false`, and the `beta` lane
  reads `CFBundleVersion` back out of the IPA and fails if it differs from the
  build number it set. This prevents the "set 40, shipped 43" mismatch.
- To release, bump `MARKETING_VERSION` in `project.yml`, run `xcodegen generate`,
  merge, then tag:
  ```bash
  git tag v1.0.1 && git push origin v1.0.1
  ```
  The lane refuses a tag that does not match `MARKETING_VERSION`.

## One-time setup (owner only)

The steps below need the repo owner. Nothing here has been done yet.

### 1. Repository secrets

Put these in a `testflight` environment (Settings → Environments → New
environment), not at repository level, so only the tag workflow can read them.
They are the same values Sashimi uses, so copy them from its org secrets.

| Secret | Value |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | `R4AM2C2PTV` |
| `APP_STORE_CONNECT_ISSUER_ID` | `6706366b-6261-4484-8694-c632a5a5c690` |
| `APP_STORE_CONNECT_KEY_CONTENT` | `base64 -i ~/.appstoreconnect/private_keys/AuthKey_R4AM2C2PTV.p8` |
| `MATCH_PASSWORD` | the passphrase of the `bitstorm-labs/certificates` repo (same as Sashimi) |
| `MATCH_GIT_URL` | `https://github.com/bitstorm-labs/certificates.git` |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `printf 'USER:TOKEN' \| base64`, where TOKEN is a fine-grained PAT with **read** access to `bitstorm-labs/certificates` only |

With `gh`:
```bash
R=mondominator/sapphoios
gh api -X PUT repos/$R/environments/testflight
gh secret set APP_STORE_CONNECT_KEY_ID      -R $R --env testflight -b R4AM2C2PTV
gh secret set APP_STORE_CONNECT_ISSUER_ID   -R $R --env testflight -b 6706366b-6261-4484-8694-c632a5a5c690
base64 -i ~/.appstoreconnect/private_keys/AuthKey_R4AM2C2PTV.p8 | gh secret set APP_STORE_CONNECT_KEY_CONTENT -R $R --env testflight
gh secret set MATCH_PASSWORD                -R $R --env testflight          # prompts
gh secret set MATCH_GIT_URL                 -R $R --env testflight -b https://github.com/bitstorm-labs/certificates.git
printf 'mondominator:<PAT>' | base64 | gh secret set MATCH_GIT_BASIC_AUTHORIZATION -R $R --env testflight
```

`sapphoios` is a personal repo. It can stay personal: the PAT gives it access to
the org's certificates repo. If you would rather transfer it to `bitstorm-labs`
to reuse Sashimi's org secrets and runner, do that first and skip the PAT.

### 2. Create the App Store profile once, locally

On CI, match runs read-only. The certificates repo already holds the team's
Apple Distribution certificate (Sashimi uses it), but it has no profile for
`com.sappho.audiobook` yet. Create it once from the Mac:

```bash
cd ~/Documents/git/sapphoios
bundle install
APP_STORE_CONNECT_KEY_ID=R4AM2C2PTV \
APP_STORE_CONNECT_ISSUER_ID=6706366b-6261-4484-8694-c632a5a5c690 \
APP_STORE_CONNECT_KEY_CONTENT="$(base64 -i ~/.appstoreconnect/private_keys/AuthKey_R4AM2C2PTV.p8)" \
MATCH_PASSWORD=... bundle exec fastlane ios certificates
```

The App ID already has the CarPlay Audio and App Group capabilities, because
the app ships with them, so the generated profile includes them. If match
complains about a missing entitlement, enable it on the App ID in the developer
portal and run the command again.

### 3. Runner

Both workflows run on `macos-26` (GitHub-hosted, free for public repos). To use
another image, such as Sashimi's `xcode-27`, set the repository variable
`MACOS_RUNNER`. Set `XCODE_VERSION` to pin an Xcode version; the default is
`latest-stable`.

### 4. Branch protection (recommended)

These settings match the Android repo. None of them have been changed.

- `main`: require a pull request, and require the `CI / Build and test` check
  with "require branches to be up to date".
- Merge settings: squash only, and delete the branch on merge.
- Add a tag ruleset for `v*` so that only you can create or delete release tags.
  A tag push is the ship gate.
- Optionally, add yourself as a required reviewer on the `testflight` environment.

```bash
gh api -X PUT repos/mondominator/sapphoios/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "contexts": ["Build and test"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
JSON
gh api -X PATCH repos/mondominator/sapphoios \
  -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true
```

Before you protect `main`, merge the PR that adds `ci.yml` and confirm the check
has run at least once. Until then the check name is not registered.

## Local equivalents

```bash
bundle exec fastlane ios test     # what CI runs on a PR
bundle exec fastlane ios beta     # the TestFlight upload (needs the env vars above)
```

The manual route (archive, export with `ExportOptions.plist`, then `xcrun altool`)
still works. Copy `ExportOptions.example.plist`, which now sets
`manageAppVersionAndBuildNumber = false`.
