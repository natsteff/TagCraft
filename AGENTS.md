# TagCraft project instructions

## GitHub publication gate
Before any GitHub publication (initial upload, push of updates, or publishing a release), explicitly ask Nate: “Should I review and update the README before publishing to GitHub?”
Wait for his answer before proceeding with publication. Do not infer consent from a request to publish, a previous review, or elapsed time. Do not automatically review or edit the README as part of publication. If he declines, continue the otherwise-authorized publication without that review. If he agrees, review it against the current app and update it before proceeding.

## Documentation accuracy
Describe current behavior, distinguish proposed work, and retain material unresolved safety limitations. Do not present passing regression checks as proof that writes to original libraries are safe.

## Version release gate
Before packaging or delivering any app build, run `python3 Checks/release-check.py`; after packaging run it again with the app bundle path. Splash, top-right toolbar label and About must use AppRelease shared bundle metadata. Build numbers are per release version: start at Build 1 when the version changes, then increment for subsequent builds of that version. Keep current README release metadata accurate. Screenshot captions retain their actual capture build.

## Screenshot publication question and recommendation
Before each GitHub publication, also ask whether Nate wants the README screenshots refreshed. Bundle this with the README-review question where practical, but allow separate answers. Screenshot refresh is opt-in; wait for the answer and do not automatically refresh images.

Include a concrete recommendation with the question: give the last capture date and app version/build, summarize visible changes since that capture, identify affected screenshots, and recommend refresh or reuse with a short reason. Consult `docs/SCREENSHOTS.md`, source history and current UI; age alone is not a reason to refresh. If the baseline or changes are uncertain, say so rather than inventing them. After capturing screenshots, update that record and preserve accurate capture-version captions.

## Update-check release metadata
The manual update checker reads published GitHub release tags for versions and `Build N` from the release title/notes for per-version builds. Always put the current build number near the start of release notes, use a supported alpha/beta/rc or stable version tag, and name install assets with `macOS-arm64`, `macOS-x86_64`, or `macOS-universal` followed by `.dmg`. Keep the initial current-release build declaration unambiguous.

## Version selection before publication
Automatically select the next release version based on changes since the last published app release; do not use time of day or number of local builds as the criterion. Local iterations increment the current build only. At the next app publication, patch bumps cover fixes/refinements and minor bumps cover new user-facing features; reset the per-version build to 1. Explain the selected version and reason in the publication update without asking a separate version-number approval. Documentation-only pushes do not bump the app version. Keep Alpha until readiness warrants a separately agreed Beta/stable transition; never infer 1.0 readiness. The pending manual Check for Updates feature warrants 0.7.0 Alpha (Build 1) for the next app release. Publication still requires the applicable README/screenshot questions; selecting a version does not authorize publishing.

## Local build artifacts
The repository is `/Users/nate/Documents/Codex/TagCraft`. Put packaged applications, release downloads/checksums, and TagCraft review artifacts in this repository's ignored `outputs/` directory. Do not use the former dated chat outputs location. The build script targets `outputs/TagCraft Music Librarian.app`. App and release DMG versions can differ: inspect metadata rather than assuming an older published DMG contains the latest local app.

## License & Usage Notice
Keep LICENSE complete and unmodified, AGPL-3.0 version 3 only. Preserve third-party notices. Generate USAGE-NOTICE.md and compiled text from Legal sources using scripts/generate-terms.py. Continue records local acknowledgment for notice identity and app version/build; never reuse old EULA acceptance or acknowledge on a user's behalf. Quit dismisses before termination without acknowledgment. Bundle license, notice and sources offline. The notice must add no restrictions or monetary liability cap. See Legal/MAINTENANCE.md.

## Change queue
Record requested changes in docs/CHANGE-QUEUE.md and keep accumulating them until Nate explicitly says to make changes. Inspection and clarification may proceed; do not implement queued items early. Mark completed items after implementation.
