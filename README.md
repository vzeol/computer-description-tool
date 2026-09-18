# Computer Description Tool

Outil Windows avec interface graphique pour modifier la description des postes d'un domaine Active Directory, à l'unité ou en masse à partir d'un fichier CSV. La description est écrite à la fois dans le registre du poste et dans l'Active Directory.

## 📦 Contenu du dépôt

| Fichier | Description |
|---|---|
| `Computer Description Tool.exe` | Exécutable prêt à l'emploi — **à utiliser pour lancer l'outil** |
| `Computer-Description-Tool-1.3.ps1` | Code source de la version actuelle (fourni pour référence/transparence, non destiné à être exécuté directement) |
| `icon.ico` | Icône de l'application, utilisée lors de la génération de l'exe |

## 🚀 Utilisation

1. Télécharger `Computer Description Tool.exe` depuis la [page Releases](https://github.com/vzeol/computer-description-tool/releases/latest) et le lancer. Les versions suivantes sont ensuite proposées automatiquement au lancement.
2. Pour un poste : saisir son nom (auto-complété depuis l'AD) et la description, puis « Appliquer ». « Vérifier le PC » affiche la description actuelle et le système du poste.
3. Pour un lot de postes : préparer un fichier CSV au format suivant :

   ```
   PC;Description
   NOM_DU_POSTE_1;Description du poste 1
   NOM_DU_POSTE_2;Description du poste 2
   ```

   **Règles du CSV :**
   - Séparateur : point-virgule (`;`)
   - Première ligne obligatoire (en-tête `PC;Description`)
   - Un poste par ligne ; une ligne sans nom de poste ou sans description est signalée « LIGNE INVALIDE » et n'est pas appliquée

4. Cliquer sur « Traiter CSV » et confirmer. Le suivi (PC / Description / État) s'affiche en temps réel. En fin de traitement, un rapport CSV (`_RAPPORT_<date>.csv`) peut être généré sur demande.

## 🔄 Mises à jour

Au lancement, l'outil vérifie sur la page Releases de ce dépôt si une version plus récente existe. Si c'est le cas, il affiche les nouveautés et propose de l'installer : il télécharge le nouvel exécutable, vérifie son empreinte SHA256, le met à la place de l'ancien et redémarre. Sans accès à Internet, l'outil démarre normalement.

Le dossier qui contient l'exe doit être accessible en écriture ; sinon, l'outil indique où télécharger la nouvelle version.

## 🧩 Fonctionnalités (v1.3.1)

- Mise à jour automatique au lancement, avec confirmation
- Liens « GitHub » et « À propos » dans le bandeau : page du projet, version, auteur
- Vérification des prérequis au lancement (contrôleur de domaine ou poste du domaine, compte administrateur du domaine, module RSAT) : si un prérequis manque, un message l'indique et les fonctions de modification sont désactivées
- Rappel du compte et du domaine utilisés dans la barre de statut
- Auto-complétion des noms de postes depuis l'Active Directory
- Pré-remplissage de la description avec le nom de l'unité d'organisation (OU) du poste, par exemple sa salle
- Vérification de la disponibilité du poste (ping + accès `ADMIN$`) avant modification
- Traitement par lot via CSV : confirmation avant lancement, suivi coloré ligne par ligne, lignes invalides signalées sans interrompre le lot, annulation possible
- Rapport CSV optionnel en fin de traitement
- Interface verrouillée pendant un traitement, barre de progression

## 🕒 Historique des versions

| Version | Notes |
|---|---|
| 0.7 | Première version fonctionnelle, interface minimale |
| 0.8 | Auto-complétion des noms de postes depuis l'AD |
| 0.9 | Aide sur le format CSV, libellés d'état revus |
| 1.0 | Gestion complète de l'interface (verrouillage, statuts, barre de progression) |
| 1.1 | Refonte visuelle, suivi CSV en temps réel, confirmation avant traitement, rapport CSV optionnel |
| 1.2 | Vérification des prérequis au lancement |
| 1.3 | Mise à jour automatique, rappel compte/domaine, traitement CSV fiabilisé (fichier d'une seule ligne, lignes incomplètes, en-tête vérifié), nouvelle icône |
| **1.3.1** | Liens « GitHub » et « À propos » dans le bandeau, icône de l'outil dans la barre de titre et la barre des tâches |

Les versions antérieures à la 1.3 ne sont pas publiées dans ce dépôt.

## ⚠️ Prérequis

- Windows avec Windows PowerShell 5.1 (inclus dans Windows 10/11 et Windows Server 2016 et suivants)
- Lancer l'outil sur un contrôleur de domaine, ou sur un poste membre du domaine
- Compte administrateur du domaine (membre du groupe « Admins du domaine ») — pas besoin de « Exécuter en tant qu'administrateur »
- Module PowerShell `ActiveDirectory` (RSAT)
- Accès réseau aux postes : ping, partage `ADMIN$` et registre à distance

Ces prérequis sont vérifiés au lancement. S'il en manque un, un message indique lequel et les fonctions « Vérifier le PC », « Appliquer » et « Traiter CSV » sont désactivées (l'aide CSV reste accessible).
