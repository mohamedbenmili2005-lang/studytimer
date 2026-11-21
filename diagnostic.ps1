<#
.SYNOPSIS
    Diagnostic de projet + extraction complète du code source
.DESCRIPTION
    Analyse la structure d'un projet, détecte le type, compte les lignes,
    liste les fichiers et génère un dump de tout le code source.
.PARAMETER ProjectPath
    Chemin du projet (par défaut = dossier courant)
.PARAMETER OutputFolder
    Dossier de sortie des rapports (par défaut = .\ProjectDiagnostic)
.PARAMETER IncludeCodeDump
    Si $true, crée un fichier unique contenant tout le code
#>

param(
    [string]$ProjectPath = (Get-Location).Path,
    [string]$OutputFolder = ".\ProjectDiagnostic",
    [switch]$IncludeCodeDump = $true
)

# ============================================================
# CONFIGURATION
# ============================================================
$ExcludeDirs = @(
    'node_modules', '.git', '.svn', '.hg', 'bin', 'obj', 'dist', 'build',
    '.vs', '.vscode', '.idea', 'coverage', '__pycache__', '.pytest_cache',
    'venv', '.venv', 'env', '.env', 'target', 'out', 'packages',
    'bower_components', '.next', '.nuxt', 'vendor', 'tmp', 'temp'
)

$SourceExtensions = @(
    '.ps1', '.psm1', '.psd1',                  # PowerShell
    '.cs', '.csproj', '.sln', '.fs', '.vb',     # .NET
    '.js', '.ts', '.jsx', '.tsx', '.mjs', '.cjs', # JS/TS
    '.py', '.pyw',                              # Python
    '.java', '.kt', '.scala',                   # JVM
    '.go', '.rs', '.cpp', '.c', '.h', '.hpp',   # System
    '.php', '.rb', '.swift', '.m', '.mm',       # Autres
    '.html', '.css', '.scss', '.sass', '.less', # Web
    '.vue', '.svelte', '.astro',
    '.sql', '.json', '.xml', '.yml', '.yaml',  # Config / data
    '.md', '.txt', '.toml', '.ini', '.cfg',
    '.sh', '.bash', '.dockerfile', 'Dockerfile'
)

# ============================================================
# FONCTIONS UTILITAIRES
# ============================================================
function Write-Color {
    param([string]$Text, [string]$Color = "White")
    Write-Host $Text -ForegroundColor $Color
}

