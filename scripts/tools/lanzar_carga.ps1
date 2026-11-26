$ErrorActionPreference = "Stop"
$ScriptPath = Join-Path $PSScriptRoot "lanzar_carga.py"
$Python = if ($env:PYTHON_BIN) { $env:PYTHON_BIN } else { "python" }

& $Python $ScriptPath @args
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}
