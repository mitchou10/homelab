# 7. Journal — ce qui a été fait

Historique de la mise en place initiale (14 novembre 2026), pour se souvenir **quoi** et **pourquoi**.

## Décisions prises

| Décision | Choix | Pourquoi |
|---|---|---|
| Distribution Kubernetes | **k3s** | léger, un seul binaire, parfait pour un homelab, Traefik + stockage local inclus |
| Déploiement des apps | **Ansible + Helm d'abord**, ArgoCD plus tard | commencer simple, GitOps ensuite |
| Topologie | **1 nœud** | un seul serveur (`tour`) |
| Environnement Python | **`uv` + `.venv`** | `python3-venv` absent sur le PC |
| Accès sudo | **NOPASSWD** pour `michou` | pour automatiser sans taper le mot de passe |

## Chronologie

1. **Dépôt vide** (git initialisé sans commit). Helm déjà présent en local, Ansible absent.
2. **Création de la structure** : inventaire, 3 rôles (`common`, `k3s`, `helm_apps`), 3 playbooks, Makefile, `.gitignore`, app d'exemple `whoami`.
3. **Serveur identifié** dans `~/.ssh/config` : `tour` = 192.168.1.12, utilisateur `michou`.
   Machine : Ubuntu 24.04, 8 CPU, 31 Go RAM.
4. **sudo** demandait un mot de passe → mis en `NOPASSWD` sur le serveur.
5. **Ansible installé en local** : `python3 -m venv` a échoué → passage à `uv`. Collections installées avec `make setup`.
6. **`ansible.cfg` corrigé** : l'ancien callback `yaml` n'existe plus.
7. **Dry-run** (`--check`) : cohérent, échec attendu sur le service k3s inexistant.
8. **Déploiement réel** (`make all`) : `ok=17 changed=10 failed=0`.
9. **Vérification** : nœud `Ready` (k3s v1.37.2+k3s1), `whoami` en `Running`, `curl` avec `Host: whoami.homelab.local` → HTTP 200.

## Modifications faites sur le serveur `tour`

- Paquets installés : `curl`, `ca-certificates`, `python3-pip`, `python3-kubernetes`, `python3-yaml`, `git`
- Swap désactivé (runtime + `/etc/fstab`)
- `/etc/sudoers.d/michou` créé (sudo sans mot de passe) — **fait à la main**, pas par Ansible
- k3s installé (`/usr/local/bin/k3s`, service systemd `k3s`)
- helm installé (`/usr/local/bin/helm`)
- Release `whoami` dans le namespace `demo`

## Modifications faites sur le PC

- `uv` installé via pip (`~/.local/bin/uv`)
- Collections Ansible dans `~/.ansible/collections`
- `.venv/` dans le dépôt (ignoré par git)
- `kubeconfig/config` récupéré (ignoré par git)

## Points à retenir

- Le fichier `/etc/sudoers.d/michou` n'est pas géré par Ansible : à refaire à la main sur une machine neuve.
- `k3s_version` n'est pas figée : la version installée est celle du jour.
- Aucun commit n'avait été fait au moment de l'écriture.

## 2026-11-14 (suite) — GPU / CUDA

- `tour` avait déjà, installés à la main : driver `nvidia-driver-580`, `cuda-toolkit-12-6` (dépôt local), `nvidia-container-toolkit`. k3s avait déjà détecté le runtime `nvidia`.
- Recherche de rôles Ansible existants : aucun ne couvre driver + CUDA + toolkit + k3s (détail dans [09](09-gpu-cuda.md)) → rôle `nvidia_cuda` écrit sur mesure.
- Ajouté : rôle `nvidia_cuda`, `playbooks/gpu.yml`, groupe `gpu` dans l'inventaire, `make gpu`, RuntimeClass `nvidia`, label de nœud, release `nvidia-device-plugin` (chart 0.20.1), `apps/manifests/gpu-test.yaml`.
- Sur `tour` : ajout du dépôt réseau CUDA (cuda-keyring), `/etc/apt/preferences.d/cuda-no-driver`, `/etc/profile.d/cuda.sh`, réécriture de `nvidia-container-toolkit.list`.
- Problème rencontré : le DaemonSet du device plugin restait à 0 pod → label `nvidia.com/gpu.present=true` manquant (voir [06](06-depannage.md)).
- Résultat : `allocatable nvidia.com/gpu = 1`, un pod de test affiche `nvidia-smi` avec la Quadro P4000.
- `tour` signale `/var/run/reboot-required` (déjà présent avant) : un reboot reste à planifier.

