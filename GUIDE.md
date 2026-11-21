# Study Timer — Guide d'installation et d'administration

## 1. Développement local
1. PostgreSQL local : base `studytimer`, utilisateur `studyuser`.
2. `.\Set-DevSecrets.ps1` : enregistre la clé JWT et la chaîne de connexion **hors du code** (dotnet user-secrets).
3. `.\Add-Phase2Migration.ps1` : crée et applique la migration (défis, badges, XP).
4. API : `dotnet run --project backend\StudyTimer.Api` (http://localhost:5293, Swagger sur /swagger).
5. App : `cd mobile\study_timer` puis `flutter run -d chrome`.
6. Tests : `dotnet test backend\StudyTimer.slnx` et `flutter test`.

## 2. Déploiement (Docker + Nginx + TLS)
1. Serveur avec Docker et le dépôt cloné.
2. `.\deploy\scripts\New-Secrets.ps1 -PublicUrl https://votre-domaine` génère `.env` (secrets aléatoires). Ne jamais le commiter.
3. Certificat TLS dans `deploy/certs/` (`fullchain.pem`, `privkey.pem`) : Let's Encrypt (certbot) en production, `deploy/scripts/new-cert-dev.sh` pour un test.
4. Application web : `cd mobile/study_timer && flutter build web --release --dart-define=API_URL=` (même domaine que l'API).
5. `docker compose up -d --build` — les migrations s'appliquent au démarrage de l'API.

## 3. Sécurité
- La clé JWT (32 caractères minimum) et les mots de passe viennent de `.env` / user-secrets ; l'API refuse de démarrer sans clé valide.
- CORS limité à `PUBLIC_URL`. HTTPS forcé par Nginx (HSTS). Limitation de débit : 10 requêtes/minute/IP sur `/api/auth/*`.
- Swagger désactivé en production (`SWAGGER_ENABLED=true` pour l'activer).
- Mots de passe hachés (PasswordHasher), refresh tokens hachés et à usage unique.

## 4. Administration
- Santé : `https://domaine/health`. Logs : `docker compose logs -f api`.
- Sauvegarde automatique quotidienne dans `./backups` (rotation `BACKUP_KEEP_DAYS`, 14 par défaut).
- Restauration : `./deploy/scripts/restore.sh backups/studytimer-AAAAMMJJ-HHMMSS.dump`.
- Mise à jour : `git pull && docker compose up -d --build`.

## 5. Règles de jeu (Phase 2)
- XP : 1 XP par minute étudiée, +10 XP pour une séance d'au moins 25 minutes. Niveau n à 100×(n−1)² XP.
- Série : un jour compte à partir de 10 minutes d'étude.
- Défis : temps total, nombre de séances, série de jours, séance la plus longue (jours calculés en UTC).
- Badges : premier pas, assidu (25 séances), 10 h, 50 h, séries de 3/7/30 jours, marathon (60 min).
