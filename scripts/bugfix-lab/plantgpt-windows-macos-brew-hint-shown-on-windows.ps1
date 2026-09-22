# bugfix-lab oracle runner (Windows) for cluster:
#   plantgpt-windows-macos-brew-hint-shown-on-windows
#
# Builds PlantGPT's web bundle and drives it in headless Chromium on this
# windows-latest runner, reading the real rendered "Ollama isn't running"
# setup-banner text. Prints BUGFIX_LAB_PRESENT / BUGFIX_LAB_ABSENT and exits
# 1 / 0 to match. Exits 2 if the probe could not observe anything.

$ErrorActionPreference = "Stop"

Write-Host "== npm ci =="
npm ci
if ($LASTEXITCODE -ne 0) { Write-Host "BUGFIX_LAB_COULD_NOT_RUN (npm ci failed)"; exit 2 }

Write-Host "== npm run build =="
npm run build
if ($LASTEXITCODE -ne 0) { Write-Host "BUGFIX_LAB_COULD_NOT_RUN (build failed)"; exit 2 }

Write-Host "== playwright install chromium =="
npx playwright install chromium --with-deps
if ($LASTEXITCODE -ne 0) { Write-Host "BUGFIX_LAB_COULD_NOT_RUN (playwright install failed)"; exit 2 }

Write-Host "== oracle probe =="
node scripts/bugfix-lab/oracle-probe.mjs
$probeExit = $LASTEXITCODE
Write-Host "oracle-probe.mjs exit code: $probeExit"
exit $probeExit
