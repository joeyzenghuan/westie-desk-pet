param(
    [string]$Runtime = "win-x64",
    [switch]$SelfContained
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Proj = Join-Path $Root "windows\WestieDeskPet.Windows\WestieDeskPet.Windows.csproj"
$Tests = Join-Path $Root "windows\WestieDeskPet.Tests\WestieDeskPet.Tests.csproj"
$OutDir = Join-Path $Root "dist\windows-$Runtime"

Write-Host "==> Running WestieDeskPet.Tests..."
dotnet test $Tests -c Release

$scFlag = if ($SelfContained) { "true" } else { "false" }
Write-Host "==> Publishing WestieDeskPet for Windows ($Runtime, SelfContained=$scFlag)..."
dotnet publish $Proj `
    -c Release `
    -r $Runtime `
    --self-contained $scFlag `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -o $OutDir

Write-Host "==> Packaged Windows app at: $OutDir\WestieDeskPet.exe"
