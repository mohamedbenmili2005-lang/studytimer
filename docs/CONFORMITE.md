# Conformité au cahier des charges - StudyTimer

Généré le 2026-11-21 23:49 par Completer-Projet.ps1. Relancer le script pour mettre à jour.

**Conformité globale : 76 %** (MVP 75 %, V2 83 %, V3 0 %)

Statuts : OK = conforme, PARTIEL = existe mais incomplet ou différent, MANQUANT = absent. Phase = priorisation du cahier (section 13).

## Module 1 - Utilisateurs et authentification

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Inscription (nom, prénom, pseudo, email, mot de passe, pays) | MVP | OK | User.cs + POST /api/auth/register |
| Photo de profil | MVP | MANQUANT | aucun champ ni endpoint d'upload |
| Connexion email / mot de passe (JWT + refresh) | MVP | OK | POST /api/auth/login, /refresh |
| Google Sign-In / Apple Sign-In | MVP | MANQUANT |  |
| Gestion du profil (lecture / modification) | MVP | OK | GET+PUT /api/users/profile |
| Suppression du compte | MVP | MANQUANT |  |

## Module 2 - Chronomètre d'étude

| Point | Phase | Statut | Constat |
|---|---|---|---|
| 3 modes : Focus, Pomodoro, Stopwatch | MVP | OK | enum SessionMode |
| Démarrer / pause / reprendre / arrêter + historique | MVP | OK | 5 routes présentes |
| Choisir une matière | MVP | OK | Subjects + SubjectId |
| Associer une tâche à une séance | MVP | OK | StartSessionRequest.TaskId |
| Chrono sur horodatages (arrière-plan) + source de vérité serveur | MVP | OK | AccumulatedSeconds + LastResumedAtUtc |
| Récupérer une séance après fermeture/redémarrage | MVP | OK | GET /api/sessions/current + recover() |
| File d'attente hors-ligne + resynchronisation (cahier 8.1) | MVP | MANQUANT | aucune file locale d'événements |

## Module 3 - Challenges

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Time Goal (objectif de temps sur une période) | MVP | OK | ChallengeType.TotalTime |
| Speed Race (premier à atteindre un seuil) | MVP | MANQUANT | types actuels : TotalTime, SessionCount, DailyStreak, LongestSession |
| Ranking Battle (classement selon le temps) | MVP | PARTIEL | classement par progression, pas de type dédié |
| Streak Challenge | MVP | OK | ChallengeType.DailyStreak |
| Créer, lister, rejoindre un challenge | MVP | OK |  |
| Définir dates et objectifs | MVP | PARTIEL | début = maintenant + durée en jours (pas de date de début choisie) |
| Inviter des amis à un challenge | MVP | OK | ChallengeInvitation + POST /api/challenges/{id}/invite |
| Rejoindre par lien ou code | MVP | PARTIEL | rejoindre par identifiant (POST /join) ; pas de code court ni de lien partageable |
| Consulter le classement | MVP | OK |  |
| Notifications de challenge (invitation, fin, récompense) | MVP | PARTIEL | notifications d'invitation créées ; fin de challenge et récompenses non déclenchées |

## Module 4 - Amis et interactions

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Rechercher, inviter, accepter/refuser, supprimer un ami | V2 | OK | FriendsController |
| Activités et statistiques publiques des amis | V2 | OK | GET /api/friends/feed et /{id}/stats |
| Réagir aux séances, commenter, partager un challenge | V2 | MANQUANT |  |

## Module 5 - Classements et statistiques

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Statistiques individuelles (total, jour/semaine/mois, moyenne, série, matières) | MVP | OK | GET /api/statistics/dashboard |
| Classement général hebdo / mensuel / global | MVP | OK | GET /api/leaderboard?period=week/month/all |
| Classement entre amis | V2 | OK | GET /api/friends/leaderboard |
| Temps par jour / histogramme hebdomadaire / répartition par matière | MVP | OK | Last7Days + BySubject |
| Calendrier d'activité (heatmap) | MVP | PARTIEL | endpoint GET /api/statistics/heatmap prêt ; widget Flutter à dessiner |

