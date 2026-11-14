.PHONY: setup ping gpu k3s apps all check
setup:  ; ansible-galaxy collection install -r requirements.yml
ping:   ; ansible all -m ping
gpu:    ; ansible-playbook playbooks/gpu.yml
k3s:    ; ansible-playbook playbooks/k3s.yml
apps:   ; ansible-playbook playbooks/apps.yml
all:    ; ansible-playbook playbooks/site.yml
check:  ; ansible-playbook playbooks/site.yml --check --diff
