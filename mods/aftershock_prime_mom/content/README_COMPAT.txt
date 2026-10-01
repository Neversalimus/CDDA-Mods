Aftershock Prime - Mind Over Matter Compatibility
=================================================

This companion mod remains separate from the main Prime mod.

Why it exists
-------------
The CDDA genemill backend can add CANNOT_GAIN_PSIONICS after gene-editing treatment.
Mind Over Matter uses the same trait ID when deciding later psionic eligibility.

Prime does not globally redefine or weaken Headblind. When this compatibility mod
is loaded, the Mercurial Resequencer exposes an explicit recovery action so a
player who wants MoM progression can restore psionic compatibility deliberately.

The explicit action is intentional: a character who deliberately chose Headblind
is not silently changed.

Dependencies:
- dda
- aftershock_prime
- mindovermatter

Supported repository targets:
- cdda_experimental_2026_09_23_0546
- cdda_experimental_2026_10_01_1040

Runtime authority for interaction-bearing dependency graphs is exact-source
cata_test when the target game's native --check-mods capability probe reports the
known mod_interactions bug.
