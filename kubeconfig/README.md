# kubeconfig/

Contient `config` : le kubeconfig récupéré par Ansible (`make k3s`).
**Secret, ignoré par git** : il donne tous les droits sur le cluster.
Usage : `export KUBECONFIG=$PWD/kubeconfig/config`.
