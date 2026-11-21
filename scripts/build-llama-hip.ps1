<#
.SYNOPSIS
  Builds llama.cpp from its pinned upstream tag for one AMD GPU architecture (ROCm/HIP) and packs it with the
  ROCm runtime, so the machine needs no HIP SDK.

.EXAMPLE
  ./scripts/build-llama-hip.ps1 -GpuTarget gfx1151 -Revision 1

Output: dist/llama-<tag>-bin-win-rocm-<gpu target>-x64.zip, the asset Dojo's `rocm-<gpu target>` variant matches.
Needs: Visual Studio build tools, Ninja, uv, and the AMD HIP SDK for Windows (HIP_PATH) as the compiler.
The runtime inside the zip comes from the AMD ROCm wheels of the same architecture (`rocm-sdk-core` and
`rocm-sdk-libraries-<gpu target>`), not from the SDK, so the redistributed files are the open source ones.
#>
param(
    [string]$GpuTarget = 'gfx1151',
    [string]$HipSdk = $env:HIP_PATH,
    # The ROCm wheels the runtime is taken from (Dojo's gfx1151 packs run on the same ones).
    [string]$RocmVersion = '7.14.0a20260612',
    [int]$Revision = 1,
    [string]$WorkDir = (Join-Path $PSScriptRoot '..\_work'),
    [string]$DistDir = (Join-Path $PSScriptRoot '..\dist')
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')
if (-not $HipSdk -or -not (Test-Path (Join-Path $HipSdk 'bin\clang++.exe'))) {
    throw 'HIP SDK not found: install it or pass -HipSdk (the folder that holds bin\clang++.exe)'
}

$upstream = @{}
Get-Content (Join-Path $root 'llama.cpp\UPSTREAM') | ForEach-Object {
    if ($_ -match '^\s*(\w+)=(.+)$') { $upstream[$Matches[1]] = $Matches[2].Trim() }
}
$src = Join-Path $WorkDir "llama.cpp-$($upstream.tag)"
if (-not (Test-Path $src)) {
    git clone --depth 1 --branch $upstream.tag $upstream.repo $src
    if ($LASTEXITCODE) { Remove-Item -Recurse -Force $src -ErrorAction SilentlyContinue; throw 'clone failed' }
}
git -C $src reset --hard --quiet
git -C $src clean -fdx --quiet -e build-hip

foreach ($patch in Get-ChildItem (Join-Path $root 'llama.cpp\patches\*.patch') -ErrorAction SilentlyContinue | Sort-Object Name) {
    git -C $src apply --check $patch.FullName
    if ($LASTEXITCODE) { throw "$($patch.Name) does not apply to $($upstream.tag)" }
    git -C $src apply $patch.FullName
    Write-Host "applied $($patch.Name)"
}

# The HIP SDK only provides the compiler; the VS environment provides the Windows headers and libraries.
if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw 'run this from a Visual Studio developer shell' }
$env:HIP_PATH = $HipSdk
$env:HIP_PLATFORM = 'amd'
$env:PATH = "$(Join-Path $HipSdk 'bin');$env:PATH"

$build = Join-Path $src 'build-hip'
cmake -S $src -B $build -G Ninja `
    "-DCMAKE_C_COMPILER=$(Join-Path $HipSdk 'bin\clang.exe')" "-DCMAKE_CXX_COMPILER=$(Join-Path $HipSdk 'bin\clang++.exe')" `
    -DCMAKE_BUILD_TYPE=Release "-DGPU_TARGETS=$GpuTarget" -DBUILD_SHARED_LIBS=ON -DLLAMA_BUILD_TESTS=OFF `
    -DGGML_HIP=ON -DGGML_HIP_ROCWMMA_FATTN=OFF -DGGML_CUDA_FORCE_CUBLAS=OFF -DGGML_RPC=ON -DGGML_OPENMP=OFF `
    -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON
if ($LASTEXITCODE) { throw 'configure failed' }
cmake --build $build --target llama-server llama-bench llama-cli
if ($LASTEXITCODE) { throw 'build failed' }

# Runtime: the ROCm wheels of this architecture, installed in a throwaway environment.
$rocmEnv = Join-Path $WorkDir "rocm-$GpuTarget-$RocmVersion"
if (-not (Test-Path $rocmEnv)) {
    uv venv $rocmEnv
    uv pip install --python (Join-Path $rocmEnv 'Scripts\python.exe') --index-url "https://rocm.nightlies.amd.com/v2/$GpuTarget/" `
        "rocm-sdk-core==$RocmVersion" "rocm-sdk-libraries-$GpuTarget==$RocmVersion"
    if ($LASTEXITCODE) { throw 'ROCm wheels install failed' }
}
$sp = Join-Path $rocmEnv 'Lib\site-packages'
$core = Join-Path $sp '_rocm_sdk_core'
$libs = Join-Path $sp "_rocm_sdk_libraries_$GpuTarget"

$stage = Join-Path $WorkDir "stage-llama-$GpuTarget"
Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $build 'bin\*') $stage -Recurse
foreach ($dll in 'amd_comgr.dll', 'amdhip64_7.dll', 'rocm_kpack.dll', 'hiprtc*.dll') {
    Copy-Item (Join-Path $core "bin\$dll") $stage
}
foreach ($dll in 'hipblas.dll', 'rocblas.dll', 'rocsolver.dll', 'libhipblaslt.dll') { Copy-Item (Join-Path $libs "bin\$dll") $stage }
foreach ($dir in 'rocblas', 'hipblaslt') { Copy-Item (Join-Path $libs "bin\$dir") (Join-Path $stage $dir) -Recurse }
# Visual C++ runtime next to the binaries: a machine without the redistributable still starts the engine.
$crt = Get-ChildItem (Join-Path $env:VCToolsRedistDir 'x64\Microsoft.VC*.CRT') -Directory | Select-Object -First 1
Copy-Item (Join-Path $crt.FullName '*.dll') $stage
$licenses = Join-Path $stage 'licenses'
New-Item -ItemType Directory -Force $licenses | Out-Null
Copy-Item (Join-Path $src 'LICENSE') (Join-Path $licenses 'llama.cpp.txt')
foreach ($pair in @(@($core, 'rocm-core'), @($libs, 'rocm-libraries'))) {
    $doc = Join-Path $pair[0] 'share\doc'
    if (Test-Path $doc) { Copy-Item $doc (Join-Path $licenses $pair[1]) -Recurse }
}
@"
llama.cpp $($upstream.tag) for AMD $GpuTarget (ROCm/HIP), built by kata-engines.
The ROCm runtime ($RocmVersion) is included: no HIP SDK is needed. Other GPU architectures are not supported by this build.
"@ | Set-Content (Join-Path $stage 'README.txt')

New-Item -ItemType Directory -Force $DistDir | Out-Null
$asset = Join-Path $DistDir "llama-$($upstream.tag)-bin-win-rocm-$GpuTarget-x64.zip"
Remove-Item $asset -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $asset
Write-Host "built $asset (release tag $($upstream.tag)-kata$Revision)"
