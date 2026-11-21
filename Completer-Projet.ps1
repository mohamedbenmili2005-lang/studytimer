# Completer-Projet.ps1
# Compatible Windows PowerShell 5.1 et PowerShell 7 (fichier volontairement en ASCII pur).
#
# 1) DIAGNOSTIC : compare le projet au cahier des charges (modules, tables, API, regles de
#    gestion, exigences, livrables) et ecrit docs\CONFORMITE.md.
# 2) COMPLETION (-Appliquer) : genere ce qui manque, sans toucher au comportement existant :
#      - backend : amis + confidentialite (RG07), taches/planificateur, salles d'etude + chat,
#        notifications, invitations aux defis, heatmap, routes du cahier (ranking, leaderboard/weekly),
#        SignalR (hub), association seance <-> tache, migration EF, tests xUnit ;
#      - mobile  : api_extras.dart, pages Communaute / Salles / Planificateur, navigation ;
#      - ops     : CI GitHub Actions, test de charge k6.
#    Chaque fichier modifie est sauvegarde dans archive\sauvegarde-completer-<date>\.
#
# Utilisation (depuis C:\dev\studytimer) :
#   .\Completer-Projet.ps1                          -> diagnostic seul (aucune modification)
#   .\Completer-Projet.ps1 -Appliquer               -> genere les modules manquants + migration
#   .\Completer-Projet.ps1 -Appliquer -Verifier     -> puis dotnet build/test + flutter analyze/test
#                                                      (annule tout si le backend ne compile pas)
# Options : -Chemin <dossier>  -Forcer (regenere les fichiers deja presents)
#           -SansMigration     -Garder (ne pas annuler en cas d'echec de -Verifier)

