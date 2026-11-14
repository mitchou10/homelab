# Rôle `nvidia_cuda`

Installe sur une machine Ubuntu avec GPU NVIDIA : driver, CUDA toolkit, NVIDIA Container Toolkit.
Idempotent, ne redémarre pas la machine (il te dit si un reboot est nécessaire), ne laisse pas le dépôt CUDA toucher au driver.

Variables : voir `defaults/main.yml`. Lancement : `make gpu` (groupe `gpu` de l'inventaire).
Tutoriel complet (et GPU dans k3s) : [../../docs/09-gpu-cuda.md](../../docs/09-gpu-cuda.md).
