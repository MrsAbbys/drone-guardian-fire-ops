#include <mpi.h>
#include <stdio.h>

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);
    int world_rank, world_size;
    char hostname[256];
    int len;

    MPI_Comm_rank(MPI_COMM_WORLD, &world_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &world_size);
    MPI_Get_processor_name(hostname, &len);

    printf("[DRONE GUARDIAN] Proceso MPI %d de %d activo en el nodo: %s\n", world_rank, world_size, hostname);

    MPI_Finalize();
    return 0;
}
