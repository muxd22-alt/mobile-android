# Arbor configuration generator
$ArborConfigDir = "C:\Users\medo\.config\arbor"
if (-not (Test-Path $ArborConfigDir)) { New-Item -ItemType Directory -Path $ArborConfigDir -Force }
$ConfigPath = Join-Path $ArborConfigDir "config.toml"

$AIProjectsDir = "D:\AI_PROJECTS"
# Reliable discovery of Git repo roots
$Repos = Get-ChildItem -Path $AIProjectsDir -Recurse -Force | Where-Object { $_.Name -eq ".git" } | ForEach-Object { $_.Parent.FullName } | Select-Object -Unique

$Content = @"
# Arbor configuration (Generated on startup)
[daemon]
bind = "0.0.0.0:8787"
auth_token = "arbor-tailscale-access"
theme = "Omarchy Dark"
terminal_backend = "embedded"
embedded_terminal_engine = "alacritty"

[ai]
openai_api_base = "http://100.67.202.80:3003/v1"
openai_api_key = "sk-lm-Lx9jGf04:PFt54YB1r3KclB2rq6N4"
model = "qwen3.5-9b-claude-4.6-opus-reasoning-distilled"
"@

foreach ($repo in $Repos) {
    if ($repo -ne $AIProjectsDir) {
        $label = Split-Path $repo -Leaf
        $root = $repo.Replace('\', '/')
        $Content += "`n`n[[repositories]]`nroot = `"$root`"`nlabel = `"$label`""
    }
}

Set-Content -Path $ConfigPath -Value $Content -Force
# Also copy to bin location
$BinConfigDir = "D:\ARBOR\bin\.config\arbor"
if (-not (Test-Path $BinConfigDir)) { New-Item -ItemType Directory -Path $BinConfigDir -Force }
Copy-Item $ConfigPath $BinConfigDir -Force
