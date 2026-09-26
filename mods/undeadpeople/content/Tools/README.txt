Rebuild and verification (Python 3.10+ and Pillow):
1. Obtain the original v2 archive; SHA256 is in SOURCES.json. Extract its tileset.
2. In a fresh working directory run: python PATH_TO_TOOLS/FETCH_V3_DONORS.py
3. python PATH_TO_TOOLS/BUILD_V3.py PATH_TO_V2 PATH_TO_TOOLS/plan.json NEW_OUTPUT_DIRECTORY
4. For coverage verification, obtain CDDA source commit e262adb299a7613b4aedc5f12c08fe0413c56a84 including data/ and src/.
5. python PATH_TO_TOOLS/VERIFY_V3.py GAME_SOURCE PATH_TO_V2 NEW_OUTPUT_DIRECTORY REPORT_DIRECTORY
6. python PATH_TO_TOOLS/VERIFY_TRANSFER.py PATH_TO_TOOLS/plan.json NEW_OUTPUT_DIRECTORY transfer.json
The plan and aliases are frozen after visual review. plan_v3.py documents discovery and expects the original audit workspace. BUILD_V3.py does not require it.
The build script creates playable tileset data; packaging adds reports, credits, previews, and this documentation.
