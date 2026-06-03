param(
    [int]$TestWidth = 128,
    [int]$TestHeight = 96,
    [int]$TemplateSize = 32,
    [int]$NumTaps = 64,
    [int]$RowW = 5,
    [int]$ColW = 5,
    [int]$FeatureW = 8,
    [int]$WeightW = 8,
    [int]$ScoreW = 32,
    [int]$DonutX = 48,
    [int]$DonutY = 32,
    [string]$TemplateInclude = "donut_edge_template_32.vh",
    [string]$TemplateVh = "",
    [string]$ModelsimBin = "C:\intelFPGA\20.1\modelsim_ase\win32aloem"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SimDir = Split-Path -Parent $ScriptDir
$RepoRoot = Split-Path -Parent $SimDir
$RtlDir = Join-Path $RepoRoot "rtl\object_detection"
$TestsDir = Join-Path $SimDir "tests"
$BuildDir = Join-Path $SimDir "build\sparse_matcher"
$LogDir = Join-Path $SimDir "logs"
$VenvDir = Join-Path $SimDir ".venv"
$SitePackages = Join-Path $VenvDir "Lib\site-packages"
$CocotbLib = Join-Path $SitePackages "cocotb\libs\cocotbvpi_modelsim.dll"
$VenvCfg = Join-Path $VenvDir "pyvenv.cfg"
$OutputDir = Join-Path $SimDir "output\sparse_matcher"
$WorkLib = Join-Path $BuildDir "work"
$Transcript = Join-Path $LogDir "transcript_sparse_matcher.log"
$ResultsXml = Join-Path $LogDir "results_sparse_matcher.xml"
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
    throw "Missing venv config: $VenvCfg. Run .\scripts\setup_env.ps1 first."
}

$PythonHomeLine = Get-Content -Path $VenvCfg | Where-Object { $_ -match "^home\s*=" } | Select-Object -First 1
$PythonHome = ($PythonHomeLine -replace "^home\s*=\s*", "").Trim()
if (!(Test-Path -LiteralPath $PythonHome)) {
    throw "Could not find Python home from venv config: $PythonHome"
}

if ([string]::IsNullOrWhiteSpace($TemplateVh)) {
    if ($TemplateInclude -eq "donut_edge_template_32.vh") {
        $TemplateVh = Join-Path (Join-Path $RtlDir "templates") $TemplateInclude
    } else {
        $TemplateVh = Join-Path (Join-Path $SimDir "templates") $TemplateInclude
    }
} elseif (!(Test-Path -LiteralPath $TemplateVh)) {
    $TemplateVh = Join-Path $SimDir $TemplateVh
}
$TemplateVh = (Resolve-Path -LiteralPath $TemplateVh).Path

New-Item -ItemType Directory -Force -Path $OutputDir, $BuildDir, $LogDir | Out-Null

$env:MODULE = "test_sparse_template_matcher"
$env:TOPLEVEL = "sparse_template_matcher"
$env:TOPLEVEL_LANG = "verilog"
$env:TEST_WIDTH = "$TestWidth"
$env:TEST_HEIGHT = "$TestHeight"
$env:TEMPLATE_SIZE = "$TemplateSize"
$env:NUM_TAPS = "$NumTaps"
$env:ROW_W = "$RowW"
$env:COL_W = "$ColW"
$env:FEATURE_W = "$FeatureW"
$env:WEIGHT_W = "$WeightW"
$env:SCORE_W = "$ScoreW"
$env:DONUT_X = "$DonutX"
$env:DONUT_Y = "$DonutY"
$env:TEMPLATE_INCLUDE = "$TemplateInclude"
$env:TEMPLATE_VH = "$TemplateVh"
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
        (Join-Path $RtlDir "score_mac_tree.v"),
        (Join-Path $RtlDir "stream_delay_engine.v"),
        (Join-Path $RtlDir "score_tree.v"),
        (Join-Path $RtlDir "sparse_template_matcher.v")
    )

    $TemplateDefine = '+define+TEMPLATE_INCLUDE=\"' + $TemplateInclude + '\"'
    Write-Host "vlog template define: $TemplateDefine"
    & $Vlog "+incdir+$(Join-Path $RtlDir 'templates')" "+incdir+$RtlDir" "+incdir+$(Join-Path $SimDir 'templates')" $TemplateDefine @Sources
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit code $LASTEXITCODE" }

    $VsimArgs = @(
        "-c",
        "-l", $Transcript,
        "-pli", $CocotbLib,
        "-gIMAGE_WIDTH=$TestWidth",
        "-gTEMPLATE_SIZE=$TemplateSize",
        "-gNUM_TAPS=$NumTaps",
        "-gROW_W=$RowW",
        "-gCOL_W=$ColW",
        "-gFEATURE_W=$FeatureW",
        "-gWEIGHT_W=$WeightW",
        "-gSCORE_W=$ScoreW",
        "-voptargs=+acc",
        "work.sparse_template_matcher",
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

    Write-Host "Simulation passed. Metrics: $OutputDir\compare_metrics.txt"
}
finally {
    Pop-Location
}
