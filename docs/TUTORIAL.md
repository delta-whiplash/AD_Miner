# Tutoriel: Audit Active Directory avec AD-Miner

Guide complet pour générer un rapport de sécurité AD avec Docker.

**Source**: [IT-Connect - Générer un rapport de sécurité Active Directory avec AD-Miner et BloodHound](https://www.it-connect.fr/generer-un-rapport-de-securite-active-directory-avec-ad-miner-et-bloodhound/)

---

## Prérequis

- VM Linux avec Docker installé
- Accès à un Active Directory (machine Windows domain-joined pour Sharphound)
- Droits administrateur AD pour collecter les données

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              ACTIVE DIRECTORY                       │
└─────────────────────┬───────────────────────────────┘
                      │
              ┌───────┴───────┐
         Sharphound.exe    RustHound
         (Windows)         (Linux)
              │                  │
              └───────┬──────────┘
                      │
                      ▼
              ┌───────────────┐
              │    Neo4j      │  ← Conteneur Docker
              │   (4.4.12)    │
              └───────┬───────┘
                      │
              ┌───────┴───────┐
         BloodHound CE    API Import
         (Windows UI)      (optionnel)
              │                  │
              └───────┬──────────┘
                      │
                      ▼
              ┌───────────────┐
              │   AD-Miner    │  ← Notre image Docker
              └───────┬───────┘
                      │
                      ▼
              ┌───────────────┐
              │ Rapport HTML  │
              │   (static)    │
              └───────────────┘
```

---

## Étape 1: Démarrer Neo4j

```bash
# Cloner le repo (si pas encore fait)
git clone https://github.com/delta-whiplash/AD_Miner.git
cd AD_Miner

# Démarrer Neo4j
docker-compose up -d neo4j
```

Vérifier que Neo4j est healthy:
```bash
docker-compose ps
```

Neo4j est accessible sur:
- **http://localhost:7474** (Browser)
- **bolt://localhost:7687** (Connexion)
- **User**: `neo4j`
- **Password**: `adminer123`

---

## Étape 2: Collecter les données AD

### Option A: Sharphound (Windows)

SharpHound est le collecteur officiel de données pour BloodHound.

1. **Télécharger Sharphound**:
   ```powershell
   # Depuis une machine Windows domain-joined
   Invoke-WebRequest -Uri "https://github.com/BloodHoundAD/SharpHound/releases/latest/download/SharpHound.exe" -OutFile SharpHound.exe
   ```

2. **Exécuter la collecte**:
   ```powershell
   # Collecte complète
   .\SharpHound.exe -c All -d MONAD.LOCAL

   # Options disponibles:
   # -c All          : Collecte complète
   # -c Session     : Sessions uniquement
   # -c ACL         : ACL uniquement
   # -d DOMAIN.LOCAL: Nom de votre domaine
   ```

3. **Récupérer le fichier ZIP** généré (format: `20230315123456_BloodHound.zip`)

### Option B: RustHound (Linux)

Alternative pour Linux/Mac:

```bash
# Installer RustHound
git clone https://github.com/NH-RED-TEAM/RustHound
cd RustHound
cargo build --release

# Exécuter la collecte
./target/release/rusthound -d MONAD.LOCAL -o output/ --zip
```

### Option C: BloodHound.py (Python)

```bash
# Installer
pip install bloodhound

# Exécuter
bloodhound -d MONAD.LOCAL -c All -u username -p password
```

---

## Étape 3: Importer dans Neo4j

### Option A: BloodHound CE (Recommandé)

BloodHound CE offre une interface graphique pour importer les données.

1. **Télécharger BloodHound CE**:
   - Windows: https://github.com/SpecterOps/BloodHound/releases

2. **Configurer la connexion**:
   - Ouvrir BloodHound CE
   - Choisir "Neo4j Connection"
   - URL: `bolt://localhost:7687`
   - User: `neo4j`
   - Password: `adminer123`

3. **Importer les données**:
   - Cliquer sur "Upload Data"
   - Sélectionner le fichier ZIP généré par Sharphound

### Option B: Import API

Si vous n'utilisez pas BloodHound CE:

```bash
# Via cypher-shell (si installé)
docker exec -i ad_miner-neo4j-1 cypher-shell -u neo4j -p adminer123 < sharphound_data.json

# Ou via script Python
docker run --rm -v /path/to/data:/data ghcr.io/delta-whiplash/ad_miner:latest python -c "
from neo4j import GraphDatabase
driver = GraphDatabase.driver('bolt://neo4j:7687', auth=('neo4j', 'adminer123'))
# Script d'import custom ici
"
```

---

## Étape 4: Générer le rapport AD-Miner

```bash
# Générer le rapport
docker-compose run ad-miner
```

Ou avec options personnalisées:

```bash
# Avec un préfixe spécifique
docker run ghcr.io/delta-whiplash/ad_miner:latest \
  -cf mondomaine1 \
  -u neo4j \
  -p adminer123 \
  -b bolt://localhost:7687
```

Options utiles:
- `-cf PREFIX` : Préfixe du rapport (défaut: "report")
- `-u USER` : Utilisateur Neo4j
- `-p PASS` : Mot de passe Neo4j
- `-b BOLT` : URL Bolt Neo4j
- `-c` : Utiliser le cache
- `-l NIVEAU` : Niveau de récursion pour les chemins
- `-e DATE` : Date d'extraction (format: YYYYMMDD)
- `-r DAYS` : Politique de renouvellement mot de passe (jours)

---

## Étape 5: Consulter le rapport

```bash
# Le rapport est généré dans
ls -la render_*/

# Ouvrir dans un navigateur
firefox render_report/index.html
# ou
chrome render_report/index.html
```

Le rapport HTML contient:
- Vue d'ensemble du domaine
- Comptes privilégiés
- Chemins d'attaque (Kerberoasting, AS-Rep Roasting, etc.)
- Vulnérabilités ACL
- Métriques de risque
- Graphiques interactifs

---

## Commandes utiles

### Gestion des containers

```bash
# Démarrer
docker-compose up -d

# Arrêter
docker-compose down

# Voir les logs
docker-compose logs -f neo4j
docker-compose logs -f ad-miner

# Re-générer le rapport
docker-compose run ad-miner

# Supprimer les données (attention!)
docker-compose down -v
```

### Plusieurs audits

Pour gérer plusieurs domaines AD:

```bash
# Domaine 1
docker run ghcr.io/delta-whiplash/ad_miner:latest -cf domaine1 -u neo4j -p adminer123 -b bolt://localhost:7687

# Domaine 2
docker run ghcr.io/delta-whiplash/ad_miner:latest -cf domaine2 -u neo4j -p adminer123 -b bolt://localhost:7687
```

Les rapports seront dans:
- `render_domaine1/`
- `render_domaine2/`

---

## Dépannage

### Neo4j ne démarre pas

```bash
# Vérifier les logs
docker-compose logs neo4j

# Problème de mot de passe
# Le mot de passe doit contenir au moins 8 caractères
# ou configurer: NEO4J_dbms_security_auth__minimum__password__length=4
```

### AD-Miner ne trouve pas Neo4j

```bash
# Vérifier que Neo4j est healthy
docker-compose ps

# Patienter que le healthcheck passe (~60s au premier démarrage)
```

### Erreur d'authentification

```bash
# Vérifier les identifiants
# Par défaut: neo4j / adminer123
# Modifier dans docker-compose.yml si nécessaire
```

---

## Pour aller plus loin

### Évolution historique

Pour comparer les rapports dans le temps:

```bash
# Premier audit
docker run ghcr.io/delta-whiplash/ad_miner:latest -cf audit1 -u neo4j -p adminer123 -b bolt://localhost:7687

# Deuxième audit (3 mois plus tard)
docker run ghcr.io/delta-whiplash/ad_miner:latest -cf audit2 -u neo4j -p adminer123 -b bolt://localhost:7687 --previous_prefix audit1
```

### Graph Data Science (GDS)

Pour les "smartest paths" (chemins d'exploitabilité):

```bash
# Activer GDS dans docker-compose.yml
NEO4J_PLUGINS: '["apoc","graph-data-science"]'
```

---

## Ressources

- [Dépôt GitHub AD-Miner](https://github.com/AD-Security/AD_Miner)
- [SharpHound](https://github.com/BloodHoundAD/SharpHound)
- [RustHound](https://github.com/NH-RED-TEAM/RustHound)
- [BloodHound.py](https://github.com/dirkjanm/BloodHound.py)
- [BloodHound CE](https://github.com/SpecterOps/BloodHound)
- [Tutoriel IT-Connect](https://www.it-connect.fr/generer-un-rapport-de-securite-active-directory-avec-ad-miner-et-bloodhound/)