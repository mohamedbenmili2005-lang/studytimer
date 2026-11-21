# Scripts

Tous les scripts se lancent **depuis la racine du projet** (PowerShell) : `.\scripts\NomDuScript.ps1`.

| Script | Rôle |
|---|---|
| `Completer-Projet.ps1` | Compare le projet au cahier des charges (docs/CONFORMITE.md) et génère les modules manquants (-Appliquer, -Verifier). |
| `Corriger-Boutons.ps1` | Correctif des boutons à largeur infinie dans les pages Communauté et Planificateur. |
| `Corriger-Chrono.ps1` | Ajoute la barre « chrono en cours » sur toutes les pages. |
| `Corriger-Docker.ps1` | Correctifs de la configuration Docker. |
| `Creer-Logo.ps1` | Dessine le logo et installe l'icône de l'application Android (-Appliquer). |
| `diagnostic.ps1` | Ancien script de diagnostic. |
| `DiagnosticProjet.ps1` | Rapport de diagnostic du projet. |
| `Organiser-Projet.ps1` | Range l'arborescence du projet et génère docs/PROJET.md. |
| `Publier-GitHub.ps1` | Prépare le dépôt Git (sans secrets) et le publie sur GitHub. |

Les scripts de déploiement (sauvegarde, restauration, certificats) sont dans `deploy/scripts/`.
