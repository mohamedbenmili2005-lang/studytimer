# Genere un .env avec des secrets aleatoires solides (PowerShell 5.1).
param([string]$PublicUrl = "https://studytimer.example.com")
function New-Secret([int]$bytes) {
    $b = New-Object byte[] $bytes
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    [Convert]::ToBase64String($b)
}
$envFile = Join-Path (Split-Path (Split-Path $PSScriptRoot)) ".env"
if (Test-Path $envFile) { Write-Host ".env existe deja, rien ecrase." -ForegroundColor Yellow; exit 1 }
$dbPass = (New-Secret 24) -replace '[^A-Za-z0-9]', 'x'
@"
DB_PASSWORD=$dbPass
JWT_KEY=$(New-Secret 48)
PUBLIC_URL=$PublicUrl
SWAGGER_ENABLED=false
BACKUP_KEEP_DAYS=14
"@ | Set-Content $envFile -Encoding ASCII
Write-Host "[OK] $envFile cree avec des secrets aleatoires." -ForegroundColor Green
