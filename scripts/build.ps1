<#
.SYNOPSIS
  Builds an engine from its pinned upstream tag with the patches of this repo applied.

.EXAMPLE
  ./scripts/build.ps1 -Engine sd.cpp -Variant cuda12
  ./scripts/build.ps1 -Engine sd.cpp -Variant cuda12 -CudaArchitectures 86 -Revision 1   # fast local build

Output: dist/<asset>.zip, named like the upstream asset so Dojo's variant regexes match it.
Run it from a Visual Studio developer shell (cl.exe, Ninja and the CUDA toolkit on PATH).
#>
param(
    [Parameter(Mandatory)][ValidateSet('audio.cpp', 'sd.cpp')][string]$Engine,
    [Parameter(Mandatory)][ValidateSet('cpu', 'cuda12', 'vulkan')][string]$Variant,
    # Default: every architecture the installed nvcc knows (Blackwell 100/120 need CUDA 12.8 or newer).
    [string]$CudaArchitectures = $(
        $ver = if ((Get-Command nvcc -ErrorAction SilentlyContinue) -and ((nvcc --version | Out-String) -match 'release (\d+)\.(\d+)')) {
            [version]"$($Matches[1]).$($Matches[2])"
        } else { [version]'0.0' }
        if ($ver -ge [version]'12.8') { '61;70;75;80;86;89;90;100;120' } else { '61;70;75;80;86;89;90' }
    ),
    [int]$Revision = 1,
    [string]$WorkDir = (Join-Path $PSScriptRoot '..\_work'),
    [string]$DistDir = (Join-Path $PSScriptRoot '..\dist')
)
$ErrorActionPreference = 'Stop'
$root = Resolve-Path (Join-Path $PSScriptRoot '..')

$upstream = @{}
Get-Content (Join-Path $root "$Engine\UPSTREAM") | ForEach-Object {
    if ($_ -match '^\s*(\w+)=(.+)$') { $upstream[$Matches[1]] = $Matches[2].Trim() }
}
$src = Join-Path $WorkDir "$Engine-$($upstream.tag)"
if (-not (Test-Path $src)) {
    # core.longpaths: some submodules (cutlass) have paths over the 260 characters of Windows.
    git -c core.longpaths=true clone --depth 1 --branch $upstream.tag --recurse-submodules --shallow-submodules $upstream.repo $src
    if ($LASTEXITCODE) {
        Remove-Item -Recurse -Force $src -ErrorAction SilentlyContinue
        throw 'clone failed'
    }
    git -C $src config core.longpaths true
}
git -C $src reset --hard --quiet
git -C $src clean -fdx --quiet -e build
$sha = (git -C $src rev-parse --short=7 HEAD).Trim()

# Patches apply in file name order. A patch that no longer applies stops the build: either upstream
# fixed the problem (delete the patch) or the code moved (rebase the patch).
foreach ($patch in Get-ChildItem (Join-Path $root "$Engine\patches\*.patch") | Sort-Object Name) {
    git -C $src apply --check $patch.FullName
    if ($LASTEXITCODE) { throw "$($patch.Name) does not apply to $($upstream.tag): see $Engine/README.md" }
    git -C $src apply $patch.FullName
    Write-Host "applied $($patch.Name)"
}

$defines = if ($Engine -eq 'sd.cpp') {
    switch ($Variant) {
        'cpu'    { @('-DGGML_NATIVE=OFF') }
        'cuda12' { @('-DSD_CUDA=ON', "-DCMAKE_CUDA_ARCHITECTURES=$CudaArchitectures",
                     '-DCMAKE_CUDA_FLAGS=-Xcudafe --diag_suppress=177 -Xcudafe --diag_suppress=550', '-DGGML_NATIVE=OFF') }
        'vulkan' { @('-DSD_VULKAN=ON', '-DGGML_NATIVE=OFF') }
    }
    @('-DSD_BUILD_SHARED_LIBS=ON', '-DSD_BUILD_SHARED_GGML_LIB=ON',
      '-DGGML_BACKEND_DL=ON', '-DGGML_CPU_ALL_VARIANTS=ON')
} else {
    switch ($Variant) {
        'cpu'    { @('-DENGINE_ENABLE_CUDA=OFF', '-DENGINE_ENABLE_VULKAN=OFF') }
        'cuda12' { @('-DENGINE_ENABLE_CUDA=ON', "-DCMAKE_CUDA_ARCHITECTURES=$CudaArchitectures",
                     '-DENGINE_ENABLE_CUDA_GRAPHS=ON', '-DENGINE_ENABLE_VULKAN=OFF') }
        'vulkan' { @('-DENGINE_ENABLE_CUDA=OFF', '-DENGINE_ENABLE_VULKAN=ON') }
    }
    @('-DAUDIOCPP_DEPLOYMENT_BUILD=ON', '-DAUDIOCPP_BUILD_NATIVE_MODEL_MANAGER=OFF',
      '-DAUDIOCPP_MODEL_SET=custom', '-DAUDIOCPP_MODELS=voxcpm2,qwen3_asr',
      "-DAUDIOCPP_VERSION=$($upstream.tag)-kata$Revision")
}

