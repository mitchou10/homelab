# Rôle `openbao`

Après le déploiement Helm : initialise (une fois), **descelle** et configure OpenBao (KV, policies, SSO Keycloak).
Idempotent. Lancé par `make apps`, ou seul par **`make unseal`** après un redémarrage.
Clé de descellement + token root : `.secrets/openbao_init.json` (local, hors git, à sauvegarder).
Tutoriel et justification du choix OpenBao : [../../docs/12-openbao.md](../../docs/12-openbao.md).
