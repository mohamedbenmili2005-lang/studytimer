# Corriger-Docker.ps1
# Compatible Windows PowerShell 5.1 (fichier volontairement en ASCII pur).
#
# Corrige l'erreur :
#   "required variable DB_PASSWORD / JWT_KEY / PUBLIC_URL is missing a value ... dans .env"
#
# Ce que fait le script :
#   1. Lit docker-compose.yml et trouve les variables obligatoires.
#   2. Cree ou complete le fichier .env (secrets aleatoires, sauvegarde de l'ancien .env).
#   3. Lance "docker compose up -d".
#   4. (option -Secrets) Configure l'API pour la base Docker (dotnet user-secrets).
#
# Utilisation (depuis C:\dev\studytimer) :
#   .\Corriger-Docker.ps1                    -> cree .env et demarre Docker
#   .\Corriger-Docker.ps1 -Dev               -> ajoute aussi deploy\docker-compose.dev.yml
#   .\Corriger-Docker.ps1 -Dev -Secrets      -> + configure l'API lancee avec dotnet run
#
# Les secrets ne sont jamais affiches a l'ecran.

param(
    [string]$Chemin = ".",
    [switch]$Dev,
    [switch]$Secrets
)

$Racine     = (Resolve-Path $Chemin).Path
$Compose    = Join-Path $Racine "docker-compose.yml"
$ComposeDev = Join-Path $Racine "deploy\docker-compose.dev.yml"
$FichierEnv = Join-Path $Racine ".env"
$Exemple    = Join-Path $Racine ".env.example"
$ApiDir     = Join-Path $Racine "backend\StudyTimer.Api"
$Placeholder = 'change|votre|your|xxx|exemple|example|todo'

function Titre($texte) {
    Write-Host ""
    Write-Host ("=== " + $texte + " ===") -ForegroundColor Cyan
}

function New-Secret([int]$longueur) {
    $alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    $octets = New-Object byte[] $longueur
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rng.GetBytes($octets)
    $rng.Dispose()
    $sb = New-Object System.Text.StringBuilder
    foreach ($b in $octets) { [void]$sb.Append($alphabet[$b % $alphabet.Length]) }
    return $sb.ToString()
}

function Read-EnvFile($chemin) {
    $h = @{}
    if (Test-Path -LiteralPath $chemin) {
        foreach ($l in (Get-Content -LiteralPath $chemin -Encoding UTF8)) {
            if ($l -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                $h[$Matches[1]] = $Matches[2].Trim().Trim('"').Trim("'")
            }
        }
    }
    return $h
}

# ---------------------------------------------------------------
# Verifications de base
# ---------------------------------------------------------------
if (-not (Test-Path $Compose)) {
    Write-Host ("docker-compose.yml introuvable dans " + $Racine) -ForegroundColor Red
    Write-Host "Lance le script depuis C:\dev\studytimer."
    return
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker n'est pas installe (commande 'docker' introuvable)." -ForegroundColor Red
    return
}
& docker info 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker Desktop n'est pas demarre. Ouvre-le, attends qu'il soit pret, puis relance ce script." -ForegroundColor Red
    return
}

$fichiersCompose = @($Compose)
if ($Dev) {
    if (Test-Path $ComposeDev) { $fichiersCompose += $ComposeDev }
    else { Write-Host "deploy\docker-compose.dev.yml introuvable : option -Dev ignoree." -ForegroundColor Yellow }
}

# ---------------------------------------------------------------
# 1. Variables obligatoires
# ---------------------------------------------------------------
Titre "1. VARIABLES REQUISES PAR DOCKER COMPOSE"
$requises = @()
foreach ($f in $fichiersCompose) {
    $texte = Get-Content -LiteralPath $f -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($texte, '\$\{([A-Za-z_][A-Za-z0-9_]*)(?::\?[^}]*|\?[^}]*)?\}')) {
        $requises += $m.Groups[1].Value
    }
}
$requises = @($requises | Select-Object -Unique)
if ($requises.Count -eq 0) {
    Write-Host "  Aucune variable obligatoire trouvee."
}
else {
    Write-Host ("  " + ($requises -join ", "))
}

# ---------------------------------------------------------------
# 2. Creation / completion du .env
# ---------------------------------------------------------------
Titre "2. FICHIER .env"
$valeurs  = Read-EnvFile $FichierEnv
$modele   = Read-EnvFile $Exemple
$nouveaux = [ordered]@{}

foreach ($nom in $requises) {
    $val = $valeurs[$nom]
    if ($val -and $val -notmatch $Placeholder) { continue }
    if ($nom -match 'PASSWORD|PWD') { $val = New-Secret 24 }
    elseif ($nom -match 'KEY|SECRET|TOKEN') { $val = New-Secret 48 }
    elseif ($nom -match 'URL') { $val = "http://localhost" }
    elseif ($modele[$nom] -and $modele[$nom] -notmatch $Placeholder) { $val = $modele[$nom] }
    else { $val = Read-Host ("Valeur pour " + $nom) }
    $nouveaux[$nom] = $val
    $valeurs[$nom] = $val
}