param(
    [string]$Chemin = ".",
    [switch]$Appliquer,
    [switch]$Verifier,
    [switch]$Forcer,
    [switch]$SansMigration,
    [switch]$Garder
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ----------------------------------------------------------------------------
# Utilitaires
# ----------------------------------------------------------------------------
function T([string]$s) {
    # Decode les sequences \uXXXX (le script reste en ASCII, la sortie est en UTF-8)
    return [regex]::Replace($s, '\\u([0-9a-fA-F]{4})', {
        param($m) [string][char][Convert]::ToInt32($m.Groups[1].Value, 16)
    })
}
function Info([string]$m) { Write-Host ("  [..] " + (T $m)) -ForegroundColor Gray }
function Ok([string]$m)   { Write-Host ("  [OK] " + (T $m)) -ForegroundColor Green }
function Warn([string]$m) { Write-Host ("  [!!] " + (T $m)) -ForegroundColor Yellow }
function Titre([string]$m) { Write-Host ""; Write-Host (T $m) -ForegroundColor Cyan }

function Lire([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return "" }
    return [System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)
}
function Has([string]$text, [string]$re) { return [regex]::IsMatch($text, $re) }

$Racine = (Resolve-Path $Chemin).Path
$BackendDir = Join-Path $Racine "backend"
$ApiDir     = Join-Path $BackendDir "StudyTimer.Api"
$DomDir     = Join-Path $BackendDir "StudyTimer.Domain"
$InfDir     = Join-Path $BackendDir "StudyTimer.Infrastructure"
$TestDir    = Join-Path $BackendDir "StudyTimer.Tests"
$AppDir     = Join-Path $Racine "mobile\study_timer"
$LibDir     = Join-Path $AppDir "lib"

if (-not (Test-Path $ApiDir) -or -not (Test-Path $LibDir)) {
    Write-Host "Projet StudyTimer introuvable dans '$Racine' (backend\StudyTimer.Api et mobile\study_timer\lib attendus)." -ForegroundColor Red
    Write-Host "Lancez le script depuis la racine du projet ou utilisez -Chemin." -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------------------------
# Lecture du projet
# ----------------------------------------------------------------------------
function Lire-Dossier([string]$dir, [string]$filtre, [string]$exclure) {
    if (-not (Test-Path $dir)) { return "" }
    $parts = New-Object System.Collections.ArrayList
    foreach ($f in Get-ChildItem $dir -Recurse -Filter $filtre -File -ErrorAction SilentlyContinue) {
        if ($exclure -and $f.FullName -match $exclure) { continue }
        [void]$parts.Add((Lire $f.FullName))
    }
    return ($parts -join "`n")
}

function Get-Routes {
    $out = New-Object System.Collections.ArrayList
    $dir = Join-Path $ApiDir "Controllers"
    if (-not (Test-Path $dir)) { return @() }
    foreach ($f in Get-ChildItem $dir -Filter *.cs -File) {
        $t = Lire $f.FullName
        $m = [regex]::Match($t, '\[Route\("([^"]+)"\)\]')
        if (-not $m.Success) { continue }
        $prefix = $m.Groups[1].Value
        foreach ($h in [regex]::Matches($t, '\[Http(Get|Post|Put|Delete)(?:\("([^"]*)"\))?\]')) {
            $sub = $h.Groups[2].Value
            $p = ('/' + $prefix.Trim('/') + '/' + $sub.Trim('/')).TrimEnd('/')
            $p = [regex]::Replace($p, '\{(\w+):[^}]+\}', '{$1}')
            [void]$out.Add(($h.Groups[1].Value.ToUpper() + ' ' + $p.ToLower()))
        }
    }
    return $out.ToArray()
}

# ----------------------------------------------------------------------------
# DIAGNOSTIC : comparaison avec le cahier des charges
# ----------------------------------------------------------------------------
$Script:Res = $null
function C([string]$mod, [string]$item, [string]$phase, [string]$statut, [string]$detail, [string]$action) {
    [void]$Script:Res.Add([pscustomobject]@{
        Module = $mod; Item = $item; Phase = $phase; Statut = $statut; Detail = $detail; Action = $action
    })
}

function Analyser {
    $Script:Res = New-Object System.Collections.ArrayList

    $cs    = Lire-Dossier $ApiDir "*.cs" '\\(bin|obj|Migrations)\\'
    $dom   = Lire-Dossier (Join-Path $DomDir "Entities") "*.cs" ''
    $inf   = Lire (Join-Path $InfDir "AppDbContext.cs")
    $dart  = Lire-Dossier $LibDir "*.dart" ''
    $pub   = Lire (Join-Path $AppDir "pubspec.yaml")
    $comp  = Lire (Join-Path $Racine "docker-compose.yml")
    $ngx   = Lire (Join-Path $Racine "deploy\nginx\default.conf")
    $tests = Lire-Dossier $TestDir "*.cs" '\\(bin|obj)\\'
    $routes = @(Get-Routes)
    $all = $cs + "`n" + $dom + "`n" + $inf

    # --- Module 1 : utilisateurs
    $m = "Module 1 - Utilisateurs et authentification"
    if ((Has $dom 'FirstName') -and (Has $dom 'Username') -and (Has $dom 'Country') -and ($routes -contains 'POST /api/auth/register')) {
        C $m "Inscription (nom, pr\u00e9nom, pseudo, email, mot de passe, pays)" "MVP" "OK" "User.cs + POST /api/auth/register" ""
    } else { C $m "Inscription (nom, pr\u00e9nom, pseudo, email, mot de passe, pays)" "MVP" "MANQUANT" "" "Compl\u00e9ter l'entit\u00e9 User et l'inscription." }
    if (Has $dom 'Photo|Avatar') { C $m "Photo de profil" "MVP" "OK" "champ photo/avatar" "" }
    else { C $m "Photo de profil" "MVP" "MANQUANT" "aucun champ ni endpoint d'upload" "Ajouter User.AvatarUrl + POST /api/users/avatar (stockage local du serveur)." }
    if ($routes -contains 'POST /api/auth/login') { C $m "Connexion email / mot de passe (JWT + refresh)" "MVP" "OK" "POST /api/auth/login, /refresh" "" }
    else { C $m "Connexion email / mot de passe" "MVP" "MANQUANT" "" "Ajouter POST /api/auth/login." }
    if (Has $all 'Google|Apple') { C $m "Google Sign-In / Apple Sign-In" "MVP" "OK" "" "" }
    else { C $m "Google Sign-In / Apple Sign-In" "MVP" "MANQUANT" "" "Exclu en mode serveur local (cahier 3.3 : pas de connexion Google/Apple hors Internet). A documenter comme \u00e9cart assum\u00e9." }
    if (($routes -contains 'GET /api/users/profile') -and ($routes -contains 'PUT /api/users/profile')) { C $m "Gestion du profil (lecture / modification)" "MVP" "OK" "GET+PUT /api/users/profile" "" }
    else { C $m "Gestion du profil" "MVP" "MANQUANT" "" "Ajouter GET/PUT /api/users/profile." }
    if ($routes -contains 'DELETE /api/users/account') { C $m "Suppression du compte" "MVP" "OK" "" "" }
    else { C $m "Suppression du compte" "MVP" "MANQUANT" "" "Ajouter DELETE /api/users/account (suppression en cascade des s\u00e9ances, mati\u00e8res, jetons, badges, amiti\u00e9s)." }

    # --- Module 2 : chronometre
    $m = "Module 2 - Chronom\u00e8tre d'\u00e9tude"
    $stOk = (Has $cs 'enum SessionMode') -or (Has $dom 'enum SessionMode')
    if ($stOk -and (Has $dom 'Focus') -and (Has $dom 'Pomodoro') -and (Has $dom 'Stopwatch')) { C $m "3 modes : Focus, Pomodoro, Stopwatch" "MVP" "OK" "enum SessionMode" "" }
    else { C $m "3 modes : Focus, Pomodoro, Stopwatch" "MVP" "MANQUANT" "" "Ajouter les modes manquants." }
    $need = @('POST /api/sessions/start','POST /api/sessions/pause','POST /api/sessions/resume','POST /api/sessions/stop','GET /api/sessions/history')
    $miss = @($need | Where-Object { $routes -notcontains $_ })
    if ($miss.Count -eq 0) { C $m "D\u00e9marrer / pause / reprendre / arr\u00eater + historique" "MVP" "OK" "5 routes pr\u00e9sentes" "" }
    else { C $m "D\u00e9marrer / pause / reprendre / arr\u00eater + historique" "MVP" "PARTIEL" ("manque : " + ($miss -join ', ')) "Ajouter les routes manquantes." }
    if ((Has $dom 'SubjectId') -and ($routes -contains 'POST /api/subjects')) { C $m "Choisir une mati\u00e8re" "MVP" "OK" "Subjects + SubjectId" "" }
    else { C $m "Choisir une mati\u00e8re" "MVP" "MANQUANT" "" "Ajouter Subjects." }
    if ((Has $cs 'request\.TaskId') -and (Has $all 'class TaskItem')) { C $m "Associer une t\u00e2che \u00e0 une s\u00e9ance" "MVP" "OK" "StartSessionRequest.TaskId" "" }
    elseif (Has $dom 'TaskId') { C $m "Associer une t\u00e2che \u00e0 une s\u00e9ance" "MVP" "PARTIEL" "StudySession.TaskId existe mais pas de table Tasks ni de TaskId dans la requ\u00eate de d\u00e9marrage" "-Appliquer : ajoute TaskItem + TaskId dans POST /api/sessions/start." }
    else { C $m "Associer une t\u00e2che \u00e0 une s\u00e9ance" "MVP" "MANQUANT" "" "Ajouter les t\u00e2ches." }
    if ((Has $dom 'LastResumedAtUtc') -and (Has $cs 'GetElapsedSeconds')) { C $m "Chrono sur horodatages (arri\u00e8re-plan) + source de v\u00e9rit\u00e9 serveur" "MVP" "OK" "AccumulatedSeconds + LastResumedAtUtc" "" }
    else { C $m "Chrono sur horodatages" "MVP" "MANQUANT" "" "Calculer le temps c\u00f4t\u00e9 serveur." }
    if ((Has $dart 'recover\(') -and ($routes -contains 'GET /api/sessions/current')) { C $m "R\u00e9cup\u00e9rer une s\u00e9ance apr\u00e8s fermeture/red\u00e9marrage" "MVP" "OK" "GET /api/sessions/current + recover()" "" }
    else { C $m "R\u00e9cup\u00e9rer une s\u00e9ance apr\u00e8s red\u00e9marrage" "MVP" "MANQUANT" "" "Ajouter /current et recover()." }
    if (Has $dart 'offline|OfflineQueue|pendingEvents|pending_events') { C $m "File d'attente hors-ligne + resynchronisation (cahier 8.1)" "MVP" "OK" "" "" }
    else { C $m "File d'attente hors-ligne + resynchronisation (cahier 8.1)" "MVP" "MANQUANT" "aucune file locale d'\u00e9v\u00e9nements" "Stocker les actions (start/pause/stop) dans shared_preferences/sqflite quand le Wi-Fi tombe, puis les rejouer." }

    # --- Module 3 : challenges
    $m = "Module 3 - Challenges"
    if (Has $dom 'TotalTime') { C $m "Time Goal (objectif de temps sur une p\u00e9riode)" "MVP" "OK" "ChallengeType.TotalTime" "" } else { C $m "Time Goal" "MVP" "MANQUANT" "" "Ajouter le type." }
    if (Has $dom 'SpeedRace') { C $m "Speed Race (premier \u00e0 atteindre un seuil)" "MVP" "OK" "" "" }
    else { C $m "Speed Race (premier \u00e0 atteindre un seuil)" "MVP" "MANQUANT" "types actuels : TotalTime, SessionCount, DailyStreak, LongestSession" "Ajouter ChallengeType.SpeedRace + date d'atteinte du seuil (ordre d'arriv\u00e9e)." }
    if ($routes -contains 'GET /api/challenges/{id}/leaderboard') { C $m "Ranking Battle (classement selon le temps)" "MVP" "PARTIEL" "classement par progression, pas de type d\u00e9di\u00e9" "Ajouter ChallengeType.RankingBattle (m\u00eame calcul que TotalTime, gagnant d\u00e9sign\u00e9 \u00e0 la fin)." }
    else { C $m "Ranking Battle" "MVP" "MANQUANT" "" "Ajouter le classement." }
    if (Has $dom 'DailyStreak') { C $m "Streak Challenge" "MVP" "OK" "ChallengeType.DailyStreak" "" } else { C $m "Streak Challenge" "MVP" "MANQUANT" "" "Ajouter le type." }
    if (($routes -contains 'POST /api/challenges') -and ($routes -contains 'GET /api/challenges') -and ($routes -contains 'POST /api/challenges/{id}/join')) { C $m "Cr\u00e9er, lister, rejoindre un challenge" "MVP" "OK" "" "" }
    else { C $m "Cr\u00e9er, lister, rejoindre un challenge" "MVP" "MANQUANT" "" "Ajouter les routes." }
    if (Has $dom 'class Challenge\b[\s\S]*?StartsAtUtc') { C $m "D\u00e9finir dates et objectifs" "MVP" "PARTIEL" "d\u00e9but = maintenant + dur\u00e9e en jours (pas de date de d\u00e9but choisie)" "Accepter StartsAtUtc dans CreateChallengeDto." }
    if (Has $dom 'class ChallengeInvitation') { C $m "Inviter des amis \u00e0 un challenge" "MVP" "OK" "ChallengeInvitation + POST /api/challenges/{id}/invite" "" }
    else { C $m "Inviter des amis \u00e0 un challenge" "MVP" "MANQUANT" "" "-Appliquer : ChallengeInvitation + routes d'invitation." }
    C $m "Rejoindre par lien ou code" "MVP" "PARTIEL" "rejoindre par identifiant (POST /join) ; pas de code court ni de lien partageable" "Ajouter Challenge.JoinCode (6 caract\u00e8res) + POST /api/challenges/join-by-code."
    if (($routes -contains 'GET /api/challenges/{id}/leaderboard') -or ($routes -contains 'GET /api/challenges/{id}/ranking')) { C $m "Consulter le classement" "MVP" "OK" "" "" }
    else { C $m "Consulter le classement" "MVP" "MANQUANT" "" "Ajouter la route." }
    if (Has $all 'class AppNotification|class Notification\b') { C $m "Notifications de challenge (invitation, fin, r\u00e9compense)" "MVP" "PARTIEL" "notifications d'invitation cr\u00e9\u00e9es ; fin de challenge et r\u00e9compenses non d\u00e9clench\u00e9es" "Cr\u00e9er une notification \u00e0 la fin d'un challenge et \u00e0 l'attribution d'un badge." }
    else { C $m "Notifications de challenge" "MVP" "MANQUANT" "" "-Appliquer : table Notifications + /api/notifications." }

    # --- Module 4 : amis
    $m = "Module 4 - Amis et interactions"
    if (Has $dom 'class Friendship|class Friend\b') {
        C $m "Rechercher, inviter, accepter/refuser, supprimer un ami" "V2" "OK" "FriendsController" ""
        C $m "Activit\u00e9s et statistiques publiques des amis" "V2" "OK" "GET /api/friends/feed et /{id}/stats" ""
    } else {
        C $m "Rechercher, inviter, accepter/refuser, supprimer un ami" "V2" "MANQUANT" "" "-Appliquer : FriendsController."
        C $m "Activit\u00e9s et statistiques publiques des amis" "V2" "MANQUANT" "" "-Appliquer."
    }
    C $m "R\u00e9agir aux s\u00e9ances, commenter, partager un challenge" "V2" "MANQUANT" "" "Ajouter table SessionReactions/Comments (apr\u00e8s validation du fil d'activit\u00e9)."

    # --- Module 5 : stats
    $m = "Module 5 - Classements et statistiques"
    if (($routes -contains 'GET /api/statistics/dashboard') -and (Has $cs 'AverageSessionSeconds') -and (Has $cs 'CurrentStreakDays') -and (Has $cs 'BySubject')) { C $m "Statistiques individuelles (total, jour/semaine/mois, moyenne, s\u00e9rie, mati\u00e8res)" "MVP" "OK" "GET /api/statistics/dashboard" "" }
    else { C $m "Statistiques individuelles" "MVP" "PARTIEL" "" "Compl\u00e9ter le tableau de bord." }
    if ($routes -contains 'GET /api/leaderboard') { C $m "Classement g\u00e9n\u00e9ral hebdo / mensuel / global" "MVP" "OK" "GET /api/leaderboard?period=week|month|all" "" }
    else { C $m "Classement g\u00e9n\u00e9ral" "MVP" "MANQUANT" "" "Ajouter /api/leaderboard." }
    if ($routes -contains 'GET /api/friends/leaderboard') { C $m "Classement entre amis" "V2" "OK" "GET /api/friends/leaderboard" "" }
    else { C $m "Classement entre amis" "V2" "MANQUANT" "" "-Appliquer : GET /api/friends/leaderboard." }
    if (Has $cs 'Last7Days') { C $m "Temps par jour / histogramme hebdomadaire / r\u00e9partition par mati\u00e8re" "MVP" "OK" "Last7Days + BySubject" "" }
    else { C $m "Visualisations de base" "MVP" "MANQUANT" "" "Ajouter les s\u00e9ries." }
    if ($routes -contains 'GET /api/statistics/heatmap') { C $m "Calendrier d'activit\u00e9 (heatmap)" "MVP" "PARTIEL" "endpoint GET /api/statistics/heatmap pr\u00eat ; widget Flutter \u00e0 dessiner" "Dessiner la grille 7x52 dans stats_page.dart avec les donn\u00e9es de /heatmap." }
    else { C $m "Calendrier d'activit\u00e9 (heatmap)" "MVP" "MANQUANT" "" "-Appliquer : endpoint /heatmap (puis widget Flutter)." }

    # --- Module 6 : gamification
    $m = "Module 6 - R\u00e9compenses et gamification"
    if ((Has $cs 'XpFor') -and (Has $cs 'Level\(')) { C $m "XP et niveaux" "MVP" "OK" "Gamification.XpFor / Level" "" } else { C $m "XP et niveaux" "MVP" "MANQUANT" "" "Ajouter." }
    if ((Has $cs 'first_session') -and (Has $cs 'streak_7')) { C $m "Badges : First Step, Consistency (7 jours), s\u00e9ries" "MVP" "OK" "8 badges" "" } else { C $m "Badges" "MVP" "MANQUANT" "" "Ajouter." }
    if (Has $cs 'hours_100') { C $m "Badge Study Champion (100 h)" "MVP" "OK" "" "" }
    else { C $m "Badge Study Champion (100 h)" "MVP" "MANQUANT" "le palier le plus haut est 50 h" "Ajouter hours_100 \u00e0 Gamification.Badges (et mettre \u00e0 jour le test qui attend 8 badges)." }
    if (Has $cs 'night_owl|NightOwl') { C $m "Badge Night Owl (5 s\u00e9ances nocturnes)" "MVP" "OK" "" "" }
    else { C $m "Badge Night Owl (5 s\u00e9ances nocturnes)" "MVP" "MANQUANT" "Gamification.Earned ne re\u00e7oit pas l'heure de d\u00e9but des s\u00e9ances" "Passer l'heure locale de d\u00e9but \u00e0 Earned() et compter les s\u00e9ances entre 22h et 5h." }
    C $m "R\u00e9compenses quotidiennes" "MVP" "MANQUANT" "" "Ajouter un bonus XP du premier jour valid\u00e9 (DailyStreaks)."
    C $m "Conditions et r\u00e9compenses configurables depuis le backend" "MVP" "MANQUANT" "badges cod\u00e9s en dur dans Gamification.cs" "Table Achievements (code, seuil, XP) \u00e9ditable + endpoint d'administration."

    # --- Module 7 : salles
    $m = "Module 7 - Study Rooms"
    if (Has $dom 'class StudyRoom') {
        C $m "Cr\u00e9er une salle priv\u00e9e, rejoindre une salle publique ou par code" "V2" "OK" "RoomsController" ""
        C $m "Participants, temps d'\u00e9tude et statut (\u00e9tude / pause / hors ligne)" "V2" "OK" "GET /api/rooms/{id}" ""
        C $m "Discuter et quitter une salle" "V2" "OK" "messages REST + hub SignalR /hubs/study" ""
    } else {
        C $m "Cr\u00e9er une salle priv\u00e9e, rejoindre une salle publique ou par code" "V2" "MANQUANT" "" "-Appliquer : StudyRoom + RoomsController."
        C $m "Participants, temps d'\u00e9tude et statut" "V2" "MANQUANT" "" "-Appliquer."
        C $m "Discuter et quitter une salle" "V2" "MANQUANT" "" "-Appliquer."
    }
    C $m "Salles virtuelles 2D/3D avec avatars" "V3" "MANQUANT" "pr\u00e9vu comme \u00e9volution" "Hors p\u00e9rim\u00e8tre actuel."

    # --- Module 8 : planificateur
    $m = "Module 8 - Planificateur d'\u00e9tude"
    if ((Has $dom 'class TaskItem|class StudyTask') -and ($routes -contains 'POST /api/tasks')) {
        C $m "Cr\u00e9er une t\u00e2che (mati\u00e8re, date/heure, dur\u00e9e estim\u00e9e, priorit\u00e9)" "V2" "OK" "TasksController" ""
        C $m "Marquer termin\u00e9e, consulter par p\u00e9riode (calendrier), t\u00e2ches en retard" "V2" "OK" "complete, GET ?from&to, /overdue" ""
    } else {
        C $m "Cr\u00e9er une t\u00e2che" "V2" "MANQUANT" "" "-Appliquer : TaskItem + TasksController."
        C $m "Marquer termin\u00e9e, calendrier, t\u00e2ches en retard" "V2" "MANQUANT" "" "-Appliquer."
    }

    # --- Module 9 : ambiances / personnalisation
    $m = "Module 9 - Ambiances sonores et personnalisation"
    if (Has $pub 'audioplayers|just_audio') { C $m "Ambiances sonores (Lo-Fi, pluie, for\u00eat...)" "V2" "OK" "" "" }
    else { C $m "Ambiances sonores (Lo-Fi, pluie, for\u00eat...)" "V2" "MANQUANT" "aucun paquet audio" "Ajouter just_audio + fichiers .mp3 libres de droits en assets locaux (pas de flux externe : mode hors-ligne)." }
    if ((Has $dart 'darkTheme') -and (Has $dart 'themeMode')) { C $m "Mode sombre / clair au choix" "V2" "OK" "" "" }
    elseif (Has $dart 'darkTheme') { C $m "Mode sombre / clair au choix" "V2" "PARTIEL" "th\u00e8me sombre pr\u00e9sent, suit le syst\u00e8me, pas de bascule manuelle" "Ajouter un ValueNotifier<ThemeMode> sauvegard\u00e9 dans shared_preferences." }
    else { C $m "Mode sombre / clair" "V2" "MANQUANT" "" "Ajouter darkTheme." }
    C $m "Personnaliser les couleurs de l'interface" "V2" "MANQUANT" "" "Choix d'une couleur d'accent dans le profil."

    # --- Module 10 : notifications
    $m = "Module 10 - Notifications"
    if (Has $pub 'flutter_local_notifications') { C $m "Rappels locaux (d\u00e9but d'\u00e9tude, t\u00e2ches, s\u00e9rie)" "MVP" "OK" "" "" }
    else { C $m "Rappels locaux (d\u00e9but d'\u00e9tude, t\u00e2ches, s\u00e9rie quotidienne)" "MVP" "MANQUANT" "flutter_local_notifications absent de pubspec.yaml" "Ajouter flutter_local_notifications (notifications locales, sans Cloud) et planifier les rappels." }
    if (Has $dart 'alert\(') { C $m "Notification de fin de Pomodoro" "MVP" "PARTIEL" "alerte dans l'application seulement (rien si l'app est en arri\u00e8re-plan)" "Notification locale planifi\u00e9e \u00e0 l'heure de fin pr\u00e9vue." }
    else { C $m "Notification de fin de Pomodoro" "MVP" "MANQUANT" "" "Ajouter." }
    if ((Has $all 'class AppNotification|class Notification\b') -and ($routes -contains 'GET /api/notifications')) { C $m "Centre de notifications (invitations, classement, r\u00e9compenses)" "V2" "OK" "GET /api/notifications" "" }
    else { C $m "Centre de notifications (invitations, classement, r\u00e9compenses)" "V2" "MANQUANT" "" "-Appliquer." }

    # --- Architecture
    $m = "Architecture technique (section 3)"
    C $m "Flutter / Dart" "MVP" "OK" "mobile\study_timer" ""
    C $m "ASP.NET Core Web API" "MVP" "OK" "backend\StudyTimer.Api" ""
    if ((Has $comp 'postgres') -and ((Has $all 'Npgsql|UseNpgsql') -or (Has (Lire (Join-Path $InfDir "StudyTimer.Infrastructure.csproj")) 'Npgsql'))) { C $m "PostgreSQL" "MVP" "OK" "docker-compose + Npgsql" "" } else { C $m "PostgreSQL" "MVP" "MANQUANT" "" "Ajouter." }
    if (Has $cs 'AddSignalR') { C $m "SignalR (temps r\u00e9el)" "V2" "OK" "hub /hubs/study" "" }
    else { C $m "SignalR (temps r\u00e9el)" "V2" "MANQUANT" "" "-Appliquer : StudyHub + MapHub." }
    if (Has $comp 'redis') { C $m "Redis (cache, optionnel pour le MVP)" "V2" "OK" "" "" } else { C $m "Redis (cache, optionnel pour le MVP)" "V2" "MANQUANT" "service absent de docker-compose.yml" "Optionnel : ajouter redis:7-alpine + cache des classements." }
    if (Has $cs 'AddJwtBearer') { C $m "JWT" "MVP" "OK" "" "" } else { C $m "JWT" "MVP" "MANQUANT" "" "Ajouter." }
    if ((Has $comp 'nginx') -and (Has $comp 'postgres')) { C $m "Docker Compose (API + PostgreSQL + Nginx + sauvegarde)" "MVP" "OK" "docker-compose.yml" "" } else { C $m "Docker Compose" "MVP" "PARTIEL" "" "Compl\u00e9ter." }
    if ((Test-Path (Join-Path $Racine ".github\workflows")) -or (Test-Path (Join-Path $Racine "Jenkinsfile"))) { C $m "CI/CD (GitHub Actions ou Jenkins)" "MVP" "OK" "" "" }
    else { C $m "CI/CD (GitHub Actions ou Jenkins)" "MVP" "MANQUANT" "" "-Appliquer : .github\workflows\ci.yml." }
    if (Has $ngx 'ssl_certificate') { C $m "Reverse proxy Nginx + TLS" "MVP" "OK" "deploy\nginx\default.conf" "" } elseif (Test-Path (Join-Path $Racine "deploy\nginx")) { C $m "Reverse proxy Nginx + TLS" "MVP" "PARTIEL" "" "V\u00e9rifier ssl_certificate." } else { C $m "Reverse proxy Nginx + TLS" "MVP" "MANQUANT" "" "Ajouter deploy\nginx\default.conf." }
    if ((Test-Path (Join-Path $Racine "deploy\scripts\backup.sh")) -and (Test-Path (Join-Path $Racine "deploy\scripts\restore.sh"))) { C $m "Sauvegarde et restauration locales" "MVP" "OK" "backup.sh / restore.sh" "" } else { C $m "Sauvegarde et restauration" "MVP" "MANQUANT" "" "Ajouter les scripts." }
    if (Has $cs 'MapHealthChecks') { C $m "Supervision locale (sant\u00e9 API + base)" "MVP" "PARTIEL" "/health v\u00e9rifie l'API et la base ; pas d'espace disque ni CPU/RAM" "Ajouter un contr\u00f4le d'espace disque (AddDiskStorageHealthCheck) ou un script de supervision." }
    else { C $m "Supervision locale" "MVP" "MANQUANT" "" "Ajouter /health." }

    # --- API REST (section 5)
    $m = "API REST (section 5)"
    $spec = @(
        @('POST /api/auth/register',''), @('POST /api/auth/login',''),
        @('GET /api/users/profile',''), @('PUT /api/users/profile',''),
        @('POST /api/sessions/start',''), @('POST /api/sessions/pause',''), @('POST /api/sessions/resume',''), @('POST /api/sessions/stop',''),
        @('GET /api/sessions/history',''), @('GET /api/statistics/dashboard',''),
        @('POST /api/challenges',''), @('GET /api/challenges',''), @('POST /api/challenges/{id}/join',''),
        @('GET /api/challenges/{id}/ranking','GET /api/challenges/{id}/leaderboard'),
        @('POST /api/friends/invite',''),
        @('GET /api/leaderboard/weekly','GET /api/leaderboard'),
        @('POST /api/rooms',''), @('GET /api/rooms',''), @('POST /api/tasks','')
    )
    foreach ($s in $spec) {
        $r = $s[0]; $alt = $s[1]
        $ph = "MVP"
        if ($r -match '/friends|/rooms|/tasks') { $ph = "V2" }
        if ($routes -contains $r.ToLower()) { C $m $r $ph "OK" "" "" }
        elseif ($alt -and ($routes -contains $alt.ToLower())) { C $m $r $ph "PARTIEL" ("existe sous : " + $alt) "-Appliquer : route alias conforme au cahier." }
        else { C $m $r $ph "MANQUANT" "" "-Appliquer." }
    }

    # --- Base de donnees (section 4)
    $m = "Base de donn\u00e9es (section 4)"
    $tables = @(
        @('Users','class User\b','',"MVP"), @('UserProfiles','','Profil fusionn\u00e9 dans Users (pr\u00e9nom, nom, pays, fuseau)',"MVP"),
        @('Friends','class Friendship|class Friend\b','',"V2"), @('StudySessions','class StudySession\b','',"MVP"),
        @('Subjects','class Subject\b','',"MVP"), @('Tasks','class TaskItem|class StudyTask','',"V2"),
        @('Challenges','class Challenge\b','',"MVP"), @('ChallengeParticipants','class ChallengeParticipant','',"MVP"),
        @('ChallengeInvitations','class ChallengeInvitation','',"MVP"),
        @('Leaderboards','','Classements calcul\u00e9s \u00e0 la vol\u00e9e depuis les s\u00e9ances valid\u00e9es (RG04) : acceptable',"MVP"),
        @('UserStatistics','','Statistiques calcul\u00e9es \u00e0 la vol\u00e9e : acceptable',"MVP"),
        @('Achievements','','Badges d\u00e9finis dans Gamification.cs (pas en base)',"MVP"),
        @('UserAchievements','class UserBadge','',"MVP"),
        @('StudyRooms','class StudyRoom\b','',"V2"), @('RoomParticipants','class RoomParticipant','',"V2"), @('RoomMessages','class RoomMessage','',"V2"),
        @('Notifications','class AppNotification|class Notification\b','',"V2"),
        @('DailyStreaks','','S\u00e9ries calcul\u00e9es \u00e0 la vol\u00e9e depuis les s\u00e9ances : acceptable',"MVP")
    )
    foreach ($tb in $tables) {
        if ($tb[1] -and (Has $dom $tb[1])) { C $m $tb[0] $tb[3] "OK" "" "" }
        elseif ($tb[2]) { C $m $tb[0] $tb[3] "PARTIEL" $tb[2] "" }
        else { C $m $tb[0] $tb[3] "MANQUANT" "" "-Appliquer." }
    }

    # --- Regles de gestion
    $m = "R\u00e8gles de gestion (section 6)"
    C $m "RG01 - Validation des s\u00e9ances" "MVP" "PARTIEL" "le statut Rejected existe mais n'est jamais utilis\u00e9 ; une s\u00e9ance de 2 secondes est 'Completed' (0 XP)" "Rejeter les s\u00e9ances < 60 s (et adapter le test Cycle_complet_de_seance_et_historique qui arr\u00eate imm\u00e9diatement)."
    if (Has $cs 'UtcNow') { C $m "RG02 - Le serveur est la source de v\u00e9rit\u00e9 du temps" "MVP" "OK" "temps calcul\u00e9 avec DateTime.UtcNow c\u00f4t\u00e9 serveur" "" } else { C $m "RG02 - Synchronisation" "MVP" "MANQUANT" "" "Calculer c\u00f4t\u00e9 serveur." }
    C $m "RG03 - Pr\u00e9vention de la fraude" "MVP" "PARTIEL" "1 seule s\u00e9ance active, dur\u00e9es n\u00e9gatives bloqu\u00e9es (Math.Max), horodatages serveur ; pas d'\u00e9dition manuelle possible" "Journaliser et refuser les arr\u00eats incoh\u00e9rents (dur\u00e9e > temps r\u00e9el depuis le d\u00e9but), limiter la fr\u00e9quence des start/stop."
    if (Has $cs 'Status == SessionStatus\.Completed') { C $m "RG04 - Classements sur s\u00e9ances valid\u00e9es" "MVP" "OK" "filtre Status == Completed" "" } else { C $m "RG04 - Classements" "MVP" "MANQUANT" "" "Filtrer." }
    if (Has $cs 'FindSystemTimeZoneById') { C $m "RG05 - S\u00e9ries avec fuseau horaire" "MVP" "PARTIEL" "statistiques en fuseau utilisateur ; badges et d\u00e9fis calcul\u00e9s en UTC (cf. GUIDE.md)" "Faire passer le fuseau \u00e0 Gamification.Earned/Progress." }
    else { C $m "RG05 - S\u00e9ries avec fuseau horaire" "MVP" "MANQUANT" "" "Utiliser le fuseau." }
    if (Has $cs 'EndsAtUtc < DateTime\.UtcNow') { C $m "RG06 - Pas de nouveau participant apr\u00e8s la date limite" "MVP" "OK" "contr\u00f4le dans Join" "" } else { C $m "RG06" "MVP" "MANQUANT" "" "Ajouter." }
    if (Has $dom 'class UserPrivacy') { C $m "RG07 - Confidentialit\u00e9 (visibilit\u00e9 stats / activit\u00e9)" "V2" "OK" "UserPrivacy + /api/users/privacy" "" }
    else { C $m "RG07 - Confidentialit\u00e9 (visibilit\u00e9 stats / activit\u00e9)" "V2" "MANQUANT" "" "-Appliquer : UserPrivacy." }

    # --- Ecrans
    $m = "Interfaces graphiques (section 7)"
    $ecrans = @(
        @('Accueil','dashboard_page\.dart'), @('Timer','timer_page\.dart'), @('Challenges','challenges_page\.dart'),
        @('Statistiques','stats_page\.dart'), @('Communaut\u00e9','community_page\.dart'), @('Planificateur','planner_page\.dart')
    )
    foreach ($e in $ecrans) {
        $f = $e[1] -replace '\\\.','.'
        if (Test-Path (Join-Path $LibDir $f)) { C $m ("\u00c9cran " + $e[0]) "MVP" "OK" $f "" }
        else { C $m ("\u00c9cran " + $e[0]) "V2" "MANQUANT" "" "-Appliquer : $f." }
    }

    # --- Exigences non fonctionnelles
    $m = "Exigences non fonctionnelles (section 8)"
    if ((Has $cs 'UseHttpsRedirection|UseHsts') -and (Has $cs 'PasswordHasher')) { C $m "S\u00e9curit\u00e9 : HTTPS, JWT, mots de passe hach\u00e9s" "MVP" "OK" "HSTS, PasswordHasher, JWT" "" } else { C $m "S\u00e9curit\u00e9" "MVP" "PARTIEL" "" "V\u00e9rifier HTTPS / hachage." }
    if (Has $cs 'AddRateLimiter') { C $m "Limitation de d\u00e9bit sur l'authentification" "MVP" "OK" "10 req/min/IP" "" } else { C $m "Limitation de d\u00e9bit" "MVP" "MANQUANT" "" "Ajouter." }
    if ((Has $pub 'flutter_localizations') -or (Has $dart 'AppLocalizations')) { C $m "Internationalisation fran\u00e7ais / anglais / arabe" "MVP" "OK" "" "" }
    else { C $m "Internationalisation fran\u00e7ais / anglais / arabe" "MVP" "MANQUANT" "textes cod\u00e9s en dur en fran\u00e7ais" "Ajouter flutter_localizations + fichiers .arb (fr, en, ar avec RTL)." }
    if (Test-Path (Join-Path $AppDir "ios")) { C $m "Compatibilit\u00e9 iOS" "MVP" "OK" "dossier ios pr\u00e9sent" "" } else { C $m "Compatibilit\u00e9 iOS" "MVP" "MANQUANT" "pas de dossier ios (projet cr\u00e9\u00e9 pour Android/Web/Windows)" "Sur un Mac : flutter create --platforms=ios . puis configurer l'adresse du serveur local." }
    if (Test-Path (Join-Path $AppDir "android")) { C $m "Compatibilit\u00e9 Android" "MVP" "OK" "dossier android pr\u00e9sent" "" } else { C $m "Compatibilit\u00e9 Android" "MVP" "MANQUANT" "" "flutter create --platforms=android ." }
    if (Test-Path (Join-Path $Racine "deploy\tests\load-test.js")) { C $m "Performance : API < 500 ms (test de charge k6)" "MVP" "PARTIEL" "script k6 pr\u00eat ; \u00e0 ex\u00e9cuter sur le serveur cible" "k6 run deploy\tests\load-test.js" }
    else { C $m "Performance : API < 500 ms" "MVP" "MANQUANT" "aucune mesure" "-Appliquer : deploy\tests\load-test.js (k6)." }
    C $m "Disponibilit\u00e9 99,5 %" "MVP" "PARTIEL" "restart: unless-stopped + healthcheck ; \u00e0 prouver par la supervision" ""

    # --- Tests
    $m = "Tests (section 10)"
    $nFact = ([regex]::Matches($tests, '\[Fact\]|\[Theory\]')).Count
    if ($nFact -gt 0) { C $m "Tests unitaires et API" "MVP" "OK" "$nFact m\u00e9thodes de test xUnit (+ cas Theory)" "" } else { C $m "Tests unitaires et API" "MVP" "MANQUANT" "" "Ajouter des tests." }
    if (Test-Path (Join-Path $AppDir "test")) { C $m "Tests Flutter" "MVP" "OK" "mobile\study_timer\test" "" } else { C $m "Tests Flutter" "MVP" "MANQUANT" "" "Ajouter." }
    if (Has $tests 'ExtrasTests') { C $m "Tests des modules sociaux / planificateur / salles" "V2" "OK" "ExtrasTests.cs" "" } else { C $m "Tests des modules sociaux / planificateur / salles" "V2" "MANQUANT" "" "-Appliquer : ExtrasTests.cs." }
    C $m "Tests de s\u00e9curit\u00e9 (autorisations, acc\u00e8s inter-utilisateurs)" "MVP" "PARTIEL" "401 sans jeton et isolation des mati\u00e8res test\u00e9s" "Ajouter des tests d'acc\u00e8s refus\u00e9 sur les nouvelles routes."
    C $m "Tests utilisateurs (ergonomie)" "MVP" "MANQUANT" "" "Organiser une session avec 5 \u00e9tudiants et consigner les retours."

    # --- Livrables
    $m = "Livrables (section 11)"
    C $m "Code source de l'application mobile" "MVP" "OK" "mobile\study_timer" ""
    C $m "Backend + Docker Compose + Nginx + sauvegardes" "MVP" "OK" "backend, docker-compose.yml, deploy" ""
    if (Test-Path (Join-Path $InfDir "Migrations")) { C $m "Scripts de cr\u00e9ation / migration de la base" "MVP" "OK" "migrations EF Core" "" } else { C $m "Scripts de migration" "MVP" "MANQUANT" "" "dotnet ef migrations add." }
    if (Test-Path (Join-Path $Racine "GUIDE.md")) { C $m "Documentation technique, guide d'installation et d'administration" "MVP" "OK" "GUIDE.md, docs\PROJET.md" "" } else { C $m "Documentation technique" "MVP" "MANQUANT" "" "R\u00e9diger GUIDE.md." }
    if (Has $cs 'AddSwaggerGen') { C $m "Documentation API (Swagger/OpenAPI)" "MVP" "OK" "/swagger" "" } else { C $m "Documentation API (Swagger)" "MVP" "MANQUANT" "" "Ajouter Swashbuckle." }
    C $m "Maquettes UI/UX (Figma)" "MVP" "MANQUANT" "non d\u00e9tectable dans le d\u00e9p\u00f4t" "Ajouter le lien ou l'export des maquettes dans docs\."
    $apk = @(Get-ChildItem (Join-Path $AppDir "build\app\outputs") -Recurse -Include *.apk,*.aab -ErrorAction SilentlyContinue)
    if ($apk.Count -gt 0) { C $m "Application Android installable (APK/AAB)" "MVP" "OK" $apk[0].Name "" } else { C $m "Application Android installable (APK/AAB)" "MVP" "MANQUANT" "aucun APK/AAB dans build\" "flutter build apk --release --dart-define=API_URL=http://<ip-serveur>:<port>" }
    if (Test-Path (Join-Path $AppDir "ios")) { C $m "Projet iOS + configuration r\u00e9seau local" "MVP" "PARTIEL" "dossier ios pr\u00e9sent" "" } else { C $m "Projet iOS + configuration r\u00e9seau local" "MVP" "MANQUANT" "" "Voir Compatibilit\u00e9 iOS." }
    if (Test-Path (Join-Path $Racine "docs\RAPPORT-ERREURS.txt")) { C $m "Rapport des tests" "MVP" "PARTIEL" "sortie brute de dotnet test / flutter test (docs\RAPPORT-ERREURS.txt)" "R\u00e9diger un rapport de tests structur\u00e9 (cas, r\u00e9sultat, couverture)." } else { C $m "Rapport des tests" "MVP" "MANQUANT" "" "R\u00e9diger." }

    return $Script:Res
}

function Score($res, [string]$phase) {
    $rows = @($res | Where-Object { ($phase -eq "ALL") -or ($_.Phase -eq $phase) })
    if ($rows.Count -eq 0) { return 0 }
    $pts = 0.0
    foreach ($r in $rows) { if ($r.Statut -eq "OK") { $pts += 1 } elseif ($r.Statut -eq "PARTIEL") { $pts += 0.5 } }
    return [math]::Round(100.0 * $pts / $rows.Count, 0)
}

function Afficher-Resume($res, [string]$titre) {
    Titre $titre
    $ok = @($res | Where-Object { $_.Statut -eq "OK" }).Count
    $pa = @($res | Where-Object { $_.Statut -eq "PARTIEL" }).Count
    $ma = @($res | Where-Object { $_.Statut -eq "MANQUANT" }).Count
    Write-Host (T ("  Points v\u00e9rifi\u00e9s : " + $res.Count + "  |  OK : " + $ok + "  |  Partiel : " + $pa + "  |  Manquant : " + $ma))
    Write-Host (T ("  Conformit\u00e9 globale : " + (Score $res "ALL") + " %   (MVP : " + (Score $res "MVP") + " %  |  V2 : " + (Score $res "V2") + " %  |  V3 : " + (Score $res "V3") + " %)")) -ForegroundColor White
    $mods = $res | Select-Object -ExpandProperty Module -Unique
    foreach ($mod in $mods) {
        $rows = @($res | Where-Object { $_.Module -eq $mod })
        $o = @($rows | Where-Object { $_.Statut -eq "OK" }).Count
        $col = "Green"
        $sc = Score $rows "ALL"
        if ($sc -lt 50) { $col = "Red" } elseif ($sc -lt 85) { $col = "Yellow" }
        Write-Host ("   {0,-52} {1,2}/{2,-2}  {3,3} %" -f (T $mod), $o, $rows.Count, $sc) -ForegroundColor $col
    }
}

function Ecrire-Rapport($res, $avant) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# Conformit\u00e9 au cahier des charges - StudyTimer")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("G\u00e9n\u00e9r\u00e9 le " + (Get-Date -Format "yyyy-MM-dd HH:mm") + " par Completer-Projet.ps1. Relancer le script pour mettre \u00e0 jour.")
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("**Conformit\u00e9 globale : " + (Score $res "ALL") + " %** (MVP " + (Score $res "MVP") + " %, V2 " + (Score $res "V2") + " %, V3 " + (Score $res "V3") + " %)")
    if ($avant -ne $null) { [void]$sb.AppendLine(""); [void]$sb.AppendLine("Avant -Appliquer : " + (Score $avant "ALL") + " %.") }
    [void]$sb.AppendLine("")
    [void]$sb.AppendLine("Statuts : OK = conforme, PARTIEL = existe mais incomplet ou diff\u00e9rent, MANQUANT = absent. Phase = priorisation du cahier (section 13).")
    [void]$sb.AppendLine("")
    foreach ($mod in ($res | Select-Object -ExpandProperty Module -Unique)) {
        [void]$sb.AppendLine("## " + $mod)
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("| Point | Phase | Statut | Constat |")
        [void]$sb.AppendLine("|---|---|---|---|")
        foreach ($r in @($res | Where-Object { $_.Module -eq $mod })) {
            $d = ($r.Detail -replace '\|','/')
            [void]$sb.AppendLine("| " + ($r.Item -replace '\|','/') + " | " + $r.Phase + " | " + $r.Statut + " | " + $d + " |")
        }
        [void]$sb.AppendLine("")
    }
    [void]$sb.AppendLine("## Reste \u00e0 faire (par priorit\u00e9)")
    [void]$sb.AppendLine("")
    foreach ($ph in @("MVP","V2","V3")) {
        $todo = @($res | Where-Object { $_.Phase -eq $ph -and $_.Statut -ne "OK" -and $_.Action })
        if ($todo.Count -eq 0) { continue }
        [void]$sb.AppendLine("### " + $ph)
        [void]$sb.AppendLine("")
        foreach ($r in $todo) { [void]$sb.AppendLine("- [ ] **" + $r.Item + "** (" + $r.Statut + ") : " + $r.Action) }
        [void]$sb.AppendLine("")
    }
    $docs = Join-Path $Racine "docs"
    New-Item -ItemType Directory -Force -Path $docs | Out-Null
    $out = Join-Path $docs "CONFORMITE.md"
    [System.IO.File]::WriteAllText($out, (T $sb.ToString()), (New-Object System.Text.UTF8Encoding($false)))
    Ok "Rapport \u00e9crit : docs\CONFORMITE.md"
}

# ----------------------------------------------------------------------------
# Execution : diagnostic
# ----------------------------------------------------------------------------
Write-Host ""
Write-Host (T "=== StudyTimer : comparaison avec le cahier des charges ===") -ForegroundColor Cyan
Write-Host ("Projet : " + $Racine)

$avant = Analyser
Afficher-Resume $avant "DIAGNOSTIC INITIAL"
Ecrire-Rapport $avant $null

if (-not $Appliquer) {
    Write-Host ""
    Write-Host (T "Aucune modification faite. Pour g\u00e9n\u00e9rer les modules manquants : .\Completer-Projet.ps1 -Appliquer  (ajoutez -Verifier pour compiler et tester)") -ForegroundColor Yellow
    exit 0
}

# ----------------------------------------------------------------------------
# COMPLETION
# ----------------------------------------------------------------------------
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SauvegardeDir = Join-Path $Racine ("archive\sauvegarde-completer-" + $Stamp)
$Script:Crees = New-Object System.Collections.ArrayList
$Script:Sauves = @{}
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Rel([string]$p) { return $p.Substring($Racine.Length).TrimStart('\','/') }

function Sauver([string]$p) {
    if (-not (Test-Path -LiteralPath $p)) { return }
    if ($Script:Sauves.ContainsKey($p)) { return }
    $dest = Join-Path $SauvegardeDir (Rel $p)
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item -LiteralPath $p -Destination $dest -Force
    $Script:Sauves[$p] = $dest
}

function Ecrire([string]$p, [string]$txt) {
    if ((Test-Path -LiteralPath $p) -and (-not $Forcer)) { Info ("existe d\u00e9j\u00e0 : " + (Rel $p)); return }
    if (Test-Path -LiteralPath $p) { Sauver $p } else { [void]$Script:Crees.Add($p) }
    New-Item -ItemType Directory -Force -Path (Split-Path $p) | Out-Null
    [System.IO.File]::WriteAllText($p, $txt, $Utf8)
    Ok ("cr\u00e9\u00e9 : " + (Rel $p))
}

function Patcher([string]$chemin, [string]$dejaRegex, [string]$ancreRegex, [string]$ajout, [switch]$Avant, [switch]$Remplacer) {
    $nom = Rel $chemin
    if (-not (Test-Path -LiteralPath $chemin)) { Warn ("introuvable : " + $nom); return $false }
    $txt = [System.IO.File]::ReadAllText($chemin, [System.Text.Encoding]::UTF8)
    if ($dejaRegex -and [regex]::IsMatch($txt, $dejaRegex)) { Info ("d\u00e9j\u00e0 \u00e0 jour : " + $nom); return $true }
    $m = [regex]::Match($txt, $ancreRegex)
    if (-not $m.Success) { Warn ("point d'ancrage introuvable dans " + $nom + " : modification \u00e0 faire \u00e0 la main (voir docs\CONFORMITE.md)"); return $false }
    Sauver $chemin
    $nl = "`n"
    if ($txt.Contains("`r`n")) { $nl = "`r`n" }
    $ins = [regex]::Replace($ajout, '\r?\n', $nl)
    if ($Remplacer) { $new = $txt.Substring(0, $m.Index) + $ins + $txt.Substring($m.Index + $m.Length) }
    elseif ($Avant) { $new = $txt.Substring(0, $m.Index) + $ins + $txt.Substring($m.Index) }
    else { $new = $txt.Substring(0, $m.Index + $m.Length) + $ins + $txt.Substring($m.Index + $m.Length) }
    [System.IO.File]::WriteAllText($chemin, $new, $Utf8)
    Ok ("modifi\u00e9 : " + $nom)
    return $true
}

function Annuler-Tout {
    Warn "Annulation des modifications..."
    foreach ($p in $Script:Crees) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
    foreach ($k in $Script:Sauves.Keys) { Copy-Item -LiteralPath $Script:Sauves[$k] -Destination $k -Force }
    Ok ("Projet remis dans son \u00e9tat d'origine (sauvegardes conserv\u00e9es dans " + (Rel $SauvegardeDir) + ")")
}

Titre "COMPL\u00c9TION : g\u00e9n\u00e9ration des modules manquants"

# ============================================================================
# Gabarits C# (le texte utilise \uXXXX nativement : aucun accent dans ce script)
# ============================================================================

$TplSocial = @'
namespace StudyTimer.Domain.Entities;

public enum RequestStatus { Pending, Accepted, Declined }

/// <summary>Relation d'amitie (demande puis acceptation).</summary>
public class Friendship
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RequesterId { get; set; }
    public Guid AddresseeId { get; set; }
    public RequestStatus Status { get; set; } = RequestStatus.Pending;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

/// <summary>RG07 : ce que l'utilisateur laisse voir a ses amis.</summary>
public class UserPrivacy
{
    public Guid UserId { get; set; }
    public bool ShowStats { get; set; } = true;
    public bool ShowActivity { get; set; } = true;
}

public class ChallengeInvitation
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid ChallengeId { get; set; }
    public Guid InviterId { get; set; }
    public Guid InviteeId { get; set; }
    public RequestStatus Status { get; set; } = RequestStatus.Pending;
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

/// <summary>Notification applicative (centre de notifications de l'application).</summary>
public class AppNotification
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public string Type { get; set; } = "";
    public string Title { get; set; } = "";
    public string Body { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
    public DateTime? ReadAtUtc { get; set; }
}
'@

$TplPlanner = @'
namespace StudyTimer.Domain.Entities;

public enum TaskPriority { Low, Medium, High }

/// <summary>Tache du planificateur d'etude.</summary>
public class TaskItem
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid UserId { get; set; }
    public Guid? SubjectId { get; set; }
    public string Title { get; set; } = "";
    public DateTime? DueAtUtc { get; set; }
    public int? EstimatedMinutes { get; set; }
    public TaskPriority Priority { get; set; } = TaskPriority.Medium;
    public bool IsDone { get; set; }
    public DateTime? CompletedAtUtc { get; set; }
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}
'@

$TplRooms = @'
namespace StudyTimer.Domain.Entities;

public class StudyRoom
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid OwnerId { get; set; }
    public string Name { get; set; } = "";
    public bool IsPublic { get; set; } = true;
    public string Code { get; set; } = "";
    public DateTime CreatedAtUtc { get; set; } = DateTime.UtcNow;
}

public class RoomParticipant
{
    public Guid RoomId { get; set; }
    public Guid UserId { get; set; }
    public DateTime JoinedAtUtc { get; set; } = DateTime.UtcNow;
}

public class RoomMessage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public Guid RoomId { get; set; }
    public Guid UserId { get; set; }
    public string Text { get; set; } = "";
    public DateTime SentAtUtc { get; set; } = DateTime.UtcNow;
}
'@

$TplDbSets = @'

    public DbSet<Friendship> Friendships => Set<Friendship>();
    public DbSet<UserPrivacy> UserPrivacies => Set<UserPrivacy>();
    public DbSet<ChallengeInvitation> ChallengeInvitations => Set<ChallengeInvitation>();
    public DbSet<AppNotification> Notifications => Set<AppNotification>();
    public DbSet<TaskItem> TaskItems => Set<TaskItem>();
    public DbSet<StudyRoom> StudyRooms => Set<StudyRoom>();
    public DbSet<RoomParticipant> RoomParticipants => Set<RoomParticipant>();
    public DbSet<RoomMessage> RoomMessages => Set<RoomMessage>();
'@

$TplDbModel = @'

        b.Entity<Friendship>().HasIndex(f => new { f.RequesterId, f.AddresseeId }).IsUnique();
        b.Entity<UserPrivacy>().HasKey(p => p.UserId);
        b.Entity<ChallengeInvitation>().HasIndex(i => new { i.ChallengeId, i.InviteeId });
        b.Entity<AppNotification>().HasIndex(n => new { n.UserId, n.CreatedAtUtc });
        b.Entity<TaskItem>().HasIndex(t => new { t.UserId, t.DueAtUtc });
        b.Entity<StudyRoom>().HasIndex(r => r.Code).IsUnique();
        b.Entity<RoomParticipant>().HasKey(p => new { p.RoomId, p.UserId });
        b.Entity<RoomMessage>().HasIndex(m => new { m.RoomId, m.SentAtUtc });
'@

$TplHub = @'
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Hubs;

/// <summary>Temps reel (cahier 5.1) : les clients rejoignent le groupe d'une salle pour recevoir les messages.</summary>
[Authorize]
public class StudyHub : Hub
{
    private readonly AppDbContext _db;
    public StudyHub(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(Context.User!.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? Context.User!.FindFirstValue("sub")!);

    public async Task JoinRoom(Guid roomId)
    {
        var uid = UserId;
        if (!await _db.RoomParticipants.AnyAsync(p => p.RoomId == roomId && p.UserId == uid))
            throw new HubException("Vous n'etes pas membre de cette salle.");
        await Groups.AddToGroupAsync(Context.ConnectionId, $"room-{roomId}");
    }

    public Task LeaveRoom(Guid roomId) =>
        Groups.RemoveFromGroupAsync(Context.ConnectionId, $"room-{roomId}");
}
'@

$TplFriends = @'
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record InviteFriendDto(string Username);

/// <summary>Module 4 : amis, activite et statistiques des amis (respecte RG07).</summary>
[ApiController, Authorize]
[Route("api/friends")]
public class FriendsController : ControllerBase
{
    private readonly AppDbContext _db;
    public FriendsController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    private async Task<List<Guid>> FriendIds()
    {
        var rows = await _db.Friendships.AsNoTracking()
            .Where(f => f.Status == RequestStatus.Accepted && (f.RequesterId == UserId || f.AddresseeId == UserId))
            .Select(f => new { f.RequesterId, f.AddresseeId })
            .ToListAsync();
        return rows.Select(r => r.RequesterId == UserId ? r.AddresseeId : r.RequesterId).Distinct().ToList();
    }

    private async Task<Dictionary<Guid, string>> Names(IEnumerable<Guid> ids)
    {
        var list = ids.Distinct().ToList();
        return await _db.Users.AsNoTracking().Where(u => list.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);
    }

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var ids = await FriendIds();
        var users = await _db.Users.AsNoTracking().Where(u => ids.Contains(u.Id))
            .OrderBy(u => u.Username).Select(u => new { u.Id, u.Username }).ToListAsync();
        return Ok(users);
    }

    [HttpGet("search")]
    public async Task<IActionResult> Search([FromQuery] string q = "")
    {
        q = (q ?? "").Trim().ToLower();
        if (q.Length < 2) return Ok(Array.Empty<object>());
        var users = await _db.Users.AsNoTracking()
            .Where(u => u.Id != UserId && u.Username.ToLower().Contains(q))
            .OrderBy(u => u.Username).Take(10)
            .Select(u => new { u.Id, u.Username }).ToListAsync();
        return Ok(users);
    }

    [HttpPost("invite")]
    public async Task<IActionResult> Invite(InviteFriendDto dto)
    {
        var name = (dto.Username ?? "").Trim().ToLower();
        if (name.Length == 0) return BadRequest("Pseudo requis.");
        var target = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == name);
        if (target is null) return NotFound("Utilisateur introuvable.");
        if (target.Id == UserId) return BadRequest("Vous ne pouvez pas vous inviter vous-m\u00eame.");

        var existing = await _db.Friendships.FirstOrDefaultAsync(f =>
            (f.RequesterId == UserId && f.AddresseeId == target.Id) ||
            (f.RequesterId == target.Id && f.AddresseeId == UserId));
        if (existing is not null)
        {
            if (existing.Status != RequestStatus.Declined) return Conflict("Invitation ou amiti\u00e9 d\u00e9j\u00e0 existante.");
            _db.Friendships.Remove(existing);
            await _db.SaveChangesAsync();
        }

        var me = await _db.Users.AsNoTracking().Where(u => u.Id == UserId).Select(u => u.Username).FirstAsync();
        var f = new Friendship { RequesterId = UserId, AddresseeId = target.Id };
        _db.Friendships.Add(f);
        Notifier.Add(_db, target.Id, "friend_invite", "Nouvelle invitation", $"{me} vous invite \u00e0 devenir ami.");
        await _db.SaveChangesAsync();
        return Ok(new { f.Id });
    }

    [HttpGet("requests")]
    public async Task<IActionResult> Requests()
    {
        var rows = await _db.Friendships.AsNoTracking()
            .Where(f => f.AddresseeId == UserId && f.Status == RequestStatus.Pending)
            .OrderByDescending(f => f.CreatedAtUtc)
            .Select(f => new { f.Id, f.RequesterId, f.CreatedAtUtc })
            .ToListAsync();
        var names = await Names(rows.Select(r => r.RequesterId));
        return Ok(rows.Select(r => new
        {
            r.Id, r.RequesterId, Username = names.GetValueOrDefault(r.RequesterId, "?"), r.CreatedAtUtc
        }));
    }

    [HttpPost("{id:guid}/accept")]
    public async Task<IActionResult> Accept(Guid id)
    {
        var f = await _db.Friendships.FirstOrDefaultAsync(x =>
            x.Id == id && x.AddresseeId == UserId && x.Status == RequestStatus.Pending);
        if (f is null) return NotFound();
        f.Status = RequestStatus.Accepted;
        var me = await _db.Users.AsNoTracking().Where(u => u.Id == UserId).Select(u => u.Username).FirstAsync();
        Notifier.Add(_db, f.RequesterId, "friend_accepted", "Invitation accept\u00e9e", $"{me} a accept\u00e9 votre invitation.");
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("{id:guid}/decline")]
    public async Task<IActionResult> Decline(Guid id)
    {
        var f = await _db.Friendships.FirstOrDefaultAsync(x =>
            x.Id == id && x.AddresseeId == UserId && x.Status == RequestStatus.Pending);
        if (f is null) return NotFound();
        f.Status = RequestStatus.Declined;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpDelete("{userId:guid}")]
    public async Task<IActionResult> Remove(Guid userId)
    {
        var rows = await _db.Friendships.Where(f =>
            (f.RequesterId == UserId && f.AddresseeId == userId) ||
            (f.RequesterId == userId && f.AddresseeId == UserId)).ToListAsync();
        if (rows.Count == 0) return NotFound();
        _db.Friendships.RemoveRange(rows);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    /// <summary>Statistiques publiques d'un ami (RG07 : refuse si l'ami les a masquees).</summary>
    [HttpGet("{userId:guid}/stats")]
    public async Task<IActionResult> FriendStats(Guid userId)
    {
        if (!(await FriendIds()).Contains(userId)) return Forbid();
        var privacy = await _db.UserPrivacies.AsNoTracking().FirstOrDefaultAsync(p => p.UserId == userId);
        if (privacy is not null && !privacy.ShowStats) return Forbid();

        var now = DateTime.UtcNow;
        var weekStart = now.Date.AddDays(-(((int)now.DayOfWeek + 6) % 7));
        var rows = await _db.StudySessions.AsNoTracking()
            .Where(s => s.UserId == userId && s.Status == SessionStatus.Completed)
            .Select(s => new { s.StartedAtUtc, s.AccumulatedSeconds, s.XpAwarded })
            .ToListAsync();
        var xp = rows.Sum(r => r.XpAwarded);
        return Ok(new
        {
            TotalSeconds = rows.Sum(r => r.AccumulatedSeconds),
            WeekSeconds = rows.Where(r => r.StartedAtUtc >= weekStart).Sum(r => r.AccumulatedSeconds),
            SessionsCount = rows.Count,
            Xp = xp,
            Level = Gamification.Level(xp).level
        });
    }

    /// <summary>Activite recente des amis (hors amis qui masquent leur activite).</summary>
    [HttpGet("feed")]
    public async Task<IActionResult> Feed()
    {
        var ids = await FriendIds();
        var hidden = await _db.UserPrivacies.AsNoTracking()
            .Where(p => ids.Contains(p.UserId) && !p.ShowActivity)
            .Select(p => p.UserId).ToListAsync();
        var visible = ids.Except(hidden).ToList();
        var items = await _db.StudySessions.AsNoTracking()
            .Where(s => visible.Contains(s.UserId) && s.Status == SessionStatus.Completed)
            .OrderByDescending(s => s.EndedAtUtc).Take(30)
            .Select(s => new { s.UserId, s.Mode, s.AccumulatedSeconds, s.EndedAtUtc })
            .ToListAsync();
        var names = await Names(items.Select(i => i.UserId));
        return Ok(items.Select(i => new
        {
            Username = names.GetValueOrDefault(i.UserId, "?"),
            Mode = i.Mode.ToString(),
            Seconds = i.AccumulatedSeconds,
            i.EndedAtUtc
        }));
    }

    /// <summary>Classement entre amis (moi inclus) : period = week | month | all.</summary>
    [HttpGet("leaderboard")]
    public async Task<IActionResult> Leaderboard([FromQuery] string period = "week")
    {
        var ids = await FriendIds();
        ids.Add(UserId);
        var now = DateTime.UtcNow;
        var from = period switch
        {
            "month" => new DateTime(now.Year, now.Month, 1, 0, 0, 0, DateTimeKind.Utc),
            "all" => DateTime.MinValue,
            _ => now.Date.AddDays(-(((int)now.DayOfWeek + 6) % 7))
        };
        var rows = await _db.StudySessions.AsNoTracking()
            .Where(s => ids.Contains(s.UserId) && s.Status == SessionStatus.Completed && s.StartedAtUtc >= from)
            .GroupBy(s => s.UserId)
            .Select(g => new { UserId = g.Key, Seconds = g.Sum(x => x.AccumulatedSeconds) })
            .ToListAsync();
        var names = await Names(ids);
        var ranking = ids
            .Select(id => new { Id = id, Seconds = rows.Where(r => r.UserId == id).Sum(r => r.Seconds) })
            .OrderByDescending(x => x.Seconds)
            .Select((x, i) => new
            {
                Rank = i + 1,
                Username = names.GetValueOrDefault(x.Id, "?"),
                x.Seconds,
                IsMe = x.Id == UserId
            });
        return Ok(ranking);
    }
}

public record PrivacyDto(bool ShowStats, bool ShowActivity);

/// <summary>RG07 : choix de visibilite du profil pour les amis.</summary>
[ApiController, Authorize]
[Route("api/users/privacy")]
public class PrivacyController : ControllerBase
{
    private readonly AppDbContext _db;
    public PrivacyController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet]
    public async Task<IActionResult> Get()
    {
        var p = await _db.UserPrivacies.AsNoTracking().FirstOrDefaultAsync(x => x.UserId == UserId);
        return Ok(new { ShowStats = p?.ShowStats ?? true, ShowActivity = p?.ShowActivity ?? true });
    }

    [HttpPut]
    public async Task<IActionResult> Put(PrivacyDto dto)
    {
        var p = await _db.UserPrivacies.FirstOrDefaultAsync(x => x.UserId == UserId);
        if (p is null)
        {
            p = new UserPrivacy { UserId = UserId };
            _db.UserPrivacies.Add(p);
        }
        p.ShowStats = dto.ShowStats;
        p.ShowActivity = dto.ShowActivity;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}
'@

$TplNotifications = @'
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

/// <summary>Aide pour creer une notification dans la meme transaction que l'action qui la declenche.</summary>
public static class Notifier
{
    public static void Add(AppDbContext db, Guid userId, string type, string title, string body) =>
        db.Notifications.Add(new AppNotification { UserId = userId, Type = type, Title = title, Body = body });
}

[ApiController, Authorize]
[Route("api/notifications")]
public class NotificationsController : ControllerBase
{
    private readonly AppDbContext _db;
    public NotificationsController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var items = await _db.Notifications.AsNoTracking()
            .Where(n => n.UserId == UserId)
            .OrderByDescending(n => n.CreatedAtUtc).Take(50)
            .Select(n => new { n.Id, n.Type, n.Title, n.Body, n.CreatedAtUtc, Read = n.ReadAtUtc != null })
            .ToListAsync();
        var unread = await _db.Notifications.CountAsync(n => n.UserId == UserId && n.ReadAtUtc == null);
        return Ok(new { Unread = unread, Items = items });
    }

    [HttpPost("{id:guid}/read")]
    public async Task<IActionResult> Read(Guid id)
    {
        var n = await _db.Notifications.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (n is null) return NotFound();
        n.ReadAtUtc ??= DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("read-all")]
    public async Task<IActionResult> ReadAll()
    {
        var rows = await _db.Notifications.Where(n => n.UserId == UserId && n.ReadAtUtc == null).ToListAsync();
        foreach (var n in rows) n.ReadAtUtc = DateTime.UtcNow;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}
'@

$TplTasks = @'
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record TaskDto(string Title, Guid? SubjectId, DateTime? DueAtUtc, int? EstimatedMinutes, string? Priority);

/// <summary>Module 8 : planificateur d'etude.</summary>
[ApiController, Authorize]
[Route("api/tasks")]
public class TasksController : ControllerBase
{
    private readonly AppDbContext _db;
    public TasksController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    private static DateTime Utc(DateTime d) =>
        d.Kind == DateTimeKind.Utc ? d
        : d.Kind == DateTimeKind.Local ? d.ToUniversalTime()
        : DateTime.SpecifyKind(d, DateTimeKind.Utc);

    private static object Map(TaskItem t, DateTime now) => new
    {
        t.Id, t.Title, t.SubjectId, t.DueAtUtc, t.EstimatedMinutes,
        Priority = t.Priority.ToString(), t.IsDone, t.CompletedAtUtc,
        Overdue = !t.IsDone && t.DueAtUtc != null && t.DueAtUtc < now
    };

    private async Task<string?> Apply(TaskItem t, TaskDto dto)
    {
        var title = (dto.Title ?? "").Trim();
        if (title.Length == 0 || title.Length > 120) return "Titre requis (120 caract\u00e8res max).";
        if (dto.EstimatedMinutes is < 1 or > 1440) return "Dur\u00e9e estim\u00e9e : 1 \u00e0 1440 minutes.";
        var priority = TaskPriority.Medium;
        if (!string.IsNullOrWhiteSpace(dto.Priority) && !Enum.TryParse(dto.Priority, true, out priority))
            return "Priorit\u00e9 invalide (Low, Medium, High).";
        if (dto.SubjectId.HasValue &&
            !await _db.Subjects.AnyAsync(s => s.Id == dto.SubjectId && s.UserId == UserId))
            return "Mati\u00e8re inconnue.";

        t.Title = title;
        t.SubjectId = dto.SubjectId;
        t.DueAtUtc = dto.DueAtUtc.HasValue ? Utc(dto.DueAtUtc.Value) : null;
        t.EstimatedMinutes = dto.EstimatedMinutes;
        t.Priority = priority;
        return null;
    }

    [HttpPost]
    public async Task<IActionResult> Create(TaskDto dto)
    {
        var t = new TaskItem { UserId = UserId };
        var error = await Apply(t, dto);
        if (error is not null) return BadRequest(error);
        _db.TaskItems.Add(t);
        await _db.SaveChangesAsync();
        return Ok(Map(t, DateTime.UtcNow));
    }

    /// <summary>status = all | open | done | overdue ; from/to filtrent sur l'echeance (calendrier).</summary>
    [HttpGet]
    public async Task<IActionResult> List([FromQuery] string status = "all",
        [FromQuery(Name = "from")] DateTime? fromUtc = null, [FromQuery(Name = "to")] DateTime? toUtc = null)
    {
        var now = DateTime.UtcNow;
        var q = _db.TaskItems.AsNoTracking().Where(t => t.UserId == UserId);
        q = status switch
        {
            "open" => q.Where(t => !t.IsDone),
            "done" => q.Where(t => t.IsDone),
            "overdue" => q.Where(t => !t.IsDone && t.DueAtUtc != null && t.DueAtUtc < now),
            _ => q
        };
        if (fromUtc.HasValue) { var f = Utc(fromUtc.Value); q = q.Where(t => t.DueAtUtc != null && t.DueAtUtc >= f); }
        if (toUtc.HasValue) { var e = Utc(toUtc.Value); q = q.Where(t => t.DueAtUtc != null && t.DueAtUtc <= e); }
        var items = await q.OrderBy(t => t.IsDone).ThenBy(t => t.DueAtUtc == null).ThenBy(t => t.DueAtUtc)
            .Take(300).ToListAsync();
        return Ok(items.Select(t => Map(t, now)));
    }

    [HttpGet("overdue")]
    public async Task<IActionResult> Overdue()
    {
        var now = DateTime.UtcNow;
        var items = await _db.TaskItems.AsNoTracking()
            .Where(t => t.UserId == UserId && !t.IsDone && t.DueAtUtc != null && t.DueAtUtc < now)
            .OrderBy(t => t.DueAtUtc).ToListAsync();
        return Ok(items.Select(t => Map(t, now)));
    }

    [HttpPut("{id:guid}")]
    public async Task<IActionResult> Update(Guid id, TaskDto dto)
    {
        var t = await _db.TaskItems.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (t is null) return NotFound();
        var error = await Apply(t, dto);
        if (error is not null) return BadRequest(error);
        await _db.SaveChangesAsync();
        return Ok(Map(t, DateTime.UtcNow));
    }

    [HttpPost("{id:guid}/complete")]
    public async Task<IActionResult> Complete(Guid id)
    {
        var t = await _db.TaskItems.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (t is null) return NotFound();
        if (!t.IsDone)
        {
            t.IsDone = true;
            t.CompletedAtUtc = DateTime.UtcNow;
            await _db.SaveChangesAsync();
        }
        return Ok(Map(t, DateTime.UtcNow));
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var t = await _db.TaskItems.FirstOrDefaultAsync(x => x.Id == id && x.UserId == UserId);
        if (t is null) return NotFound();
        _db.TaskItems.Remove(t);
        await _db.SaveChangesAsync();
        return NoContent();
    }
}
'@

$TplRoomsCtl = @'
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Api.Hubs;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record CreateRoomDto(string Name, bool IsPublic = true);
public record JoinRoomDto(string Code);
public record SendMessageDto(string Text);

/// <summary>Module 7 : salles d'etude collaboratives (publiques, privees, par code) + chat.</summary>
[ApiController, Authorize]
[Route("api/rooms")]
public class RoomsController : ControllerBase
{
    private readonly AppDbContext _db;
    private readonly IHubContext<StudyHub> _hub;
    public RoomsController(AppDbContext db, IHubContext<StudyHub> hub) { _db = db; _hub = hub; }

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    private static DateTime Utc(DateTime d) =>
        d.Kind == DateTimeKind.Utc ? d
        : d.Kind == DateTimeKind.Local ? d.ToUniversalTime()
        : DateTime.SpecifyKind(d, DateTimeKind.Utc);

    private static string NewCode()
    {
        const string alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
        var chars = new char[6];
        for (int i = 0; i < chars.Length; i++)
            chars[i] = alphabet[System.Security.Cryptography.RandomNumberGenerator.GetInt32(alphabet.Length)];
        return new string(chars);
    }

    private Task<bool> IsMember(Guid roomId) =>
        _db.RoomParticipants.AnyAsync(p => p.RoomId == roomId && p.UserId == UserId);

    [HttpPost]
    public async Task<IActionResult> Create(CreateRoomDto dto)
    {
        var name = (dto.Name ?? "").Trim();
        if (name.Length == 0 || name.Length > 60) return BadRequest("Nom requis (60 caract\u00e8res max).");

        string code = NewCode();
        for (int i = 0; i < 5 && await _db.StudyRooms.AnyAsync(r => r.Code == code); i++) code = NewCode();

        var room = new StudyRoom { OwnerId = UserId, Name = name, IsPublic = dto.IsPublic, Code = code };
        _db.StudyRooms.Add(room);
        _db.RoomParticipants.Add(new RoomParticipant { RoomId = room.Id, UserId = UserId });
        await _db.SaveChangesAsync();
        return Ok(new { room.Id, room.Code });
    }

    [HttpGet]
    public async Task<IActionResult> List()
    {
        var mine = await _db.RoomParticipants.AsNoTracking()
            .Where(p => p.UserId == UserId).Select(p => p.RoomId).ToListAsync();
        var rooms = await _db.StudyRooms.AsNoTracking()
            .Where(r => r.IsPublic || mine.Contains(r.Id))
            .OrderByDescending(r => r.CreatedAtUtc).Take(100).ToListAsync();
        var rids = rooms.Select(r => r.Id).ToList();
        var counts = await _db.RoomParticipants.AsNoTracking()
            .Where(p => rids.Contains(p.RoomId))
            .GroupBy(p => p.RoomId)
            .Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => x.N);
        return Ok(rooms.Select(r => new
        {
            r.Id, r.Name, r.IsPublic,
            Participants = counts.GetValueOrDefault(r.Id),
            Joined = mine.Contains(r.Id)
        }));
    }

    /// <summary>Rejoindre par code (salle privee ou publique).</summary>
    [HttpPost("join")]
    public async Task<IActionResult> JoinByCode(JoinRoomDto dto)
    {
        var code = (dto.Code ?? "").Trim().ToUpperInvariant();
        var room = await _db.StudyRooms.AsNoTracking().FirstOrDefaultAsync(r => r.Code == code);
        if (room is null) return NotFound("Code inconnu.");
        if (!await IsMember(room.Id))
        {
            _db.RoomParticipants.Add(new RoomParticipant { RoomId = room.Id, UserId = UserId });
            await _db.SaveChangesAsync();
        }
        return Ok(new { room.Id, room.Name });
    }

    /// <summary>Rejoindre une salle publique.</summary>
    [HttpPost("{id:guid}/join")]
    public async Task<IActionResult> Join(Guid id)
    {
        var room = await _db.StudyRooms.AsNoTracking().FirstOrDefaultAsync(r => r.Id == id);
        if (room is null || (!room.IsPublic && !await IsMember(id))) return NotFound();
        if (!await IsMember(id))
        {
            _db.RoomParticipants.Add(new RoomParticipant { RoomId = id, UserId = UserId });
            await _db.SaveChangesAsync();
        }
        return NoContent();
    }

    [HttpPost("{id:guid}/leave")]
    public async Task<IActionResult> Leave(Guid id)
    {
        var p = await _db.RoomParticipants.FirstOrDefaultAsync(x => x.RoomId == id && x.UserId == UserId);
        if (p is null) return NotFound();
        _db.RoomParticipants.Remove(p);
        await _db.SaveChangesAsync();

        if (!await _db.RoomParticipants.AnyAsync(x => x.RoomId == id))
        {
            _db.RoomMessages.RemoveRange(_db.RoomMessages.Where(m => m.RoomId == id));
            _db.StudyRooms.RemoveRange(_db.StudyRooms.Where(r => r.Id == id));
            await _db.SaveChangesAsync();
        }
        return NoContent();
    }

    /// <summary>Detail d'une salle : participants, statut (Studying / Paused / Offline) et temps du jour.</summary>
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id)
    {
        var room = await _db.StudyRooms.AsNoTracking().FirstOrDefaultAsync(r => r.Id == id);
        if (room is null) return NotFound();
        var ids = await _db.RoomParticipants.AsNoTracking()
            .Where(p => p.RoomId == id).Select(p => p.UserId).ToListAsync();
        if (!ids.Contains(UserId)) return Forbid();

        var names = await _db.Users.AsNoTracking().Where(u => ids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);
        var active = await _db.StudySessions.AsNoTracking()
            .Where(s => ids.Contains(s.UserId) &&
                        (s.Status == SessionStatus.Running || s.Status == SessionStatus.Paused))
            .Select(s => new { s.UserId, s.Status }).ToListAsync();
        var dayStart = DateTime.UtcNow.Date;
        var today = await _db.StudySessions.AsNoTracking()
            .Where(s => ids.Contains(s.UserId) && s.Status == SessionStatus.Completed && s.StartedAtUtc >= dayStart)
            .GroupBy(s => s.UserId)
            .Select(g => new { UserId = g.Key, Seconds = g.Sum(x => x.AccumulatedSeconds) })
            .ToListAsync();

        var participants = ids.Select(uid => new
        {
            UserId = uid,
            Username = names.GetValueOrDefault(uid, "?"),
            Status = active.Any(a => a.UserId == uid && a.Status == SessionStatus.Running) ? "Studying"
                   : active.Any(a => a.UserId == uid) ? "Paused" : "Offline",
            TodaySeconds = today.Where(t => t.UserId == uid).Sum(t => t.Seconds)
        }).OrderBy(p => p.Username).ToList();

        return Ok(new { room.Id, room.Name, room.Code, room.IsPublic, IsOwner = room.OwnerId == UserId, Participants = participants });
    }

    [HttpGet("{id:guid}/messages")]
    public async Task<IActionResult> Messages(Guid id, [FromQuery] DateTime? after = null)
    {
        if (!await IsMember(id)) return Forbid();
        var q = _db.RoomMessages.AsNoTracking().Where(m => m.RoomId == id);
        if (after.HasValue) { var a = Utc(after.Value); q = q.Where(m => m.SentAtUtc > a); }
        var rows = await q.OrderByDescending(m => m.SentAtUtc).Take(100).ToListAsync();
        rows.Reverse();
        var uids = rows.Select(m => m.UserId).Distinct().ToList();
        var names = await _db.Users.AsNoTracking().Where(u => uids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);
        return Ok(rows.Select(m => new
        {
            m.Id, m.UserId, Username = names.GetValueOrDefault(m.UserId, "?"), m.Text, m.SentAtUtc
        }));
    }

    [HttpPost("{id:guid}/messages")]
    public async Task<IActionResult> Send(Guid id, SendMessageDto dto)
    {
        if (!await IsMember(id)) return Forbid();
        var text = (dto.Text ?? "").Trim();
        if (text.Length is 0 or > 500) return BadRequest("Message : 1 \u00e0 500 caract\u00e8res.");

        var m = new RoomMessage { RoomId = id, UserId = UserId, Text = text };
        _db.RoomMessages.Add(m);
        await _db.SaveChangesAsync();

        var me = await _db.Users.AsNoTracking().Where(u => u.Id == UserId).Select(u => u.Username).FirstAsync();
        var payload = new { m.Id, m.UserId, Username = me, m.Text, m.SentAtUtc };
        await _hub.Clients.Group($"room-{id}").SendAsync("message", payload);
        return Ok(payload);
    }
}
'@