## 2026-11-14 (suite) — Releases

- Ajout de release-please via les workflows partagés `Mitchou10/github-workflow@v0` (mode une seule branche `main`) + lint des commits sur les PR. Voir [10](10-releases-et-commits.md).
- Historique git initial découpé en commits Conventional Commits par morceau.
- À faire côté GitHub : autoriser les Actions à créer des PR (Settings → Actions → General).

## 2026-11-14 (suite) — Argo CD, Keycloak, SSO

- Ajout du rôle `platform` (DNS interne CoreDNS `*.homelab.local` → Traefik, secrets, Postgres, realm Keycloak), des releases `keycloak` (chart codecentric/keycloakx 7.4.0, Keycloak 26.8.1) et `argocd` (chart 10.18.0).
- Mots de passe générés par Ansible (lookup `password`) dans `.secrets/`, jamais dans git.
- Les values Helm sont maintenant rendues avec Jinja (`template`), puis supprimées du serveur après déploiement.
- Realm `homelab` : groupes `homelab-admins`/`homelab-users`, utilisateur `michou`, client `argocd`. Argo CD : `homelab-admins` = admin, les autres = lecture seule.
- Choix : Postgres maison (StatefulSet) plutôt que les charts Bitnami (changement de politique sur leurs images) ; HTTP sans TLS pour l'instant (`sslRequired=NONE` sur le realm master, voir [11](11-argocd-keycloak.md)).
- Piège trouvé : `--import-realm` ignore un realm existant → les clients ajoutés plus tard sont créés par Ansible via `kcadm.sh` (`roles/platform/tasks/post.yml`).
- Vérifié : login complet scripté (michou → Keycloak → Argo CD), groupes présents dans le token.

## 2026-11-14 (suite) — OpenBao

- Décision : **OpenBao** plutôt que Vault (licence MPL 2.0 vs BUSL, pas de risque commercial, gouvernance Linux Foundation, compatible Vault pour notre usage). Justification complète : [12](12-openbao.md).
- Ajout : release `openbao` (chart 0.30.7, OpenBao 2.7.2, raft 1 réplique), rôle `openbao` (init, unseal, config), `playbooks/openbao.yml`, `make unseal`, client OIDC `openbao` dans Keycloak.
- Piège : `bao operator unseal -` ne lit pas stdin ; on utilise `bao write sys/unseal key=-`.
- Piège : sonde de readiness par défaut échoue quand le pod est scellé → `helm --wait` bloquerait ; sonde HTTP avec `sealedcode=204&uninitcode=204`.
- Vérifié : SSO complet scripté (michou → policy `homelab-admin` via le groupe), pod supprimé puis `make unseal` OK, données conservées.
- Initialisation faite : clé + token root dans `.secrets/openbao_init.json` (**à sauvegarder**).

## 2026-11-14 (suite) — Déploiement d'applications

- Règle : **ce dépôt reste infra uniquement**, aucune config ni lien propre à un projet applicatif.
- Ajout d'**External Secrets Operator** (chart 2.15.0), de l'authentification Kubernetes d'OpenBao (rôle `eso`) et du `ClusterSecretStore` `openbao`. Vérifié : un secret posé dans OpenBao devient un Secret Kubernetes (`SecretSynced`).
- Extension générique des clients Keycloak : `attributes` (ex. PKCE), `client_roles`, `user_roles`, `groups_full_path` (`client.json.j2`, `post.yml`).
- Documentation du flux complet : [13](13-deployer-une-application.md).
- Cause d'une erreur d'une appli déployée à la main dans Argo CD : namespace de destination absent, puis chart dépendant du Vault Secrets Operator (voir tableau d'erreurs de [13](13-deployer-une-application.md)).

## Suite du journal

Ajoute ici une ligne datée à chaque changement important (nouvelle app, upgrade k3s, panne…).
