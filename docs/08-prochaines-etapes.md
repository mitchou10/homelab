# 8. Prochaines étapes

Idées classées par priorité. Coche au fur et à mesure.

- [ ] **Premier commit git** de tout le dépôt
- [ ] **Figer les versions** : `k3s_version` et `version:` des charts
- [ ] **IP fixe** pour `tour` (réservation DHCP)
- [ ] **DNS local** pour `*.homelab.local` (Pi-hole / AdGuard Home)
- [ ] **ArgoCD** : rôle `argocd` (chart `argo/argo-cd`), puis migrer chaque release en `Application` ;
      Ansible installe le cluster + ArgoCD, ArgoCD synchronise les apps depuis git
- [ ] **Secrets** : `ansible-vault` (secrets Ansible) ou `sops` + `age` (secrets dans git, chiffrés)
- [ ] **HTTPS** : `cert-manager` + Let's Encrypt (ou certificats auto-signés en local)
- [ ] **Sauvegardes** : snapshots etcd k3s (`k3s etcd-snapshot`), sauvegarde de `/var/lib/rancher/k3s/storage` (Velero / restic)
- [ ] **Monitoring** : `kube-prometheus-stack` (Prometheus + Grafana) ou Uptime Kuma
- [ ] **Gérer le sudoers par Ansible** (actuellement fait à la main)
- [ ] **Pare-feu** (`ufw`) : n'ouvrir que 22, 80, 443, 6443
- [ ] **Mises à jour** : procédure d'upgrade k3s (changer `k3s_version`, relancer `make k3s`)
- [ ] **2e nœud** : groupe `k3s_agent` + rôle d'ajout d'agents
- [ ] **Redémarrer `tour`** (`/var/run/reboot-required` présent) puis vérifier `nvidia-smi` et le pod `gpu-test`
- [ ] **Partage du GPU** entre pods (time-slicing du device plugin) si besoin
- [ ] **TLS** (cert-manager) puis retirer `sslRequired=NONE` du realm master et passer les URLs en https
- [ ] **Sauvegarde** de `.secrets/` et de la base Postgres de Keycloak (`pg_dump`)
- [ ] **Migrer les apps Helm vers des `Application` Argo CD**
- [ ] Créer un **admin nominatif** dans Keycloak (realm master) et désactiver le compte `admin` de bootstrap
- [ ] **Sauvegarder `.secrets/openbao_init.json`** et planifier des snapshots raft d'OpenBao
- [x] External Secrets Operator + auth Kubernetes d'OpenBao (fait, voir [13](13-deployer-une-application.md))
- [ ] Isoler les secrets par application (un SecretStore et un rôle OpenBao par namespace)
- [ ] Durcir le descellement : plusieurs parts de clé ou auto-unseal ; révoquer le token root
