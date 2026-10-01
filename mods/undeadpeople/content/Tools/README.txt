Rebuild and verification (Python 3.10+ and Pillow)

This toolchain reproduces/verifies the historical Hybrid v3 coverage baseline.
The audit source commit remains e262adb299a7613b4aedc5f12c08fe0413c56a84
(CDDA experimental 2026-09-23-0546). Do not silently substitute a newer source
commit and compare percentages as if the object registry were unchanged.

1. Obtain the original v2 archive; SHA256 is in SOURCES.json.
2. Run: python PATH_TO_TOOLS/FETCH_V3_DONORS.py
3. Run: python PATH_TO_TOOLS/BUILD_V3.py PATH_TO_V2 PATH_TO_TOOLS/plan.json NEW_OUTPUT_DIRECTORY
4. Obtain exact CDDA source commit e262adb299a7613b4aedc5f12c08fe0413c56a84.
5. Run: python PATH_TO_TOOLS/VERIFY_V3.py GAME_SOURCE PATH_TO_V2 NEW_OUTPUT_DIRECTORY REPORT_DIRECTORY
6. Run: python PATH_TO_TOOLS/VERIFY_TRANSFER.py PATH_TO_TOOLS/plan.json NEW_OUTPUT_DIRECTORY transfer.json

The plan and aliases are frozen after visual review.
Current package compatibility with newer CDDA targets is handled by repository
CI/installer and is separate from this frozen coverage reproduction.
