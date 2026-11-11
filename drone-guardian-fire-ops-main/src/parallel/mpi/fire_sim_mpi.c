#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STATE_BURNT    0
#define STATE_VEG      1
#define STATE_BURNING  2

typedef struct {
    int state;
    float temp;
    float fuel;
} Cell;

int main(int argc, char* argv[]) {
    MPI_Init(&argc, &argv);

    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    int N = (argc > 1) ? atoi(argv[1]) : 600;
    int STEPS = (argc > 2) ? atoi(argv[2]) : 150;

    // Descomposición de dominio unidimensional por franjas horizontales
    int local_rows = N / size;
    // Filas locales + 2 filas fantasma (halo cells) para intercambio de bordes
    int total_local_rows = local_rows + 2;

    Cell *local_current = (Cell*)malloc(total_local_rows * N * sizeof(Cell));
    Cell *local_next    = (Cell*)malloc(total_local_rows * N * sizeof(Cell));

    if (!local_current || !local_next) {
        fprintf(stderr, "[Rank %d] Error asignando memoria local.\n", rank);
        MPI_Abort(MPI_COMM_WORLD, 1);
    }

    // Inicialización del estado local
    for (int i = 0; i < total_local_rows * N; i++) {
        local_current[i].state = STATE_VEG;
        local_current[i].temp  = 25.0f;
        local_current[i].fuel  = 100.0f;
    }

    // Foco de calor inicial ubicado en el centro global
    int global_center_row = N / 2;
    int global_center_col = N / 2;
    int local_start_row = rank * local_rows;
    int local_end_row   = local_start_row + local_rows - 1;

    if (global_center_row >= local_start_row && global_center_row <= local_end_row) {
        int r_local = (global_center_row - local_start_row) + 1;
        int idx = r_local * N + global_center_col;
        local_current[idx].state = STATE_BURNING;
        local_current[idx].temp  = 600.0f;
    }

    float wind_x = 0.5f;
    float wind_y = 0.5f;

    // Identificación de vecinos topológicos
    int top_neighbor    = (rank > 0) ? rank - 1 : MPI_PROC_NULL;
    int bottom_neighbor = (rank < size - 1) ? rank + 1 : MPI_PROC_NULL;

    // Sincronización previa e inicio de cronómetro distribuido
    MPI_Barrier(MPI_COMM_WORLD);
    double start_time = MPI_Wtime();

    // Bucle temporal
    for (int step = 0; step < STEPS; step++) {
        memcpy(local_next, local_current, total_local_rows * N * sizeof(Cell));
        // Intercambio no bloqueante / punto a punto de filas fantasma
        // Enviar primera fila de cálculo a arriba, recibir fila fantasma superior
        MPI_Sendrecv(&local_current[1 * N], N * sizeof(Cell), MPI_BYTE, top_neighbor, 0,
                     &local_current[0 * N], N * sizeof(Cell), MPI_BYTE, top_neighbor, 1,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        // Enviar última fila de cálculo a abajo, recibir fila fantasma inferior
        MPI_Sendrecv(&local_current[local_rows * N], N * sizeof(Cell), MPI_BYTE, bottom_neighbor, 1,
                     &local_current[(local_rows + 1) * N], N * sizeof(Cell), MPI_BYTE, bottom_neighbor, 0,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);

        // Actualización numérica local (Stencil de Von Neumann)
        for (int i = 1; i <= local_rows; i++) {
            int global_i = local_start_row + (i - 1);
            if (global_i == 0 || global_i == N - 1) continue;

            for (int j = 1; j < N - 1; j++) {
                int idx = i * N + j;
                local_next[idx] = local_current[idx];

                if (local_current[idx].state == STATE_BURNING) {
                    local_next[idx].fuel -= 15.0f;
                    if (local_next[idx].fuel <= 0.0f) {
                        local_next[idx].state = STATE_BURNT;
                        local_next[idx].temp  = 80.0f;
                    }
                } else if (local_current[idx].state == STATE_VEG) {
                    float heat = 0.0f;
                    heat += (local_current[(i-1) * N + j].state == STATE_BURNING) ? 1.0f + wind_y : 0.0f;
                    heat += (local_current[(i+1) * N + j].state == STATE_BURNING) ? 1.0f - wind_y : 0.0f;
                    heat += (local_current[i * N + (j-1)].state == STATE_BURNING) ? 1.0f - wind_x : 0.0f;
                    heat += (local_current[i * N + (j+1)].state == STATE_BURNING) ? 1.0f + wind_x : 0.0f;

                    if (heat > 1.2f) {
                        local_next[idx].state = STATE_BURNING;
                        local_next[idx].temp  = 550.0f;
                    }
                }
            }
        }

        Cell *tmp = local_current;
        local_current = local_next;
        local_next = tmp;
    }

    MPI_Barrier(MPI_COMM_WORLD);
    double end_time = MPI_Wtime();
    double local_elapsed = end_time - start_time;

    // Obtener el tiempo del proceso más lento mediante MPI_Reduce
    double max_elapsed = 0.0;
    MPI_Reduce(&local_elapsed, &max_elapsed, 1, MPI_DOUBLE, MPI_MAX, 0, MPI_COMM_WORLD);

    // Reducción colectiva de métricas del incendio
    int local_burned = 0, local_burning = 0;
    for (int i = 1; i <= local_rows; i++) {
        for (int j = 0; j < N; j++) {
            if (local_current[i * N + j].state == STATE_BURNT) local_burned++;
            else if (local_current[i * N + j].state == STATE_BURNING) local_burning++;
        }
    }

    int global_burned = 0, global_burning = 0;
    MPI_Reduce(&local_burned, &global_burned, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);
    MPI_Reduce(&local_burning, &global_burning, 1, MPI_INT, MPI_SUM, 0, MPI_COMM_WORLD);

    if (rank == 0) {
        printf("====================================================\n");
        printf("[DRONE GUARDIAN: FIRE OPS] Motor Distribuido OpenMPI\n");
        printf("Grilla: %d x %d | Pasos: %d | Procesos Clúster: %d\n", N, N, STEPS, size);
        printf("Tiempo Distribuido (T_p): %.6f segundos\n", max_elapsed);
        printf("Celdas Consumidas: %d | Focos Activos: %d\n", global_burned, global_burning);
        printf("====================================================\n");
    }

    free(local_current);
    free(local_next);
    MPI_Finalize();
    return 0;
}
