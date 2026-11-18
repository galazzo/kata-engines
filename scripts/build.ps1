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
    [Parameter(Mandatory)][ValidateSet('sd.cpp')][string]$Engine,
    [Parameter(Mandatory)][ValidateSet('cpu', 'cuda12', 'vulkan')][string]$Variant,
    [string]$CudaArchitectures = '61;70;75;80;86;89;90;100;120',
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
    git clone --depth 1 --branch $upstream.tag --recurse-submodules --shallow-submodules $upstream.repo $src
    if ($LASTEXITCODE) { throw 'clone failed' }
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

$defines = switch ($Variant) {
    'cpu'    { @('-DGGML_NATIVE=OFF') }
    'cuda12' { @('-DSD_CUDA=ON', "-DCMAKE_CUDA_ARCHITECTURES=$CudaArchitectures",
                 '-DCMAKE_CUDA_FLAGS=-Xcudafe --diag_suppress=177 -Xcudafe --diag_suppress=550', '-DGGML_NATIVE=OFF') }
    'vulkan' { @('-DSD_VULKAN=ON', '-DGGML_NATIVE=OFF') }
}
$defines += @('-DSD_BUILD_SHARED_LIBS=ON', '-DSD_BUILD_SHARED_GGML_LIB=ON', '-DGGML_BACKEND_DL=ON', '-DGGML_CPU_ALL_VARIANTS=ON')

$build = Join-Path $src "build-$Variant"
cmake -S $src -B $build -G Ninja -DCMAKE_CXX_FLAGS=/bigobj -DCMAKE_C_COMPILER=cl.exe -DCMAKE_CXX_COMPILER=cl.exe -DCMAKE_BUILD_TYPE=Release @defines
if ($LASTEXITCODE) { throw 'configure failed' }
cmake --build $build
if ($LASTEXITCODE) { throw 'build failed' }

$bin = if (Test-Path (Join-Path $build 'bin\Release')) { Join-Path $build 'bin\Release' } else { Join-Path $build 'bin' }
Copy-Item (Join-Path $src 'LICENSE') (Join-Path $bin 'stable-diffusion.cpp.txt')
Copy-Item (Join-Path $src 'ggml\LICENSE') (Join-Path $bin 'ggml.txt')
Copy-Item (Join-Path $root "$Engine\capabilities.json") (Join-Path $bin 'dojo-capabilities.json')

New-Item -ItemType Directory -Force $DistDir | Out-Null
$asset = Join-Path $DistDir "sd-master-$sha-bin-win-$Variant-x64.zip"
Remove-Item $asset -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $bin '*') -DestinationPath $asset
Write-Host "built $asset (release tag $($upstream.tag)-kata$Revision)"
