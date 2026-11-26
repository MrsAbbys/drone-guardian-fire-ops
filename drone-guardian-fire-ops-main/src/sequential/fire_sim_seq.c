#include <errno.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/time.h>

#define STATE_BURNT 0
#define STATE_VEG 1
#define STATE_BURNING 2

#define FIREGRID_CELL_METERS 2.0
#define FIREGRID_TICK_SECONDS 0.3
#define FIREGRID_IGNITION_RATE 0.0575
#define FIREGRID_WIND_FACTOR 0.25
#define FIREGRID_SLOPE_FACTOR 0.1
#define FIREGRID_CONSUMPTION_PER_TICK 0.75
#define FIREGRID_SEED UINT64_C(0xD60E6A4D)

typedef struct {
    int state;
    float temp;
    float fuel;
} Cell;

static double get_wall_time(void) {
    struct timeval time;
    if (gettimeofday(&time, NULL)) return 0.0;
    return (double)time.tv_sec + (double)time.tv_usec * 1e-6;
}

static int parse_int(const char *text, int *value) {
    char *end = NULL;
    errno = 0;
    long parsed = strtol(text, &end, 10);
    if (errno || end == text || *end != '\0' || parsed < 0 || parsed > 2147483647L) {
        return 0;
    }
    *value = (int)parsed;
    return 1;
}

static int parse_float(const char *text, float *value) {
    char *end = NULL;
    errno = 0;
    float parsed = strtof(text, &end);
    if (errno || end == text || *end != '\0' || !isfinite(parsed)) {
        return 0;
    }
    *value = parsed;
    return 1;
}

static double random_unit(int step, size_t source, size_t target) {
    uint64_t value = FIREGRID_SEED;
    value ^= ((uint64_t)(unsigned int)step + 1U) * UINT64_C(0x9E3779B185EBCA87);
    value ^= ((uint64_t)source + 1U) * UINT64_C(0xC2B2AE3D27D4EB4F);
    value ^= ((uint64_t)target + 1U) * UINT64_C(0x165667B19E3779F9);
    value += UINT64_C(0x9E3779B97F4A7C15);
    value = (value ^ (value >> 30)) * UINT64_C(0xBF58476D1CE4E5B9);
    value = (value ^ (value >> 27)) * UINT64_C(0x94D049BB133111EB);
    value ^= value >> 31;
    return (double)(value >> 11) / 9007199254740992.0;
}

static int should_spread(
    int step,
    size_t source,
    size_t target,
    int dx,
    int dy,
    float wind_x,
    float wind_y,
    float gradient
) {
    double distance_cells = sqrt((double)(dx * dx + dy * dy));
    double distance_meters = distance_cells * FIREGRID_CELL_METERS;
    double wind_dot = ((double)dx / distance_cells) * wind_x
        + ((double)dy / distance_cells) * wind_y;
    double wind_factor = 1.0 + FIREGRID_WIND_FACTOR * fmax(0.0, wind_dot);
    double slope_meters = (double)dy * gradient;
    double exponent = FIREGRID_SLOPE_FACTOR * slope_meters / distance_meters;
    double slope_factor = exp(exponent);
    double rate;
    double probability;

    if (wind_factor > 3.0) wind_factor = 3.0;
    if (wind_factor < 0.0) wind_factor = 0.0;
    if (slope_factor > 3.0) slope_factor = 3.0;
    if (slope_factor < 0.0) slope_factor = 0.0;

    rate = FIREGRID_IGNITION_RATE * wind_factor * slope_factor;
    probability = 1.0 - exp(-rate * FIREGRID_TICK_SECONDS);
    if (probability < 0.0) probability = 0.0;
    if (probability > 1.0) probability = 1.0;
    return random_unit(step, source, target) < probability;
}

static int ignites_from_neighbor(
    const Cell *current,
    int n,
    int row,
    int column,
    int step,
    float wind_x,
    float wind_y,
    float gradient
) {
    size_t target = (size_t)row * (size_t)n + (size_t)column;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int source_row = row - dy;
            int source_column = column - dx;
            size_t source;
            if (dx == 0 && dy == 0) continue;
            if (source_row < 0 || source_row >= n || source_column < 0 || source_column >= n) {
                continue;
            }
            source = (size_t)source_row * (size_t)n + (size_t)source_column;
            if (current[source].state != STATE_BURNING || current[source].temp < 300.0f) {
                continue;
            }
            if (should_spread(step, source, target, dx, dy, wind_x, wind_y, gradient)) {
                return 1;
            }
        }
    }
    return 0;
}

