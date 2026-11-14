# 2. Préparer le serveur (la machine cible)

Hypothèse : le serveur a **juste un OS Linux installé** (testé sur Ubuntu 24.04), un utilisateur
normal, et un accès réseau. Rien d'autre n'est requis : Ansible installe le reste
(paquets, k3s, helm).

## Prérequis minimum sur le serveur

| Besoin | Pourquoi |
|---|---|
| Ubuntu/Debian récent | le rôle `common` utilise `apt` |
| Serveur SSH (`openssh-server`) | Ansible se connecte en SSH |
| Un utilisateur avec droits sudo | pour installer des choses |
| Accès internet | télécharger k3s, helm, les images de conteneurs |
| Python 3 | Ansible l'exécute sur la cible (présent par défaut sur Ubuntu) |
| ~2 Go RAM, 2 CPU minimum | k3s est léger (le serveur actuel : 8 CPU / 31 Go) |

## Étape A — Activer SSH sur le serveur (si pas déjà fait)

Sur le serveur (clavier/écran ou console) :

```bash
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable --now ssh
ip -4 addr        # noter l'adresse IP, ex: 192.168.1.12
```

> Conseil : donne une **IP fixe** au serveur (réservation DHCP dans ta box/routeur), sinon
> l'adresse peut changer et l'inventaire ne marchera plus.

## Étape B — Connexion SSH par clé (depuis ton PC)

Sur **ton PC** :

```bash
# 1. créer une clé si tu n'en as pas
ssh-keygen -t ed25519

# 2. copier la clé publique sur le serveur
ssh-copy-id michou@192.168.1.12

# 3. tester (ne doit PAS demander de mot de passe)
ssh michou@192.168.1.12
```

Pratique : un alias dans `~/.ssh/config` sur ton PC (c'est le cas actuellement) :

```
Host tour
    HostName 192.168.1.12
    User michou
    IdentityFile ~/.ssh/id_ed25519
    Port 22
```

Ensuite `ssh tour` suffit.

## Étape C — sudo sans mot de passe (important)

Ansible a besoin de `sudo` à chaque tâche. Plutôt que de taper le mot de passe à chaque fois,
on autorise `michou` à utiliser sudo sans mot de passe. **Sur le serveur** :

```bash
echo 'michou ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/michou
sudo chmod 440 /etc/sudoers.d/michou
```

Vérifier depuis ton PC :

```bash
ssh tour 'sudo -n true && echo sudo-ok'     # doit afficher sudo-ok
```

> Alternative sans cette étape : lancer Ansible avec `-K` (`--ask-become-pass`) et taper le
> mot de passe à chaque exécution. Moins pratique, plus sûr.

## Étape D — Déclarer le serveur dans l'inventaire

Fichier [inventory/hosts.yml](../inventory/hosts.yml) :

```yaml
all:
  children:
    k3s_server:
      hosts:
        tour:                                    # nom libre (pas forcément le hostname)
          ansible_host: 192.168.1.12             # IP du serveur
          ansible_user: michou                   # utilisateur SSH
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
```

Tester :

```bash
source .venv/bin/activate
make ping       # attendu : tour | SUCCESS => ... "ping": "pong"
```

Si `pong` : le serveur est prêt, passe à [03-deployer-le-cluster.md](03-deployer-le-cluster.md).

## Ajouter une 2e machine plus tard

Ajouter un hôte dans `inventory/hosts.yml`. Pour un vrai multi-nœuds il faudra ajouter un groupe
`k3s_agent` et un rôle pour joindre les agents (non fait, voir [prochaines étapes](08-prochaines-etapes.md)).
