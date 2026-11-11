# Guion breve para defender los hitos 1 y 2

## Hito 1: simulador de respuesta a incendios

> “En el Hito 1 desarrollé el simulador interactivo en Godot, ambientado en la
> zona del Aguaragüe. El jugador controla un dron para desplazarse por el
> escenario, localizar focos de incendio, aplicar agua y regresar a una fuente
> para recargar. Implementé la interacción entre el dron, el agua y los focos,
> además de elementos de interfaz para mostrar el estado de la misión.”

Controles implementados: **WASD** para desplazamiento, **Espacio** para subir,
**C** para bajar, **E** para recargar cuando el dron está en la fuente de agua,
y **clic izquierdo** para descargar agua. **Esc** libera o captura el mouse.

## Hito 2: simulación paralela

> “En el Hito 2 implementé una simulación de propagación del fuego en C. Primero
> usé la versión secuencial como referencia; luego paralelicé el cálculo con
> OpenMP y distribuí filas de la grilla entre procesos MPI, intercambiando las
> filas frontera. Para probar MPI levanté con Docker Compose un clúster
> virtualizado de un nodo maestro y dos workers.”

Con una grilla de `600 x 600` durante 150 pasos, las ejecuciones registradas
reportaron 10 440 celdas consumidas y 1 036 focos activos. El mejor tiempo
OpenMP de esa tanda fue 0.046586 s con 4 hilos (speedup 2.525 respecto al
secuencial de 0.117626 s). El mejor MPI fue 0.062795 s con 6 procesos (speedup
1.873).

## Aclaración importante sobre las pruebas

> “Las mediciones son una corrida por configuración y el clúster MPI se ejecutó
> en contenedores sobre una sola PC. Por eso las presento como pruebas
> funcionales y resultados iniciales, no como promedios estadísticos ni como
> mediciones de varias máquinas físicas.”

La publicación del código en GitHub no significa que el host público ya esté
desplegado. El acceso desde Internet mediante `cloudflared` todavía requiere
configuración y una prueba real desde otra computadora.

## Si preguntan qué se verificó

- Los motores secuencial, OpenMP y MPI terminaron con los mismos conteos en las
  configuraciones probadas.
- Se probó la infraestructura Docker/OpenMPI y la comunicación entre
  contenedores, incluyendo un smoke test MPI.
- Los ejecutables no se subieron al repositorio; se compilan desde los archivos
  fuente.
- La conexión pública de compañeros al host aún no se debe presentar como
  completada hasta desplegar y verificar el túnel.
