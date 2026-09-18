# CLAUDE.md — Computer Description Tool

Ce fichier fait référence pour toute session Claude qui travaille sur ce dépôt, quel que soit le PC. En cas de conflit avec les notes locales d'une session, c'est ce fichier qui s'applique.

## Le projet

- Outil Windows (Windows PowerShell 5.1 + WinForms) qui modifie la description des postes : valeur de registre `srvcomment` et attribut AD `description`, à l'unité ou par lot via un CSV.
- Un seul script, compilé en exe avec ps2exe. Les utilisateurs lancent **uniquement l'exe**, téléchargé depuis la page Releases puis mis à jour par l'outil lui-même. Le `.ps1` n'est que le code source de référence : le README ne doit jamais proposer de lancer le `.ps1`.
- L'outil doit rester léger, portable et mono-fichier : pas de dépendance ajoutée, pas de fichier de configuration, pas d'installeur. Pas d'usine à gaz.

## Dépôt public : rester neutre

- Aucune information propre à un établissement, un employeur, un domaine ou une personne ne doit entrer dans le dépôt : code, README, messages de commit, notes de release. Pas de noms d'établissements ni de domaines réels, pas de conventions de nommage réelles, pas de noms de personnes. Exemples neutres uniquement (`NOM_DU_POSTE_1`, `SALLE`, `domaine.local`).
- Commits avec l'identité masquée, en configuration locale du dépôt (à vérifier sur chaque PC) : `git config user.name vzeol` et `git config user.email 40955660+vzeol@users.noreply.github.com`.

## Organisation du dépôt

- `Computer-Description-Tool-X.Y.ps1` : script de la version actuelle (publiée ou en préparation). Il porte le numéro de la version mineure : les correctifs X.Y.Z gardent le même fichier.
- `Computer Description Tool.exe` : exe compilé depuis ce script.
- `icon.ico` : icône, à toujours passer à la compilation.
- `archive/` : versions précédentes, figées telles qu'elles ont été publiées (à partir de la 1.3).

## Façon de travailler

1. Avant de commencer : `git pull --ff-only`. Le dépôt est modifié depuis plusieurs PC.
2. Les modifications se font directement dans le script actuel. Pas de nouveau numéro de version tant que l'utilisateur ne le demande pas.
3. Après chaque modification : vérifier la syntaxe (parser PowerShell), passer PSScriptAnalyzer, recompiler l'exe dans le dépôt en gardant le numéro de version actuel, puis envoyer l'exe à l'utilisateur pour qu'il le teste.
4. Ne pas lancer l'outil pour le tester : les PC de développement ne sont pas dans le domaine. L'utilisateur teste sur son contrôleur de domaine. Les tests locaux se limitent à la syntaxe, au lint et à des bouts de logique isolés : fonctions extraites du script par l'AST, réseau, AD et fenêtres simulés.
5. Commit en local avec un message en français : une ligne de titre, puis une liste à puces des changements. Demander avant de pousser, sauf si l'utilisateur a déjà donné son feu vert pour ce travail. Jamais de force push.
6. Répondre à l'utilisateur en français, court et direct. Le travail, lui, doit être complet et vérifié.

## Mise à jour automatique

- Au lancement, l'exe lit `https://api.github.com/repos/vzeol/computer-description-tool/releases/latest` (sans identifiant) et compare le tag à sa propre version, celle passée à `ps2exe -version`.
- Cette adresse est inscrite dans chaque exe installé : ne jamais renommer, déplacer ni passer en privé ce dépôt, sinon les exe installés ne se mettront plus à jour.
- Chaque release doit avoir un tag `vX.Y` (version mineure) ou `vX.Y.Z` (correctif) et contenir **un seul** fichier `.exe`, compilé avec `-version "X.Y.Z.0"` (Z = 0 pour une version mineure). Les brouillons et pré-versions sont ignorés par l'outil.
- Les notes de release s'affichent dans la fenêtre « Mise à jour disponible » des exe installés, qui ne comprend pas le markdown (seuls les `#` de titre sont retirés) et coupe à 800 caractères. Notes courtes, en simple liste à puces : pas de gras, pas de liens, pas de section « Installation » (sa place est le README).
- Test de bout en bout, sur le DC : compiler le même script avec une version inférieure (ex. `-version "1.2.99.0"`) et le lancer. Il doit proposer la dernière release, se remplacer et redémarrer.

## Réveil des postes (Wake-on-LAN)