## Module 6 - Récompenses et gamification

| Point | Phase | Statut | Constat |
|---|---|---|---|
| XP et niveaux | MVP | OK | Gamification.XpFor / Level |
| Badges : First Step, Consistency (7 jours), séries | MVP | OK | 8 badges |
| Badge Study Champion (100 h) | MVP | MANQUANT | le palier le plus haut est 50 h |
| Badge Night Owl (5 séances nocturnes) | MVP | MANQUANT | Gamification.Earned ne reçoit pas l'heure de début des séances |
| Récompenses quotidiennes | MVP | MANQUANT |  |
| Conditions et récompenses configurables depuis le backend | MVP | MANQUANT | badges codés en dur dans Gamification.cs |

## Module 7 - Study Rooms

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Créer une salle privée, rejoindre une salle publique ou par code | V2 | OK | RoomsController |
| Participants, temps d'étude et statut (étude / pause / hors ligne) | V2 | OK | GET /api/rooms/{id} |
| Discuter et quitter une salle | V2 | OK | messages REST + hub SignalR /hubs/study |
| Salles virtuelles 2D/3D avec avatars | V3 | MANQUANT | prévu comme évolution |

## Module 8 - Planificateur d'étude

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Créer une tâche (matière, date/heure, durée estimée, priorité) | V2 | OK | TasksController |
| Marquer terminée, consulter par période (calendrier), tâches en retard | V2 | OK | complete, GET ?from&to, /overdue |

## Module 9 - Ambiances sonores et personnalisation

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Ambiances sonores (Lo-Fi, pluie, forêt...) | V2 | MANQUANT | aucun paquet audio |
| Mode sombre / clair au choix | V2 | PARTIEL | thème sombre présent, suit le système, pas de bascule manuelle |
| Personnaliser les couleurs de l'interface | V2 | MANQUANT |  |

## Module 10 - Notifications

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Rappels locaux (début d'étude, tâches, série quotidienne) | MVP | MANQUANT | flutter_local_notifications absent de pubspec.yaml |
| Notification de fin de Pomodoro | MVP | PARTIEL | alerte dans l'application seulement (rien si l'app est en arrière-plan) |
| Centre de notifications (invitations, classement, récompenses) | V2 | OK | GET /api/notifications |

## Architecture technique (section 3)

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Flutter / Dart | MVP | OK | mobile\study_timer |
| ASP.NET Core Web API | MVP | OK | backend\StudyTimer.Api |
| PostgreSQL | MVP | OK | docker-compose + Npgsql |
| SignalR (temps réel) | V2 | OK | hub /hubs/study |
| Redis (cache, optionnel pour le MVP) | V2 | MANQUANT | service absent de docker-compose.yml |
| JWT | MVP | OK |  |
| Docker Compose (API + PostgreSQL + Nginx + sauvegarde) | MVP | OK | docker-compose.yml |
| CI/CD (GitHub Actions ou Jenkins) | MVP | OK |  |
| Reverse proxy Nginx + TLS | MVP | OK | deploy\nginx\default.conf |
| Sauvegarde et restauration locales | MVP | OK | backup.sh / restore.sh |
| Supervision locale (santé API + base) | MVP | PARTIEL | /health vérifie l'API et la base ; pas d'espace disque ni CPU/RAM |

## API REST (section 5)

