# Creer-Logo.ps1 - Windows PowerShell 5.1 / 7 (Windows), ASCII pur.
# Dessine le logo Study Timer (chronometre blanc sur degrade) et genere :
#   mobile\study_timer\assets\icon\icon.png      (1024x1024, icone complete)
#   mobile\study_timer\assets\icon\icon_fg.png   (1024x1024, fond transparent, pour l'icone adaptative Android)
#   mobile\study_timer\assets\icon\apercu.png    (512x512)
# Avec -Appliquer : configure pubspec.yaml (flutter_launcher_icons), met le nom "Study Timer"
#   dans AndroidManifest.xml, puis lance flutter pub get et dart run flutter_launcher_icons.
#
# Utilisation (depuis C:\dev\studytimer) :
#   .\Creer-Logo.ps1                      -> genere les images
#   .\Creer-Logo.ps1 -Appliquer           -> genere + installe l'icone dans l'app Android
#   .\Creer-Logo.ps1 -Couleur1 "#0F766E" -Couleur2 "#14B8A6"   (autres couleurs)

param(
    [string]$Chemin = ".",
    [string]$Couleur1 = "#4F46E5",
    [string]$Couleur2 = "#7C3AED",
    [switch]$Appliquer
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$Racine = (Resolve-Path $Chemin).Path
$App = Join-Path $Racine "mobile\study_timer"
if (-not (Test-Path $App)) { Write-Host "Dossier mobile\study_timer introuvable : lancez le script depuis la racine du projet." -ForegroundColor Red; exit 1 }
$Sortie = Join-Path $App "assets\icon"
New-Item -ItemType Directory -Force -Path $Sortie | Out-Null

$c1 = [System.Drawing.ColorTranslator]::FromHtml($Couleur1)
$c2 = [System.Drawing.ColorTranslator]::FromHtml($Couleur2)

# Dessine le chronometre dans un repere 1024x1024, reduit de $zone (ex. 0.70 = 70 % de la largeur)
function Dessiner-Chrono($g, [int]$taille, [double]$zone) {
    $k = $taille / 1024.0 * $zone
    $g.TranslateTransform($taille / 2.0, $taille / 2.0)
    $g.ScaleTransform([single]$k, [single]$k)
    $g.TranslateTransform(-512, -540)

    $blanc = [System.Drawing.Color]::White
    $brush = New-Object System.Drawing.SolidBrush($blanc)

    # cadran : anneau
    $pen = New-Object System.Drawing.Pen($blanc, 60)
    $g.DrawEllipse($pen, 242, 290, 540, 540)

    # bouton du haut + tige
    $g.FillRectangle($brush, 487, 190, 50, 80)
    $g.FillRectangle($brush, 432, 150, 160, 52)

    # aiguilles
    $pen2 = New-Object System.Drawing.Pen($blanc, 46)
    $pen2.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen2.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen2, 512, 560, 512, 410)
    $g.DrawLine($pen2, 512, 560, 625, 625)

    # centre
    $g.FillEllipse($brush, 482, 530, 60, 60)

    # petites graduations (12h, 3h, 6h, 9h)
    $pen3 = New-Object System.Drawing.Pen($blanc, 24)
    $pen3.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen3.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen3, 512, 335, 512, 360)
    $g.DrawLine($pen3, 512, 760, 512, 785)
    $g.DrawLine($pen3, 297, 560, 322, 560)
    $g.DrawLine($pen3, 702, 560, 727, 560)

    $pen.Dispose(); $pen2.Dispose(); $pen3.Dispose(); $brush.Dispose()
    $g.ResetTransform()
}

function Creer-Image([string]$fichier, [int]$taille, [bool]$avecFond, [double]$zone) {
    $bmp = New-Object System.Drawing.Bitmap($taille, $taille, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    if ($avecFond) {
        $rect = New-Object System.Drawing.Rectangle(0, 0, $taille, $taille)
        $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 45.0)
        $g.FillRectangle($grad, $rect)
        $grad.Dispose()
    } else {
        $g.Clear([System.Drawing.Color]::Transparent)
    }
    Dessiner-Chrono $g $taille $zone
    $g.Dispose()
    $bmp.Save($fichier, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host ("  [OK] " + $fichier) -ForegroundColor Green
}

Write-Host "Generation du logo..." -ForegroundColor Cyan
Creer-Image (Join-Path $Sortie "icon.png")    1024 $true  0.74
Creer-Image (Join-Path $Sortie "icon_fg.png") 1024 $false 0.58
Creer-Image (Join-Path $Sortie "apercu.png")  512  $true  0.74

if (-not $Appliquer) {
    Write-Host ""
    Write-Host "Ouvrez apercu.png pour voir le resultat. Pour l'installer dans l'app : .\Creer-Logo.ps1 -Appliquer" -ForegroundColor Yellow
    exit 0
}

# --- Installation dans l'application ---
Write-Host "Installation de l'icone..." -ForegroundColor Cyan
$utf8 = New-Object System.Text.UTF8Encoding($false)

$pub = Join-Path $App "pubspec.yaml"
$txt = [System.IO.File]::ReadAllText($pub, [System.Text.Encoding]::UTF8)
if ($txt -notmatch 'flutter_launcher_icons') {
    Copy-Item $pub ($pub + ".bak-logo") -Force
    $nl = "`n"; if ($txt.Contains("`r`n")) { $nl = "`r`n" }
    # dependance de dev (apres flutter_lints)
    $re = New-Object System.Text.RegularExpressions.Regex('^(\s*)flutter_lints:[^\r\n]*', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $txt = $re.Replace($txt, { param($m) $m.Value + $nl + $m.Groups[1].Value + "flutter_launcher_icons: ^0.14.3" }, 1)
    $bloc = $nl + "flutter_launcher_icons:" + $nl +
            "  android: true" + $nl +
            "  ios: false" + $nl +
            '  image_path: "assets/icon/icon.png"' + $nl +
            ('  adaptive_icon_background: "' + $Couleur1 + '"') + $nl +
            '  adaptive_icon_foreground: "assets/icon/icon_fg.png"' + $nl
    $txt = $txt.TrimEnd() + $nl + $bloc
    [System.IO.File]::WriteAllText($pub, $txt, $utf8)
    Write-Host "  [OK] pubspec.yaml mis a jour (copie : pubspec.yaml.bak-logo)" -ForegroundColor Green
} else {
    Write-Host "  [..] pubspec.yaml deja configure" -ForegroundColor Gray
}

$man = Join-Path $App "android\app\src\main\AndroidManifest.xml"
if (Test-Path $man) {
    $m = [System.IO.File]::ReadAllText($man, [System.Text.Encoding]::UTF8)
    if ($m -match 'android:label="study_timer"') {
        $m = $m.Replace('android:label="study_timer"', 'android:label="Study Timer"')
        [System.IO.File]::WriteAllText($man, $m, $utf8)
        Write-Host "  [OK] nom de l'app : Study Timer" -ForegroundColor Green
    }
}

Push-Location $App
try {
    & flutter pub get
    & dart run flutter_launcher_icons
} finally { Pop-Location }

Write-Host ""
Write-Host "Termine. Desinstallez l'ancienne app du telephone puis relancez :" -ForegroundColor Yellow
Write-Host "  flutter run --dart-define=API_URL=http://192.168.1.12:5293" -ForegroundColor Yellow
