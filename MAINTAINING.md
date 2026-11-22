# Maintaining kata-engines

How the pieces fit: Dojo pins an upstream tag per engine (`apps/dojo/src/kata_dojo/data/engines/pinned.json`).
At install time Dojo looks in this repo for a release named `<that tag>-kata<N>` with the assets of the
machine's platform and variant. If there is none it installs the upstream build. So a missing release is
never an error, but it silently drops the patches.

## Publish a release

The workflows build and publish every variant, so a release is complete without any manual upload:

```powershell
gh workflow run release-sd-cpp.yml -R galazzo/kata-engines -f revision=1            # cuda12 and vulkan
gh workflow run release-audio-cpp.yml -R galazzo/kata-engines -f revision=1         # cuda12 and vulkan
gh workflow run release-llama-cpp.yml -R galazzo/kata-engines -f revision=1         # ROCm gfx1151
gh run watch -R galazzo/kata-engines
gh release list -R galazzo/kata-engines
```

Each workflow creates the release when it does not exist and otherwise adds to it, replacing an asset of the same
name, so a failed variant can be run again alone (`-f variants=vulkan`, or `cuda12`). To test a llama.cpp build
without touching the release, run it with `-f publish=false` and download the workflow artifact. The weekly
`check-upstream` workflow also fails when the release of a pinned tag lacks one of the builds Dojo needs
(job `releases-complete`).

A green workflow does not prove the engine runs: before relying on a release, download the asset and run it on a
machine with the GPU. For audio.cpp run `audiocpp_server.exe --version` and one generation request that uses the
patched capability. For the llama.cpp ROCm build run `llama-server --list-devices` with a PATH that has no HIP SDK
(it must list `ROCm0`) and a short `llama-bench`.

A local build is the fallback, for a quick check or when Actions is not available:

```powershell
./scripts/build.ps1 -Engine audio.cpp -Variant cuda12 `
  -CudaArchitectures 86 -Revision 1 `
  -WorkDir C:\keng-work -DistDir C:\keng-dist
gh release create v0.9.5-kata1 C:\keng-dist\audio-v0.9.5-*.zip `
  -R galazzo/kata-engines --target main
```

Use short Windows paths for audio.cpp because SentencePiece fails while writing
objects when the source/build path is too long.

`revision` is the `N` of `-kataN`. Use `1` for a new upstream tag and increase it when you rebuild the same
tag (changed patch, build fix). Dojo takes the highest `N` of the pinned tag. A release is public, so test the
build (above) before publishing a new revision.

## Dojo moves to a new upstream tag

1. Edit `tag=` in the engine's `UPSTREAM`.
2. Run `./scripts/build.ps1 -Engine <engine> -Variant cuda12 -CudaArchitectures 86` from a Visual Studio developer
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