if ($nouveaux.Count -eq 0) {
    Write-Host "  .env deja complet : rien a changer." -ForegroundColor Green
}
else {
    if (Test-Path $FichierEnv) {
        $sauvegarde = $FichierEnv + ".bak-" + (Get-Date -Format "yyyyMMdd-HHmmss")
        Copy-Item -LiteralPath $FichierEnv -Destination $sauvegarde
        Write-Host ("  Ancien .env sauvegarde : " + $sauvegarde)
        $lignes = @(Get-Content -LiteralPath $FichierEnv -Encoding UTF8)
    }
    else {
        $lignes = @()
    }
    foreach ($nom in $nouveaux.Keys) {
        $trouve = $false
        for ($i = 0; $i -lt $lignes.Count; $i++) {
            if ($lignes[$i] -match ('^\s*' + [regex]::Escape($nom) + '\s*=')) {
                $lignes[$i] = $nom + "=" + $nouveaux[$nom]
                $trouve = $true
                break
            }
        }
        if (-not $trouve) { $lignes += ($nom + "=" + $nouveaux[$nom]) }
        Write-Host ("  Defini : " + $nom) -ForegroundColor Green
    }
    Set-Content -LiteralPath $FichierEnv -Value $lignes -Encoding ASCII
}

$gitignore = Join-Path $Racine ".gitignore"
if (Test-Path $gitignore) {
    if (-not (Select-String -Path $gitignore -Pattern '^\s*\.env\s*$' -Quiet)) {
        Write-Host "  Attention : .env n'est pas dans .gitignore. Ajoute la ligne  .env  pour ne jamais publier tes secrets." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------
# 3. Demarrage de Docker Compose
# ---------------------------------------------------------------
Titre "3. DEMARRAGE DES CONTENEURS"
$cmd = @("compose")
foreach ($f in $fichiersCompose) { $cmd += @("-f", $f) }
Push-Location $Racine
& docker @cmd up -d
$codeSortie = $LASTEXITCODE
Write-Host ""
& docker @cmd ps
Pop-Location

if ($codeSortie -ne 0) {
    Write-Host ""
    Write-Host "docker compose a echoue (code $codeSortie). Copie-moi le message d'erreur ci-dessus." -ForegroundColor Red
    return
}

# ---------------------------------------------------------------
# 4. Configuration de l'API (option -Secrets)
# ---------------------------------------------------------------
if ($Secrets) {
    Titre "4. CONFIGURATION DE L'API (dotnet user-secrets)"
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        Write-Host "  dotnet introuvable : etape ignoree." -ForegroundColor Yellow
        return
    }

    # Port de la base publie sur ce PC
    Push-Location $Racine
    $sortiePort = (& docker @cmd port db 5432 2>&1 | Out-String).Trim()
    Pop-Location
    $port = $null
    $premiere = ($sortiePort -split "`n")[0].Trim()
    if ($premiere -match '^\S*:(\d+)$') { $port = $Matches[1] }
    if (-not $port) {
        Write-Host "  Le port 5432 de la base n'est pas publie sur ton PC : l'API lancee avec dotnet run ne pourra pas l'atteindre." -ForegroundColor Yellow
        Write-Host "  Relance avec :  .\Corriger-Docker.ps1 -Dev -Secrets   (si deploy\docker-compose.dev.yml publie le port)"
        return
    }

    # Utilisateur et base lus dans le fichier compose
    $texteCompose = ""
    foreach ($f in $fichiersCompose) { $texteCompose += (Get-Content -LiteralPath $f -Raw -Encoding UTF8) + "`n" }
    $utilisateur = $null
    $base = $null
    if ($texteCompose -match 'POSTGRES_USER\s*[:=]\s*([^\r\n]+)') { $utilisateur = $Matches[1] }
    if ($texteCompose -match 'POSTGRES_DB\s*[:=]\s*([^\r\n]+)')   { $base = $Matches[1] }

    function Resolve-Valeur($brut) {
        if (-not $brut) { return $null }
        $t = $brut.Trim().Trim('"').Trim("'")
        if ($t -match '^\$\{([A-Za-z_][A-Za-z0-9_]*)(?:(?::-|-)([^}]*))?\}$') {
            $nom = $Matches[1]
            $defaut = $Matches[2]
            if ($valeurs[$nom]) { return $valeurs[$nom] }
            return $defaut
        }
        return $t
    }
    $utilisateur = Resolve-Valeur $utilisateur
    $base = Resolve-Valeur $base
    if (-not $utilisateur) { $utilisateur = Read-Host "Nom d'utilisateur Postgres (POSTGRES_USER)" }
    if (-not $base) { $base = Read-Host "Nom de la base (POSTGRES_DB)" }

    $chaine = "Host=localhost;Port=" + $port + ";Database=" + $base + ";Username=" + $utilisateur + ";Password=" + $valeurs["DB_PASSWORD"]
    & dotnet user-secrets set "ConnectionStrings:Default" $chaine --project $ApiDir | Out-Null
    & dotnet user-secrets set "Database:MigrateOnStart" "true" --project $ApiDir | Out-Null
    Write-Host "  ConnectionStrings:Default et Database:MigrateOnStart (creation des tables au demarrage) configures." -ForegroundColor Green
    Write-Host "  Verifie que Jwt:Key existe :  dotnet user-secrets list --project backend\StudyTimer.Api"
}

Write-Host ""
Write-Host "Termine. Etape suivante : relance l'API." -ForegroundColor Cyan
Write-Host "  cd C:\dev\studytimer\backend"
Write-Host "  dotnet run --project StudyTimer.Api --urls http://localhost:5293"
Write-Host "Puis ouvre http://localhost:5293/health : il doit afficher Healthy."
