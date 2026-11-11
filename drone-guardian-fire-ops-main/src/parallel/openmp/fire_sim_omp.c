#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <omp.h>

#define STATE_BURNT    0
#define STATE_VEG      1
#define STATE_BURNING  2

typedef struct {
    int state;
    float temp;
    float fuel;
} Cell;

int main(int argc, char* argv[]) {
    int N = (argc > 1) ? atoi(argv[1]) : 600;
    int STEPS = (argc > 2) ? atoi(argv[2]) : 150;

    int threads = omp_get_max_threads();
    printf("====================================================\n");
    printf("[DRONE GUARDIAN: FIRE OPS] Motor OpenMP (T_p)\n");
    printf("Resolución: %d x %d | Pasos: %d | Hilos Activos: %d\n", N, N, STEPS, threads);
    printf("====================================================\n");

    Cell *current = (Cell*)malloc(N * N * sizeof(Cell));
    Cell *next = (Cell*)malloc(N * N * sizeof(Cell));

    if (!current || !next) {
        fprintf(stderr, "Error al reservar memoria en el host.\n");
        return 1;
    }

    // Inicialización paralela del paisaje chaqueño
    #pragma omp parallel for schedule(static)
    for (int i = 0; i < N * N; i++) {
        current[i].state = STATE_VEG;
        current[i].temp = 25.0f;
        current[i].fuel = 100.0f;
    }

    // Foco de calor inicial en el centro
    int center = (N / 2) * N + (N / 2);
    current[center].state = STATE_BURNING;
    current[center].temp = 600.0f;

    float wind_x = 0.5f;
    float wind_y = 0.5f;

    double start_time = omp_get_wtime();

    // Bucle temporal
    for (int step = 0; step < STEPS; step++) {
        memcpy(next, current, N * N * sizeof(Cell));
        // Descomposición de dominio 2D mediante OpenMP
        #pragma omp parallel for schedule(static) shared(current, next, N, wind_x, wind_y)
        for (int i = 1; i < N - 1; i++) {
            for (int j = 1; j < N - 1; j++) {
                int idx = i * N + j;
                next[idx] = current[idx];

                if (current[idx].state == STATE_BURNING) {
                    next[idx].fuel -= 15.0f;
                    if (next[idx].fuel <= 0.0f) {
                        next[idx].state = STATE_BURNT;
                        next[idx].temp = 80.0f;
                    }
                } else if (current[idx].state == STATE_VEG) {
                    float neighbor_heat = 0.0f;
                    neighbor_heat += (current[(i-1) * N + j].state == STATE_BURNING) ? 1.0f + wind_y : 0.0f;
                    neighbor_heat += (current[(i+1) * N + j].state == STATE_BURNING) ? 1.0f - wind_y : 0.0f;
                    neighbor_heat += (current[i * N + (j-1)].state == STATE_BURNING) ? 1.0f - wind_x : 0.0f;
                    neighbor_heat += (current[i * N + (j+1)].state == STATE_BURNING) ? 1.0f + wind_x : 0.0f;

                    if (neighbor_heat > 1.2f) {
                        next[idx].state = STATE_BURNING;
                        next[idx].temp = 550.0f;
                    }
                }
            }
        }

        Cell *temp_ptr = current;
        current = next;
        next = temp_ptr;
    }

    double end_time = omp_get_wtime();
    double total_time = end_time - start_time;

    // Reducción paralela sin condiciones de carrera
    int burned_count = 0, burning_count = 0;
    #pragma omp parallel for reduction(+:burned_count, burning_count) schedule(static)
    for (int i = 0; i < N * N; i++) {
        if (current[i].state == STATE_BURNT) burned_count++;
        else if (current[i].state == STATE_BURNING) burning_count++;
    }

    printf("[RESULTADOS OPENMP T_p]\n");
    printf("Tiempo Paralelo (T_p): %.6f segundos\n", total_time);
    printf("Celdas Consumidas: %d | Focos Activos: %d\n", burned_count, burning_count);
    printf("====================================================\n");

    free(current);
    free(next);
    return 0;
}
