# Publier-GitHub.ps1 - Windows PowerShell 5.1 / 7, ASCII pur.
# Prepare le depot Git de StudyTimer (sans secrets ni fichiers lourds) et le publie sur GitHub.
#
# Utilisation (depuis C:\dev\studytimer) :
#   .\Publier-GitHub.ps1                              -> verifie tout, commit, puis cree un depot PRIVE avec GitHub CLI (gh)
#   .\Publier-GitHub.ps1 -Nom "studytimer" -Public    -> depot public
#   .\Publier-GitHub.ps1 -Remote "https://github.com/MON-COMPTE/studytimer.git"
#                                                     -> si vous avez deja cree le depot vide sur github.com
#   .\Publier-GitHub.ps1 -SeulementPreparer           -> prepare et commit, sans publier
#
# Securite : le script REFUSE de commiter .env, cles privees, sauvegardes de base (.dump) et fichiers > 50 Mo.

param(
    [string]$Chemin = ".",
    [string]$Nom = "studytimer",
    [string]$Remote = "",
    [switch]$Public,
    [switch]$SeulementPreparer,
    [string]$Message = "Study Timer : backend ASP.NET, application Flutter, deploiement Docker"
)

$ErrorActionPreference = "Stop"
function Ok([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Info([string]$m) { Write-Host "  [..] $m" -ForegroundColor Gray }
function Warn([string]$m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Stop-Net([string]$m) { Write-Host ""; Write-Host "ARRET : $m" -ForegroundColor Red; exit 1 }

$Racine = (Resolve-Path $Chemin).Path
Set-Location $Racine
Write-Host ""
Write-Host "=== Publication de StudyTimer sur GitHub ===" -ForegroundColor Cyan
Write-Host "Projet : $Racine"

# --- 1. Git installe ?
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Stop-Net "Git n'est pas installe. Installez-le : winget install --id Git.Git -e  (puis rouvrez PowerShell)."
}
Ok ("git : " + (& git --version))

# --- 2. .gitignore : ajouter ce qui manque (idempotent)
$requis = @(
    "# --- ajoute par Publier-GitHub.ps1 ---",
    ".env", ".env.*", "!.env.example",
    "*.pem", "*.key", "*.pfx", "deploy/certs/",
    "*.dump", "backups/", "archive/",
    "*.log", "*.bak", "*.bak-*", "*.old",
    "bin/", "obj/", ".vs/", "*.user",
    ".dart_tool/", "build/", ".flutter-plugins-dependencies", "*.iml", ".idea/",
    "mobile/study_timer/android/local.properties", "mobile/study_timer/android/key.properties",
    "*.jks", "*.keystore",
    "docs/CODE-MOBILE.txt", "code_complet_*.txt", "diagnostic_*.txt"
)
$gi = Join-Path $Racine ".gitignore"
$existant = @()
if (Test-Path $gi) { $existant = @(Get-Content $gi -Encoding UTF8) }
$ajout = @($requis | Where-Object { ($_ -notmatch '^#') -and ($existant -notcontains $_) })
if ($ajout.Count -gt 0) {
    $bloc = @("", "# --- ajoute par Publier-GitHub.ps1 ---") + $ajout
    Add-Content -Path $gi -Value $bloc -Encoding UTF8
    Ok (".gitignore complete (" + $ajout.Count + " regles ajoutees)")
} else { Info ".gitignore deja complet" }

# --- 3. Depot Git
if (-not (Test-Path (Join-Path $Racine ".git"))) {
    & git init -b main | Out-Null
    Ok "depot Git initialise (branche main)"
} else { Info "depot Git existant" }

# identite
$nomGit = (& git config user.name) 2>$null
$mailGit = (& git config user.email) 2>$null
if (-not $nomGit -or -not $mailGit) {
    Stop-Net "Identite Git manquante. Lancez : git config --global user.name `"Votre Nom`"  puis  git config --global user.email `"vous@exemple.com`""
}

# --- 4. Preparer l'index et controler
& git add -A
$fichiers = @(& git ls-files)      # tout ce qui sera publie (nouveaux fichiers ET fichiers deja suivis)
if ($fichiers.Count -eq 0) { Info "aucun fichier a publier" }

$interdits = @($fichiers | Where-Object {
    $_ -match '(^|/)\.env$' -or $_ -match '\.(pem|key|pfx|jks|keystore|dump)$' -or $_ -match '(^|/)backups/' -or $_ -match 'privkey'
})
if ($interdits.Count -gt 0) {
    Stop-Net ("fichiers sensibles suivis par Git, rien n'a ete publie :`n    " + ($interdits -join "`n    ") + "`nRetirez-les du suivi : git rm --cached <fichier>   (puis relancez).`nS'ils ont deja ete commites dans le passe, changez les secrets concernes (mot de passe, cle JWT) : l'historique les contient encore.")
}

$lourds = @()
foreach ($f in $fichiers) {
    $p = Join-Path $Racine $f
    if ((Test-Path -LiteralPath $p) -and ((New-Object System.IO.FileInfo($p)).Length -gt 50MB)) { $lourds += $f }
}
if ($lourds.Count -gt 0) {
    Stop-Net ("fichiers de plus de 50 Mo (GitHub refuse > 100 Mo) :`n    " + ($lourds -join "`n    ") + "`nAjoutez-les a .gitignore puis relancez.")
}

# secrets en clair dans les fichiers de configuration suivis
$suspects = @()
foreach ($f in ($fichiers | Where-Object { $_ -match '\.(json|yml|yaml|cs|ps1|sh|md|txt)$' })) {
    $p = Join-Path $Racine $f
    if (-not (Test-Path -LiteralPath $p)) { continue }
    if ((New-Object System.IO.FileInfo($p)).Length -gt 1MB) { continue }
    $t = [System.IO.File]::ReadAllText($p)
    if ($t -match '(?i)(Jwt__?Key|"Key"|DB_PASSWORD|Password)\s*[:=]\s*"?[A-Za-z0-9+/=_\-]{24,}') { $suspects += $f }
}
if ($suspects.Count -gt 0) {
    Warn "valeurs ressemblant a un secret dans : $($suspects -join ', ') - verifiez qu'il s'agit d'exemples."
}

Ok ("fichiers a publier : " + $fichiers.Count)

# README minimal si absent
$readme = Join-Path $Racine "README.md"
if (-not (Test-Path $readme)) {
    $r = @(
        "# Study Timer",
        "",
        "Application de gestion du temps d'etude (chronometre, Pomodoro, defis, classements, salles d'etude).",
        "",
        "- backend : ASP.NET Core + PostgreSQL + SignalR (backend/)",
        "- mobile : Flutter (mobile/study_timer)",
        "- deploiement : Docker Compose + Nginx (docker-compose.yml, deploy/)",
        "",
        "Installation et administration : voir GUIDE.md. Conformite au cahier des charges : docs/CONFORMITE.md.",
        "",
        "Ne jamais commiter le fichier .env (copier .env.example)."
    )
    [System.IO.File]::WriteAllLines($readme, $r, (New-Object System.Text.UTF8Encoding($false)))
    & git add README.md
    Ok "README.md cree"
}

# --- 5. Commit
if (@(& git diff --cached --name-only).Count -gt 0) {
    & git commit -m $Message | Out-Null
    Ok "commit cree"
} else { Info "aucun changement a commiter" }

if ($SeulementPreparer) {
    Write-Host ""
    Write-Host "Prepare. Pour publier plus tard : relancez sans -SeulementPreparer." -ForegroundColor Yellow
    exit 0
}

# --- 6. Publication
$visibilite = "--private"; if ($Public) { $visibilite = "--public" }
$gh = Get-Command gh -ErrorAction SilentlyContinue

if ($Remote) {
    $deja = (& git remote) -contains "origin"
    if ($deja) { & git remote set-url origin $Remote } else { & git remote add origin $Remote }
    & git push -u origin main
    if ($LASTEXITCODE -ne 0) { Stop-Net "git push a echoue (connexion GitHub requise : identifiants ou jeton d'acces personnel)." }
    Ok "publie sur $Remote"
}
elseif ($gh) {
    & gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Warn "GitHub CLI non connecte : une page de connexion va s'ouvrir."
        & gh auth login
        if ($LASTEXITCODE -ne 0) { Stop-Net "connexion GitHub annulee." }
    }
    if ((& git remote) -contains "origin") {
        & git push -u origin main
    } else {
        & gh repo create $Nom $visibilite --source . --remote origin --push
    }
    if ($LASTEXITCODE -ne 0) { Stop-Net "la creation ou l'envoi a echoue (le depot '$Nom' existe-t-il deja ?)." }
    Ok "depot publie"
    & gh repo view --web 2>$null | Out-Null
}
else {
    Write-Host ""
    Write-Host "GitHub CLI (gh) n'est pas installe. Deux options :" -ForegroundColor Yellow
    Write-Host "  A) winget install --id GitHub.cli -e   puis rouvrez PowerShell et relancez ce script" -ForegroundColor Yellow
    Write-Host "  B) Creez un depot VIDE sur https://github.com/new (sans README), puis :" -ForegroundColor Yellow
    Write-Host "       .\Publier-GitHub.ps1 -Remote `"https://github.com/MON-COMPTE/$Nom.git`"" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "Termine. Ensuite : git add -A ; git commit -m `"message`" ; git push" -ForegroundColor Cyan
