# Organiser-Projet.ps1
# Compatible Windows PowerShell 5.1 (fichier volontairement en ASCII pur : pas d'accents).
#
# Ce que fait le script :
#   1. Range les scripts et zips en vrac a la racine (simulation par defaut)
#   2. (option) Lance les corrections automatiques et le diagnostic des erreurs
#   3. Extrait le code Dart de l'app mobile dans docs\CODE-MOBILE.txt (pour le bug du chrono)
#   4. Genere docs\PROJET.md : guide du projet et des technologies
#
# Utilisation (depuis la racine du projet) :
#   .\Organiser-Projet.ps1                          -> simulation + generation des docs
#   .\Organiser-Projet.ps1 -Appliquer               -> range vraiment les fichiers
#   .\Organiser-Projet.ps1 -Appliquer -Diagnostic   -> + build/tests/analyse et rapport d'erreurs
#   .\Organiser-Projet.ps1 -CorrigerAuto            -> + dart format / dart fix / dotnet format
#   .\Organiser-Projet.ps1 -Annuler                 -> remet les fichiers deplaces a leur place

param(
    [string]$Chemin = ".",
    [switch]$Appliquer,
    [switch]$Diagnostic,
    [switch]$CorrigerAuto,
    [switch]$Annuler
)

$Racine  = (Resolve-Path $Chemin).Path
$MoiMeme = $PSCommandPath
$Docs    = Join-Path $Racine "docs"
$Journal = Join-Path $Docs "deplacements.log"
$Date    = Get-Date -Format "yyyy-MM-dd HH:mm"
$Ignorer = @(".git", "node_modules", "bin", "obj", ".dart_tool", "build", ".idea", ".vscode", "__pycache__", "venv", ".venv")
$NePasOuvrir = @("android", "windows", "web", "ios", "linux", "macos")

if (-not (Test-Path $Docs)) { New-Item -ItemType Directory -Path $Docs | Out-Null }

function Titre($texte) {
    Write-Host ""
    Write-Host ("=== " + $texte + " ===") -ForegroundColor Cyan
}

function Test-GitPropre {
    if (-not (Test-Path (Join-Path $Racine ".git"))) { return $true }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $true }
    $etat = & git -C $Racine status --porcelain 2>$null
    if ($etat) {
        Write-Host "Attention : des modifications Git ne sont pas enregistrees (commit)." -ForegroundColor Yellow
        $rep = Read-Host "Continuer quand meme ? (o/n)"
        return ($rep -eq "o")
    }
    return $true
}

# ---------------------------------------------------------------
# ANNULER les deplacements
# ---------------------------------------------------------------
if ($Annuler) {
    Titre "ANNULATION DES DEPLACEMENTS"
    if (-not (Test-Path $Journal)) {
        Write-Host "Aucun journal trouve : rien a annuler."
        return
    }
    $lignes = @(Get-Content $Journal -Encoding UTF8)
    [array]::Reverse($lignes)
    foreach ($l in $lignes) {
        $p = $l -split '\|'
        if ($p.Count -eq 2 -and (Test-Path -LiteralPath $p[1])) {
            Move-Item -LiteralPath $p[1] -Destination $p[0]
            Write-Host ("  remis en place : " + $p[0])
        }
    }
    Remove-Item $Journal
    Write-Host "Termine."
    return
}

if ($Appliquer -or $CorrigerAuto) {
    if (-not (Test-GitPropre)) { Write-Host "Arret demande."; return }
}

# ---------------------------------------------------------------
# 1. ORGANISATION DES FICHIERS A LA RACINE
# ---------------------------------------------------------------
Titre "1. ORGANISATION DES FICHIERS A LA RACINE"
if (-not $Appliquer) {
    Write-Host "(Mode simulation : rien n'est deplace. Ajoute -Appliquer pour ranger.)" -ForegroundColor Yellow
}

