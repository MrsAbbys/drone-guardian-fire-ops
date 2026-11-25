#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

// Estados de la celda en el modelo de autómata celular
#define STATE_BURNT    0
#define STATE_VEG      1
#define STATE_BURNING  2

typedef struct {
    int state;
    float temp;
    float fuel;
} Cell;

// Función para medir tiempo de pared con precisión de microsegundos
double get_wall_time() {
    struct timeval time;
    if (gettimeofday(&time, NULL)) return 0;
    return (double)time.tv_sec + (double)time.tv_usec * 1e-6;
}

int main(int argc, char* argv[]) {
    // Parámetros: N (tamaño de grilla), STEPS (iteraciones temporales)
    int N = (argc > 1) ? atoi(argv[1]) : 500;
    int STEPS = (argc > 2) ? atoi(argv[2]) : 100;

    printf("====================================================\n");
    printf("[DRONE GUARDIAN: FIRE OPS] Motor Secuencial (T_1)\n");
    printf("Resolución de Grilla: %d x %d | Pasos de Simulación: %d\n", N, N, STEPS);
    printf("====================================================\n");

    // Asignación de matrices contiguas en memoria
    Cell *current = (Cell*)malloc(N * N * sizeof(Cell));
    Cell *next = (Cell*)malloc(N * N * sizeof(Cell));

    if (!current || !next) {
        fprintf(stderr, "Error al reservar memoria para la grilla.\n");
        return 1;
    }

    // Inicialización del paisaje chaqueño
    for (int i = 0; i < N * N; i++) {
        current[i].state = STATE_VEG;
        current[i].temp = 25.0f;     // Temperatura ambiente (25 °C)
        current[i].fuel = 100.0f;    // 100% de combustible vegetal
    }

    // Foco de calor inicial (ignición en el centro de la grilla)
    int center = (N / 2) * N + (N / 2);
    current[center].state = STATE_BURNING;
    current[center].temp = 600.0f;

    // Vector de viento hacia el Noreste característico de la región
    float wind_x = 0.5f;
    float wind_y = 0.5f;

    double start_time = get_wall_time();

    // Bucle temporal de simulación
    for (int step = 0; step < STEPS; step++) {
        memcpy(next, current, N * N * sizeof(Cell));
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
                    // Difusión térmica de vecinos (Stencil de Von Neumann)
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

        // Intercambio de punteros (Double Buffering)
        Cell *temp_ptr = current;
        current = next;
        next = temp_ptr;
    }

    double end_time = get_wall_time();
    double total_time = end_time - start_time;

    // Conteo estadístico de celdas
    int burned_count = 0, burning_count = 0;
    for (int i = 0; i < N * N; i++) {
        if (current[i].state == STATE_BURNT) burned_count++;
        else if (current[i].state == STATE_BURNING) burning_count++;
    }

    printf("[RESULTADOS T_1]\n");
    printf("Tiempo Secuencial (T_1): %.6f segundos\n", total_time);
    printf("Celdas Consumidas: %d | Focos Activos: %d\n", burned_count, burning_count);
    printf("====================================================\n");

    free(current);
    free(next);
    return 0;
}
