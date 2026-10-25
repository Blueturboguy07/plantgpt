# bugfix-lab oracle (windows-latest) for plantgpt-20261021-1652b7:
# PlantGPT desktop reports "Ollama isn't running" while Ollama serves localhost:11434.
# Installs real Ollama, builds the real PlantGPT.exe, launches it, reads the rendered banner.
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
$repo = (Get-Location).Path
$tools = Join-Path $env:RUNNER_TEMP "probe"
New-Item -ItemType Directory -Force $tools | Out-Null

Write-Host "== install Ollama =="
$setup = Join-Path $env:RUNNER_TEMP "OllamaSetup.exe"
Invoke-WebRequest -Uri "https://ollama.com/download/OllamaSetup.exe" -OutFile $setup
$inst = Start-Process $setup -ArgumentList "/VERYSILENT","/NORESTART","/SUPPRESSMSGBOXES" -PassThru
# do NOT use -Wait: it also waits for the tray app the installer launches
if (-not $inst.WaitForExit(300000)) { Write-Host "installer still running after 5 min; continuing" }
Write-Host "installer exit code: $($inst.ExitCode)"
$ollamaDir = Join-Path $env:LOCALAPPDATA "Programs\Ollama"
$env:PATH = "$ollamaDir;$env:PATH"
& ollama --version

function Test-Ollama {
  try { return (Invoke-WebRequest -Uri "http://localhost:11434/" -UseBasicParsing -TimeoutSec 3).Content } catch { return $null }
}
$up = $null
for ($i = 0; $i -lt 20 -and -not $up; $i++) { $up = Test-Ollama; if (-not $up) { Start-Sleep 2 } }
if (-not $up) {
  Write-Host "installer did not leave a server up; starting 'ollama serve'"
  Start-Process -FilePath (Join-Path $ollamaDir "ollama.exe") -ArgumentList "serve" -WindowStyle Hidden
  for ($i = 0; $i -lt 20 -and -not $up; $i++) { Start-Sleep 2; $up = Test-Ollama }
}
Write-Host "BROWSER-EQUIVALENT GET http://localhost:11434/ -> $up"
if (-not $up) { Write-Host "BUGFIX_LAB_COULD_NOT_RUN (Ollama not serving)"; exit 2 }
try { Write-Host ("GET /api/tags -> " + (Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing).Content) } catch { Write-Host "api/tags failed: $_" }
Write-Host "== listeners on 11434 =="
netstat -ano | Select-String ":11434"

Write-Host "== build PlantGPT.exe =="
npm ci
if ($LASTEXITCODE -ne 0) { Write-Host "BUGFIX_LAB_COULD_NOT_RUN (npm ci)"; exit 2 }
npx tauri build --no-bundle
if ($LASTEXITCODE -ne 0) { Write-Host "BUGFIX_LAB_COULD_NOT_RUN (tauri build)"; exit 2 }
$exe = Join-Path $repo "src-tauri\target\release\plantgpt.exe"
if (-not (Test-Path $exe)) { Write-Host "BUGFIX_LAB_COULD_NOT_RUN (no exe)"; exit 2 }

Write-Host "== probe deps =="
Copy-Item (Join-Path $repo "scripts\bugfix-lab\plantgpt-20261021-1652b7.mjs") (Join-Path $tools "probe.mjs")
Push-Location $tools
npm init -y | Out-Null
npm i playwright-core
Pop-Location

Write-Host "== launch app =="
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=9222 --remote-allow-origins=*"
$env:WEBVIEW2_USER_DATA_FOLDER = Join-Path $env:RUNNER_TEMP "wv2"
$app = Start-Process -FilePath $exe -PassThru
Start-Sleep 5

Write-Host "== diagnostics: 9222 + processes =="
netstat -ano | Select-String ":9222"
Get-Process plantgpt,msedgewebview2 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,MainWindowTitle | Format-Table | Out-String | Write-Host
try { Write-Host ("json/version -> " + (Invoke-WebRequest -Uri "http://127.0.0.1:9222/json/version" -UseBasicParsing -TimeoutSec 5).Content) } catch { Write-Host "json/version failed: $_" }

Push-Location $tools
node probe.mjs
$code = $LASTEXITCODE
Pop-Location
Write-Host "CDP probe exit code: $code"

if ($code -eq 2) {
  Write-Host "== fallback: read rendered text via UI Automation =="
  Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
  $texts = New-Object System.Collections.Generic.List[string]
  $rendered = $false; $renderedAt = $null
  $deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $deadline) {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $app.Id)
    $win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
    if ($win) {
      $texts.Clear()
      foreach ($e in $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        $n = $e.Current.Name
        if ($n) { $texts.Add($n) }
      }
      if (-not $rendered -and ($texts -join " | ") -match "What can I help with|Ask anything") { $rendered = $true; $renderedAt = Get-Date }
      # ollamaHealth() runs once at mount (2.5 s timeout); wait 10 s after first render
      if ($rendered -and ((Get-Date) - $renderedAt).TotalSeconds -ge 10) { break }
    }
    Start-Sleep 3
  }
  $all = ($texts | Select-Object -Unique) -join " | "
  Write-Host "UIA_TEXTS: $all"
  if (-not $rendered) { Write-Host "BUGFIX_LAB_COULD_NOT_OBSERVE (UIA saw no rendered app)"; $code = 2 }
  elseif ($all -match "isn.t running") { Write-Host "BUGFIX_LAB_PRESENT"; $code = 1 }
  else { Write-Host "BUGFIX_LAB_ABSENT"; $code = 0 }
}
Write-Host "final probe exit code: $code"

Write-Host "== Ollama server.log tail =="
$log = Join-Path $env:LOCALAPPDATA "Ollama\server.log"
if (Test-Path $log) { Get-Content $log -Tail 40 } else { Write-Host "no server.log at $log" }
Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue
exit $code