| Point | Phase | Statut | Constat |
|---|---|---|---|
| POST /api/auth/register | MVP | OK |  |
| POST /api/auth/login | MVP | OK |  |
| GET /api/users/profile | MVP | OK |  |
| PUT /api/users/profile | MVP | OK |  |
| POST /api/sessions/start | MVP | OK |  |
| POST /api/sessions/pause | MVP | OK |  |
| POST /api/sessions/resume | MVP | OK |  |
| POST /api/sessions/stop | MVP | OK |  |
| GET /api/sessions/history | MVP | OK |  |
| GET /api/statistics/dashboard | MVP | OK |  |
| POST /api/challenges | MVP | OK |  |
| GET /api/challenges | MVP | OK |  |
| POST /api/challenges/{id}/join | MVP | OK |  |
| GET /api/challenges/{id}/ranking | MVP | PARTIEL | existe sous : GET /api/challenges/{id}/leaderboard |
| POST /api/friends/invite | V2 | OK |  |
| GET /api/leaderboard/weekly | MVP | PARTIEL | existe sous : GET /api/leaderboard |
| POST /api/rooms | V2 | OK |  |
| GET /api/rooms | V2 | OK |  |
| POST /api/tasks | V2 | OK |  |

## Base de données (section 4)

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Users | MVP | OK |  |
| UserProfiles | MVP | PARTIEL | Profil fusionné dans Users (prénom, nom, pays, fuseau) |
| Friends | V2 | OK |  |
| StudySessions | MVP | OK |  |
| Subjects | MVP | OK |  |
| Tasks | V2 | OK |  |
| Challenges | MVP | OK |  |
| ChallengeParticipants | MVP | OK |  |
| ChallengeInvitations | MVP | OK |  |
| Leaderboards | MVP | PARTIEL | Classements calculés à la volée depuis les séances validées (RG04) : acceptable |
| UserStatistics | MVP | PARTIEL | Statistiques calculées à la volée : acceptable |
| Achievements | MVP | PARTIEL | Badges définis dans Gamification.cs (pas en base) |
| UserAchievements | MVP | OK |  |
| StudyRooms | V2 | OK |  |
| RoomParticipants | V2 | OK |  |
| RoomMessages | V2 | OK |  |
| Notifications | V2 | OK |  |
| DailyStreaks | MVP | PARTIEL | Séries calculées à la volée depuis les séances : acceptable |

## Règles de gestion (section 6)

| Point | Phase | Statut | Constat |
|---|---|---|---|
| RG01 - Validation des séances | MVP | PARTIEL | le statut Rejected existe mais n'est jamais utilisé ; une séance de 2 secondes est 'Completed' (0 XP) |
| RG02 - Le serveur est la source de vérité du temps | MVP | OK | temps calculé avec DateTime.UtcNow côté serveur |
| RG03 - Prévention de la fraude | MVP | PARTIEL | 1 seule séance active, durées négatives bloquées (Math.Max), horodatages serveur ; pas d'édition manuelle possible |
| RG04 - Classements sur séances validées | MVP | OK | filtre Status == Completed |
| RG05 - Séries avec fuseau horaire | MVP | PARTIEL | statistiques en fuseau utilisateur ; badges et défis calculés en UTC (cf. GUIDE.md) |
| RG06 - Pas de nouveau participant après la date limite | MVP | OK | contrôle dans Join |
| RG07 - Confidentialité (visibilité stats / activité) | V2 | OK | UserPrivacy + /api/users/privacy |

## Interfaces graphiques (section 7)

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Écran Accueil | MVP | OK | dashboard_page.dart |
| Écran Timer | MVP | OK | timer_page.dart |
| Écran Challenges | MVP | OK | challenges_page.dart |
| Écran Statistiques | MVP | OK | stats_page.dart |
| Écran Communauté | MVP | OK | community_page.dart |
| Écran Planificateur | MVP | OK | planner_page.dart |

