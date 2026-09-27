# Survivor Progression 0.9.14 (v8.5 source)

Build only this module with CMake and an external compatible NCMM SDK. The pinned 0.9.9 SDK can be prepared for compilation using `python tools/prepare_survivor_sdk.py external/ncmm/sdk`. This deterministic header-only recipe implements the two upstream API 1.5 declaration changes; it does not implement host behavior.

The compiled DLL is a development candidate. Installation remains blocked until the external NCMM host has API 1.5, active_mods.v1 and all matching Survivor v8.5 engine hooks and the exact game passes runtime tests. This repository neither builds nor installs the host.
