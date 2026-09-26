# Source and attribution inventory

This collection preserves third-party author names in MOD_INFO, metadata and
original notices. It does not apply a new blanket license to third-party mods or
art. Keep existing copyright and license notices when redistributing.

| Component | Source of imported content |
|---|---|
| AXIOM-7 | User's 0.8.2.7 FULL_RUNTIME_AUDIT archive, author Neversalimus |
| Blazemod | OromisElf/blazemod @ 59b79c74bf398221279dfe2a628c974cd0f62a17 + user Revival 0.5.5 transforms |
| Secronom / Secronom+ | Erin105/Secronom-Zombies @ 150a75d1346fbcbf545cb22a4c9d672c0f483e9b + core 1.1, emit 1.5.1, expansion 0.3–0.3.4 recovery layers |
| Tankmod Revived | chaosvolt/cdda-tankmod-revived-mod @ 7456a2e7d4f31dfb25714a2015ea7bebbd6b0dbe + user Fix4 transforms |
| Aftershock Prime | CleverRaven/Cataclysm-DDA @ e262adb299a7613b4aedc5f12c08fe0413c56a84, selected Aftershock Exoplanet content + user's Hotfix14a builder; upstream CC BY-SA notice retained |
| UndeadPeople Hybrid | User's v3 FULL All Patches archive; original tileset/source credits retained inside content |
| Advanced World Settings | Neversalimus/NCMM @ 97b93e7dbc1ea95a46d69ce8e603b25782589cc8, module only |
| Survivor Progression | Neversalimus/NCMM seed c15fbff6dffbded6382a638288f3984228873fa4 + module-only 0.9.10 transformations from CLEAN_v13 |

The initial AWS DLL came from NCMM_Runtime_v0.7.0.zip, SHA256
`eb0eb0d2b381f83b9a382777e191750a8344ff06651286437f116913957c37c3`.
Only the mod DLL/manifest is included, never NCMMSetup, bootstrap or host.
The native source/SDK for the original release were compared with the imported
snapshot; no module diff was present at import.

Secronom was reconstructed because its universal archive was a builder reading
an already-installed working copy, not a complete payload. Validator-guided text
cleanup from that local copy is not assumed recovered. Its status remains pending.
This is deliberately documented rather than represented as an identical copy of
that PC's installation. A later exported working snapshot may replace it after
comparison and validation.

Public release of the collection must preserve each upstream component's license
and graphics credits; no new permission is claimed for assets whose original
license was not supplied in the user's archive.
