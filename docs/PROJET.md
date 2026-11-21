# StudyTimer - Guide du projet

Document genere automatiquement le 2026-11-21 15:08 par Organiser-Projet.ps1.
Relance le script pour le mettre a jour.

## 1. De quoi parle le projet ?

StudyTimer est une application de minuteur pour etudier : l'utilisateur lance un chrono de session de travail.
Le backend contient aussi un module de gamification (Gamification.cs) avec ses tests.
Voir aussi GUIDE.md a la racine.

## 2. Architecture : qui fait quoi ?

| Dossier | Role |
|---|---|
| backend | Serveur (API) en C# / .NET |
| backend\StudyTimer.Api | Point d'entree de l'API : controleurs, configuration (Program.cs, appsettings.json) |
| backend\StudyTimer.Domain | Coeur metier : les entites (objets de l'application) |
| backend\StudyTimer.Infrastructure | Acces a la base de donnees (AppDbContext, migrations) |
| backend\StudyTimer.Tests | Tests automatiques du backend |
| mobile\study_timer | Application Flutter (Dart) : Android, Web, Windows |
| mobile\study_timer\lib | Code de l'application : ecrans, logique, chrono |
| deploy | Deploiement : nginx, scripts de sauvegarde/restauration, certificats |
| docs | Documentation et rapports generes |
| archive | Anciennes archives .zip (apres rangement) |

## 3. Technologies utilisees

### Backend (C# / .NET)

**StudyTimer.Api**
- Cadre .NET : net10.0
- Paquet : Microsoft.AspNetCore.Authentication.JwtBearer 10.*
- Paquet : Microsoft.EntityFrameworkCore.Design 10.*
- Paquet : Microsoft.Extensions.Diagnostics.HealthChecks.EntityFrameworkCore 10.*
- Paquet : Swashbuckle.AspNetCore 6.9.0

**StudyTimer.Domain**
- Cadre .NET : net10.0

**StudyTimer.Infrastructure**
- Cadre .NET : net10.0
- Paquet : Microsoft.EntityFrameworkCore.Design 10.*
- Paquet : Npgsql.EntityFrameworkCore.PostgreSQL 10.*

**StudyTimer.Tests**
- Cadre .NET : net10.0
- Paquet : Microsoft.NET.Test.Sdk 17.*
- Paquet : xunit 2.*
- Paquet : xunit.runner.visualstudio 2.*
- Paquet : Microsoft.AspNetCore.Mvc.Testing 10.*
- Paquet : Microsoft.EntityFrameworkCore.InMemory 10.*

### Application mobile (Flutter / Dart)

**study_timer**
- Dependance : flutter
- Dependance : cupertino_icons
- Dependance : dio
- Dependance : shared_preferences
- Dependance de dev : flutter_test
- Dependance de dev : flutter_lints

### Docker et deploiement

**docker-compose.yml**
- Service : db
  - Image : postgres:17-alpine
- Service : api
- Service : nginx
  - Image : nginx:1.27-alpine
- Service : backup
  - Image : postgres:17-alpine

**docker-compose.dev.yml**
- Service : db
  - Image : postgres:16

- nginx est utilise comme serveur web / proxy (deploy\nginx).
- Le backend a un Dockerfile (execution en conteneur).

## 4. Structure des fichiers

```
archive/
    docs.zip
    StudyTimer-update.zip
backend/
    StudyTimer.Api/
        Controllers/
            AuthController.cs
            ChallengesController.cs
            ProgressController.cs
            SessionsController.cs
            StatisticsController.cs
            SubjectsController.cs
            UsersController.cs
        Properties/
            launchSettings.json
        appsettings.Development.json
        appsettings.json
        Gamification.cs
        Program.cs
        StudyTimer.Api.csproj
        StudyTimer.Api.http
    StudyTimer.Domain/
        Entities/
            Challenge.cs
            RefreshToken.cs
            StudySession.cs
            Subject.cs
            User.cs
        StudyTimer.Domain.csproj
    StudyTimer.Infrastructure/
        Migrations/
            20261120202254_InitialCreate.cs
            20261120202254_InitialCreate.Designer.cs
            20261120230700_AddRefreshTokens.cs
            20261120230700_AddRefreshTokens.Designer.cs
            20261121125310_Phase2_Gamification.cs
            20261121125310_Phase2_Gamification.Designer.cs
            AppDbContextModelSnapshot.cs
        AppDbContext.cs
        StudyTimer.Infrastructure.csproj
    StudyTimer.Tests/
        ApiFactory.cs
        ApiTests.cs
        GamificationTests.cs
        StudyTimer.Tests.csproj
    .dockerignore
    .gitignore
    Dockerfile
    StudyTimer.slnx
deploy/
    nginx/
        default.conf
    scripts/
        backup.sh
        new-cert-dev.sh
        New-Secrets.ps1
        restore.sh
    docker-compose.dev.yml
docs/
    CODE-MOBILE.txt
    deplacements.log
    PROJET.md
    RAPPORT-ERREURS.txt
mobile/
    study_timer/
        android/  (plateforme, non detaille)
        assets/
            images/
                logo.svg
        lib/
            api.dart
            challenges_page.dart
            config.dart
            dashboard_page.dart
            history_page.dart
            home_page.dart
            login_page.dart
            logo.dart
            main.dart
            profile_page.dart
            ring.dart
            stats_page.dart
            ... (+4 autres fichiers)
        test/
            util_test.dart
            widget_test.dart
        web/  (plateforme, non detaille)
        windows/  (plateforme, non detaille)
        .flutter-plugins-dependencies
        .gitignore
        .metadata
        analysis_options.yaml
        pubspec.lock
        pubspec.yaml
        README.md
        study_timer.iml
.env.example
.gitignore
docker-compose.yml
GUIDE.md
Organiser-Projet.ps1
```

## 5. Scripts disponibles

- deploy\scripts\backup.sh
- deploy\scripts\new-cert-dev.sh
- deploy\scripts\New-Secrets.ps1
- deploy\scripts\restore.sh
- Organiser-Projet.ps1

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
