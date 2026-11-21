# Organiser-Depot.ps1 - Windows PowerShell 5.1 / 7 (fichier UTF-8 avec BOM, accents autorises).
# Range le depot StudyTimer pour GitHub :
#   - range tous les scripts .ps1 de la racine dans scripts\
#   - range les rapports de diagnostic dans docs\
#   - cree docs\images\ (logo + captures d'ecran) et un README.md complet avec images
#   - (option) commit et push
#
# Utilisation (depuis C:\dev\studytimer) :
#   .\Organiser-Depot.ps1              -> range et genere le README
#   .\Organiser-Depot.ps1 -Publier     -> range, genere le README, commit et push sur GitHub
#
# Captures d'ecran : enregistrez-les dans docs\images\ avec ces noms (Win + Maj + S pour capturer) :
#   accueil.png  timer.png  defis.png  communaute.png  planificateur.png  mobile-connexion.png
# puis relancez le script : le README affiche celles qui existent.

param(
    [string]$Chemin = ".",
    [switch]$Publier,
    [string]$Message = "Organisation du depot : scripts/, docs/images/, README"
)

$ErrorActionPreference = "Stop"
function Ok([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green }
function Info([string]$m) { Write-Host "  [..] $m" -ForegroundColor Gray }
function Warn([string]$m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }

$Racine = (Resolve-Path $Chemin).Path
Set-Location $Racine
$utf8 = New-Object System.Text.UTF8Encoding($false)
$estGit = Test-Path (Join-Path $Racine ".git")

Write-Host ""
Write-Host "=== Organisation du dépôt StudyTimer ===" -ForegroundColor Cyan

$Scripts = Join-Path $Racine "scripts"
$Docs = Join-Path $Racine "docs"
$Images = Join-Path $Docs "images"
New-Item -ItemType Directory -Force -Path $Scripts, $Docs, $Images | Out-Null

function Deplacer([string]$source, [string]$destDir) {
    $nom = Split-Path $source -Leaf
    $dest = Join-Path $destDir $nom
    if (Test-Path -LiteralPath $dest) { Info "déjà rangé : $nom"; return }
    $suivi = $false
    if ($estGit) {
        & git ls-files --error-unmatch -- $source 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $suivi = $true }
    }
    if ($suivi) { & git mv -- $source $dest } else { Move-Item -LiteralPath $source -Destination $dest }
    Ok ("déplacé : $nom -> " + (Split-Path $destDir -Leaf) + "\")
}

# --- 1. Scripts de la racine -> scripts\
$moi = $MyInvocation.MyCommand.Path
foreach ($f in Get-ChildItem $Racine -Filter *.ps1 -File) {
    if ($moi -and ($f.FullName -eq $moi)) { continue }   # ce script reste a la racine
    Deplacer $f.FullName $Scripts
}

# --- 2. Rapports de diagnostic -> docs\
foreach ($f in @(Get-ChildItem $Racine -File | Where-Object { $_.Name -match '^(DIAGNOSTIC|diagnostic_).*\.txt$' -or $_.Name -eq 'DIAGNOSTIC.txt' })) {
    Deplacer $f.FullName $Docs
}

# --- 3. Logo
$logoPng = Join-Path $Images "logo.png"
$apercu = Join-Path $Racine "mobile\study_timer\assets\icon\apercu.png"
$icon = Join-Path $Racine "mobile\study_timer\assets\icon\icon.png"
if (-not (Test-Path $logoPng)) {
    if (Test-Path $icon) { Copy-Item $icon $logoPng; Ok "logo copié : docs\images\logo.png" }
    elseif (Test-Path $apercu) { Copy-Item $apercu $logoPng; Ok "logo copié : docs\images\logo.png" }
    else { Warn "logo introuvable : lancez d'abord scripts\Creer-Logo.ps1" }
}

# --- 4. README des scripts
$descr = [ordered]@{
    "Completer-Projet.ps1" = "Compare le projet au cahier des charges (docs/CONFORMITE.md) et génère les modules manquants (-Appliquer, -Verifier)."
    "Corriger-Boutons.ps1" = "Correctif des boutons à largeur infinie dans les pages Communauté et Planificateur."
    "Creer-Logo.ps1"       = "Dessine le logo et installe l'icône de l'application Android (-Appliquer)."
    "Organiser-Depot.ps1"  = "Range le dépôt (scripts/, docs/images/) et génère le README avec images."
    "Publier-GitHub.ps1"   = "Prépare le dépôt Git (sans secrets) et le publie sur GitHub."
    "Organiser-Projet.ps1" = "Range l'arborescence du projet et génère docs/PROJET.md."
    "Corriger-Chrono.ps1"  = "Ajoute la barre « chrono en cours » sur toutes les pages."
    "Corriger-Docker.ps1"  = "Correctifs de la configuration Docker."
    "DiagnosticProjet.ps1" = "Rapport de diagnostic du projet."
    "diagnostic.ps1"       = "Ancien script de diagnostic."
}
$lignes = New-Object System.Collections.ArrayList
[void]$lignes.Add("# Scripts")
[void]$lignes.Add("")
[void]$lignes.Add("Tous les scripts se lancent **depuis la racine du projet** (PowerShell) : ``.\scripts\NomDuScript.ps1``.")
[void]$lignes.Add("")
[void]$lignes.Add("| Script | Rôle |")
[void]$lignes.Add("|---|---|")
foreach ($f in Get-ChildItem $Scripts -Filter *.ps1 -File | Sort-Object Name) {
    $d = "(voir l'en-tête du script)"
    if ($descr.Contains($f.Name)) { $d = $descr[$f.Name] }
    [void]$lignes.Add("| ``$($f.Name)`` | $d |")
}
[void]$lignes.Add("")
[void]$lignes.Add("Les scripts de déploiement (sauvegarde, restauration, certificats) sont dans ``deploy/scripts/``.")
[System.IO.File]::WriteAllLines((Join-Path $Scripts "README.md"), $lignes, $utf8)
Ok "scripts\README.md généré"

# --- 5. README principal
$captures = @(
    @("accueil.png", "Accueil"),
    @("timer.png", "Chronomètre"),
    @("defis.png", "Défis"),
    @("communaute.png", "Communauté"),
    @("planificateur.png", "Planificateur"),
    @("mobile-connexion.png", "Connexion (mobile)")
)
$galerie = New-Object System.Collections.ArrayList
$manquantes = @()
foreach ($c in $captures) {
    if (Test-Path (Join-Path $Images $c[0])) {
        [void]$galerie.Add("<td align=`"center`"><img src=`"docs/images/$($c[0])`" width=`"260`"><br><sub>$($c[1])</sub></td>")
    } else { $manquantes += $c[0] }
}
$blocCaptures = ""
if ($galerie.Count -gt 0) {
    $rows = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $galerie.Count; $i += 3) {
        $fin = [math]::Min($i + 2, $galerie.Count - 1)
        [void]$rows.Add("<tr>" + (($galerie[$i..$fin]) -join "") + "</tr>")
    }
    $blocCaptures = "## Captures d'écran`n`n<table>`n" + ($rows -join "`n") + "`n</table>`n"
}
$logoLigne = ""
if (Test-Path $logoPng) { $logoLigne = "<p align=`"center`"><img src=`"docs/images/logo.png`" width=`"120`" alt=`"Logo Study Timer`"></p>`n`n" }

$readme = @"
$logoLigne<h1 align="center">Study Timer</h1>

<p align="center">
Application de gestion du temps d'étude : chronomètre, Pomodoro, défis entre étudiants, classements, badges, salles d'étude et planificateur.
</p>

<p align="center">
<img src="https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter" alt="Flutter">
<img src="https://img.shields.io/badge/ASP.NET%20Core-10-512BD4?logo=dotnet" alt="ASP.NET Core">
<img src="https://img.shields.io/badge/PostgreSQL-17-336791?logo=postgresql&logoColor=white" alt="PostgreSQL">
<img src="https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white" alt="Docker">
<img src="https://img.shields.io/badge/SignalR-temps%20r%C3%A9el-7C3AED" alt="SignalR">
</p>

$blocCaptures
## Fonctionnalités

| Module | Contenu |
|---|---|
| Authentification | Inscription, connexion JWT avec refresh, profil et fuseau horaire |
| Chronomètre | Focus, Pomodoro, Stopwatch ; pause/reprise ; calcul côté serveur (fiable en arrière-plan) ; reprise après redémarrage |
| Défis | Temps total, nombre de séances, série de jours, plus longue séance ; invitations ; classement par défi |
| Gamification | XP, niveaux, 8 badges, séries quotidiennes |
| Statistiques | Jour / semaine / mois, moyenne, séries, répartition par matière, calendrier d'activité (heatmap) |
| Communauté | Amis (invitation, acceptation), activité et statistiques des amis, confidentialité réglable |
| Salles d'étude | Salles publiques ou privées (code), statut des participants, chat |
| Planificateur | Tâches avec échéance, priorité, durée estimée, tâches en retard, association à une séance |
| Notifications | Centre de notifications (invitations, acceptations) |

La conformité détaillée au cahier des charges est dans [docs/CONFORMITE.md](docs/CONFORMITE.md).

## Architecture

``````mermaid
flowchart LR
    A["Application Flutter<br/>Android / Web / Windows"] -->|"HTTP + JSON + JWT"| B["API ASP.NET Core"]
    A -. "WebSocket" .-> H["SignalR /hubs/study"]
    H --- B
    B --> D[("PostgreSQL")]
    N["Nginx (TLS)"] --> B
    N --> W["Application web Flutter"]
``````

| Couche | Technologie |
|---|---|
| Mobile / web | Flutter, Dart, dio |
| API | ASP.NET Core (net10.0), Entity Framework Core, Swagger |
| Base de données | PostgreSQL |
| Temps réel | SignalR |
| Déploiement | Docker Compose, Nginx, sauvegardes quotidiennes |
| Qualité | xUnit (tests API et règles métier), flutter test, GitHub Actions |

## Démarrage rapide

### 1. Backend

``````powershell
# secrets hors du code (une seule fois)
dotnet user-secrets set "Jwt:Key" "une-cle-de-32-caracteres-minimum-xxxxxxxx" --project backend/StudyTimer.Api
dotnet user-secrets set "ConnectionStrings:Default" "Host=localhost;Database=studytimer;Username=studyuser;Password=..." --project backend/StudyTimer.Api

dotnet run --project backend/StudyTimer.Api --urls http://0.0.0.0:5293
``````

Swagger : http://localhost:5293/swagger

### 2. Application

``````powershell
cd mobile/study_timer
flutter pub get
flutter run -d chrome
# téléphone Android (même Wi-Fi que le PC) :
flutter run --dart-define=API_URL=http://<IP-DU-PC>:5293
``````

### 3. Déploiement (Docker + Nginx + TLS)

``````powershell
.\deploy\scripts\New-Secrets.ps1 -PublicUrl https://votre-domaine   # génère .env (ne jamais le commiter)
docker compose up -d --build
``````

Voir [GUIDE.md](GUIDE.md) pour l'installation et l'administration complètes.

## Tests

``````powershell
dotnet test backend/StudyTimer.slnx
cd mobile/study_timer ; flutter test
``````

## Scripts

Les scripts d'aide sont dans [scripts/](scripts/README.md) : diagnostic de conformité, génération de modules, logo, publication GitHub.

## Structure du dépôt

``````text
backend/            API ASP.NET Core (Api, Domain, Infrastructure, Tests)
mobile/study_timer/ Application Flutter
deploy/             Nginx, sauvegarde / restauration, certificats de test
scripts/            Scripts PowerShell d'aide
docs/               Documentation, conformité, images
docker-compose.yml  PostgreSQL + API + Nginx + sauvegardes
``````

## Feuille de route

- Speed Race et code de partage des défis
- Photo de profil, suppression de compte
- Notifications locales et mode hors-ligne
- Internationalisation français / anglais / arabe
- Ambiances sonores, version iOS, assistant IA

## Auteur

Projet réalisé dans le cadre d'un mini-projet de développement mobile avancé.
"@

$cible = Join-Path $Racine "README.md"
if (Test-Path $cible) {
    $actuel = [System.IO.File]::ReadAllText($cible, [System.Text.Encoding]::UTF8)
    if ($actuel -notmatch 'Study Timer</h1>') { Copy-Item $cible ($cible + ".bak-depot") -Force; Info "ancien README sauvegardé : README.md.bak-depot" }
}
[System.IO.File]::WriteAllText($cible, $readme, $utf8)
Ok "README.md généré"

if ($manquantes.Count -gt 0) {
    Write-Host ""
    Warn "Captures d'écran manquantes (ajoutez-les dans docs\images\ puis relancez le script) :"
    foreach ($m in $manquantes) { Write-Host "       $m" -ForegroundColor Yellow }
}

# --- 6. Publication
if ($Publier) {
    if (-not $estGit) { Warn "pas de dépôt Git ici : lancez d'abord .\scripts\Publier-GitHub.ps1"; exit 1 }
    & git add -A
    if (@(& git diff --cached --name-only).Count -gt 0) {
        & git commit -m $Message | Out-Null
        Ok "commit créé"
    } else { Info "rien à commiter" }
    & git push
    if ($LASTEXITCODE -eq 0) { Ok "publié sur GitHub" } else { Warn "git push a échoué (essayez : git push -u origin main)" }
} else {
    Write-Host ""
    Write-Host "Terminé. Pour publier : .\Organiser-Depot.ps1 -Publier   (ou git add -A ; git commit -m `"organisation`" ; git push)" -ForegroundColor Cyan
}
