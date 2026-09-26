Aftershock Prime - Mind Over Matter Compatibility
=================================================

This companion mod is intentionally separate from the main Prime mod.

Why it exists
-------------
The CDDA C++ genemill backend unconditionally adds CANNOT_GAIN_PSIONICS after a gene-editing treatment.
Mind Over Matter uses that same trait ID as Headblind and checks it when deciding whether later psionic
awakening / learning is allowed.

Prime does NOT globally redefine or weaken Headblind. Instead, when this compatibility mod is loaded,
the Mercurial Resequencer has two examine actions:

1. Genetic treatment
2. Restore psionic compatibility

After using a genetic treatment, examine the resequencer again and choose the second action if you want
the character to remain eligible for Mind Over Matter progression.

The explicit second action is deliberate: a player who intentionally chose Headblind is not silently
changed by the compatibility layer.

Dependencies: dda, aftershock_prime, mindovermatter
Target build: cdda_experimental_2026_09_23_0546
