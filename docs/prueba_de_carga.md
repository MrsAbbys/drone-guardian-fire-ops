# Prueba de carga

La prueba usa clientes headless que se conectan por el directorio, comienzan la
misión cuando todos los bots de la sala están conectados, extinguen focos
obtenidos de la grilla replicada y vuelven a la isla de agua cuando necesitan
recargar. El servidor guarda una muestra por sala cada cinco segundos.

## Preparación y ejecución

1. Exporta el preset `Linux Server` y construye la imagen de juego, o inicia el
   directorio desde la raíz del proyecto:

   ```sh
   python server/directorio/directorio.py \
     --host 0.0.0.0 --port 8080 \
     --game-port-start 9000 --game-port-end 9031 \
     --max-rooms 4 --logs logs
   ```

2. Desde otra terminal, lanza la carga en Linux:

   ```sh
   bash scripts/tools/lanzar_carga.sh --salas 4 --bots-por-sala 6 --duracion 300
   ```

   En Windows, usa `scripts/tools/lanzar_carga.ps1` con los mismos argumentos.
   El directorio debe anunciar una dirección accesible para los bots y clientes.
   Puede configurarse con `--directorio` o la variable `DIRECTORY_URL`. Para
   usar un cliente Linux exportado, pasa `--cliente-binario <ruta>`. También se
   pueden ajustar `--timeout-inicial` y `--reconectar-despues`.

La prueba arranca hasta seis bots por sala, espera a que sus drones estén
activos, mata un bot y relanza el mismo nombre. Continúa únicamente si el bot
recupera el rol y vuelve a crear su dron; el resultado se guarda en
`logs/carga/`. Los clientes se detienen al finalizar, y el directorio elimina
las salas vacías vencidas.

El directorio agrega las muestras de todos los procesos en
`logs/servidor_metricas.csv`. En Docker, la ruta corresponde al volumen de logs
configurado (`/var/log/drone-game` dentro del contenedor). Cada fila contiene:

- instante UTC, código de sala, número de muestra y tiempo de ejecución;
- promedio, p95 y máximo del intervalo entre frames del servidor (ms);
- jugadores y celdas que siguen ardiendo;
- bytes/s enviados totales y bytes/s por jugador;
- RSS del proceso (MiB) y CPU porcentual por núcleo, calculados desde `/proc`.

## Gráfica

Instala el requisito de visualización y genera el PNG:

```sh
python -m pip install -r requirements-load-test.txt
python scripts/tools/graficar_metricas.py logs/servidor_metricas.csv \
  --salida logs/servidor_metricas.png
```

La gráfica presenta ticks promedio/p95/máximo, CPU/RAM y ancho de banda por
jugador; la línea roja marca 20 KiB/s. CPU y RAM quedan vacíos cuando el
directorio no puede leer `/proc` (por ejemplo, ejecución nativa en Windows).

## Plantilla de resultados

Completa los valores con las filas del CSV para la duración medida. Reporta el
p95 máximo observado entre las salas y el ancho de banda máximo por jugador.

| Salas × jugadores | Duración | Tick p95 (ms) | CPU máx. (%) | RAM máx. (MiB) | Ancho máx./jugador (KiB/s) | Resultado |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1 × 2 |  |  |  |  |  |  |
| 1 × 6 |  |  |  |  |  |  |
| 2 × 6 |  |  |  |  |  |  |
| 4 × 6 | 300 s |  |  |  |  |  |

Meta sugerida para 4 × 6: tick p95 menor que 50 ms y menos de 20 KiB/s
enviados por jugador. El script no declara éxito automáticamente si no se
alcanzan esas metas; usa las métricas medidas y los límites del host para
evaluarlo.
