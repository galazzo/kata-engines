# sd.cpp patches

## 0001 high noise LoRAs on quantized models

Problem: with quantized weights (GGUF) sd.cpp applies LoRAs at runtime. `apply_loras_at_runtime` only
keeps tensors named `model.diffusion_model.*`, but a LoRA loaded as `<lora:|high_noise|NAME:W>` has its
tensors renamed to `lora.model.high_noise_diffusion_model.*`, so it ends up empty and is dropped without an
error. The LOW expert works, the HIGH expert never gets its LoRA.

Test (Wan2.2 T2V A14B Q5_0, 256x256, 5 frames, 2+2 steps, fixed seed): render with and without
`<lora:|high_noise|NAME:1>` and compare the frames (`ffmpeg -i a.webm -i b.webm -lavfi psnr -f null -`).
Before the patch the PSNR is `inf` (identical), after it is finite.
