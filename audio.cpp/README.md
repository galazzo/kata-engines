# Patched audio.cpp builds

Upstream repository and tag are declared in `UPSTREAM`. The release contains
the `audiocpp_server` deployment build plus a pinned Apache-2.0 Sonic DLL for
pitch-preserving TTS speed adjustment.

## Patches

### 0001-openai-offline-speech-speed

audio.cpp v0.9.5 treats an unsupported non-neutral OpenAI `speed` field as a
model style condition. VoxCPM2 does not consume style conditions, so requests
fail before synthesis. The patch:

- treats the speed field as a server postprocessor when the selected model
  contract does not accept `speed` or `speaking_rate`;
- preserves model-native speed handling;
- applies pitch-preserving Sonic tempo processing for offline speech;
- accepts `0.5` through `2.0`;
- keeps `1.0` as an exact no-op;
- reports a clear error for streaming fallback until streaming tempo is wired
  into the OpenAI SSE endpoint.

The output duration must be approximately inversely proportional to speed,
while the sample rate, pitch and output WAV format remain unchanged.

## Local build

Run from a Visual Studio 2022 developer shell:

```powershell
./scripts/build.ps1 -Engine audio.cpp -Variant cuda12 -CudaArchitectures 86
```

The build packages `sonic.dll`, `LICENSE.audio.cpp.txt`, `LICENSE.ggml.txt`,
`LICENSE.sonic.txt` and `dojo-capabilities.json`.