function Get-RelativePath {
    param([string]$FullPath, [string]$BasePath)
    $FullPath.Substring($BasePath.Length).TrimStart('\', '/')
}

function Should-Exclude {
    param([string]$Path)
    foreach ($dir in $ExcludeDirs) {
        if ($Path -match [regex]::Escape("\$dir\") -or $Path -match [regex]::Escape("/$dir/")) {
            return $true
        }
    }
    return $false
}

# ============================================================
# DÉBUT DU SCRIPT
# ============================================================
Clear-Host
Write-Color "================================================" "Cyan"
Write-Color "   DIAGNOSTIC DE PROJET + EXTRACTION DE CODE" "Cyan"
Write-Color "================================================" "Cyan"
Write-Host ""

$ProjectPath = Resolve-Path $ProjectPath -ErrorAction Stop
Write-Color "Projet analysé : $ProjectPath" "Yellow"

# Création du dossier de sortie
if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder | Out-Null
}
$OutputFolder = Resolve-Path $OutputFolder
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = Join-Path $OutputFolder "diagnostic_$timestamp.txt"
$codeDumpFile = Join-Path $OutputFolder "code_complet_$timestamp.txt"

# ============================================================
# 1. DÉTECTION DU TYPE DE PROJET
# ============================================================
Write-Color "`n[1/6] Détection du type de projet..." "Green"

$projectType = "Inconnu"
$indicators = @{
    "Node.js / JavaScript" = @("package.json")
    "TypeScript"           = @("tsconfig.json")
    ".NET / C#"            = @("*.csproj", "*.sln")
    "Python"               = @("requirements.txt", "pyproject.toml", "setup.py", "Pipfile")
    "Java / Maven"         = @("pom.xml")
    "Java / Gradle"        = @("build.gradle", "build.gradle.kts")
    "Go"                   = @("go.mod")
    "Rust"                 = @("Cargo.toml")
    "PHP / Composer"       = @("composer.json")
    "Ruby"                 = @("Gemfile")
    "Docker"               = @("Dockerfile", "docker-compose.yml")
}

$detected = @()
foreach ($type in $indicators.Keys) {
    foreach ($pattern in $indicators[$type]) {
        $found = Get-ChildItem -Path $ProjectPath -Filter $pattern -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { -not (Should-Exclude $_.FullName) } |
                 Select-Object -First 1
        if ($found) {
            $detected += $type
            break
        }
    }
}
$projectType = if ($detected.Count -gt 0) { ($detected | Select-Object -Unique) -join " + " } else { "Inconnu / Générique" }

Write-Color "  → Type détecté : $projectType" "White"

# ============================================================
# 2. STRUCTURE DU PROJET
# ============================================================
Write-Color "`n[2/6] Analyse de la structure..." "Green"

$allFiles = Get-ChildItem -Path $ProjectPath -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { -not (Should-Exclude $_.FullName) }

$totalFiles = $allFiles.Count
$totalSize = ($allFiles | Measure-Object -Property Length -Sum).Sum
$totalSizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Color "  → Fichiers trouvés : $totalFiles" "White"
Write-Color "  → Taille totale    : $totalSizeMB MB" "White"

# ============================================================
# 3. STATISTIQUES PAR EXTENSION
# ============================================================
Write-Color "`n[3/6] Statistiques par type de fichier..." "Green"

$stats = $allFiles | Group-Object Extension | Sort-Object Count -Descending |
         Select-Object Name, Count, @{N='SizeMB';E={[math]::Round(($_.Group | Measure-Object Length -Sum).Sum / 1MB, 2)}}

# ============================================================
# 4. COMPTAGE DES LIGNES DE CODE
# ============================================================
Write-Color "`n[4/6] Comptage des lignes de code..." "Green"

$sourceFiles = $allFiles | Where-Object {
    $ext = $_.Extension.ToLower()
    $name = $_.Name
    ($SourceExtensions -contains $ext) -or ($name -eq "Dockerfile") -or ($name -eq "Makefile")
}

$lineStats = @{}
$totalLines = 0
$codeByLanguage = @{}

foreach ($file in $sourceFiles) {
    try {
        $content = Get-Content -Path $file.FullName -ErrorAction Stop
        $lines = $content.Count
        $totalLines += $lines

        $ext = if ($file.Extension) { $file.Extension.ToLower() } else { $file.Name }
        if (-not $lineStats.ContainsKey($ext)) { $lineStats[$ext] = 0 }
        $lineStats[$ext] += $lines
    } catch {
        # Fichier binaire ou inaccessible
    }
}

Write-Color "  → Lignes de code totales : $totalLines" "White"

# ============================================================
# 5. GÉNÉRATION DU RAPPORT
# ============================================================
Write-Color "`n[5/6] Génération du rapport..." "Green"

$report = @"
================================================
   RAPPORT DE DIAGNOSTIC DE PROJET
================================================
Date              : $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
Chemin du projet  : $ProjectPath
Type de projet    : $projectType

------------------------------------------------
RÉSUMÉ
------------------------------------------------
Nombre de fichiers : $totalFiles
Taille totale      : $totalSizeMB MB
Lignes de code     : $totalLines
Fichiers source    : $($sourceFiles.Count)

------------------------------------------------
STATISTIQUES PAR EXTENSION
------------------------------------------------
$($stats | Format-Table -AutoSize | Out-String)

------------------------------------------------
LIGNES DE CODE PAR EXTENSION
------------------------------------------------
$($lineStats.GetEnumerator() | Sort-Object Value -Descending | ForEach-Object {
    "{0,-12} : {1,8} lignes" -f $_.Key, $_.Value
} | Out-String)

------------------------------------------------
ARBORESCENCE (fichiers source uniquement)
------------------------------------------------
$($sourceFiles | ForEach-Object {
    $rel = Get-RelativePath $_.FullName $ProjectPath
    $size = [math]::Round($_.Length / 1KB, 1)
    "{0,-70} {1,8} KB" -f $rel, $size
} | Out-String)

================================================
Fin du rapport
================================================
"@

$report | Out-File -FilePath $reportFile -Encoding UTF8
Write-Color "  → Rapport sauvegardé : $reportFile" "White"

# ============================================================
# 6. DUMP COMPLET DU CODE
# ============================================================
if ($IncludeCodeDump) {
    Write-Color "`n[6/6] Extraction de tout le code source..." "Green"

    $dumpHeader = @"
================================================================================
  DUMP COMPLET DU CODE SOURCE
  Projet : $ProjectPath
  Date   : $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
  Type   : $projectType
================================================================================


"@

    $dumpHeader | Out-File -FilePath $codeDumpFile -Encoding UTF8

    $count = 0
    foreach ($file in $sourceFiles) {
        $count++
        $relPath = Get-RelativePath $file.FullName $ProjectPath
        Write-Progress -Activity "Extraction du code" -Status $relPath -PercentComplete (($count / $sourceFiles.Count) * 100)

        $separator = @"

################################################################################
# FICHIER : $relPath
# Taille  : $([math]::Round($file.Length / 1KB, 1)) KB
################################################################################

"@
        $separator | Out-File -FilePath $codeDumpFile -Append -Encoding UTF8

        try {
            Get-Content -Path $file.FullName -Raw -ErrorAction Stop |
                Out-File -FilePath $codeDumpFile -Append -Encoding UTF8
        } catch {
            ">>> Impossible de lire ce fichier (binaire ou accès refusé) <<<" |
                Out-File -FilePath $codeDumpFile -Append -Encoding UTF8
        }
    }

    Write-Progress -Activity "Extraction du code" -Completed
    Write-Color "  → Code complet sauvegardé : $codeDumpFile" "White"
    Write-Color "  → $($sourceFiles.Count) fichiers extraits" "White"
}

# ============================================================
# RÉSUMÉ FINAL
# ============================================================
Write-Host ""
Write-Color "================================================" "Cyan"
Write-Color "                 TERMINÉ !" "Green"
Write-Color "================================================" "Cyan"
Write-Host ""
Write-Color "Fichiers générés :" "Yellow"
Write-Host "  • Rapport diagnostic : $reportFile"
if ($IncludeCodeDump) {
    Write-Host "  • Dump du code       : $codeDumpFile"
}
Write-Host ""
Write-Color "Résumé rapide :" "Yellow"
Write-Host "  Type de projet     : $projectType"
Write-Host "  Fichiers totaux    : $totalFiles"
Write-Host "  Fichiers source    : $($sourceFiles.Count)"
Write-Host "  Lignes de code     : $totalLines"
Write-Host "  Taille             : $totalSizeMB MB"
Write-Host ""