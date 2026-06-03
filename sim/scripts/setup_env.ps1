param(
    [string]$PythonVersion = "3.12",
    [string]$PythonExe = "",
    [switch]$Recreate
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SimDir = Split-Path -Parent $ScriptDir
$VenvDir = Join-Path $SimDir ".venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"

function Invoke-CheckedCommand {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [string]$FailureMessage
    )

    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage Exit code: $LASTEXITCODE"
    }
}

function Get-PythonCommand {
    if (![string]::IsNullOrWhiteSpace($PythonExe)) {
        if (!(Test-Path -LiteralPath $PythonExe)) {
            throw "PythonExe does not exist: $PythonExe"
        }
        return @($PythonExe)
    }

    $PyLauncher = Get-Command py -ErrorAction SilentlyContinue
    if ($null -eq $PyLauncher) {
        throw "Python launcher 'py' was not found. Install Python 3.12 with the launcher, or pass -PythonExe C:\path\to\Python312\python.exe."
    }
    return @($PyLauncher.Source, "-$PythonVersion")
}

function Invoke-SelectedPython {
    param([string[]]$Arguments)

    $Command = Get-PythonCommand
    $Exe = $Command[0]
    $BaseArgs = @()
    if ($Command.Count -gt 1) {
        $BaseArgs = $Command[1..($Command.Count - 1)]
    }
    $AllArgs = @() + $BaseArgs + $Arguments
    Invoke-CheckedCommand -Exe $Exe -Arguments $AllArgs -FailureMessage "Python $PythonVersion command failed."
}

function Read-SelectedPythonValue {
    param([string]$Code)

    $Command = Get-PythonCommand
    $Exe = $Command[0]
    $BaseArgs = @()
    if ($Command.Count -gt 1) {
        $BaseArgs = $Command[1..($Command.Count - 1)]
    }
    $AllArgs = @() + $BaseArgs + @("-c", $Code)
    $Value = & $Exe @AllArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Could not run selected Python command. Exit code: $LASTEXITCODE"
    }
    return ($Value | Select-Object -First 1).Trim()
}

function Read-VenvPythonVersion {
    if (!(Test-Path -LiteralPath $VenvPython)) {
        return ""
    }
    $Value = & $VenvPython -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    if ($LASTEXITCODE -ne 0) {
        return "unknown"
    }
    return ($Value | Select-Object -First 1).Trim()
}

Push-Location $SimDir
try {
    $SelectedVersion = Read-SelectedPythonValue "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')"
    $SelectedExe = Read-SelectedPythonValue "import sys; print(sys.executable)"

    if ($SelectedVersion -ne $PythonVersion) {
        throw "Selected interpreter is Python $SelectedVersion, but Python $PythonVersion is required. Selected executable: $SelectedExe"
    }

    Write-Host "Using Python ${SelectedVersion}: $SelectedExe"

    if (Test-Path -LiteralPath $VenvPython) {
        $ExistingVersion = Read-VenvPythonVersion
        if ($ExistingVersion -ne $PythonVersion) {
            if ($Recreate) {
                Write-Host "Removing existing .venv because it uses Python $ExistingVersion."
                Remove-Item -LiteralPath $VenvDir -Recurse -Force
            } else {
                throw "Existing sim\.venv uses Python $ExistingVersion. Re-run with -Recreate, or delete sim\.venv, to rebuild it with Python $PythonVersion."
            }
        }
    }

    if (!(Test-Path -LiteralPath $VenvPython)) {
        Invoke-SelectedPython @("-m", "venv", ".venv")
    }

    $FinalVenvVersion = Read-VenvPythonVersion
    if ($FinalVenvVersion -ne $PythonVersion) {
        throw "Created venv uses Python $FinalVenvVersion, but Python $PythonVersion is required."
    }

    & $VenvPython --version
    if ($LASTEXITCODE -ne 0) { throw "Could not run $VenvPython" }

    & $VenvPython -m pip install --upgrade pip
    if ($LASTEXITCODE -ne 0) { throw "pip upgrade failed." }

    & $VenvPython -m pip install -r requirements.txt
    if ($LASTEXITCODE -ne 0) { throw "requirements install failed." }

    Write-Host ""
    Write-Host "Environment ready with Python $PythonVersion. Activate it with:"
    Write-Host ".\.venv\Scripts\Activate.ps1"
}
finally {
    Pop-Location
}
