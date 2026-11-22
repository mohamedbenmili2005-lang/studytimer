<p align="center"><img src="docs/images/logo.png" width="120" alt="Logo Study Timer"></p>

<h1 align="center">Study Timer</h1>

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

```mermaid
flowchart LR
    A["Application Flutter<br/>Android / Web / Windows"] -->|"HTTP + JSON + JWT"| B["API ASP.NET Core"]
    A -. "WebSocket" .-> H["SignalR /hubs/study"]
    H --- B
    B --> D[("PostgreSQL")]
    N["Nginx (TLS)"] --> B
    N --> W["Application web Flutter"]
```

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

```powershell
# secrets hors du code (une seule fois)
dotnet user-secrets set "Jwt:Key" "une-cle-de-32-caracteres-minimum-xxxxxxxx" --project backend/StudyTimer.Api
dotnet user-secrets set "ConnectionStrings:Default" "Host=localhost;Database=studytimer;Username=studyuser;Password=..." --project backend/StudyTimer.Api

dotnet run --project backend/StudyTimer.Api --urls http://0.0.0.0:5293
```

Swagger : http://localhost:5293/swagger

### 2. Application

```powershell
cd mobile/study_timer
flutter pub get
flutter run -d chrome
# téléphone Android (même Wi-Fi que le PC) :
flutter run --dart-define=API_URL=http://<IP-DU-PC>:5293
```

### 3. Déploiement (Docker + Nginx + TLS)

```powershell
.\deploy\scripts\New-Secrets.ps1 -PublicUrl https://votre-domaine   # génère .env (ne jamais le commiter)
docker compose up -d --build
```

Voir [GUIDE.md](GUIDE.md) pour l'installation et l'administration complètes.

## Tests

```powershell
dotnet test backend/StudyTimer.slnx
cd mobile/study_timer ; flutter test
```

## Scripts

Les scripts d'aide sont dans [scripts/](scripts/README.md) : diagnostic de conformité, génération de modules, logo, publication GitHub.

## Structure du dépôt

```text
backend/            API ASP.NET Core (Api, Domain, Infrastructure, Tests)
mobile/study_timer/ Application Flutter
deploy/             Nginx, sauvegarde / restauration, certificats de test
scripts/            Scripts PowerShell d'aide
docs/               Documentation, conformité, images
docker-compose.yml  PostgreSQL + API + Nginx + sauvegardes
```

## Feuille de route

- Speed Race et code de partage des défis
- Photo de profil, suppression de compte
- Notifications locales et mode hors-ligne
- Internationalisation français / anglais / arabe
- Ambiances sonores, version iOS, assistant IA

## Auteur

Projet réalisé dans le cadre d'un mini-projet de développement mobile avancé.
<img width="720" height="1600" alt="ee1df266-033d-474a-9870-698c33bc5a4b" src="https://github.com/user-attachments/assets/ea55a982-6d2c-4735-8069-a163be9516d4" />
<img width="720" height="1600" alt="9ef06019-771e-47e5-8cc5-19e1d9ca2c09" src="https://github.com/user-attachments/assets/de620e1f-b055-41e9-964a-5c033cd2b931" />
<img width="720" height="1600" alt="0af9ebbb-12ac-4b53-925d-71a0c81569e9" src="https://github.com/user-attachments/assets/f88db281-a507-4992-992c-c5ac3e3863fd" />
<img width="720" height="1600" alt="1f5462c6-8615-43fa-895d-bf800943ec17" src="https://github.com/user-attachments/assets/d0cae7f0-a8ac-4b8e-98f3-df56462551de" />
<img width="720" height="1600" alt="9ef06019-771e-47e5-8cc5-19e1d9ca2c09" src="https://github.com/user-attachments/assets/20c5f0a9-c584-4f9a-a28c-08f2cc6e86f7" />
<img width="720" height="1600" alt="86c42db8-bbb2-4e36-a462-37e825180740" src="https://github.com/user-attachments/assets/06b9f89d-9a9f-4030-9a4f-495708088079" />
<img width="720" height="1600" alt="556ef62a-a55d-4974-8911-36f887d94eef" src="https://github.com/user-attachments/assets/1cfa72a5-d6d4-4e0d-85a9-b00a55bdb0d6" />
<img width="720" height="1600" alt="2268bbda-678e-45c8-b90f-fca62e5dae43" src="https://github.com/user-attachments/assets/218c0ed1-b687-442a-a142-7d44d2ec9c0f" />
<img width="720" height="1600" alt="a3c66c27-33f1-47e7-b900-c6b0d12f8030" src="https://github.com/user-attachments/assets/e3f0a23b-954a-4808-a25e-a9c9b09c5cb0" />
<img width="720" height="1600" alt="a8c4e58b-21c1-488a-a36c-98935d0dbdbc" src="https://github.com/user-attachments/assets/a53120a7-e114-411b-bdd4-64fcd902352f" />
<img width="720" height="1600" alt="b2abddfe-6f22-4d57-8071-d161a2ed9bfa" src="https://github.com/user-attachments/assets/4265355e-9f0c-4f13-b71d-b500744e5520" />
<img width="720" height="1600" alt="f408c922-aed0-4f24-8d97-4a03bf7fd392" src="https://github.com/user-attachments/assets/89ce86ed-999e-417a-a738-18c6c484b05d" />
<img width="720" height="1600" alt="fe315d13-46ae-472a-b7e1-64808753d5c7" src="https://github.com/user-attachments/assets/9a35607b-c8e2-41a4-a347-8a77095d779d" />


