# 1. Le poste de contrôle (ton PC)

Le « poste de contrôle » est la machine **depuis laquelle tu lances Ansible** (ton PC, `michou-...`).
Ansible n'est **pas** installé sur le serveur : il s'y connecte en SSH.

## Ce qu'il faut

- Python 3 et `git`
- Une clé SSH (`~/.ssh/id_ed25519`)
- Ansible + quelques librairies Python, **installés dans un environnement isolé `.venv`** du dépôt

## Étapes

### 1. Installer `uv` (gestionnaire d'environnements Python)

On utilise `uv` car `python3 -m venv` échoue sur Ubuntu sans le paquet `python3-venv`
(voir [dépannage](06-depannage.md)).

```bash
python3 -m pip install --user --break-system-packages uv
# ou : curl -LsSf https://astral.sh/uv/install.sh | sh
```

`uv` s'installe dans `~/.local/bin`. Vérifie que ce dossier est dans ton `PATH` :

```bash
export PATH=$HOME/.local/bin:$PATH
uv --version
```

### 2. Créer l'environnement et installer Ansible

Depuis la racine du dépôt :

```bash
cd ~/Documents/homelab
uv venv .venv
uv pip install --python .venv/bin/python ansible-core kubernetes PyYAML
```

- `ansible-core` : Ansible lui-même
- `kubernetes`, `PyYAML` : librairies Python utilisées par le module Helm/K8s d'Ansible

### 3. Activer l'environnement (à refaire à chaque nouveau terminal)

```bash
source .venv/bin/activate
ansible --version
```

### 4. Installer les collections Ansible

```bash
make setup      # = ansible-galaxy collection install -r requirements.yml
```

Installe `kubernetes.core` (module Helm), `ansible.posix`, `community.general`.
Elles atterrissent dans `~/.ansible/collections`.

### 5. (Optionnel) kubectl en local

Pas indispensable : on peut utiliser `ssh tour 'sudo k3s kubectl ...'`.
Pour l'avoir en local : https://kubernetes.io/docs/tasks/tools/ puis voir [05-utiliser-le-cluster.md](05-utiliser-le-cluster.md).

## Vérifier

```bash
source .venv/bin/activate
ansible --version          # affiche la version
ansible-galaxy collection list | grep kubernetes
```

## Refaire sur un nouveau PC

Cloner le dépôt, puis refaire les étapes 1 à 4. Rien d'autre.
