# Maintaining kata-engines

How the pieces fit: Dojo pins an upstream tag per engine (`apps/dojo/src/kata_dojo/data/engines/pinned.json`).
At install time Dojo looks in this repo for a release named `<that tag>-kata<N>` with the assets of the
machine's platform and variant. If there is none it installs the upstream build. So a missing release is
never an error, but it silently drops the patches.

## Publish a release

```powershell
gh workflow run release-sd-cpp.yml -R galazzo/kata-engines -f revision=1
gh run watch -R galazzo/kata-engines
gh release list -R galazzo/kata-engines
```

`revision` is the `N` of `-kataN`. Use `1` for a new upstream tag and increase it when you rebuild the same
tag (changed patch, build fix). Dojo takes the highest `N` of the pinned tag. A release is public and
cannot be changed without republishing, so test locally first (below).

## Dojo moves to a new upstream tag

1. Edit `tag=` in `sd.cpp/UPSTREAM`.
2. `./scripts/build.ps1 -Engine sd.cpp -Variant cuda12 -CudaArchitectures 86` from a Visual Studio developer
   shell. A patch that no longer applies stops the build and names the patch.
   - Upstream fixed it: delete the patch and, if nothing else needs it, the key in `capabilities.json`.
     Also update `lora_warnings` in Dojo's Wan pack so it stops expecting `dojo-capabilities.json` from that
     tag on, or the warning would show on a correct upstream build.
   - The code moved: apply the change by hand on the new tag in a checkout of upstream, regenerate the file
     with `git diff`, keep the message block at the top.
3. Run the test of each patch (see `sd.cpp/README.md`).
4. Commit and push, then publish the release with `revision=1`.
5. Only then change the tag in Dojo's `pinned.json` and ship Dojo.

## Add a patch

Make the change in a checkout of the pinned upstream tag, write `NNNN-short-name.patch` with `git diff`
(message block first), add a row to the table in `README.md`, add a capability in `capabilities.json` if Dojo
has to know the build has it, and write the test in `sd.cpp/README.md`. Prefer sending the fix upstream too
(`sd.cpp/UPSTREAM-ISSUE.md` has the text for the first one).

## What runs by itself

`check-upstream.yml` runs every Monday: it takes the newest upstream release and checks that every patch
still applies, or is already in upstream. A red run means the next bump needs work on that patch.
