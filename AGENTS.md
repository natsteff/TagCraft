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
