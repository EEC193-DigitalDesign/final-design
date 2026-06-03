param(
    [int]$VgaWidth = 64,
    [int]$VgaHeight = 48,
    [int]$DsWidth = 32,
    [int]$DsHeight = 24,
    [int]$ScoreW = 32,
    [int]$ScoreShift = 10,
    [int]$AutocontrastEn = 1,
    [int]$BoxSizeDs = 32,
    [int]$BoxThick = 2,
    [int]$FailOnMismatch = 1,
    [double]$FailMismatchRatio = 0.03,
    [string]$ModelsimBin = "C:\intelFPGA\20.1\modelsim_ase\win32aloem"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SimDir = Split-Path -Parent $ScriptDir
$RepoRoot = Split-Path -Parent $SimDir
$RtlDir = Join-Path $RepoRoot "rtl\object_detection"
$TestsDir = Join-Path $SimDir "tests"
$BuildDir = Join-Path $SimDir "build\heatmap_signed"
$LogDir = Join-Path $SimDir "logs"
$VenvDir = Join-Path $SimDir ".venv"
$SitePackages = Join-Path $VenvDir "Lib\site-packages"
$CocotbLib = Join-Path $SitePackages "cocotb\libs\cocotbvpi_modelsim.dll"
$VenvCfg = Join-Path $VenvDir "pyvenv.cfg"
$OutputDir = Join-Path $SimDir "output\heatmap_signed"
$WorkLib = Join-Path $BuildDir "work"
$Transcript = Join-Path $LogDir "transcript_heatmap_signed.log"
$ResultsXml = Join-Path $LogDir "results_heatmap_signed.xml"
$ExceptionText = Join-Path $OutputDir "test_exception.txt"

$Vlib = Join-Path $ModelsimBin "vlib.exe"
$Vmap = Join-Path $ModelsimBin "vmap.exe"
$Vlog = Join-Path $ModelsimBin "vlog.exe"
$Vsim = Join-Path $ModelsimBin "vsim.exe"

foreach ($Path in @($Vlib, $Vmap, $Vlog, $Vsim, $CocotbLib)) {
    if (!(Test-Path -LiteralPath $Path)) {
        throw "Missing required file: $Path"
    }
}
if (!(Test-Path -LiteralPath $VenvCfg)) {
    throw "Missing venv config: $VenvCfg. Run .\scripts\setup_env.ps1 first, or rebuild sim\.venv."
}

$PythonHomeLine = Get-Content -Path $VenvCfg | Where-Object { $_ -match "^home\s*=" } | Select-Object -First 1
$PythonHome = ($PythonHomeLine -replace "^home\s*=\s*", "").Trim()
if (!(Test-Path -LiteralPath $PythonHome)) {
    throw "Could not find Python home from venv config: $PythonHome"
}

New-Item -ItemType Directory -Force -Path $OutputDir, $BuildDir, $LogDir | Out-Null

$env:MODULE = "test_vga_signed_heatmap_autocontrast"
$env:TOPLEVEL = "vga_debug_mux"
$env:TOPLEVEL_LANG = "verilog"
$env:VGA_WIDTH = "$VgaWidth"
$env:VGA_HEIGHT = "$VgaHeight"
$env:DS_WIDTH = "$DsWidth"
$env:DS_HEIGHT = "$DsHeight"
$env:SCORE_W = "$ScoreW"
$env:SCORE_SHIFT = "$ScoreShift"
$env:AUTOCONTRAST_EN = "$AutocontrastEn"
$env:FAIL_ON_MISMATCH = "$FailOnMismatch"
$env:FAIL_MISMATCH_RATIO = "$FailMismatchRatio"
$env:PROJECT_ROOT = "$RepoRoot"
$env:OUTPUT_DIR = "$OutputDir"
$env:COCOTB_RESULTS_FILE = "$ResultsXml"
$env:COCOTB_ANSI_OUTPUT = "0"
$env:PYTHONPATH = "$TestsDir;$SimDir;$SitePackages;$env:PYTHONPATH"
$env:PYTHONHOME = "$PythonHome"
$env:PATH = "$PythonHome;$(Join-Path $PythonHome 'DLLs');$(Join-Path $VenvDir 'Scripts');$ModelsimBin;$env:PATH"

Push-Location $SimDir
try {
    if (Test-Path -LiteralPath $WorkLib) { Remove-Item -LiteralPath $WorkLib -Recurse -Force }
    if (Test-Path -LiteralPath $Transcript) { Remove-Item -LiteralPath $Transcript -Force }
    if (Test-Path -LiteralPath $ResultsXml) { Remove-Item -LiteralPath $ResultsXml -Force }
    if (Test-Path -LiteralPath $ExceptionText) { Remove-Item -LiteralPath $ExceptionText -Force }

    & $Vlib $WorkLib
    if ($LASTEXITCODE -ne 0) { throw "vlib failed with exit code $LASTEXITCODE" }
    & $Vmap work $WorkLib
    if ($LASTEXITCODE -ne 0) { throw "vmap failed with exit code $LASTEXITCODE" }

    $Sources = @(
        (Join-Path $RtlDir "vga_debug_mux.v")
    )

    & $Vlog @Sources
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit code $LASTEXITCODE" }

    $VsimArgs = @(
        "-c",
        "-l", $Transcript,
        "-pli", $CocotbLib,
        "-gSCORE_W=$ScoreW",
        "-gBOX_SIZE_DS=$BoxSizeDs",
        "-gBOX_THICK=$BoxThick",
        "-gDS_WIDTH=$DsWidth",
        "-gDS_HEIGHT=$DsHeight",
        "-gVGA_WIDTH=$VgaWidth",
        "-gVGA_HEIGHT=$VgaHeight",
        "-gSCORE_SHIFT=$ScoreShift",
        "-gAUTOCONTRAST_EN=$AutocontrastEn",
        "-voptargs=+acc",
        "work.vga_debug_mux",
        "-do", "run -all; quit -f"
    )
    & $Vsim @VsimArgs
    if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit code $LASTEXITCODE" }

    $TranscriptText = Get-Content -Raw -Path $Transcript
    if ($TranscriptText -match "Unable to open lib python" -or $TranscriptText -match "ERROR\s+gpi") {
        throw "cocotb did not start cleanly. Check transcript: $Transcript"
    }
    if (!(Test-Path -LiteralPath $ResultsXml)) {
        throw "ModelSim exited, but cocotb did not write results XML. Check transcript: $Transcript"
    }

    [xml]$Results = Get-Content -Path $ResultsXml
    $Failures = Select-Xml -Xml $Results -XPath "//failure"
    if ($Failures.Count -gt 0) {
        if (Test-Path -LiteralPath $ExceptionText) {
            $Details = Get-Content -Raw -Path $ExceptionText
            throw "cocotb test failed:`n$Details"
        }
        throw "cocotb test failed. Check $ResultsXml and $Transcript"
    }

    Write-Host "Signed heatmap simulation completed. Outputs: $OutputDir"
}
finally {
    Pop-Location
}