$TplInvites = @'
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

public record ChallengeInviteDto(string Username);

/// <summary>Invitations aux defis (cahier module 3) ; RG06 : refusees apres la date limite.</summary>
[ApiController, Authorize]
[Route("api/challenges")]
public class ChallengeInvitesController : ControllerBase
{
    private readonly AppDbContext _db;
    public ChallengeInvitesController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpPost("{id:guid}/invite")]
    public async Task<IActionResult> Invite(Guid id, ChallengeInviteDto dto)
    {
        var c = await _db.Challenges.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id);
        if (c is null) return NotFound();
        if (c.EndsAtUtc < DateTime.UtcNow) return BadRequest("Ce d\u00e9fi est termin\u00e9.");
        if (!await _db.ChallengeParticipants.AnyAsync(p => p.ChallengeId == id && p.UserId == UserId)) return Forbid();

        var name = (dto.Username ?? "").Trim().ToLower();
        var target = await _db.Users.FirstOrDefaultAsync(u => u.Username.ToLower() == name);
        if (target is null) return NotFound("Utilisateur introuvable.");
        if (await _db.ChallengeParticipants.AnyAsync(p => p.ChallengeId == id && p.UserId == target.Id))
            return Conflict("D\u00e9j\u00e0 participant.");
        if (await _db.ChallengeInvitations.AnyAsync(i =>
                i.ChallengeId == id && i.InviteeId == target.Id && i.Status == RequestStatus.Pending))
            return Conflict("Invitation d\u00e9j\u00e0 envoy\u00e9e.");

        var me = await _db.Users.AsNoTracking().Where(u => u.Id == UserId).Select(u => u.Username).FirstAsync();
        var inv = new ChallengeInvitation { ChallengeId = id, InviterId = UserId, InviteeId = target.Id };
        _db.ChallengeInvitations.Add(inv);
        Notifier.Add(_db, target.Id, "challenge_invite", "Invitation \u00e0 un d\u00e9fi", $"{me} vous invite au d\u00e9fi \u00ab {c.Title} \u00bb.");
        await _db.SaveChangesAsync();
        return Ok(new { inv.Id });
    }

    [HttpGet("invitations")]
    public async Task<IActionResult> Pending()
    {
        var rows = await _db.ChallengeInvitations.AsNoTracking()
            .Where(i => i.InviteeId == UserId && i.Status == RequestStatus.Pending)
            .OrderByDescending(i => i.CreatedAtUtc).ToListAsync();
        var cids = rows.Select(r => r.ChallengeId).Distinct().ToList();
        var titles = await _db.Challenges.AsNoTracking().Where(c => cids.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, c => c.Title);
        var uids = rows.Select(r => r.InviterId).Distinct().ToList();
        var names = await _db.Users.AsNoTracking().Where(u => uids.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username);
        return Ok(rows.Select(r => new
        {
            r.Id, r.ChallengeId,
            Title = titles.GetValueOrDefault(r.ChallengeId, "?"),
            Inviter = names.GetValueOrDefault(r.InviterId, "?"),
            r.CreatedAtUtc
        }));
    }

    [HttpPost("invitations/{invId:guid}/accept")]
    public async Task<IActionResult> Accept(Guid invId)
    {
        var inv = await _db.ChallengeInvitations.FirstOrDefaultAsync(i =>
            i.Id == invId && i.InviteeId == UserId && i.Status == RequestStatus.Pending);
        if (inv is null) return NotFound();

        var c = await _db.Challenges.AsNoTracking().FirstOrDefaultAsync(x => x.Id == inv.ChallengeId);
        if (c is null || c.EndsAtUtc < DateTime.UtcNow)
        {
            inv.Status = RequestStatus.Declined;
            await _db.SaveChangesAsync();
            return BadRequest("Ce d\u00e9fi est termin\u00e9.");
        }

        inv.Status = RequestStatus.Accepted;
        if (!await _db.ChallengeParticipants.AnyAsync(p => p.ChallengeId == inv.ChallengeId && p.UserId == UserId))
            _db.ChallengeParticipants.Add(new ChallengeParticipant { ChallengeId = inv.ChallengeId, UserId = UserId });
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPost("invitations/{invId:guid}/decline")]
    public async Task<IActionResult> Decline(Guid invId)
    {
        var inv = await _db.ChallengeInvitations.FirstOrDefaultAsync(i =>
            i.Id == invId && i.InviteeId == UserId && i.Status == RequestStatus.Pending);
        if (inv is null) return NotFound();
        inv.Status = RequestStatus.Declined;
        await _db.SaveChangesAsync();
        return NoContent();
    }
}
'@

