#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <omp.h>

#define STATE_BURNT    0
#define STATE_VEG      1
#define STATE_BURNING  2

typedef struct {
    int state;
    float temp;
    float fuel;
} Cell;

void render_ascii(Cell *grid, int N, int step, double time_sec, int threads) {
    // Código de escape ANSI para limpiar pantalla y ubicar cursor en (0,0)
    printf("\033[H\033[J");
    printf("========================================================================\n");
    printf(" [DRONE GUARDIAN: FIRE OPS] - SIMULADOR TERMICO GRAN CHACO (TEL420)      \n");
    printf(" Autores: Abigail Quispe (E123639) & Moises Vasquez (E123568)            \n");
    printf(" Paso: %03d | Hilos OpenMP: %d | Tiempo Computo: %.4f s                 \n", step, threads, time_sec);
    printf(" Simbologia: [.] Vegetacion Chaco  [*] Foco Fuego  [x] Ceniza/Consumido  \n");
    printf("========================================================================\n");

    int sample_rate = N / 25; // Escalar la matriz para visualización en terminal estándar
    for (int i = 0; i < N; i += sample_rate) {
        for (int j = 0; j < N; j += sample_rate) {
            int state = grid[i * N + j].state;
            if (state == STATE_BURNING) {
                printf("\033[1;31m*\033[0m "); // Rojo brillante para fuego
            } else if (state == STATE_BURNT) {
                printf("\033[1;30mx\033[0m "); // Gris oscuro para cenizas
            } else {
                printf("\033[0;32m.\033[0m "); // Verde para vegetación
            }
        }
        printf("\n");
    }
    printf("========================================================================\n");
    fflush(stdout);
}

int main(int argc, char* argv[]) {
    int N = (argc > 1) ? atoi(argv[1]) : 100;
    int STEPS = (argc > 2) ? atoi(argv[2]) : 60;
    int threads = omp_get_max_threads();

    Cell *current = (Cell*)malloc(N * N * sizeof(Cell));
    Cell *next = (Cell*)malloc(N * N * sizeof(Cell));

    #pragma omp parallel for schedule(static)
    for (int i = 0; i < N * N; i++) {
        current[i].state = STATE_VEG;
        current[i].temp = 25.0f;
        current[i].fuel = 100.0f;
    }

    // Encender foco inicial en el centro
    int center = (N / 2) * N + (N / 2);
    current[center].state = STATE_BURNING;

    float wind_x = 0.4f;
    float wind_y = 0.4f;

    for (int step = 0; step < STEPS; step++) {
        double t0 = omp_get_wtime();

        #pragma omp parallel for schedule(static) shared(current, next, N, wind_x, wind_y)
        for (int i = 1; i < N - 1; i++) {
            for (int j = 1; j < N - 1; j++) {
                int idx = i * N + j;
                next[idx] = current[idx];

                if (current[idx].state == STATE_BURNING) {
                    next[idx].fuel -= 20.0f;
                    if (next[idx].fuel <= 0.0f) next[idx].state = STATE_BURNT;
                } else if (current[idx].state == STATE_VEG) {
                    float heat = 0.0f;
                    heat += (current[(i-1) * N + j].state == STATE_BURNING) ? 1.0f + wind_y : 0.0f;
                    heat += (current[(i+1) * N + j].state == STATE_BURNING) ? 1.0f - wind_y : 0.0f;
                    heat += (current[i * N + (j-1)].state == STATE_BURNING) ? 1.0f - wind_x : 0.0f;
                    heat += (current[i * N + (j+1)].state == STATE_BURNING) ? 1.0f + wind_x : 0.0f;

                    if (heat > 1.1f) next[idx].state = STATE_BURNING;
                }
            }
        }

        Cell *tmp = current;
        current = next;
        next = tmp;

        double elapsed = omp_get_wtime() - t0;
        if (step % 2 == 0) {
            render_ascii(current, N, step, elapsed, threads);
            usleep(60000); // 60 ms para animación fluida
        }
    }

    free(current);
    free(next);
    return 0;
}
