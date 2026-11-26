# Drone Guardian: Fire Ops — Hito 2

Simulación de propagación de incendios en C con versiones secuencial, OpenMP y
OpenMPI. Docker Compose levanta un clúster de tres contenedores: `master`,
`worker1` y `worker2`.

## Requisitos

- Git.
- Docker Desktop con el motor Linux y Docker Compose v2.

## Clonar y levantar el clúster

En PowerShell:

```powershell
git clone https://github.com/MrsAbbys/drone-guardian-fire-ops.git
Set-Location drone-guardian-fire-ops\drone-guardian-fire-ops-main
docker compose -f infrastructure/docker-compose.yml up -d --build
docker compose -f infrastructure/docker-compose.yml ps
```

La primera construcción descarga Ubuntu e instala GCC, OpenMP, OpenMPI y SSH;
puede tardar varios minutos. Los tres contenedores comparten `/workspace`, que
corresponde a esta carpeta del proyecto.

## Compilar y ejecutar

Desde PowerShell, con el clúster activo:

```powershell
docker exec --user mpiuser -w /workspace fireops-master gcc -O2 src/sequential/fire_sim_seq.c -lm -o src/sequential/fire_sim_seq
docker exec --user mpiuser -w /workspace fireops-master gcc -O2 -fopenmp src/parallel/openmp/fire_sim_omp.c -lm -o src/parallel/openmp/fire_sim_omp
docker exec --user mpiuser -w /workspace fireops-master mpicc -O2 src/parallel/mpi/fire_sim_mpi.c -o src/parallel/mpi/fire_sim_mpi
```

Secuencial:

```powershell
docker exec --user mpiuser -w /workspace fireops-master ./src/sequential/fire_sim_seq 600 150
```

OpenMP con cuatro hilos:

```powershell
docker exec --user mpiuser -w /workspace -e OMP_NUM_THREADS=4 fireops-master ./src/parallel/openmp/fire_sim_omp 600 150
```

MPI con cuatro procesos distribuidos entre master y workers:

```powershell
docker exec --user mpiuser -w /workspace fireops-master mpirun -np 4 --hostfile /workspace/infrastructure/hosts --map-by ppr:2:node /workspace/src/parallel/mpi/fire_sim_mpi 600 150
```

Los argumentos son el tamaño de la grilla (`N`) y la cantidad de pasos.
Secuencial y OpenMP aceptan además el vector de viento `(vx, vy)` y un
gradiente fijo en metros de elevación por celda en el eje `y`. Los valores
predeterminados son viento `(0.5, 0.5)` y gradiente `0`:

```sh
docker exec --user mpiuser -w /workspace fireops-master ./src/sequential/fire_sim_seq 600 150 0.5 0.5 0.1
docker exec --user mpiuser -w /workspace -e OMP_NUM_THREADS=4 fireops-master ./src/parallel/openmp/fire_sim_omp 600 150 0.5 0.5 0.1
```

La forma anterior `N pasos` sigue siendo válida. El viento y la pendiente
aplican los factores direccionales y la probabilidad por tick del modelo
FireGrid; la secuencia pseudoaleatoria C es determinista para que OpenMP y el
motor secuencial produzcan los mismos estados.

## Benchmark de FireGrid y gráficas C

Con Godot 4.7 instalado, desde la raíz del proyecto Godot (donde está
`project.godot`):

```sh
godot --headless --path . --script res://scripts/tools/benchmark_fire_grid.gd
```

El benchmark usa semilla fija, 150 ticks, viento `(0.5, 0.5)` y reporta
`ms/tick` y celdas que ardieron para tamaños 100, 200, 400 y 600. El CSV queda
en la carpeta de datos de usuario que imprime el script. También compara el
total FireGrid de `N=600` con las mediciones C históricas del CSV.

Para generar las cuatro gráficas de los resultados C:

```sh
python docs/graficas.py
```

Los PNG se guardan en `docs/graficas/`. El script calcula speedup,
eficiencia y fracción serial estimada con la ley de Amdahl a partir de
`data/benchmark_results.csv`.

## Prueba de conectividad MPI

```powershell
docker exec --user mpiuser -w /workspace fireops-master mpicc smoke_test.c -o smoke_test
docker exec --user mpiuser -w /workspace fireops-master mpirun -np 4 --hostfile /workspace/infrastructure/hosts --map-by ppr:2:node /workspace/smoke_test
```

La salida debe mostrar cuatro procesos MPI y el hostname donde se ejecutó cada
uno.

## Estado y apagado

Mostrar consumo de recursos desde el host:

```powershell
docker stats fireops-master fireops-worker1 fireops-worker2
```

Detener y retirar los contenedores y la red:

```powershell
docker compose -f infrastructure/docker-compose.yml down
```

## Alcance del acceso SSH

El puerto SSH del maestro se publica únicamente en `127.0.0.1:2222`; los workers
no publican puertos al host. Esta configuración permite el uso local del clúster
y no expone SSH a la red LAN o a Internet. Para ofrecer acceso remoto hace falta
configurar un túnel y controlar quién está autorizado antes de habilitarlo.

## Resultados de referencia

Las mediciones de `data/benchmark_results.csv` corresponden a una corrida por
configuración con grilla `600 x 600` y 150 pasos, tomadas antes de alinear los
factores de propagación C con FireGrid. Son una referencia histórica de
rendimiento y de salida del modelo previo; deben volver a medirse antes de
comparar resultados o reportar celdas consumidas para el código actual.