$regles = @(
    @("Fix-*.ps1",               "scripts\correctifs-anciens"),
    @("Add-Phase2Migration.ps1", "scripts\correctifs-anciens"),
    @("Apply-Update.ps1",        "scripts\correctifs-anciens"),
    @("analyse_projet*.ps1",     "scripts\outils"),
    @("Diagnostiquer-*.ps1",     "scripts\outils"),
    @("Export-*.ps1",            "scripts\outils"),
    @("Reset-*.ps1",             "scripts\base-de-donnees"),
    @("Set-DevSecrets.ps1",      "scripts\base-de-donnees"),
    @("*.zip",                   "archive")
)

$nbDeplaces = 0
foreach ($r in $regles) {
    $fichiers = @(Get-ChildItem -Path $Racine -File -Filter $r[0] -ErrorAction SilentlyContinue)
    foreach ($f in $fichiers) {
        if ($f.FullName -eq $MoiMeme) { continue }
        $dossierDest = Join-Path $Racine $r[1]
        $dest = Join-Path $dossierDest $f.Name
        if (Test-Path -LiteralPath $dest) {
            Write-Host ("  ignore (existe deja) : " + $f.Name)
            continue
        }
        if ($Appliquer) {
            if (-not (Test-Path $dossierDest)) { New-Item -ItemType Directory -Path $dossierDest -Force | Out-Null }
            Move-Item -LiteralPath $f.FullName -Destination $dest
            Add-Content -Path $Journal -Value ($f.FullName + "|" + $dest) -Encoding UTF8
            Write-Host ("  deplace : " + $f.Name + "  ->  " + $r[1])
        }
        else {
            Write-Host ("  [simulation] " + $f.Name + "  ->  " + $r[1])
        }
        $nbDeplaces++
    }
}
if ($nbDeplaces -eq 0) { Write-Host "  Rien a ranger." }
if ($Appliquer -and $nbDeplaces -gt 0) {
    Write-Host "  Pour tout remettre : .\Organiser-Projet.ps1 -Annuler" -ForegroundColor Yellow
    Write-Host "  Attention : un script deplace qui utilise des chemins relatifs doit etre lance depuis la racine." -ForegroundColor Yellow
}

# ---------------------------------------------------------------
# 2. CORRECTIONS AUTOMATIQUES + DIAGNOSTIC
# ---------------------------------------------------------------
$rapport = Join-Path $Docs "RAPPORT-ERREURS.txt"

function Lancer($titre, $sousDossier, $exe, $arguments) {
    $dossier = Join-Path $Racine $sousDossier
    if (-not (Test-Path $dossier)) {
        Write-Host ("  ignore (dossier absent) : " + $titre)
        return
    }
    if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) {
        Write-Host ("  ignore (" + $exe + " introuvable) : " + $titre)
        return
    }
    Write-Host ("  en cours : " + $titre) -ForegroundColor Gray
    Push-Location $dossier
    $texte = ""
    try { $texte = (& $exe @arguments 2>&1 | Out-String) } catch { $texte = $_.Exception.Message }
    Pop-Location
    Add-Content -Path $rapport -Value ("##### " + $titre + " #####") -Encoding UTF8
    Add-Content -Path $rapport -Value $texte -Encoding UTF8
    $nb = @($texte -split "`n" | Where-Object { $_ -match ': error |^\s*error\s|Failed!|Some tests failed' }).Count
    if ($nb -gt 0) {
        Write-Host ("    -> " + $nb + " ligne(s) d'erreur") -ForegroundColor Red
    }
    else {
        Write-Host "    -> aucune erreur detectee" -ForegroundColor Green
    }
}

if ($Diagnostic -or $CorrigerAuto) {
    Set-Content -Path $rapport -Value ("RAPPORT du " + $Date) -Encoding UTF8
}

if ($CorrigerAuto) {
    Titre "2a. CORRECTIONS AUTOMATIQUES (format + fixes simples)"
    Lancer "dart format"   "mobile\study_timer" "dart"   @("format", "lib", "test")
    Lancer "dart fix"      "mobile\study_timer" "dart"   @("fix", "--apply")
    Lancer "dotnet format" "backend"            "dotnet" @("format")
}

