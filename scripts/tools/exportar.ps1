param(
	[string]$Godot = "godot"
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ServerOutput = Join-Path $Root "exports\linux-server\drone-server.x86_64"
$ClientOutput = Join-Path $Root "exports\windows-client\drone-client.exe"

New-Item -ItemType Directory -Force -Path (Split-Path $ServerOutput), (Split-Path $ClientOutput) | Out-Null

& $Godot --headless --editor --path $Root --quit
if ($LASTEXITCODE -ne 0) {
	throw "Godot no pudo importar el proyecto (código $LASTEXITCODE)."
}

& $Godot --headless --path $Root --export-release "Linux Server" $ServerOutput
if ($LASTEXITCODE -ne 0) {
	throw "Falló la exportación Linux Server (código $LASTEXITCODE)."
}

& $Godot --headless --path $Root --export-release "Windows Desktop" $ClientOutput
if ($LASTEXITCODE -ne 0) {
	throw "Falló la exportación Windows Desktop (código $LASTEXITCODE)."
}