$build = Join-Path $src "build-$Variant"
cmake -S $src -B $build -G Ninja -DCMAKE_CXX_FLAGS=/bigobj -DCMAKE_C_COMPILER=cl.exe -DCMAKE_CXX_COMPILER=cl.exe -DCMAKE_BUILD_TYPE=Release @defines
if ($LASTEXITCODE) { throw 'configure failed' }
$target = if ($Engine -eq 'audio.cpp') { 'audiocpp_server' } else { 'all' }
cmake --build $build --target $target
if ($LASTEXITCODE) { throw 'build failed' }

$bin = if (Test-Path (Join-Path $build 'bin\Release')) { Join-Path $build 'bin\Release' } else { Join-Path $build 'bin' }
if ($Engine -eq 'audio.cpp') {
    $sonic = @{}
    Get-Content (Join-Path $root 'audio.cpp\SONIC') | ForEach-Object {
        if ($_ -match '^\s*(\w+)=(.+)$') { $sonic[$Matches[1]] = $Matches[2].Trim() }
    }
    $sonicSrc = Join-Path $WorkDir "sonic-$($sonic.commit)"
    if (-not (Test-Path $sonicSrc)) {
        git clone $sonic.repo $sonicSrc
        if ($LASTEXITCODE) { throw 'sonic clone failed' }
    }
    git -C $sonicSrc checkout --quiet --detach $sonic.commit
    Push-Location $sonicSrc
    cl /nologo /O2 /LD sonic.c /Fosonic.obj /link "/DEF:$(Join-Path $root 'audio.cpp\sonic.def')" /OUT:sonic.dll
    if ($LASTEXITCODE) { Pop-Location; throw 'sonic build failed' }
    Pop-Location
    Copy-Item (Join-Path $sonicSrc 'sonic.dll') (Join-Path $bin 'sonic.dll')
    Copy-Item (Join-Path $sonicSrc 'LICENSE') (Join-Path $bin 'LICENSE.sonic.txt')
    Copy-Item (Join-Path $src 'LICENSE') (Join-Path $bin 'LICENSE.audio.cpp.txt')
    Copy-Item (Join-Path $src 'external\ggml\LICENSE') (Join-Path $bin 'LICENSE.ggml.txt')
} else {
    Copy-Item (Join-Path $src 'LICENSE') (Join-Path $bin 'stable-diffusion.cpp.txt')
    Copy-Item (Join-Path $src 'ggml\LICENSE') (Join-Path $bin 'ggml.txt')
}
Copy-Item (Join-Path $root "$Engine\capabilities.json") (Join-Path $bin 'dojo-capabilities.json')

New-Item -ItemType Directory -Force $DistDir | Out-Null
$assetVariant = if ($Variant -eq 'cuda12' -and $Engine -eq 'audio.cpp') { 'cuda12.8' } else { $Variant }
$asset = if ($Engine -eq 'audio.cpp') {
    Join-Path $DistDir "audio-$($upstream.tag)-bin-windows-x64-$assetVariant.zip"
} else {
    Join-Path $DistDir "sd-master-$sha-bin-win-$Variant-x64.zip"
}
Remove-Item $asset -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $bin '*') -DestinationPath $asset
Write-Host "built $asset (release tag $($upstream.tag)-kata$Revision)"
