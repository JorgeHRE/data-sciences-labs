#!/bin/bash
# user data del lab 21 (Amazon Linux 2023). cloud-init lo corre UNA vez, como root, al primer arranque.
# Salida completa: /var/log/cloud-init-output.log (evidencia de la actividad 4).
# NO contiene credenciales (el user data es legible desde la consola y desde IMDS): los permisos los pone el rol.
# Regla del lab: si algo falla, se corrige ESTE archivo y se relanza; no se arregla a mano por SSH.
set -euxo pipefail   # -e: se detiene al primer error; -x: imprime cada comando en el log

IMAGEN="ghcr.io/jorgehre/auditoria-obs:0.2.0"

# 1) Paquetes. Sin "dnf upgrade": AL2023 fija la versión del repositorio a la de la AMI (reproducible).
#    docker: motor de contenedores | tmux: actividad 8 | python3.12: Jupyter (pandas 3 exige >= 3.11)
dnf install -y docker tmux python3.12 python3.12-pip

# 2) Docker arrancado ahora y en cada reinicio; ec2-user lo usa sin sudo.
systemctl enable --now docker
usermod -aG docker ec2-user

# 3) Imagen pública descargada de antemano: el pull es anónimo, sin token en la máquina (D10).
docker pull "$IMAGEN"

# 4) JupyterLab en un venv del usuario (D6-A). Se arranca a mano en la actividad 7, solo en 127.0.0.1.
#    Versiones fijas (probadas en amazonlinux:2023 el 2026-11-21); pandas/pyarrow = uv.lock del pipeline.
sudo -u ec2-user python3.12 -m venv /home/ec2-user/jupyter-venv
sudo -u ec2-user /home/ec2-user/jupyter-venv/bin/pip install --quiet --no-cache-dir \
  "jupyterlab==4.6.6" "pandas==3.1.1" "pyarrow==26.0.1"

# 5) Marca de "listo" con lo instalado: si este archivo existe, el script terminó sin errores.
{
  echo "user data terminado: $(date -u +%FT%TZ)"
  docker --version
  aws --version
  tmux -V
  /home/ec2-user/jupyter-venv/bin/jupyter lab --version | sed 's/^/jupyterlab /'
  docker image ls "$IMAGEN" --format 'imagen {{.Repository}}:{{.Tag}} {{.Size}}'
} | tee /home/ec2-user/LISTO.txt
chown ec2-user:ec2-user /home/ec2-user/LISTO.txt