if ($Diagnostic) {
    Titre "2b. DIAGNOSTIC DES ERREURS"
    Lancer "dotnet build"    "backend"            "dotnet"  @("build")
    Lancer "dotnet test"     "backend"            "dotnet"  @("test")
    Lancer "flutter analyze" "mobile\study_timer" "flutter" @("analyze")
    Lancer "flutter test"    "mobile\study_timer" "flutter" @("test")
    Write-Host ("  Rapport complet : " + $rapport)
}

# ---------------------------------------------------------------
# 3. CODE DE L'APP MOBILE (pour le bug du chrono)
# ---------------------------------------------------------------
Titre "3. CODE DE L'APP MOBILE (bug : le chrono continue sur les autres pages)"
$lib = Join-Path $Racine "mobile\study_timer\lib"
$sortieCode = Join-Path $Docs "CODE-MOBILE.txt"
if (Test-Path $lib) {
    $dart = @(Get-ChildItem -Path $lib -Recurse -File -Filter *.dart)
    $chrono = @($dart | Where-Object { Select-String -LiteralPath $_.FullName -Pattern 'Timer\.periodic|Stopwatch|Timer\(' -Quiet })
    Write-Host ("  " + $dart.Count + " fichier(s) Dart trouves dans lib")
    if ($chrono.Count -gt 0) {
        Write-Host "  Fichiers qui contiennent le chrono :" -ForegroundColor Green
        foreach ($f in $chrono) { Write-Host ("    - " + $f.FullName.Substring($Racine.Length + 1)) }
    }
    else {
        Write-Host "  Aucun Timer.periodic / Stopwatch trouve (le chrono est peut-etre gere autrement)." -ForegroundColor Yellow
    }
    $ordre = @($chrono) + @($dart | Where-Object { $chrono.FullName -notcontains $_.FullName })
    $contenu = New-Object System.Collections.Generic.List[string]
    $contenu.Add("CODE DE L'APP MOBILE - genere le " + $Date)
    $contenu.Add("Les fichiers qui contiennent le chrono sont en premier.")
    foreach ($f in $ordre) {
        $contenu.Add("")
        $contenu.Add("=" * 70)
        $contenu.Add("FICHIER : " + $f.FullName.Substring($Racine.Length + 1))
        $contenu.Add("=" * 70)
        $contenu.Add((Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8))
    }
    Set-Content -Path $sortieCode -Value $contenu -Encoding UTF8
    Write-Host ("  Code enregistre dans : " + $sortieCode)
}
else {
    Write-Host "  Dossier mobile\study_timer\lib introuvable."
}

# ---------------------------------------------------------------
# 4. GENERATION DE docs\PROJET.md
# ---------------------------------------------------------------
Titre "4. GENERATION DE docs\PROJET.md"

function Get-Pubspec($fichier) {
    $res = @{ dependencies = @(); dev_dependencies = @() }
    $section = ""
    foreach ($l in (Get-Content -LiteralPath $fichier -Encoding UTF8)) {
        if ($l -match '^([A-Za-z_]+):') { $section = $Matches[1]; continue }
        if (($section -eq "dependencies" -or $section -eq "dev_dependencies") -and $l -match '^  ([A-Za-z0-9_]+):') {
            $res[$section] += $Matches[1]
        }
    }
    return $res
}

