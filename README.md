# kata-engines

Patched builds of the native engines Dojo runs (sd.cpp, llama.cpp). Dojo installs a build from here when
this repo has one for the pinned upstream tag and the machine's platform and variant, and falls back to
the upstream release otherwise. So only what has a patch needs to be built and published.

```text
sd.cpp/
  UPSTREAM            upstream repo and the tag the patches are written against
  capabilities.json   what the build can do, shipped inside the zip as dojo-capabilities.json
  patches/            one patch per problem, applied in file name order
llama.cpp/            same layout, no patches yet (Dojo uses upstream)
scripts/build.ps1     clone the tag, apply the patches, build, zip
.github/workflows/    publishes a release `<upstream tag>-kata<N>`
```

How to publish a release, move to a new upstream tag and add a patch: see [MAINTAINING.md](MAINTAINING.md).

## Patches

| Engine | Patch | What it fixes | Upstream |
| --- | --- | --- | --- |
| sd.cpp | `0001-fix-lora-apply-high-noise-loras-at-runtime` | A `<lora:\|high_noise\|NAME>` LoRA is silently ignored on quantized (GGUF) Wan2.2 models: the clip is identical with and without it | to open, see `sd.cpp/UPSTREAM-ISSUE.md` |

## Build locally

From a Visual Studio developer shell (cl.exe, Ninja, CUDA toolkit on PATH). CUDA 12.x does not accept
Visual Studio 2026 as host compiler: use the 2019 or 2022 tools.

```powershell
./scripts/build.ps1 -Engine sd.cpp -Variant cuda12 -CudaArchitectures 86   # fast, your GPU only
```

## Move to a new upstream version

1. Change `tag=` in `sd.cpp/UPSTREAM`.
2. Run `scripts/build.ps1`. A patch that no longer applies stops the build and names the patch.
3. If upstream fixed the problem, delete the patch (and the capability if nothing else needs it). If the code
   moved, rebase the patch: apply it by hand on the new tag, fix, and regenerate it with `git diff`.
4. Check the patch still works (see the test in the patch's section of `sd.cpp/README.md`).
5. Run the `release-sd-cpp` workflow with the next `kata<N>` number. Dojo picks the release up by its tag.

## Add a patch

Make the change in a checkout of the upstream tag, write `NNNN-short-name.patch` with `git diff`
(keep the commit-style message at the top), add a row to the table above and, if Dojo has to know the
build has it, a key in `capabilities.json`.

## License

- The patches, scripts and workflows in this repo are MIT, see [LICENSE](LICENSE).
- The engines themselves are not part of this repo's license. Each one is under its upstream license,
  copied in [licenses/](licenses/): stable-diffusion.cpp (MIT, leejet), llama.cpp (MIT, ggml authors),
  and ggml (MIT, ggml authors, shipped inside the stable-diffusion.cpp build).
- The release zips include the upstream license texts (`stable-diffusion.cpp.txt`, `ggml.txt`).
