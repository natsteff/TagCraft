# TagCraft project instructions

## GitHub publication gate
Before any GitHub publication (initial upload, push of updates, or publishing a release), explicitly ask Nate: “Should I review and update the README before publishing to GitHub?”
Wait for his answer before proceeding with publication. Do not infer consent from a request to publish, a previous review, or elapsed time. Do not automatically review or edit the README as part of publication. If he declines, continue the otherwise-authorized publication without that review. If he agrees, review it against the current app and update it before proceeding.

## Documentation accuracy
Describe current behavior, distinguish proposed work, and retain material unresolved safety limitations. Do not present passing regression checks as proof that writes to original libraries are safe.

## Version release gate
Before packaging or delivering any app build, run `python3 Checks/release-check.py`; after packaging run it again with the app bundle path. Splash, top-right toolbar label and About must use AppRelease shared bundle metadata. Increment the build number for a new app build, and keep current README release metadata accurate. Screenshot captions retain their actual capture build.
