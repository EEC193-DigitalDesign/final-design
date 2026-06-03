param(
    [string]$Sim = "modelsim",
    [int]$VgaWidth = 64,
    [int]$VgaHeight = 48,
    [int]$DsWidth = 32,
    [int]$DsHeight = 24,
    [switch]$FullSize,
    [switch]$Waves,
    [switch]$Gui,
    [switch]$Clean,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SimDir = Split-Path -Parent $ScriptDir
Set-Location $SimDir

if ($FullSize) {
    $VgaWidth = 640
    $VgaHeight = 480
    $DsWidth = 320
    $DsHeight = 240
}

$Python = Join-Path $SimDir ".venv\Scripts\python.exe"
if (!(Test-Path $Python)) {
    throw "Missing $Python. Run .\scripts\setup_env.ps1 first."
}

$argsList = @(
    (Join-Path $ScriptDir "run_signed_heatmap_runner.py"),
    "--sim", $Sim,
    "--vga-width", $VgaWidth,
    "--vga-height", $VgaHeight,
    "--ds-width", $DsWidth,
    "--ds-height", $DsHeight
)
if ($Waves) { $argsList += "--waves" }
if ($Gui) { $argsList += "--gui" }
if ($Clean) { $argsList += "--clean" }
if ($Verbose) { $argsList += "--verbose" }

& $Python @argsList
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
