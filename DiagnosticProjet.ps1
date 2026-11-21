param(
    [Parameter(Mandatory=$true)]
    [string]$ProjectPath
)

$ErrorActionPreference = "SilentlyContinue"

Write-Host "`n====================================" -ForegroundColor Cyan
Write-Host "       DIAGNOSTIC AUTOMATIQUE" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan

if (!(Test-Path -LiteralPath $ProjectPath)) {
    Write-Host "ERREUR : Dossier introuvable !" -ForegroundColor Red
    exit 1
}

$ProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$Report = Join-Path $ProjectPath "DIAGNOSTIC.txt"

$Files = Get-ChildItem -LiteralPath $ProjectPath -Recurse -File |
    Where-Object {
        $_.FullName -notmatch '[\\/](node_modules|\.git|bin|obj|build|dist|\.dart_tool|\.venv|venv|packages)[\\/]'
    }

Write-Host "`n[1] Structure du projet..." -ForegroundColor Yellow
$Files | ForEach-Object { Write-Host $_.FullName }

Write-Host "`n[2] Analyse des langages..." -ForegroundColor Yellow
$Languages = $Files | Group-Object Extension | Sort-Object Count -Descending
$LanguageReport = ($Languages | ForEach-Object {
    "$($_.Name) : $($_.Count) fichier(s)"
}) -join "`n"
$Languages | Format-Table Name, Count -AutoSize

Write-Host "`n[3] Recherche des technologies..." -ForegroundColor Yellow
$TechnologyFiles = @{
    "Flutter" = @("pubspec.yaml")
    "Node.js" = @("package.json")
    "ASP.NET" = @("*.csproj", "*.sln")
    "Android" = @("AndroidManifest.xml", "build.gradle", "build.gradle.kts")
    "Arduino" = @("*.ino")
    "Docker" = @("Dockerfile", "docker-compose.yml", "compose.yaml")
    "Python" = @("*.py", "requirements.txt", "pyproject.toml")
    "Java" = @("*.java", "pom.xml", "build.gradle")
    "PHP" = @("*.php", "composer.json")
}
$FoundTech = @()
foreach ($tech in $TechnologyFiles.Keys) {
    $found = $false
    foreach ($pattern in $TechnologyFiles[$tech]) {
        if ($Files | Where-Object { $_.Name -like $pattern } | Select-Object -First 1) {
            $found = $true
            break
        }
    }
    if ($found) {
        $FoundTech += $tech
        Write-Host "[+] $tech détecté" -ForegroundColor Green
    }
}

# Recherche de mots-clés dans les noms et le contenu des fichiers texte.
Write-Host "`n[4] Recherche du sujet du projet..." -ForegroundColor Yellow
$Keywords = [ordered]@{
    "Internet des objets (IoT)" = '\b(esp32|esp8266|arduino|mqtt|sensor|capteur|temperature|humidity|iot)\b'
    "Application éducative / gestion des études" = '\b(student|etudiant|course|quiz|learning|study|pomodoro|focus|matiere)\b'
    "E-commerce / vente en ligne" = '\b(product|cart|payment|commande|shop|ecommerce|checkout)\b'
    "Gestion de stock" = '\b(stock|inventory|warehouse|quantity|inventaire)\b'
    "Réseau social / messagerie" = '\b(post|comment|message|friend|profile|chat)\b'
    "Gestion financière" = '\b(budget|expense|income|transaction|invoice|facture)\b'
    "Intelligence artificielle / machine learning" = '\b(model|prediction|training|tensorflow|classification|machine learning|pytorch)\b'
    "Gestion médicale" = '\b(patient|doctor|medical|hospital|rendezvous|appointment)\b'
    "Gestion de bibliothèque" = '\b(book|library|bibliotheque|emprunt|borrow)\b'
}
$TextFiles = $Files | Where-Object {
    $_.Extension -in @(".py", ".dart", ".java", ".kt", ".js", ".ts", ".cs", ".php",
        ".html", ".sql", ".json", ".xml", ".md", ".txt", ".yaml", ".yml") -and
    $_.Length -lt 500000
}
$AllText = (($Files | ForEach-Object { $_.Name }) -join "`n") + "`n"
foreach ($file in $TextFiles) {
    $AllText += "`n" + (Get-Content -LiteralPath $file.FullName -Raw)
}
$Scores = foreach ($entry in $Keywords.GetEnumerator()) {
    $count = [regex]::Matches($AllText, $entry.Value, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Count
    [pscustomobject]@{ Subject = $entry.Key; Score = $count }
}
$BestSubject = $Scores | Sort-Object Score -Descending | Select-Object -First 1
if ($BestSubject -and $BestSubject.Score -gt 0) {
    $Subject = $BestSubject.Subject
} else {
    $Subject = "Sujet non identifié automatiquement (analyse manuelle nécessaire)"
}
Write-Host "SUJET DETECTE : $Subject" -ForegroundColor Green

Write-Host "`n[5] Fichiers importants..." -ForegroundColor Yellow
$Important = $Files | Where-Object {
    $_.Name -match '^(README|main|app|config|database|server|pubspec|package)' -or
    $_.Extension -in @(".sln", ".csproj")
}
$ImportantNames = @($Important | ForEach-Object { $_.FullName })
$ImportantNames | ForEach-Object { Write-Host "[+] $_" -ForegroundColor Cyan }

Write-Host "`n[6] Vérifications structurelles..." -ForegroundColor Yellow
$Problems = @()
if ($Files.Count -eq 0) { $Problems += "Aucun fichier trouvé dans le dossier." }
if ($FoundTech.Count -eq 0) { $Problems += "Technologies non identifiées automatiquement." }
if (!($Files | Where-Object { $_.Name -match '^README(\..*)?$' } | Select-Object -First 1)) {
    $Problems += "README absent : documentation du projet manquante."
}
if (!($Files | Where-Object { $_.Name -match '(^|\.)(test|spec)\.' -or $_.Name -match 'Tests?' } | Select-Object -First 1)) {
    $Problems += "Aucun fichier de test détecté par son nom."
}
if ($Problems.Count -eq 0) { $Problems += "Aucun problème structurel évident détecté par les contrôles simples." }
$Problems | ForEach-Object { Write-Host "[-] $_" -ForegroundColor Red }

Write-Host "`n[7] Génération du rapport..." -ForegroundColor Yellow
$ReportContent = @"
========================================
       RAPPORT DE DIAGNOSTIC
========================================

PROJET :
$ProjectPath

NOMBRE DE FICHIERS :
$($Files.Count)

SUJET ESTIME :
$Subject

LANGAGES / EXTENSIONS :
$LanguageReport

TECHNOLOGIES DETECTEES :
$($FoundTech -join ", ")

FICHIERS IMPORTANTS :
$($ImportantNames -join "`n")

VERIFICATIONS STRUCTURELLES :
$($Problems -join "`n")

DATE :
$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

NOTE :
Le sujet est estime a partir de mots-cles et de fichiers detectes.
Ce diagnostic ne garantit pas la detection de tous les bugs et ne remplace
pas une analyse complete du code et de son execution.
========================================
"@
$ReportContent | Out-File -LiteralPath $Report -Encoding utf8

Write-Host "`n====================================" -ForegroundColor Green
Write-Host "DIAGNOSTIC TERMINE !" -ForegroundColor Green
Write-Host "Rapport : $Report" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Green
