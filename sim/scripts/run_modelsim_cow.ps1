param(
    [int]$TestWidth = 192,
    [int]$TestHeight = 144,
    [int]$TemplateSize = 64,
    [int]$NumTaps = 64,
    [int]$RowW = 6,
    [int]$ColW = 6,
    [int]$FeatureW = 8,
    [int]$WeightW = 8,
    [int]$ScoreW = 32,
    [int]$CowX = 64,
    [int]$CowY = 40,
    [string]$TemplateInclude = "cow_edge_template_64.vh",
    [string]$TemplateVh = "",
    [string]$TemplateFeatureImage = "",
    [string]$ModelsimBin = "C:\intelFPGA\20.1\modelsim_ase\win32aloem"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SimDir = Split-Path -Parent $ScriptDir
$RepoRoot = Split-Path -Parent $SimDir
$RtlDir = Join-Path $RepoRoot "rtl\object_detection"
$TestsDir = Join-Path $SimDir "tests"
$BuildDir = Join-Path $SimDir "build\sparse_matcher_cow"
$LogDir = Join-Path $SimDir "logs"
$VenvDir = Join-Path $SimDir ".venv"
$SitePackages = Join-Path $VenvDir "Lib\site-packages"
$CocotbLib = Join-Path $SitePackages "cocotb\libs\cocotbvpi_modelsim.dll"
$VenvCfg = Join-Path $VenvDir "pyvenv.cfg"
$OutputDir = Join-Path $SimDir "output\sparse_matcher_cow"
$WorkLib = Join-Path $BuildDir "work"
$Transcript = Join-Path $LogDir "transcript_sparse_matcher_cow.log"
$ResultsXml = Join-Path $LogDir "results_sparse_matcher_cow.xml"
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
    $TemplateVh = Join-Path (Join-Path $RtlDir "templates") $TemplateInclude
} elseif (!(Test-Path -LiteralPath $TemplateVh)) {
    $Candidate = Join-Path $SimDir $TemplateVh
    if (Test-Path -LiteralPath $Candidate) {
        $TemplateVh = $Candidate
    }
}
$TemplateVh = (Resolve-Path -LiteralPath $TemplateVh).Path

if ([string]::IsNullOrWhiteSpace($TemplateFeatureImage)) {
    $TemplateFeatureImage = Join-Path $RepoRoot "objects\cow_64_64tap\cow_dbg_02_sobel_mag_64.png"
}
if (!(Test-Path -LiteralPath $TemplateFeatureImage)) {
    $TemplateFeatureImage = ""
} else {
    $TemplateFeatureImage = (Resolve-Path -LiteralPath $TemplateFeatureImage).Path
}

New-Item -ItemType Directory -Force -Path $OutputDir, $BuildDir, $LogDir | Out-Null

$env:MODULE = "test_sparse_template_matcher_cow"
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
$env:OBJECT_NAME = "cow"
$env:OBJECT_X = "$CowX"
$env:OBJECT_Y = "$CowY"
$env:COW_X = "$CowX"
$env:COW_Y = "$CowY"
$env:TEMPLATE_CROP_MODE = "foreground"
$env:TEMPLATE_FEATURE_IMAGE = "$TemplateFeatureImage"
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

    Write-Host "Cow sparse matcher simulation passed. Metrics: $OutputDir\compare_metrics.txt"
}
finally {
    Pop-Location
}
