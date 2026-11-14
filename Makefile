.PHONY: setup ping gpu k3s apps all check creds unseal
setup:  ; ansible-galaxy collection install -r requirements.yml
ping:   ; ansible all -m ping
gpu:    ; ansible-playbook playbooks/gpu.yml
k3s:    ; ansible-playbook playbooks/k3s.yml
apps:   ; ansible-playbook playbooks/apps.yml
all:    ; ansible-playbook playbooks/site.yml
check:  ; ansible-playbook playbooks/site.yml --check --diff

unseal: ; ansible-playbook playbooks/openbao.yml

# Affiche les identifiants générés (stockés dans .secrets/, ignoré par git)
creds:
	@for f in .secrets/keycloak_admin_password .secrets/homelab_user_password; do printf '%s: ' $$f; cat $$f; done
