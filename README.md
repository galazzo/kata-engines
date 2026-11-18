# kata-engines

Patched builds of the native engines that Kata Dojo runs (stable-diffusion.cpp and llama.cpp).
Each engine is pinned to an upstream tag, carries its patches in `patches/`, and is published as a
GitHub release named `<upstream tag>-kata<N>`. Dojo installs a patched build when one exists for the
machine's platform and variant, and falls back to the upstream release otherwise.