function Get-Arbre($dossier, $niveau, $prefixe) {
    if ($niveau -ge 6) { return }
    $elements = @(Get-ChildItem -LiteralPath $dossier -Force -ErrorAction SilentlyContinue | Where-Object { $Ignorer -notcontains $_.Name })
    $dossiers = @($elements | Where-Object { $_.PSIsContainer } | Sort-Object Name)
    $fichiers = @($elements | Where-Object { -not $_.PSIsContainer } | Sort-Object Name)
    foreach ($d in $dossiers) {
        if ($NePasOuvrir -contains $d.Name) {
            $prefixe + $d.Name + "/  (plateforme, non detaille)"
        }
        else {
            $prefixe + $d.Name + "/"
            Get-Arbre $d.FullName ($niveau + 1) ($prefixe + "    ")
        }
    }
    $n = 0
    foreach ($f in $fichiers) {
        $n++
        if ($n -le 12) { $prefixe + $f.Name }
    }
    if ($fichiers.Count -gt 12) { $prefixe + "... (+" + ($fichiers.Count - 12) + " autres fichiers)" }
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add("# StudyTimer - Guide du projet")
$md.Add("")
$md.Add("Document genere automatiquement le " + $Date + " par Organiser-Projet.ps1.")
$md.Add("Relance le script pour le mettre a jour.")
$md.Add("")

# --- 1. Sujet
$md.Add("## 1. De quoi parle le projet ?")
$md.Add("")
$md.Add("StudyTimer est une application de minuteur pour etudier : l'utilisateur lance un chrono de session de travail.")
$gami = @(Get-ChildItem -Path $Racine -Recurse -File -Filter "Gamification*.cs" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' })
if ($gami.Count -gt 0) {
    $md.Add("Le backend contient aussi un module de gamification (" + $gami[0].Name + ") avec ses tests.")
}
if (Test-Path (Join-Path $Racine "GUIDE.md")) {
    $md.Add("Voir aussi GUIDE.md a la racine.")
}
$md.Add("")

# --- 2. Architecture
$md.Add("## 2. Architecture : qui fait quoi ?")
$md.Add("")
$md.Add("| Dossier | Role |")
$md.Add("|---|---|")
$roles = [ordered]@{
    "backend"                           = "Serveur (API) en C# / .NET"
    "backend\StudyTimer.Api"            = "Point d'entree de l'API : controleurs, configuration (Program.cs, appsettings.json)"
    "backend\StudyTimer.Domain"         = "Coeur metier : les entites (objets de l'application)"
    "backend\StudyTimer.Infrastructure" = "Acces a la base de donnees (AppDbContext, migrations)"
    "backend\StudyTimer.Tests"          = "Tests automatiques du backend"
    "mobile\study_timer"                = "Application Flutter (Dart) : Android, Web, Windows"
    "mobile\study_timer\lib"            = "Code de l'application : ecrans, logique, chrono"
    "deploy"                            = "Deploiement : nginx, scripts de sauvegarde/restauration, certificats"
    "docs"                              = "Documentation et rapports generes"
    "scripts"                           = "Scripts PowerShell de maintenance (apres rangement)"
    "archive"                           = "Anciennes archives .zip (apres rangement)"
    "diagnostic-report"                 = "Sorties des anciens diagnostics (build, tests, analyse)"
}
foreach ($k in $roles.Keys) {
    if (Test-Path (Join-Path $Racine $k)) {
        $md.Add("| " + $k + " | " + $roles[$k] + " |")
    }
}
$md.Add("")

# --- 3. Technologies
$md.Add("## 3. Technologies utilisees")
$md.Add("")
$md.Add("### Backend (C# / .NET)")
$md.Add("")
$projets = @(Get-ChildItem -Path $Racine -Recurse -File -Filter *.csproj -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' })
foreach ($p in $projets) {
    $md.Add("**" + $p.BaseName + "**")
    try {
        [xml]$x = Get-Content -LiteralPath $p.FullName -Raw -Encoding UTF8
        $tf = @($x.Project.PropertyGroup | ForEach-Object { $_.TargetFramework } | Where-Object { $_ })
        if ($tf.Count -gt 0) { $md.Add("- Cadre .NET : " + ($tf -join ", ")) }
        $refs = @($x.Project.ItemGroup | ForEach-Object { $_.PackageReference } | Where-Object { $_ })
        foreach ($ref in $refs) { $md.Add("- Paquet : " + $ref.Include + " " + $ref.Version) }
    }
    catch { }
    $md.Add("")
}
if ($projets.Count -eq 0) { $md.Add("(aucun projet .csproj trouve)"); $md.Add("") }

$md.Add("### Application mobile (Flutter / Dart)")
$md.Add("")
$pubs = @(Get-ChildItem -Path $Racine -Recurse -File -Filter pubspec.yaml -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(\.dart_tool|build|ephemeral|\.symlinks)\\' })
foreach ($pub in $pubs) {
    $info = Get-Pubspec $pub.FullName
    $md.Add("**" + $pub.Directory.Name + "**")
    foreach ($d in $info["dependencies"]) { $md.Add("- Dependance : " + $d) }
    foreach ($d in $info["dev_dependencies"]) { $md.Add("- Dependance de dev : " + $d) }
    $md.Add("")
}
if ($pubs.Count -eq 0) { $md.Add("(aucun pubspec.yaml trouve)"); $md.Add("") }

$md.Add("### Docker et deploiement")
$md.Add("")
$composes = @(Get-ChildItem -Path $Racine -Recurse -File -Filter "docker-compose*.yml" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(node_modules|\.git)\\' })
foreach ($c in $composes) {
    $md.Add("**" + $c.Name + "**")
    $section = ""
    foreach ($l in (Get-Content -LiteralPath $c.FullName -Encoding UTF8)) {
        if ($l -match '^([A-Za-z_]+):') { $section = $Matches[1] }
        elseif ($section -eq "services" -and $l -match '^  ([A-Za-z0-9_-]+):\s*$') { $md.Add("- Service : " + $Matches[1]) }
        if ($l -match '^\s+image:\s*(\S+)') { $md.Add("  - Image : " + $Matches[1]) }
    }
    $md.Add("")
}
if (Test-Path (Join-Path $Racine "deploy\nginx")) { $md.Add("- nginx est utilise comme serveur web / proxy (deploy\nginx).") }
if (Test-Path (Join-Path $Racine "backend\Dockerfile")) { $md.Add("- Le backend a un Dockerfile (execution en conteneur).") }
$md.Add("")

# --- 4. Structure
$md.Add("## 4. Structure des fichiers")
$md.Add("")
$md.Add('```')
foreach ($ligne in (Get-Arbre $Racine 0 "")) { $md.Add($ligne) }
$md.Add('```')
$md.Add("")

# --- 5. Scripts
$md.Add("## 5. Scripts disponibles")
$md.Add("")
$scripts = @(Get-ChildItem -Path $Racine -Recurse -File -Include *.ps1, *.sh -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(bin|obj|\.dart_tool|build|node_modules|\.git)\\' } | Sort-Object FullName)
foreach ($s in $scripts) { $md.Add("- " + $s.FullName.Substring($Racine.Length + 1)) }
$md.Add("")

# --- 6 et 7 : texte fixe
$fixe = @'
## 6. Commandes habituelles

Commandes classiques pour ce type de projet (a verifier avec GUIDE.md) :

```
# Backend
cd backend
dotnet build
dotnet test
dotnet run --project StudyTimer.Api

# Application mobile
cd mobile\study_timer
flutter pub get
flutter analyze
flutter test
flutter run -d windows

# Base de donnees et services
docker compose up -d
```

## 7. Probleme connu : le chrono ne s'arrete pas

Symptome : quand le chrono est lance et que l'on change de page, il continue de tourner et on ne peut plus l'arreter.

Cause probable : le Timer vit dans une page (ou dans une variable globale) et n'est jamais annule, ou alors il n'existe aucun bouton d'arret accessible depuis les autres pages.

Correction habituelle :
- garder le chrono dans UN seul service partage (par exemple un ChangeNotifier fourni au demarrage de l'app) ;
- afficher une barre "chrono en cours" avec un bouton Stop sur toutes les pages ;
- annuler le Timer (timer.cancel()) dans dispose() si le chrono est local a une page.

Pour une correction precise, envoyer le fichier docs\CODE-MOBILE.txt.
'@
foreach ($ligne in ($fixe -split "`r?`n")) { $md.Add($ligne) }

$fichierMd = Join-Path $Docs "PROJET.md"
Set-Content -Path $fichierMd -Value $md -Encoding UTF8
Write-Host ("  Guide genere : " + $fichierMd) -ForegroundColor Green

# ---------------------------------------------------------------
Titre "TERMINE"
Write-Host "Fichiers generes dans le dossier docs :"
foreach ($nom in @("PROJET.md", "CODE-MOBILE.txt", "RAPPORT-ERREURS.txt")) {
    $f = Join-Path $Docs $nom
    if (Test-Path $f) { Write-Host ("  - " + $f) }
}