## Exigences non fonctionnelles (section 8)

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Sécurité : HTTPS, JWT, mots de passe hachés | MVP | OK | HSTS, PasswordHasher, JWT |
| Limitation de débit sur l'authentification | MVP | OK | 10 req/min/IP |
| Internationalisation français / anglais / arabe | MVP | MANQUANT | textes codés en dur en français |
| Compatibilité iOS | MVP | MANQUANT | pas de dossier ios (projet créé pour Android/Web/Windows) |
| Compatibilité Android | MVP | OK | dossier android présent |
| Performance : API < 500 ms (test de charge k6) | MVP | PARTIEL | script k6 prêt ; à exécuter sur le serveur cible |
| Disponibilité 99,5 % | MVP | PARTIEL | restart: unless-stopped + healthcheck ; à prouver par la supervision |

## Tests (section 10)

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Tests unitaires et API | MVP | OK | 32 méthodes de test xUnit (+ cas Theory) |
| Tests Flutter | MVP | OK | mobile\study_timer\test |
| Tests des modules sociaux / planificateur / salles | V2 | OK | ExtrasTests.cs |
| Tests de sécurité (autorisations, accès inter-utilisateurs) | MVP | PARTIEL | 401 sans jeton et isolation des matières testés |
| Tests utilisateurs (ergonomie) | MVP | MANQUANT |  |

## Livrables (section 11)

| Point | Phase | Statut | Constat |
|---|---|---|---|
| Code source de l'application mobile | MVP | OK | mobile\study_timer |
| Backend + Docker Compose + Nginx + sauvegardes | MVP | OK | backend, docker-compose.yml, deploy |
| Scripts de création / migration de la base | MVP | OK | migrations EF Core |
| Documentation technique, guide d'installation et d'administration | MVP | OK | GUIDE.md, docs\PROJET.md |
| Documentation API (Swagger/OpenAPI) | MVP | OK | /swagger |
| Maquettes UI/UX (Figma) | MVP | MANQUANT | non détectable dans le dépôt |
| Application Android installable (APK/AAB) | MVP | OK | app-debug.apk |
| Projet iOS + configuration réseau local | MVP | MANQUANT |  |
| Rapport des tests | MVP | PARTIEL | sortie brute de dotnet test / flutter test (docs\RAPPORT-ERREURS.txt) |

## Reste à faire (par priorité)

### MVP