$TplExtrasApi = @'
using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using StudyTimer.Domain.Entities;
using StudyTimer.Infrastructure;

namespace StudyTimer.Api.Controllers;

/// <summary>Calendrier d'activite (heatmap) : secondes etudiees par jour, dans le fuseau de l'utilisateur.</summary>
[ApiController, Authorize]
[Route("api/statistics")]
public class StatisticsExtrasController : ControllerBase
{
    private readonly AppDbContext _db;
    public StatisticsExtrasController(AppDbContext db) => _db = db;

    private Guid UserId => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)
                                      ?? User.FindFirstValue("sub")!);

    [HttpGet("heatmap")]
    public async Task<IActionResult> Heatmap([FromQuery] int days = 365)
    {
        days = Math.Clamp(days, 7, 730);
        var user = await _db.Users.AsNoTracking().FirstAsync(u => u.Id == UserId);
        TimeZoneInfo tz;
        try { tz = TimeZoneInfo.FindSystemTimeZoneById(user.TimeZone); }
        catch { tz = TimeZoneInfo.Utc; }

        var since = DateTime.UtcNow.AddDays(-days - 1);
        var raw = await _db.StudySessions.AsNoTracking()
            .Where(s => s.UserId == UserId && s.Status == SessionStatus.Completed && s.StartedAtUtc >= since)
            .Select(s => new { s.StartedAtUtc, s.AccumulatedSeconds })
            .ToListAsync();

        var byDay = raw
            .GroupBy(s => DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(
                DateTime.SpecifyKind(s.StartedAtUtc, DateTimeKind.Utc), tz)))
            .ToDictionary(g => g.Key, g => g.Sum(x => x.AccumulatedSeconds));

        var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, tz));
        return Ok(Enumerable.Range(0, days)
            .Select(i => today.AddDays(i - days + 1))
            .Select(d => new { Date = d, Seconds = byDay.GetValueOrDefault(d) }));
    }
}

