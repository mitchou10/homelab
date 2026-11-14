# 5. Utiliser le cluster au quotidien

## Option 1 : depuis le serveur (sans rien installer en local)

```bash
ssh tour 'sudo k3s kubectl get pods -A'
# ou, une fois connecté en SSH :
ssh tour
sudo k3s kubectl get nodes
```

## Option 2 : kubectl en local (confortable)

1. Installer `kubectl` : https://kubernetes.io/docs/tasks/tools/
2. Utiliser le kubeconfig récupéré par Ansible :

```bash
export KUBECONFIG=~/Documents/homelab/kubeconfig/config
kubectl get nodes
```

> Le fichier `kubeconfig/config` donne **tous les droits** sur le cluster. Il est ignoré par git :
> ne le commit jamais, ne le partage pas. Il est recréé à chaque `make k3s`.

Pour ne pas le retaper, ajoute l'`export` dans ton `~/.bashrc` ou utilise un alias.

## Commandes utiles

| Besoin | Commande |
|---|---|
| Voir les nœuds | `kubectl get nodes` |
| Tous les pods | `kubectl get pods -A` |
| Pods d'un namespace | `kubectl get pods -n demo` |
| Logs d'un pod | `kubectl logs -n demo <pod>` |
| Détails / erreurs d'un pod | `kubectl describe pod -n demo <pod>` |
| Ingress | `kubectl get ingress -A` |
| Releases Helm | `ssh tour 'sudo helm --kubeconfig /etc/rancher/k3s/k3s.yaml list -A'` |
| Utilisation CPU/RAM | `kubectl top nodes` |
| Redémarrer un déploiement | `kubectl rollout restart deploy/<nom> -n <ns>` |

## Accéder à une application

Traefik écoute sur les ports 80/443 du serveur et route selon le **nom d'hôte** HTTP.

- **Test rapide sans toucher à rien :**
  `curl -H 'Host: whoami.homelab.local' http://192.168.1.12`
- **Dans le navigateur :** ajoute dans `/etc/hosts` de ton PC :
  ```
  192.168.1.12  whoami.homelab.local
  ```
  puis ouvre http://whoami.homelab.local
- **Pour tout le réseau :** crée un DNS local (Pi-hole, AdGuard Home, ou ta box) qui pointe
  `*.homelab.local` vers `192.168.1.12`.

## Fichiers importants sur le serveur

| Chemin | Contenu |
|---|---|
| `/etc/rancher/k3s/k3s.yaml` | kubeconfig d'origine |
| `/var/lib/rancher/k3s/` | données de k3s (etcd/sqlite, images, volumes `local-path`) |
| `/usr/local/bin/k3s` | binaire k3s |
| `/usr/local/bin/k3s-uninstall.sh` | script de désinstallation |
| `journalctl -u k3s` | logs du service k3s |
