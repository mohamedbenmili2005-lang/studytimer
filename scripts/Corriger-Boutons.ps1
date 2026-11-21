# Corriger-Boutons.ps1 - ASCII pur. Corrige les pages Communaute/Planificateur (boutons a largeur infinie).
# Utilisation (depuis C:\dev\studytimer) :  .\Corriger-Boutons.ps1
param([string]$Chemin = ".")
$lib = Join-Path (Resolve-Path $Chemin).Path "mobile\study_timer\lib"
$style = "style: FilledButton.styleFrom(minimumSize: const Size(110, 44)), "
foreach ($n in "community_page.dart","planner_page.dart") {
    $f = Join-Path $lib $n
    if (-not (Test-Path $f)) { Write-Host "introuvable : $n"; continue }
    $t = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
    if ($t.Contains("minimumSize: const Size(110, 44)")) { Write-Host "deja corrige : $n"; continue }
    Copy-Item $f ($f + ".bak-boutons") -Force
    $t = $t.Replace("FilledButton.icon(", "FilledButton.icon(" + $style).Replace("FilledButton(", "FilledButton(" + $style)
    [System.IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "corrige : $n"
}
Write-Host "Terminez par : R (restart) dans le terminal flutter run."
