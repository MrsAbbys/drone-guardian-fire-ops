FROM ubuntu:24.04

# Evitar prompts interactivos durante instalación
ENV DEBIAN_FRONTEND=noninteractive

# Instalar herramientas esenciales de compilación, OpenMPI, OpenMP, SSH y utilidades
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    gdb \
    make \
    cmake \
    libopenmpi-dev \
    openmpi-bin \
    libomp-dev \
    openssh-server \
    openssh-client \
    rsync \
    htop \
    iputils-ping \
    net-tools python3 \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Crear usuario estándar para cómputo paralelo mpiuser
RUN useradd -m -s /bin/bash mpiuser && \
    echo "mpiuser:mpiuser" | chpasswd && \
    usermod -aG sudo mpiuser && \
    echo "mpiuser ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Configuración de SSH para ejecución de MPI sin contraseñas entre nodos
USER mpiuser
WORKDIR /home/mpiuser

RUN mkdir -p /home/mpiuser/.ssh && \
    ssh-keygen -q -t rsa -N "" -f /home/mpiuser/.ssh/id_rsa && \
    cp /home/mpiuser/.ssh/id_rsa.pub /home/mpiuser/.ssh/authorized_keys && \
    chmod 700 /home/mpiuser/.ssh && \
    chmod 600 /home/mpiuser/.ssh/authorized_keys

# Deshabilitar verificación de host estricta para SSH interno
RUN echo "Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n" > /home/mpiuser/.ssh/config && \
    chmod 600 /home/mpiuser/.ssh/config

USER root
RUN mkdir -p /var/run/sshd && chmod 0755 /var/run/sshd

# Exponer el puerto SSH y directorio compartido
EXPOSE 22
WORKDIR /workspace

CMD ["/usr/sbin/sshd", "-D"]
