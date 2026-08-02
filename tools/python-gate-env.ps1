function Get-GatePython {
    param([string]$Repo)

    $venvPython = Join-Path $Repo ".venv\Scripts\python.exe"
    if (Test-Path $venvPython) {
        return (Resolve-Path $venvPython).Path
    }

    return "python"
}

function Test-GatePythonImports {
    param(
        [string]$Python,
        [string[]]$Imports,
        [string]$WorkingDirectory
    )

    $script = @'
import importlib
import sys

for name in sys.argv[1:]:
    module_name, _, attr_name = name.partition(':')
    try:
        module = importlib.import_module(module_name)
        if attr_name and not hasattr(module, attr_name):
            print(f'{name}: missing attribute {attr_name}', file=sys.stderr)
            sys.exit(44)
    except ModuleNotFoundError as exc:
        missing = exc.name if exc.name else module_name
        print(f'{name}: missing {missing}', file=sys.stderr)
        sys.exit(42)
    except Exception as exc:
        print(f'{name}: {exc.__class__.__name__}: {exc}', file=sys.stderr)
        sys.exit(43)
'@

    $previousLocation = Get-Location
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Set-Location $WorkingDirectory
        }
        $output = & $Python -c $script @Imports 2>&1
        $code = $LASTEXITCODE
    } catch {
        $output = @($_.Exception.Message)
        $code = 1
    } finally {
        Set-Location $previousLocation
    }

    return @{
        Ok = ($code -eq 0)
        Code = $code
        Output = (($output | ForEach-Object { $_.ToString() }) -join "`n")
    }
}

function Assert-GatePythonImports {
    param(
        [string]$GateName,
        [string]$Python,
        [string[]]$Imports,
        [string]$WorkingDirectory
    )

    $result = Test-GatePythonImports -Python $Python -Imports $Imports -WorkingDirectory $WorkingDirectory
    if (-not $result.Ok) {
        $details = [string]$result.Output
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = "exit=$($result.Code)"
        }
        Write-Output "${GateName}: FAILED (ENV) -- python import preflight failed using $Python -- $details"
        exit 3
    }
}