- Le magic packet vise la **MAC** du poste et part en **diffusion dirigée** sur le sous-réseau de l'étendue DHCP (réseau OU inverse du masque). Jamais vers l'IP du poste (baux courts, IP changeantes) ni en `255.255.255.255` (ne franchit pas les routeurs et part par n'importe quelle interface).
- Les MAC viennent des baux et réservations du **DHCP du DC** (module `DhcpServer`, local puis `$env:LOGONSERVER`), relues au lancement et avant chaque lot, et sont **mémorisées dans l'AD** (attribut `networkAddress` de l'objet ordinateur, réputé libre) pour survivre à l'expiration des baux.
- Sans DHCP lisible, tout fonctionne comme avant, avec « réveil indisponible » dans l'info-bulle de la barre de statut.
- Le réveil est un choix : case « Réveil automatique des postes éteints » (cochée par défaut si disponible) pour les lots et relances, et bouton « Réveiller le PC » pour le poste saisi. « Vérifier le PC » ne réveille jamais, il indique seulement si la MAC est connue.
- Après des réveils, l'outil sonde les postes toutes les 5 s (`$script:WolAttenteMax` = 120 s) et traite chacun dès que ping et `ADMIN$` répondent ; ceux qui ne répondent pas reprennent leur état réel.
- Diagnostic hors outil : un script `test-wol.ps1` (Bureau de l'utilisateur, hors dépôt) reproduit la chaîne DHCP → diffusion → magic packet et chronomètre le démarrage.

## Passage à une nouvelle version (uniquement sur demande)

Deux niveaux, au choix de l'utilisateur :
- **Correctif `X.Y.Z`** (1.3 → 1.3.1) : corrections et petites améliorations. Même script, pas d'archive.
- **Version mineure `X.Y`** (1.3.2 → 1.4) : nouveautés plus importantes. Le script est archivé puis renommé.

1. Version mineure seulement : copier dans `archive/` la dernière version publiée, telle qu'elle est dans son tag (`git show vA.B.C:<fichier> > archive/<fichier>`), puis renommer le script de travail en `Computer-Description-Tool-X.Y.ps1` (`git mv`).
2. Recompiler l'exe avec `-version "X.Y.Z.0"`.
3. Mettre à jour le README : titre et contenu de « Fonctionnalités (vX.Y[.Z]) », nouvelle ligne dans « Historique des versions », « Prérequis » si besoin.
4. Commit « Passage en vX.Y[.Z] », tag annoté `vX.Y[.Z]`, push, puis release GitHub avec l'exe en pièce jointe et des notes en français.
5. Vérifier : le SHA256 de l'exe local est identique à celui de l'asset de la release (`gh release view <tag> --json assets`), et l'exe lancé avec `-extract:<fichier>` redonne exactement le script.

Chaque release est proposée automatiquement à tous les exe installés : ne publier qu'après le test de l'utilisateur sur le DC.

## Compilation

```powershell
Invoke-ps2exe -inputFile .\Computer-Description-Tool-X.Y.ps1 -outputFile ".\Computer Description Tool.exe" -iconFile .\icon.ico -noConsole -title "Computer Description Tool" -product "Computer Description Tool" -copyright "vzeol" -version "X.Y.Z.0"
```

- `-title` remplit la description visible de l'exe ; `-description` n'est pas affichée.
- Ne pas compiler depuis un chemin très long : ps2exe échoue.

## Pièges connus

- Les `.ps1` doivent rester en UTF-8 **avec BOM** et en CRLF, sinon PowerShell 5.1 casse les accents. Le `.gitattributes` impose le CRLF ; le BOM, lui, est à vérifier après chaque écriture (3 premiers octets `EF BB BF`), car certains outils enregistrent sans.
- Dans une chaîne, écrire `${nl}` et non `$nl` devant une lettre accentuée : `$nlÊtes` est lu comme une seule variable.
- La cible est Windows PowerShell 5.1, pas PowerShell 7. Exemple : un `Import-Csv` qui ne renvoie qu'une ligne donne un objet sans `.Count` ; toujours l'entourer de `@()`.
- `gh` : si la commande n'est pas trouvée, utiliser le chemin complet `C:\Program Files\GitHub CLI\gh.exe`.
- PSScriptAnalyzer remonte des avertissements connus et sans gravité : ShouldProcess sur les fonctions `Set-*`, `New-*`, `Update-*` et `Remove-*`, « pluriel » sur les noms français (`Test-Prerequis`, `Invoke-LotPostes`, `Get-LignesAReessayer`, `Set-LiensEnTeteActifs`, `Wait-PostesReveilles`, `Get-ParamsDhcp`), `catch` vides volontaires (`Get-SalleFromAD`, lectures DHCP/AD du réveil).
- Le glisser-déposer depuis l'Explorateur ne fonctionne pas si l'outil est lancé « en tant qu'administrateur » (isolation UIPI de Windows) ; l'outil n'a pas besoin d'élévation.
- Windows limite la description d'un poste (`srvcomment`) à 48 caractères : le champ est limité à 48 et une ligne CSV plus longue est signalée « DESC. TROP LONGUE » sans être appliquée.
