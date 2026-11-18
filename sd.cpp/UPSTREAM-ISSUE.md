# Issue to open on leejet/stable-diffusion.cpp

Title: Wan2.2 A14B: `|high_noise|` LoRAs are ignored when the weights are quantized (runtime LoRA)

Body:

```text
Version: master-1106-532d2c1 (also master-929-3f8527a). Windows, CUDA 12 build, RTX 3090.

Problem
With a Wan2.2 A14B model in a quantized format (GGUF Q5_0 here), a LoRA given for the high noise
expert with the documented tag `<lora:|high_noise|NAME:W>` has no effect. The log shows
"apply lora at runtime" and "high noise lora: ...", no error or warning, but the video is
bit-identical to the one rendered without the LoRA (ffmpeg PSNR = inf), even at weight 2.
The same LoRA given for the low noise expert (`<lora:NAME:W>`) changes the video as expected.

Repro
sd-cli -M vid_gen --diffusion-model Wan2.2-T2V-A14B-LowNoise-Q5_0.gguf \
  --high-noise-diffusion-model Wan2.2-T2V-A14B-HighNoise-Q5_0.gguf \
  --t5xxl umt5-xxl-encoder-Q8_0.gguf --vae wan_2.1_vae.safetensors \
  --lora-model-dir <dir> -p "a fox in a forest <lora:|high_noise|SOME_LORA:1>" \
  --steps 2 --high-noise-steps 2 --cfg-scale 3.5 --high-noise-cfg-scale 3.5 --flow-shift 3 \
  -W 256 -H 256 --video-frames 5 -s 1 --offload-to-cpu -o a.webm
Render again without the tag (b.webm): a.webm and b.webm have identical frames.
`--lora-apply-mode immediately` does not help on a quantized model (0 / N LoRA tensors applied),
and on a non quantized (fp8) model `immediately` does apply the high noise LoRA (1200 / 1200).

Cause
apply_loras_at_runtime() (src/pipeline/diffusion_engine.cpp) filters the LoRA tensors with
is_diffusion_model_name(), which only accepts `model.diffusion_model.` and
`lora.model.diffusion_model.`. A high noise LoRA is registered with the prefix
`lora.model.high_noise_` (ModelManager::prepare_lora_sources), so its tensors are named
`lora.model.high_noise_diffusion_model.*`, the filter drops all of them, the LoRA is empty and is
skipped silently.

Proposed fix
Also accept `model.high_noise_diffusion_model.` / `lora.model.high_noise_diffusion_model.` in that
filter (new helper is_high_noise_diffusion_model_name() in name_conversion.cpp). The adapter built
there is already set on both experts, which is fine because each runner looks its weights up by
its own prefix. Patch attached (sd.cpp/patches/0001-...patch in the Kata engines repo); with it the
same repro gives different frames, and a Lightning high noise LoRA works as on fp8.

It would also be worth logging a warning when a LoRA ends up with no matching tensors, so this kind
of mistake does not pass unnoticed.
```
