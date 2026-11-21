# Publishing Stack Attack

In GitHub Actions, choose **Publish Stack Attack → Run workflow**, select branch
`main` and enter a stable SemVer such as `1.2.3`. The owner can dispatch by
default. To delegate releases, grant the maintainer repository write access and
add their exact GitHub login to the optional repository variable
`RELEASE_MAINTAINERS`, a JSON array such as `["maintainer-login"]`. The original
actor and the person rerunning a job must both be authorized.

Android and Web use the full main commit captured at dispatch. The published
`v1.2.3` tag points to that commit. The release includes a signed ARM64 APK,
a complete Web ZIP, SHA256SUMS.txt, source SHA, Android versionCode and signing
certificate SHA-256. Extract the whole ZIP, run `python3 -m http.server 8765`
in the extracted directory and open http://127.0.0.1:8765/ in a WebGL 2 browser.
The live demo linked in the release is deployed independently.

## Configure signing

In **IlyasYOY/stack-attack → Settings → Environments → android-release**, select
deployment branches and tags and add **one branch rule for main**, with no tag
rule. Restrict changes to main and to the release workflow and scripts. Configure
required reviewers for the environment if an additional approval is desired.
Restrict tag changes and deletion (`v*`) to trusted release administrators and
allow the publication job to create its release tag.

| Environment setting | Name | Expected value |
| --- | --- | --- |
| Secret | `APK_SIGNING_KEYSTORE_BASE64` | Standard RFC 4648 Base64 of the original binary PKCS#12 file, one line |
| Secret | `APK_SIGNING_STORE_PASSWORD` | Shared password for the PKCS#12 store and its private key |
| Variable | `APK_SIGNING_KEY_ALIAS` | `voice-dictation`, the owner's selected signing alias |
| Variable | `APK_SIGNING_CERT_SHA256` | SHA-256 of the DER signing certificate, 64 lowercase hex digits without separators |

Use the public certificate of the intended distribution key to set the fingerprint.
The build runs without signing secrets. The signing job has read-only repository
access and exposes the two secrets only to the signing step. The publisher uses the
built-in GitHub token with `contents: write` and receives the expected public
fingerprint for an independent signature check. PR checks generate a disposable
keystore and run with `contents: read`.

## Updates and retries

Release installs use `org.ilyasyoy.stackattack`. Technical builds retain
`org.ilyasyoy.stackattack.techtest`; both can be installed side by side and keep
separate saves. Updating a release requires the same package and compatible
signing certificate. Sharing the Voice Dictation certificate leaves the two apps
with distinct package identities.

For a stable version M.m.p, Android versionCode is
`1 + M × 1,000,000 + m × 1,000 + p`. The supported ranges are 0–2099 for M and
0–999 for m and p, giving codes 1–2,100,000,000. Choose a version above all
existing stable version tags and releases. Preserve release tags and releases,
including the highest allocated version. Distribute this Android ID through this
workflow to keep that ordering.

Release runs are serialized. A superseded pending dispatch can be dispatched
again. Repeating a published version and SHA checks the tag and asset checksums
and exits. A tag for another SHA, an unrelated tag or draft, or a version below a
higher reservation stops the run. The publisher stages three assets on a draft,
compares their GitHub digests, and binds the tag before making it public.

If publication is interrupted, use **Re-run failed jobs** on the original run
while its artifacts are retained (seven days). The job reuses matching draft assets
and fills in missing ones. A different build, unexpected asset or failed upload
with a mismatching asset stops for inspection. An administrator can inspect the
unpublished draft and remove a failed partial upload before retrying. For expired
artifacts or conflicting state, inspect the old draft/tag and choose a fresh higher
version. A retry never replaces published files or moves an existing tag.