- [ ] **Photo de profil** (MANQUANT) : Ajouter User.AvatarUrl + POST /api/users/avatar (stockage local du serveur).
- [ ] **Google Sign-In / Apple Sign-In** (MANQUANT) : Exclu en mode serveur local (cahier 3.3 : pas de connexion Google/Apple hors Internet). A documenter comme écart assumé.
- [ ] **Suppression du compte** (MANQUANT) : Ajouter DELETE /api/users/account (suppression en cascade des séances, matières, jetons, badges, amitiés).
- [ ] **File d'attente hors-ligne + resynchronisation (cahier 8.1)** (MANQUANT) : Stocker les actions (start/pause/stop) dans shared_preferences/sqflite quand le Wi-Fi tombe, puis les rejouer.
- [ ] **Speed Race (premier à atteindre un seuil)** (MANQUANT) : Ajouter ChallengeType.SpeedRace + date d'atteinte du seuil (ordre d'arrivée).
- [ ] **Ranking Battle (classement selon le temps)** (PARTIEL) : Ajouter ChallengeType.RankingBattle (même calcul que TotalTime, gagnant désigné à la fin).
- [ ] **Définir dates et objectifs** (PARTIEL) : Accepter StartsAtUtc dans CreateChallengeDto.
- [ ] **Rejoindre par lien ou code** (PARTIEL) : Ajouter Challenge.JoinCode (6 caractères) + POST /api/challenges/join-by-code.
- [ ] **Notifications de challenge (invitation, fin, récompense)** (PARTIEL) : Créer une notification à la fin d'un challenge et à l'attribution d'un badge.
- [ ] **Calendrier d'activité (heatmap)** (PARTIEL) : Dessiner la grille 7x52 dans stats_page.dart avec les données de /heatmap.
- [ ] **Badge Study Champion (100 h)** (MANQUANT) : Ajouter hours_100 à Gamification.Badges (et mettre à jour le test qui attend 8 badges).
- [ ] **Badge Night Owl (5 séances nocturnes)** (MANQUANT) : Passer l'heure locale de début à Earned() et compter les séances entre 22h et 5h.
- [ ] **Récompenses quotidiennes** (MANQUANT) : Ajouter un bonus XP du premier jour validé (DailyStreaks).
- [ ] **Conditions et récompenses configurables depuis le backend** (MANQUANT) : Table Achievements (code, seuil, XP) éditable + endpoint d'administration.
- [ ] **Rappels locaux (début d'étude, tâches, série quotidienne)** (MANQUANT) : Ajouter flutter_local_notifications (notifications locales, sans Cloud) et planifier les rappels.
- [ ] **Notification de fin de Pomodoro** (PARTIEL) : Notification locale planifiée à l'heure de fin prévue.
- [ ] **Supervision locale (santé API + base)** (PARTIEL) : Ajouter un contrôle d'espace disque (AddDiskStorageHealthCheck) ou un script de supervision.
- [ ] **GET /api/challenges/{id}/ranking** (PARTIEL) : -Appliquer : route alias conforme au cahier.
- [ ] **GET /api/leaderboard/weekly** (PARTIEL) : -Appliquer : route alias conforme au cahier.
- [ ] **RG01 - Validation des séances** (PARTIEL) : Rejeter les séances < 60 s (et adapter le test Cycle_complet_de_seance_et_historique qui arrête immédiatement).
- [ ] **RG03 - Prévention de la fraude** (PARTIEL) : Journaliser et refuser les arrêts incohérents (durée > temps réel depuis le début), limiter la fréquence des start/stop.
- [ ] **RG05 - Séries avec fuseau horaire** (PARTIEL) : Faire passer le fuseau à Gamification.Earned/Progress.
- [ ] **Internationalisation français / anglais / arabe** (MANQUANT) : Ajouter flutter_localizations + fichiers .arb (fr, en, ar avec RTL).
- [ ] **Compatibilité iOS** (MANQUANT) : Sur un Mac : flutter create --platforms=ios . puis configurer l'adresse du serveur local.
- [ ] **Performance : API < 500 ms (test de charge k6)** (PARTIEL) : k6 run deploy\tests\load-test.js
- [ ] **Tests de sécurité (autorisations, accès inter-utilisateurs)** (PARTIEL) : Ajouter des tests d'accès refusé sur les nouvelles routes.
- [ ] **Tests utilisateurs (ergonomie)** (MANQUANT) : Organiser une session avec 5 étudiants et consigner les retours.
- [ ] **Maquettes UI/UX (Figma)** (MANQUANT) : Ajouter le lien ou l'export des maquettes dans docs\.
- [ ] **Projet iOS + configuration réseau local** (MANQUANT) : Voir Compatibilité iOS.
- [ ] **Rapport des tests** (PARTIEL) : Rédiger un rapport de tests structuré (cas, résultat, couverture).

### V2

- [ ] **Réagir aux séances, commenter, partager un challenge** (MANQUANT) : Ajouter table SessionReactions/Comments (après validation du fil d'activité).
- [ ] **Ambiances sonores (Lo-Fi, pluie, forêt...)** (MANQUANT) : Ajouter just_audio + fichiers .mp3 libres de droits en assets locaux (pas de flux externe : mode hors-ligne).
- [ ] **Mode sombre / clair au choix** (PARTIEL) : Ajouter un ValueNotifier<ThemeMode> sauvegardé dans shared_preferences.
- [ ] **Personnaliser les couleurs de l'interface** (MANQUANT) : Choix d'une couleur d'accent dans le profil.
- [ ] **Redis (cache, optionnel pour le MVP)** (MANQUANT) : Optionnel : ajouter redis:7-alpine + cache des classements.

### V3

- [ ] **Salles virtuelles 2D/3D avec avatars** (MANQUANT) : Hors périmètre actuel.

