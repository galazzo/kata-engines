# kata-engines

Patched builds of the native engines Dojo runs (audio.cpp, sd.cpp, llama.cpp).
Dojo installs a build from here when this repo has one for the pinned upstream
tag and the machine's platform and variant, and falls back to the upstream
release otherwise. So only what has a patch needs to be built and published.

```text
audio.cpp/           audio inference runtime with TTS speed patch
sd.cpp/
  UPSTREAM            upstream repo and the tag the patches are written against
  capabilities.json   what the build can do, shipped inside the zip as dojo-capabilities.json
  patches/            one patch per problem, applied in file name order
llama.cpp/            no patches; builds the AMD ROCm variant that upstream does not publish
scripts/build.ps1     clone the tag, apply the patches, build, zip (sd.cpp, audio.cpp)
scripts/build-llama-hip.ps1   llama.cpp for one AMD architecture (ROCm), with its runtime
.github/workflows/    publishes a release `<upstream tag>-kata<N>`
```

How to publish a release, move to a new upstream tag and add a patch: see [MAINTAINING.md](MAINTAINING.md).

## Patches

| Engine | Patch | What it fixes | Upstream |
| --- | --- | --- | --- |
| audio.cpp | `0001-openai-offline-speech-speed` | Adds pitch-preserving `speed` 0.5-2.0 to offline `/v1/audio/speech` for models without a native speed option | to open after CI validation |
| sd.cpp | `0001-fix-lora-apply-high-noise-loras-at-runtime` | A `<lora:\|high_noise\|NAME>` LoRA is silently ignored on quantized (GGUF) Wan2.2 models: the clip is identical with and without it | to open, see `sd.cpp/UPSTREAM-ISSUE.md` |

## Build locally

From a Visual Studio developer shell (cl.exe, Ninja, CUDA toolkit on PATH). CUDA 12.x does not accept
Visual Studio 2026 as host compiler: use the 2019 or 2022 tools.

The released CUDA build uses CUDA 12.8 (architectures 61 to 120, Blackwell included), and the cudart zip carries
the 12.8 DLLs: it needs an NVIDIA driver 570 or newer. With an older toolkit `build.ps1` drops the architectures
the toolkit does not know (12.6 stops at 90), so only build the release with 12.8.

```powershell
./scripts/build.ps1 -Engine audio.cpp -Variant cuda12 -CudaArchitectures 86
./scripts/build.ps1 -Engine sd.cpp -Variant cuda12 -CudaArchitectures 86   # fast, your GPU only
```

The Windows Vulkan builds of sd.cpp and audio.cpp (AMD and Intel GPUs) need no architecture: build them from a
Visual Studio developer shell with the Vulkan SDK installed.

```powershell
./scripts/build.ps1 -Engine sd.cpp -Variant vulkan
./scripts/build.ps1 -Engine audio.cpp -Variant vulkan
```

### llama.cpp for AMD (ROCm)

Upstream publishes a ROCm zip without the ROCm runtime, which needs an installed HIP SDK and is slower than a
build made for one architecture. `build-llama-hip.ps1` builds the pinned tag for a single architecture and packs
it with the ROCm runtime, so the user installs nothing. The compiler, the HIP headers and the runtime all come
from the AMD ROCm wheels (`rocm[libraries,devel]` plus `rocm-sdk-device-<gpu target>`, the recipe of upstream's own
Windows ROCm release), so no HIP SDK installer is needed:

```powershell
./scripts/build-llama-hip.ps1 -GpuTarget gfx1151   # AMD Strix Halo (Ryzen AI MAX)
```

It needs the Visual Studio 2022 build tools: the ROCm 10 clang does not compile against the Visual Studio 2026
headers, so on a machine that only has 2026 use the `release-llama-cpp` workflow, which runs on `windows-2022`.

The asset is `llama-<tag>-bin-win-rocm-gfx1151-x64.zip`, matched by Dojo's `rocm-gfx1151` variant. On an
AMD Ryzen AI MAX+ 395 with Qwen3.8-27B Q4_K_XL it processes the prompt at about 330 tokens/s, against 262 for the
upstream ROCm zip and 218 for the upstream Vulkan one (generation is memory bound, about 11 tokens/s on all).

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
- The release zips include the upstream license texts (`stable-diffusion.cpp.txt`, `ggml.txt`). The llama.cpp
  ROCm zip also carries the ROCm runtime (AMD ROCm wheels, with their license texts under `licenses/`).