int main(int argc, char *argv[]) {
    int n = 500;
    int steps = 100;
    float wind_x = 0.5f;
    float wind_y = 0.5f;
    float gradient = 0.0f;
    size_t cell_count;
    Cell *current;
    Cell *next;

    if (argc > 6 || argc == 4) {
        fprintf(stderr, "Uso: %s [N [pasos [vx vy [gradiente_m_por_celda]]]]\n", argv[0]);
        return 2;
    }
    if ((argc > 1 && !parse_int(argv[1], &n))
        || (argc > 2 && !parse_int(argv[2], &steps))
        || n < 1
        || (argc >= 5 && (!parse_float(argv[3], &wind_x) || !parse_float(argv[4], &wind_y)))
        || (argc == 6 && !parse_float(argv[5], &gradient))) {
        fprintf(stderr, "Parámetros inválidos. Uso: %s [N [pasos [vx vy [gradiente_m_por_celda]]]]\n", argv[0]);
        return 2;
    }
    if ((size_t)n > SIZE_MAX / (size_t)n) {
        fprintf(stderr, "El tamaño de la grilla excede el límite de memoria.\n");
        return 1;
    }
    cell_count = (size_t)n * (size_t)n;
    if (cell_count > SIZE_MAX / sizeof(Cell)) {
        fprintf(stderr, "El tamaño de la grilla excede el límite de memoria.\n");
        return 1;
    }

    printf("====================================================\n");
    printf("[DRONE GUARDIAN: FIRE OPS] Motor Secuencial (T_1)\n");
    printf("Resolución: %d x %d | Pasos: %d\n", n, n, steps);
    printf("Viento: (%.3f, %.3f) | Gradiente: %.3f m/celda\n", wind_x, wind_y, gradient);
    printf("====================================================\n");

    current = (Cell *)malloc(cell_count * sizeof(Cell));
    next = (Cell *)malloc(cell_count * sizeof(Cell));
    if (!current || !next) {
        fprintf(stderr, "Error al reservar memoria para la grilla.\n");
        free(current);
        free(next);
        return 1;
    }

    for (size_t i = 0; i < cell_count; i++) {
        current[i].state = STATE_VEG;
        current[i].temp = 25.0f;
        current[i].fuel = 100.0f;
    }

    size_t center = (size_t)(n / 2) * (size_t)n + (size_t)(n / 2);
    current[center].state = STATE_BURNING;
    current[center].temp = 600.0f;

    double start_time = get_wall_time();
    for (int step = 0; step < steps; step++) {
        for (size_t idx = 0; idx < cell_count; idx++) {
            int row = (int)(idx / (size_t)n);
            int column = (int)(idx % (size_t)n);
            next[idx] = current[idx];
            if (current[idx].state == STATE_BURNING) {
                next[idx].fuel -= (float)FIREGRID_CONSUMPTION_PER_TICK;
                if (next[idx].fuel <= 0.0f) {
                    next[idx].state = STATE_BURNT;
                    next[idx].temp = 80.0f;
                }
            } else if (current[idx].state == STATE_VEG
                && ignites_from_neighbor(current, n, row, column, step, wind_x, wind_y, gradient)) {
                next[idx].state = STATE_BURNING;
                next[idx].temp = 550.0f;
            }
        }

        Cell *temp_ptr = current;
        current = next;
        next = temp_ptr;
    }
    double total_time = get_wall_time() - start_time;

    size_t burned_count = 0;
    size_t burning_count = 0;
    for (size_t i = 0; i < cell_count; i++) {
        if (current[i].state == STATE_BURNT) burned_count++;
        else if (current[i].state == STATE_BURNING) burning_count++;
    }

    printf("[RESULTADOS T_1]\n");
    printf("Tiempo Secuencial (T_1): %.6f segundos\n", total_time);
    printf("Celdas Consumidas: %zu | Focos Activos: %zu\n", burned_count, burning_count);
    printf("====================================================\n");

    free(current);
    free(next);
    return 0;
}
