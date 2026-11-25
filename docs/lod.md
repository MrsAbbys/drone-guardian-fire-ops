# LOD de mallas importadas en Godot

Para generar niveles de detalle para los modelos de árboles y `roca_custom`:

1. En el panel **FileSystem**, selecciona el archivo `.glb` del modelo.
2. Abre la pestaña **Import** del Inspector.
3. En **Meshes**, activa **Generate LODs**.
4. Pulsa **Reimport** y espera a que termine la importación.
5. Repite el proceso para cada modelo de árbol y `roca_custom`.
6. Ejecuta el mapa y revisa los modelos a distintas distancias para confirmar que las transiciones no resulten visibles de forma brusca.

En un archivo lateral `.glb.import`, Godot guarda esta opción como:

```ini
[params]
meshes/generate_lods=true
```

Este repositorio no contiene modelos `.glb` ni archivos `.glb.import` en este momento; por eso no hay importaciones que actualizar.