/// <summary>Routes alias conformes au cahier des charges (section 5).</summary>
[ApiController, Authorize]
[Route("api")]
public class CahierAliasController : ControllerBase
{
    private readonly AppDbContext _db;
    public CahierAliasController(AppDbContext db) => _db = db;

    /// <summary>GET /api/leaderboard/weekly = /api/leaderboard?period=week</summary>
    [HttpGet("leaderboard/weekly")]
    public Task<IActionResult> Weekly() =>
        new ProgressController(_db) { ControllerContext = ControllerContext }.Leaderboard("week");

    /// <summary>GET /api/challenges/{id}/ranking = /api/challenges/{id}/leaderboard</summary>
    [HttpGet("challenges/{id:guid}/ranking")]
    public Task<IActionResult> Ranking(Guid id) =>
        new ChallengesController(_db) { ControllerContext = ControllerContext }.Leaderboard(id);
}
'@

$TplTests = @'
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace StudyTimer.Tests;

/// <summary>Tests des modules ajoutes : amis, confidentialite, taches, salles, invitations, notifications.</summary>
public class ExtrasTests : IClassFixture<ApiFactory>
{
    private readonly ApiFactory _factory;
    public ExtrasTests(ApiFactory factory) => _factory = factory;

    private static int _n;
    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);
    private record Tokens(string Token, string RefreshToken);

    private async Task<(HttpClient client, string username)> NewUser()
    {
        var i = Interlocked.Increment(ref _n);
        var username = $"extra{i}";
        var client = _factory.CreateClient();
        var r = await client.PostAsJsonAsync("/api/auth/register", new
        {
            firstName = "Extra", lastName = "User", username, email = $"{username}@test.com",
            password = "MotDePasse123", country = "MA", timeZone = "UTC"
        });
        r.EnsureSuccessStatusCode();
        var t = (await r.Content.ReadFromJsonAsync<Tokens>(Web))!;
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", t.Token);
        return (client, username);
    }

    private static async Task<JsonElement> Json(HttpClient c, string url) =>
        await c.GetFromJsonAsync<JsonElement>(url, Web);

    private async Task MakeFriends(HttpClient a, HttpClient b, string bName)
    {
        Assert.Equal(HttpStatusCode.OK, (await a.PostAsJsonAsync("/api/friends/invite", new { username = bName })).StatusCode);
        var reqs = await Json(b, "/api/friends/requests");
        var id = reqs[0].GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/friends/{id}/accept", null)).StatusCode);
    }

    [Fact]
    public async Task Amis_invitation_acceptation_liste_et_notification()
    {
        var (a, _) = await NewUser();
        var (b, bName) = await NewUser();
        await MakeFriends(a, b, bName);

        Assert.Equal(1, (await Json(a, "/api/friends")).GetArrayLength());
        Assert.Equal(1, (await Json(b, "/api/friends")).GetArrayLength());
        Assert.Equal(HttpStatusCode.Conflict,
            (await a.PostAsJsonAsync("/api/friends/invite", new { username = bName })).StatusCode);

        var notifs = await Json(b, "/api/notifications");
        Assert.True(notifs.GetProperty("unread").GetInt32() >= 1);
        var nid = notifs.GetProperty("items")[0].GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/notifications/{nid}/read", null)).StatusCode);
    }

    [Fact]
    public async Task Amis_inconnu_ou_soi_meme_refuse()
    {
        var (a, aName) = await NewUser();
        Assert.Equal(HttpStatusCode.NotFound,
            (await a.PostAsJsonAsync("/api/friends/invite", new { username = "personne-inconnue" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest,
            (await a.PostAsJsonAsync("/api/friends/invite", new { username = aName })).StatusCode);
    }

    [Fact]
    public async Task Confidentialite_RG07_masque_les_statistiques_aux_amis()
    {
        var (a, _) = await NewUser();
        var (b, bName) = await NewUser();
        await MakeFriends(a, b, bName);
        var bId = (await Json(a, "/api/friends"))[0].GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.OK, (await a.GetAsync($"/api/friends/{bId}/stats")).StatusCode);
        var put = await b.PutAsJsonAsync("/api/users/privacy", new { showStats = false, showActivity = true });
        Assert.Equal(HttpStatusCode.NoContent, put.StatusCode);
        Assert.Equal(HttpStatusCode.Forbidden, (await a.GetAsync($"/api/friends/{bId}/stats")).StatusCode);
    }

    [Fact]
    public async Task Statistiques_d_un_non_ami_refusees()
    {
        var (a, _) = await NewUser();
        var (b, _) = await NewUser();
        var bId = (await Json(b, "/api/users/profile")).GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.Forbidden, (await a.GetAsync($"/api/friends/{bId}/stats")).StatusCode);
    }

    [Fact]
    public async Task Classement_entre_amis_contient_moi()
    {
        var (a, _) = await NewUser();
        var r = await Json(a, "/api/friends/leaderboard?period=week");
        Assert.Equal(1, r.GetArrayLength());
        Assert.True(r[0].GetProperty("isMe").GetBoolean());
    }

    [Fact]
    public async Task Taches_creation_liste_retard_et_terminaison()
    {
        var (c, _) = await NewUser();
        var past = DateTime.UtcNow.AddDays(-1);
        var r = await c.PostAsJsonAsync("/api/tasks", new { title = "Revoir le chapitre 3", dueAtUtc = past, estimatedMinutes = 45, priority = "High" });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var id = (await r.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();

        Assert.Equal(1, (await Json(c, "/api/tasks")).GetArrayLength());
        Assert.Equal(1, (await Json(c, "/api/tasks/overdue")).GetArrayLength());

        Assert.Equal(HttpStatusCode.OK, (await c.PostAsync($"/api/tasks/{id}/complete", null)).StatusCode);
        Assert.Equal(0, (await Json(c, "/api/tasks/overdue")).GetArrayLength());
        Assert.Equal(1, (await Json(c, "/api/tasks?status=done")).GetArrayLength());
    }

    [Fact]
    public async Task Taches_validation_et_isolation()
    {
        var (a, _) = await NewUser();
        var (b, _) = await NewUser();
        Assert.Equal(HttpStatusCode.BadRequest, (await a.PostAsJsonAsync("/api/tasks", new { title = "" })).StatusCode);
        Assert.Equal(HttpStatusCode.BadRequest, (await a.PostAsJsonAsync("/api/tasks", new { title = "x", priority = "Urgent" })).StatusCode);

        var r = await a.PostAsJsonAsync("/api/tasks", new { title = "Priv\u00e9e" });
        var id = (await r.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.NotFound, (await b.PostAsync($"/api/tasks/{id}/complete", null)).StatusCode);
        Assert.Equal(0, (await Json(b, "/api/tasks")).GetArrayLength());
    }

    [Fact]
    public async Task Seance_associee_a_une_tache()
    {
        var (c, _) = await NewUser();
        var t = await c.PostAsJsonAsync("/api/tasks", new { title = "Exercices" });
        var taskId = (await t.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();

        var ok = await c.PostAsJsonAsync("/api/sessions/start", new { mode = "Focus", taskId });
        Assert.Equal(HttpStatusCode.OK, ok.StatusCode);
        await c.PostAsync("/api/sessions/stop", null);

        var bad = await c.PostAsJsonAsync("/api/sessions/start", new { mode = "Focus", taskId = Guid.NewGuid() });
        Assert.Equal(HttpStatusCode.BadRequest, bad.StatusCode);
    }

    [Fact]
    public async Task Salles_creation_code_messages_et_acces_reserve_aux_membres()
    {
        var (a, _) = await NewUser();
        var (b, _) = await NewUser();
        var (outsider, _) = await NewUser();

        var r = await a.PostAsJsonAsync("/api/rooms", new { name = "R\u00e9visions", isPublic = false });
        Assert.Equal(HttpStatusCode.OK, r.StatusCode);
        var created = await r.Content.ReadFromJsonAsync<JsonElement>(Web);
        var id = created.GetProperty("id").GetGuid();
        var code = created.GetProperty("code").GetString()!;
        Assert.Equal(6, code.Length);

        Assert.Equal(HttpStatusCode.OK, (await b.PostAsJsonAsync("/api/rooms/join", new { code = code.ToLower() })).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await outsider.PostAsJsonAsync("/api/rooms/join", new { code = "ZZZZZZ" })).StatusCode);

        Assert.Equal(HttpStatusCode.OK, (await b.PostAsJsonAsync($"/api/rooms/{id}/messages", new { text = "Bonjour !" })).StatusCode);
        var msgs = await Json(a, $"/api/rooms/{id}/messages");
        Assert.Equal(1, msgs.GetArrayLength());
        Assert.Equal("Bonjour !", msgs[0].GetProperty("text").GetString());

        var room = await Json(a, $"/api/rooms/{id}");
        Assert.Equal(2, room.GetProperty("participants").GetArrayLength());
        Assert.Equal("Offline", room.GetProperty("participants")[0].GetProperty("status").GetString());

        Assert.Equal(HttpStatusCode.Forbidden, (await outsider.GetAsync($"/api/rooms/{id}/messages")).StatusCode);
        Assert.Equal(HttpStatusCode.NotFound, (await outsider.PostAsync($"/api/rooms/{id}/join", null)).StatusCode);
    }

    [Fact]
    public async Task Salles_publiques_visibles_et_salle_supprimee_quand_vide()
    {
        var (a, _) = await NewUser();
        var (b, _) = await NewUser();
        var r = await a.PostAsJsonAsync("/api/rooms", new { name = "Biblioth\u00e8que", isPublic = true });
        var id = (await r.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();

        var list = await Json(b, "/api/rooms");
        Assert.Contains(list.EnumerateArray(), x => x.GetProperty("id").GetGuid() == id);
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/rooms/{id}/join", null)).StatusCode);

        await a.PostAsync($"/api/rooms/{id}/leave", null);
        await b.PostAsync($"/api/rooms/{id}/leave", null);
        Assert.Equal(HttpStatusCode.NotFound, (await b.GetAsync($"/api/rooms/{id}")).StatusCode);
    }

    [Fact]
    public async Task Invitation_a_un_defi_acceptation_et_classement()
    {
        var (a, _) = await NewUser();
        var (b, bName) = await NewUser();
        var c = await a.PostAsJsonAsync("/api/challenges", new { title = "Semaine intense", type = "TotalTime", target = 600, durationDays = 7 });
        var cid = (await c.Content.ReadFromJsonAsync<JsonElement>(Web)).GetProperty("id").GetGuid();

        Assert.Equal(HttpStatusCode.OK, (await a.PostAsJsonAsync($"/api/challenges/{cid}/invite", new { username = bName })).StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, (await a.PostAsJsonAsync($"/api/challenges/{cid}/invite", new { username = bName })).StatusCode);

        var pending = await Json(b, "/api/challenges/invitations");
        Assert.Equal(1, pending.GetArrayLength());
        var invId = pending[0].GetProperty("id").GetGuid();
        Assert.Equal(HttpStatusCode.NoContent, (await b.PostAsync($"/api/challenges/invitations/{invId}/accept", null)).StatusCode);

        Assert.Equal(2, (await Json(b, $"/api/challenges/{cid}/ranking")).GetArrayLength());
    }

    [Fact]
    public async Task Routes_du_cahier_et_heatmap()
    {
        var (a, _) = await NewUser();
        Assert.Equal(HttpStatusCode.OK, (await a.GetAsync("/api/leaderboard/weekly")).StatusCode);
        Assert.Equal(30, (await Json(a, "/api/statistics/heatmap?days=30")).GetArrayLength());
    }

    [Fact]
    public async Task Nouvelles_routes_protegees_refusent_sans_token()
    {
        var anon = _factory.CreateClient();
        foreach (var url in new[] { "/api/friends", "/api/tasks", "/api/rooms", "/api/notifications", "/api/statistics/heatmap" })
            Assert.Equal(HttpStatusCode.Unauthorized, (await anon.GetAsync(url)).StatusCode);
    }
}
'@

$TplCi = @'
name: CI

on:
  push:
  pull_request:

jobs:
  backend:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'
      - run: dotnet build backend/StudyTimer.slnx --configuration Release
      - run: dotnet test backend/StudyTimer.slnx --configuration Release --no-build

  mobile:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: mobile/study_timer
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
'@

$TplK6 = @'
// Test de charge k6 (cahier 8 : API < 500 ms pour les operations courantes).
// Utilisation : k6 run deploy/tests/load-test.js          (serveur : BASE_URL=https://mon-serveur k6 run ...)
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 50,
  duration: '30s',
  thresholds: {
    http_req_duration: ['p(95)<500'],
    http_req_failed: ['rate<0.01'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:5293';
const JSON_HEADERS = { 'Content-Type': 'application/json' };

export function setup() {
  const id = Date.now();
  const body = JSON.stringify({
    firstName: 'Load', lastName: 'Test', username: 'load' + id, email: 'load' + id + '@test.com',
    password: 'MotDePasse123', country: 'MA', timeZone: 'UTC',
  });
  const r = http.post(BASE + '/api/auth/register', body, { headers: JSON_HEADERS });
  check(r, { 'inscription ok': (x) => x.status === 200 });
  return { token: r.json('token') };
}

export default function (data) {
  const params = { headers: { Authorization: 'Bearer ' + data.token } };
  const res = http.batch([
    ['GET', BASE + '/api/leaderboard?period=week', null, params],
    ['GET', BASE + '/api/statistics/dashboard', null, params],
    ['GET', BASE + '/api/sessions/history', null, params],
    ['GET', BASE + '/api/challenges', null, params],
  ]);
  for (const r of res) check(r, { 'statut 200': (x) => x.status === 200 });
  sleep(1);
}
'@

# ============================================================================
# Gabarits Dart
# ============================================================================

$TplApiExtras = @'
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'api.dart';

/// Petit message en bas d'ecran.
void showMsg(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Appels API des modules Communaute, Salles, Planificateur et Notifications.
extension ApiExtras on Api {
  Future<List<Map<String, dynamic>>> _list(Future<Response> Function() request) async {
    final d = await call(request);
    return d is List ? List<Map<String, dynamic>>.from(d) : <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> _map(Future<Response> Function() request) async =>
      Map<String, dynamic>.from(await call(request));

  // --- Amis
  Future<List<Map<String, dynamic>>> friends() => _list(() => dio.get('/api/friends'));
  Future<List<Map<String, dynamic>>> friendRequests() =>
      _list(() => dio.get('/api/friends/requests'));
  Future<List<Map<String, dynamic>>> friendFeed() => _list(() => dio.get('/api/friends/feed'));
  Future<List<Map<String, dynamic>>> friendsLeaderboard([String period = 'week']) =>
      _list(() => dio.get('/api/friends/leaderboard', queryParameters: {'period': period}));
  Future<Map<String, dynamic>> friendStats(String userId) =>
      _map(() => dio.get('/api/friends/$userId/stats'));
  Future<void> inviteFriend(String username) async {
    await call(() => dio.post('/api/friends/invite', data: {'username': username}));
  }

  Future<void> acceptFriend(String id) async {
    await call(() => dio.post('/api/friends/$id/accept'));
  }

  Future<void> declineFriend(String id) async {
    await call(() => dio.post('/api/friends/$id/decline'));
  }

  Future<void> removeFriend(String userId) async {
    await call(() => dio.delete('/api/friends/$userId'));
  }

  // --- Confidentialite (RG07)
  Future<Map<String, dynamic>> privacy() => _map(() => dio.get('/api/users/privacy'));
  Future<void> setPrivacy(bool showStats, bool showActivity) async {
    await call(() => dio.put('/api/users/privacy',
        data: {'showStats': showStats, 'showActivity': showActivity}));
  }

  // --- Taches
  Future<List<Map<String, dynamic>>> tasks({String status = 'all'}) =>
      _list(() => dio.get('/api/tasks', queryParameters: {'status': status}));
  Future<void> createTask(Map<String, dynamic> body) async {
    await call(() => dio.post('/api/tasks', data: body));
  }

  Future<void> completeTask(String id) async {
    await call(() => dio.post('/api/tasks/$id/complete'));
  }

  Future<void> deleteTask(String id) async {
    await call(() => dio.delete('/api/tasks/$id'));
  }

  // --- Salles
  Future<List<Map<String, dynamic>>> rooms() => _list(() => dio.get('/api/rooms'));
  Future<Map<String, dynamic>> room(String id) => _map(() => dio.get('/api/rooms/$id'));
  Future<Map<String, dynamic>> createRoom(String name, bool isPublic) =>
      _map(() => dio.post('/api/rooms', data: {'name': name, 'isPublic': isPublic}));
  Future<Map<String, dynamic>> joinRoomByCode(String code) =>
      _map(() => dio.post('/api/rooms/join', data: {'code': code}));
  Future<void> joinRoom(String id) async {
    await call(() => dio.post('/api/rooms/$id/join'));
  }

  Future<void> leaveRoom(String id) async {
    await call(() => dio.post('/api/rooms/$id/leave'));
  }

  Future<List<Map<String, dynamic>>> roomMessages(String id) =>
      _list(() => dio.get('/api/rooms/$id/messages'));
  Future<void> sendRoomMessage(String id, String text) async {
    await call(() => dio.post('/api/rooms/$id/messages', data: {'text': text}));
  }

  // --- Notifications
  Future<Map<String, dynamic>> notifications() => _map(() => dio.get('/api/notifications'));
  Future<void> readAllNotifications() async {
    await call(() => dio.post('/api/notifications/read-all'));
  }

  // --- Calendrier d'activite
  Future<List<Map<String, dynamic>>> heatmap({int days = 365}) =>
      _list(() => dio.get('/api/statistics/heatmap', queryParameters: {'days': days}));
}
'@

$TplCommunity = @'
import 'package:flutter/material.dart';

import 'api.dart';
import 'api_extras.dart';
import 'room_page.dart';
import 'util.dart';
import 'widgets.dart';

/// Communaute : amis (invitations, activite) et salles d'etude.
class CommunityPage extends StatelessWidget {
  const CommunityPage({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTabController(
    length: 2,
    child: Column(
      children: [
        TabBar(tabs: [Tab(text: 'Amis'), Tab(text: 'Salles')]),
        Expanded(child: TabBarView(children: [_FriendsTab(), _RoomsTab()])),
      ],
    ),
  );
}

class _FriendsTab extends StatefulWidget {
  const _FriendsTab();
  @override
  State<_FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<_FriendsTab> {
  final username = TextEditingController();
  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> feed = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    username.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final r = await Future.wait([
        Api.instance.friends(),
        Api.instance.friendRequests(),
        Api.instance.friendFeed(),
      ]);
      if (!mounted) return;
      setState(() {
        friends = r[0];
        requests = r[1];
        feed = r[2];
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> act(Future<void> Function() action, {String? ok}) async {
    try {
      await action();
      if (!mounted) return;
      if (ok != null) showMsg(context, ok);
      await reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> showStats(Map<String, dynamic> f) async {
    try {
      final s = await Api.instance.friendStats('${f['id']}');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${f['username']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total : ${fmtShort((s['totalSeconds'] as num).toInt())}'),
              Text('Cette semaine : ${fmtShort((s['weekSeconds'] as num).toInt())}'),
              Text('S\u00e9ances : ${s['sessionsCount']}'),
              Text('Niveau : ${s['level']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(
        context,
        e.status == 403 ? 'Les statistiques de cet ami ne sont pas visibles.' : e.message,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorView(message: error!, onRetry: reload);
    return RefreshIndicator(
      onRefresh: reload,
      child: Body(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Inviter un ami',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: username,
                      decoration: const InputDecoration(labelText: 'Pseudo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      final u = username.text.trim();
                      if (u.isEmpty) return;
                      username.clear();
                      act(() => Api.instance.inviteFriend(u), ok: 'Invitation envoy\u00e9e');
                    },
                    child: const Text('Inviter'),
                  ),
                ],
              ),
            ),
            if (requests.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionCard(
                title: 'Invitations re\u00e7ues',
                child: Column(
                  children: [
                    for (final r in requests)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${r['username']}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Accepter',
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () => act(() => Api.instance.acceptFriend('${r['id']}')),
                            ),
                            IconButton(
                              tooltip: 'Refuser',
                              icon: const Icon(Icons.cancel_outlined),
                              onPressed: () => act(() => Api.instance.declineFriend('${r['id']}')),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SectionCard(
              title: 'Mes amis',
              child: friends.isEmpty
                  ? const Text('Aucun ami pour le moment.')
                  : Column(
                      children: [
                        for (final f in friends)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_outline),
                            title: Text('${f['username']}'),
                            onTap: () => showStats(f),
                            trailing: IconButton(
                              tooltip: 'Supprimer',
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: () => act(
                                () => Api.instance.removeFriend('${f['id']}'),
                                ok: 'Ami supprim\u00e9',
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Activit\u00e9 des amis',
              child: feed.isEmpty
                  ? const Text('Rien \u00e0 afficher pour le moment.')
                  : Column(
                      children: [
                        for (final s in feed)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${s['username']} \u00b7 ${fmtShort((s['seconds'] as num).toInt())}',
                            ),
                            subtitle: Text('${s['mode']}'),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomsTab extends StatefulWidget {
  const _RoomsTab();
  @override
  State<_RoomsTab> createState() => _RoomsTabState();
}

class _RoomsTabState extends State<_RoomsTab> {
  final code = TextEditingController();
  List<Map<String, dynamic>> rooms = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final r = await Api.instance.rooms();
      if (!mounted) return;
      setState(() {
        rooms = r;
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  void open(String id, String name) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => RoomPage(roomId: id, name: name)))
        .then((_) => reload());
  }

  Future<void> joinByCode() async {
    final c = code.text.trim();
    if (c.isEmpty) return;
    try {
      final r = await Api.instance.joinRoomByCode(c);
      code.clear();
      if (!mounted) return;
      open('${r['id']}', '${r['name']}');
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> openRoom(Map<String, dynamic> r) async {
    try {
      if (r['joined'] != true) await Api.instance.joinRoom('${r['id']}');
      if (!mounted) return;
      open('${r['id']}', '${r['name']}');
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> create() async {
    final name = TextEditingController();
    var isPublic = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nouvelle salle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom de la salle'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Salle publique'),
                value: isPublic,
                onChanged: (v) => setS(() => isPublic = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cr\u00e9er')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    try {
      final r = await Api.instance.createRoom(name.text.trim(), isPublic);
      if (!mounted) return;
      open('${r['id']}', name.text.trim());
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) return ErrorView(message: error!, onRetry: reload);
    return RefreshIndicator(
      onRefresh: reload,
      child: Body(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Rejoindre par code',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Code de la salle'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: joinByCode, child: const Text('Rejoindre')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Salles',
              trailing: IconButton(
                tooltip: 'Cr\u00e9er une salle',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: create,
              ),
              child: rooms.isEmpty
                  ? const Text('Aucune salle. Cr\u00e9ez-en une !')
                  : Column(
                      children: [
                        for (final r in rooms)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(r['isPublic'] == true ? Icons.public : Icons.lock_outline),
                            title: Text('${r['name']}'),
                            subtitle: Text('${r['participants']} participant(s)'),
                            trailing: r['joined'] == true
                                ? const Icon(Icons.check_circle, size: 18)
                                : null,
                            onTap: () => openRoom(r),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
'@

$TplRoomPage = @'
import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'api_extras.dart';
import 'util.dart';

/// Salle d'etude : participants (statut, temps du jour) et chat.
/// Les messages sont rafraichis toutes les 4 s (le hub SignalR /hubs/study est pret cote serveur).
class RoomPage extends StatefulWidget {
  final String roomId;
  final String name;
  const RoomPage({super.key, required this.roomId, required this.name});
  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final input = TextEditingController();
  Timer? poll;
  Map<String, dynamic>? room;
  List<Map<String, dynamic>> messages = [];
  String? error;

  @override
  void initState() {
    super.initState();
    refresh();
    poll = Timer.periodic(const Duration(seconds: 4), (_) => refresh());
  }

  @override
  void dispose() {
    poll?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    try {
      final r = await Api.instance.room(widget.roomId);
      final m = await Api.instance.roomMessages(widget.roomId);
      if (!mounted) return;
      setState(() {
        room = r;
        messages = m;
        error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => error = e.message);
    }
  }

  Future<void> send() async {
    final t = input.text.trim();
    if (t.isEmpty) return;
    input.clear();
    try {
      await Api.instance.sendRoomMessage(widget.roomId, t);
      await refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> leave() async {
    try {
      await Api.instance.leaveRoom(widget.roomId);
      if (!mounted) return;
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  String statusLabel(String s) => switch (s) {
    'Studying' => 'En \u00e9tude',
    'Paused' => 'En pause',
    _ => 'Hors ligne',
  };

  IconData statusIcon(String s) => switch (s) {
    'Studying' => Icons.local_fire_department,
    'Paused' => Icons.pause_circle_outline,
    _ => Icons.circle_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final parts = (room?['participants'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          if (room != null)
            IconButton(
              tooltip: 'Code de la salle',
              icon: const Icon(Icons.vpn_key_outlined),
              onPressed: () => showMsg(context, 'Code : ${room!['code']}'),
            ),
          IconButton(
            tooltip: 'Quitter la salle',
            icon: const Icon(Icons.exit_to_app),
            onPressed: leave,
          ),
        ],
      ),
      body: Column(
        children: [
          if (error != null)
            Padding(padding: const EdgeInsets.all(8), child: Text(error!)),
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final p in parts)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Chip(
                      avatar: Icon(statusIcon('${p['status']}'), size: 18),
                      label: Text(
                        '${p['username']} \u00b7 ${statusLabel('${p['status']}')}'
                        ' \u00b7 ${fmtShort((p['todaySeconds'] as num).toInt())}',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (_, i) {
                final m = messages[messages.length - 1 - i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '${m['username']} : ',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: '${m['text']}'),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      maxLength: 500,
                      decoration: const InputDecoration(hintText: 'Votre message', counterText: ''),
                      onSubmitted: (_) => send(),
                    ),
                  ),
                  IconButton(onPressed: send, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
'@

$TplPlannerPage = @'
import 'package:flutter/material.dart';

import 'api.dart';
import 'api_extras.dart';
import 'util.dart';
import 'widgets.dart';

/// Planificateur d'etude : taches, echeances, priorites, taches en retard.
class PlannerPage extends StatefulWidget {
  const PlannerPage({super.key});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends State<PlannerPage> {
  static const filters = <(String, String)>[
    ('all', 'Toutes'),
    ('open', '\u00c0 faire'),
    ('overdue', 'En retard'),
    ('done', 'Termin\u00e9es'),
  ];

  String filter = 'open';
  List<Map<String, dynamic>> tasks = [];
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final t = await Api.instance.tasks(status: filter);
      if (!mounted) return;
      setState(() {
        tasks = t;
        error = null;
        loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.message;
        loading = false;
      });
    }
  }

  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      await reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      showMsg(context, e.message);
    }
  }

  Future<void> add() async {
    final title = TextEditingController();
    final minutes = TextEditingController(text: '30');
    var priority = 'Medium';
    DateTime? due;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nouvelle t\u00e2che'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Titre'),
                ),
                TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Dur\u00e9e estim\u00e9e (min)'),
                ),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: priority,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: 'Low', child: Text('Priorit\u00e9 basse')),
                    DropdownMenuItem(value: 'Medium', child: Text('Priorit\u00e9 moyenne')),
                    DropdownMenuItem(value: 'High', child: Text('Priorit\u00e9 haute')),
                  ],
                  onChanged: (v) => setS(() => priority = v ?? 'Medium'),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(due == null ? '\u00c9ch\u00e9ance (facultatif)' : fmtDateTime(due!)),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 730)),
                    );
                    if (d == null || !ctx.mounted) return;
                    final t = await showTimePicker(
                      context: ctx,
                      initialTime: const TimeOfDay(hour: 18, minute: 0),
                    );
                    if (t == null) return;
                    setS(() => due = DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    await act(
      () => Api.instance.createTask({
        'title': title.text.trim(),
        'estimatedMinutes': int.tryParse(minutes.text.trim()),
        'priority': priority,
        'dueAtUtc': due?.toUtc().toIso8601String(),
      }),
    );
  }

  String subtitle(Map<String, dynamic> t) {
    final parts = <String>[];
    final d = t['dueAtUtc'];
    if (d is String) parts.add(fmtDateTime(parseUtc(d)));
    if (t['estimatedMinutes'] != null) parts.add('${t['estimatedMinutes']} min');
    parts.add(switch ('${t['priority']}') {
      'High' => 'haute',
      'Low' => 'basse',
      _ => 'moyenne',
    });
    return parts.join(' \u00b7 ');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Body(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final f in filters)
                      ChoiceChip(
                        label: Text(f.$2),
                        selected: filter == f.$1,
                        onSelected: (_) {
                          setState(() => filter = f.$1);
                          reload();
                        },
                      ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: add,
                icon: const Icon(Icons.add),
                label: const Text('T\u00e2che'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (error != null)
            ErrorView(message: error!, onRetry: reload)
          else if (tasks.isEmpty)
            const EmptyState(icon: Icons.event_available, message: 'Aucune t\u00e2che ici.')
          else
            for (final t in tasks)
              Card(
                child: ListTile(
                  leading: Checkbox(
                    value: t['isDone'] == true,
                    onChanged: t['isDone'] == true
                        ? null
                        : (_) => act(() => Api.instance.completeTask('${t['id']}')),
                  ),
                  title: Text(
                    '${t['title']}',
                    style: TextStyle(
                      decoration: t['isDone'] == true ? TextDecoration.lineThrough : null,
                      color: t['overdue'] == true ? cs.error : null,
                    ),
                  ),
                  subtitle: Text(subtitle(t)),
                  trailing: IconButton(
                    tooltip: 'Supprimer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => act(() => Api.instance.deleteTask('${t['id']}')),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
'@

# ============================================================================
# 1) Backend : entites, DbContext, controleurs, hub, tests
# ============================================================================
Titre "1/4  Backend"

Ecrire (Join-Path $DomDir "Entities\Social.cs")   $TplSocial
Ecrire (Join-Path $DomDir "Entities\Planner.cs")  $TplPlanner
Ecrire (Join-Path $DomDir "Entities\Rooms.cs")    $TplRooms

[void](Patcher (Join-Path $InfDir "AppDbContext.cs") 'Friendships' 'public DbSet<UserBadge> UserBadges => Set<UserBadge>\(\);' $TplDbSets)
[void](Patcher (Join-Path $InfDir "AppDbContext.cs") 'HasKey\(p => p\.UserId\)' 'b\.Entity<UserBadge>\(\)\.HasIndex\(x => new \{ x\.UserId, x\.Code \}\)\.IsUnique\(\);' $TplDbModel)

Ecrire (Join-Path $ApiDir "Hubs\StudyHub.cs")                          $TplHub
Ecrire (Join-Path $ApiDir "Controllers\FriendsController.cs")          $TplFriends
Ecrire (Join-Path $ApiDir "Controllers\NotificationsController.cs")    $TplNotifications
Ecrire (Join-Path $ApiDir "Controllers\TasksController.cs")            $TplTasks
Ecrire (Join-Path $ApiDir "Controllers\RoomsController.cs")            $TplRoomsCtl
Ecrire (Join-Path $ApiDir "Controllers\ChallengeInvitesController.cs") $TplInvites
Ecrire (Join-Path $ApiDir "Controllers\ExtrasApiController.cs")        $TplExtrasApi

# Program.cs : SignalR + jeton dans l'URL des WebSockets + MapHub
$prog = Join-Path $ApiDir "Program.cs"
$signalrServices = @'


builder.Services.AddSignalR();
// SignalR (WebSocket) ne peut pas envoyer l'en-tete Authorization : le jeton passe en ?access_token=
builder.Services.Configure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, o =>
{
    var events = o.Events ?? new JwtBearerEvents();
    events.OnMessageReceived = ctx =>
    {
        var token = ctx.Request.Query["access_token"];
        if (!string.IsNullOrEmpty(token) && ctx.HttpContext.Request.Path.StartsWithSegments("/hubs"))
            ctx.Token = token;
        return Task.CompletedTask;
    };
    o.Events = events;
});
'@
[void](Patcher $prog 'StudyTimer\.Api\.Hubs' 'using StudyTimer\.Infrastructure;' "`nusing StudyTimer.Api.Hubs;")
[void](Patcher $prog 'AddSignalR' 'builder\.Services\.AddAuthorization\(\);' $signalrServices)
[void](Patcher $prog 'MapHub' 'app\.MapHealthChecks\("/health"\);' "`napp.MapHub<StudyHub>(`"/hubs/study`");")

# Seances : association a une tache (StartSessionRequest.TaskId)
$sess = Join-Path $ApiDir "Controllers\SessionsController.cs"
$taskCheck = @'
if (request.TaskId.HasValue &&
            !await _db.TaskItems.AnyAsync(t => t.Id == request.TaskId && t.UserId == UserId))
        {
            return BadRequest(new { message = "T\u00e2che inconnue." });
        }
'@ + "`n`n        "
[void](Patcher $sess 'public Guid\? TaskId' 'public int\? TargetSeconds \{ get; set; \}' "`n    public Guid? TaskId { get; set; }")
[void](Patcher $sess 'TaskId = request\.TaskId' 'SubjectId = request\.SubjectId,' "`n            TaskId = request.TaskId,")
[void](Patcher $sess 'T\\u00e2che inconnue' 'var active = await _db\.StudySessions\.AnyAsync\(' $taskCheck -Avant)

Ecrire (Join-Path $TestDir "ExtrasTests.cs") $TplTests

# ============================================================================
# 2) Migration EF Core
# ============================================================================
Titre "2/4  Migration de la base"
if ($SansMigration) {
    Info "ignor\u00e9e (-SansMigration). Commande : dotnet ef migrations add Phase3_Social_Planner --project backend\StudyTimer.Infrastructure --startup-project backend\StudyTimer.Api"
} else {
    $migDir = Join-Path $InfDir "Migrations"
    $deja = @(Get-ChildItem $migDir -Filter "*Phase3_Social_Planner.cs" -ErrorAction SilentlyContinue)
    if ($deja.Count -gt 0) { Info "migration Phase3_Social_Planner d\u00e9j\u00e0 pr\u00e9sente" }
    else {
        $ef = $null
        try { $ef = (& dotnet tool list -g 2>$null) | Select-String "dotnet-ef" } catch {}
        if (-not $ef) { try { $ef = (& dotnet ef --version 2>$null) } catch {} }
        if (-not $ef) {
            Warn "outil dotnet-ef absent : dotnet tool install --global dotnet-ef   puis relancez avec -Appliquer"
        } else {
            $avantMig = @(Get-ChildItem $migDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
            Sauver (Join-Path $migDir "AppDbContextModelSnapshot.cs")
            Push-Location $BackendDir
            try {
                & dotnet ef migrations add Phase3_Social_Planner --project StudyTimer.Infrastructure --startup-project StudyTimer.Api --output-dir Migrations
                if ($LASTEXITCODE -ne 0) { throw "dotnet ef a \u00e9chou\u00e9 (code $LASTEXITCODE)" }
                foreach ($f in Get-ChildItem $migDir -File) { if ($avantMig -notcontains $f.FullName) { [void]$Script:Crees.Add($f.FullName) } }
                Ok "migration cr\u00e9\u00e9e : Phase3_Social_Planner (appliqu\u00e9e au d\u00e9marrage de l'API si Database:MigrateOnStart=true, sinon : dotnet ef database update)"
            } catch {
                Warn ("migration non cr\u00e9\u00e9e : " + $_.Exception.Message)
                Warn "V\u00e9rifiez les secrets (dotnet user-secrets : Jwt:Key et ConnectionStrings:Default), puis relancez ou cr\u00e9ez la migration \u00e0 la main."
            } finally { Pop-Location }
        }
    }
}

# ============================================================================
# 3) Mobile Flutter
# ============================================================================
Titre "3/4  Application mobile"
$apiDart = Join-Path $LibDir "api.dart"
$apiOk = Patcher $apiDart 'Future<dynamic> call\(' 'Future<void> login\(String email, String password\) async \{' "/// Appel authentifie reutilisable par les extensions (api_extras.dart).`n  Future<dynamic> call(Future<Response> Function() request) => _call(request);`n`n  " -Avant
if (-not $apiOk) {
    Warn "api.dart n'a pas pu \u00eatre adapt\u00e9 : les pages Flutter ne sont pas g\u00e9n\u00e9r\u00e9es (elles en d\u00e9pendent)."
} else {
    Ecrire (Join-Path $LibDir "api_extras.dart")     $TplApiExtras
    Ecrire (Join-Path $LibDir "community_page.dart") $TplCommunity
    Ecrire (Join-Path $LibDir "room_page.dart")      $TplRoomPage
    Ecrire (Join-Path $LibDir "planner_page.dart")   $TplPlannerPage

    $homeDart = Join-Path $LibDir "home_page.dart"
    [void](Patcher $homeDart 'community_page\.dart' "import 'challenges_page\.dart';" "`nimport 'community_page.dart';`nimport 'planner_page.dart';")
    [void](Patcher $homeDart "Icons\.group_outlined" "\(Icons\.emoji_events_outlined, Icons\.emoji_events, 'D[^']*fis'\)," "`n    (Icons.group_outlined, Icons.group, 'Communaut\u00e9'),`n    (Icons.event_note_outlined, Icons.event_note, 'Planificateur'),")
    [void](Patcher $homeDart '6 => const CommunityPage' '5 => const ChallengesPage\(\),' "`n    6 => const CommunityPage(),`n    7 => const PlannerPage(),")
    [void](Patcher $homeDart 'navItem\(6\)' 'navItem\(5\),\s*const SizedBox\(width: 72\),\s*navItem\(3\),' "navItem(5),`n            navItem(6),`n            const SizedBox(width: 72),`n            navItem(7),`n            navItem(3)," -Remplacer)
}

# ============================================================================
# 4) CI et test de charge
# ============================================================================
Titre "4/4  CI et test de charge"
Ecrire (Join-Path $Racine ".github\workflows\ci.yml") $TplCi
Ecrire (Join-Path $Racine "deploy\tests\load-test.js") $TplK6

# ----------------------------------------------------------------------------
# Verification (optionnelle) avec annulation automatique si le backend ne compile pas
# ----------------------------------------------------------------------------
$echec = $false
if ($Verifier) {
    Titre "V\u00c9RIFICATION"
    $ErrorActionPreference = "Continue"   # PS 5.1 : stderr natif (2>&1) ne doit pas interrompre
    $sln = Join-Path $BackendDir "StudyTimer.slnx"
    if (-not (Test-Path $sln)) { $sln = $BackendDir }

    Info "dotnet build..."
    & dotnet build $sln --nologo -v q 2>&1 | Select-Object -Last 25 | ForEach-Object { Write-Host "    $_" }
    if ($LASTEXITCODE -ne 0) { $echec = $true; Warn "dotnet build a \u00e9chou\u00e9." }

    if (-not $echec) {
        Info "dotnet test..."
        & dotnet test $sln --no-build --nologo 2>&1 | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" }
        if ($LASTEXITCODE -ne 0) { $echec = $true; Warn "dotnet test a \u00e9chou\u00e9." }
    }

    if ($echec -and -not $Garder) {
        Annuler-Tout
        Write-Host (T "Aucune modification conserv\u00e9e. Corrigez l'erreur ci-dessus (ou relancez avec -Garder pour conserver les fichiers g\u00e9n\u00e9r\u00e9s) puis relancez.") -ForegroundColor Red
        exit 1
    }

    if (Test-Path (Join-Path $AppDir "pubspec.yaml")) {
        Push-Location $AppDir
        try {
            Info "flutter analyze..."
            & flutter analyze --no-fatal-infos 2>&1 | Select-Object -Last 20 | ForEach-Object { Write-Host "    $_" }
            if ($LASTEXITCODE -ne 0) { Warn "flutter analyze signale des erreurs dans les pages g\u00e9n\u00e9r\u00e9es : corrigez-les ou supprimez les fichiers cr\u00e9\u00e9s (liste dans la sauvegarde)." }
            Info "flutter test..."
            & flutter test 2>&1 | Select-Object -Last 8 | ForEach-Object { Write-Host "    $_" }
        } catch { Warn ("flutter indisponible : " + $_.Exception.Message) }
        finally { Pop-Location }
    }
}

# ----------------------------------------------------------------------------
# Bilan
# ----------------------------------------------------------------------------
$apres = Analyser
Afficher-Resume $apres "DIAGNOSTIC APR\u00c8S COMPL\u00c9TION"
Ecrire-Rapport $apres $avant

Write-Host ""
Write-Host (T ("Conformit\u00e9 : " + (Score $avant "ALL") + " % -> " + (Score $apres "ALL") + " %   (MVP : " + (Score $avant "MVP") + " % -> " + (Score $apres "MVP") + " %)")) -ForegroundColor White
Write-Host (T "Reste \u00e0 faire (hors p\u00e9rim\u00e8tre g\u00e9n\u00e9r\u00e9) : voir docs\CONFORMITE.md, section 'Reste \u00e0 faire'.") -ForegroundColor Yellow
if (-not $Verifier) {
    Write-Host (T "Conseil : relancez avec -Verifier pour compiler et ex\u00e9cuter les tests (annulation automatique si le backend ne compile pas).") -ForegroundColor Yellow
}
if ($Script:Sauves.Count -gt 0) {
    Write-Host (T ("Sauvegardes des fichiers modifi\u00e9s : " + (Rel $SauvegardeDir))) -ForegroundColor Gray
}
Write-Host ""
