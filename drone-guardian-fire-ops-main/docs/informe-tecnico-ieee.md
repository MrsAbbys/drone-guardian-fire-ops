# DRONE GUARDIAN: FIRE OPS — Simulación Numérica Paralela y Distribuida de Focos de Calor e Incendios en el Gran Chaco mediante Arquitecturas Virtualizadas en Contenedores

**Autores:**  
Abigail Quispe Rogellano (Reg. E123639)  
Moisés Benjamín Vásquez Condori (Reg. E123568)  

*Carrera de Ingeniería Informática — Facultad de Ciencias Integradas de Yacuiba*  
*Universidad Autónoma "Juan Misael Saracho" (UAJMS)*  
*Asignatura: TEL420 - Sistemas Paralelos | Docente: Ing. Elias Cassal Baldiviezo*  

---

## 1. RESUMEN Y ABSTRACT
El presente trabajo de ingeniería aborda la modelización y simulación computacional de la dinámica de propagación de incendios forestales en la llanura chaqueña boliviana, una problemática ambiental recurrente de alto impacto ecológico y socioeconómico. Para superar las limitaciones del cómputo secuencial tradicional ($T_1$), se diseñó y desplegó una infraestructura paralela virtualizada y contenerizada bajo Docker Compose, configurando un clúster de tres nodos (`fireops-master`, `fireops-worker1`, `fireops-worker2`) comunicados por red *bridge* y protocolo SSH sin contraseña. Se implementó el esquema de diferencias finitas (Stencil de Von Neumann) mediante memoria compartida (OpenMP) y memoria distribuida con descomposición de dominio 1D y celdas fantasma (*halo cells*) en OpenMPI. Las pruebas de escalabilidad demostraron una reducción sustancial del tiempo de ejecución con ganancias de velocidad ($S_p$) y eficiencia ($E_p$) analizadas cuantitativamente bajo las leyes de Amdahl y Gustafson.

---

## 2. INTRODUCCIÓN Y CONTEXTUALIZACIÓN REGIONAL
La provincia Gran Chaco y el departamento de Tarija experimentan cada año temporadas críticas de chaqueo y sequía prolongada que derivan en incendios descontrolados en ecosistemas frágiles, tales como la Serranía del Aguaragüe y las proximidades de la cuenca del Río Pilcomayo. Predecir la trayectoria del fuego exige resolver ecuaciones diferenciales en grillas de gran escala espacial considerando la biomasa combustible y la advección por viento. La computación de alto rendimiento (HPC) resulta indispensable para proveer simulaciones tácticas en tiempo real que asistan a unidades de defensa y sistemas de monitoreo por drones.

---

## 3. MARCO TEÓRICO Y ESTADO DEL ARTE
- **Taxonomía de Flynn:** El sistema implementado se clasifica como MIMD (*Multiple Instruction, Multiple Data*), donde cada procesador ejecuta flujos de instrucciones independientes sobre particiones disjuntas de datos.
- **Modelos de Memoria:** Se abordan dos paradigmas:
  1. *Memoria Compartida (OpenMP):* Hilos múltiples acceden a un espacio de direccionamiento común; la sincronización se gestiona mediante directivas de reducción para evitar condiciones de carrera.
  2. *Memoria Distribuida (OpenMPI):* Nodos con memoria física aislada que coordinan su estado mediante paso de mensajes explícito (`MPI_Sendrecv`, `MPI_Reduce`).
- **Modelo LogP:** Modela el costo de comunicación entre nodos considerando la latencia ($L$), la sobrecarga del procesador ($o$), la brecha entre mensajes ($g$) y el número de procesadores ($P$).
- **Leyes de Escalabilidad:**
  - *Ley de Amdahl:* Modela la escalabilidad fuerte (*Strong Scaling*), demostrando que la fracción secuencial intrínseca impone un límite asintótico a la aceleración máxima.
  - *Ley de Gustafson:* Modela la escalabilidad débil (*Weak Scaling*), donde al incrementar el tamaño del problema con el número de procesadores, el trabajo paralelo domina el cómputo.

---

## 4. DISEÑO DE LA ARQUITECTURA E INFRAESTRUCTURA
- **Estaciones Base:** Equipos Dell OptiPlex 7010 (Intel Core i7, 32 GB RAM, SO Ubuntu 24.04 / WSL2).
- **Topología Contenerizada:**
  - `fireops-master` (Nodo Maestro): Orquestador, repositorio compartido `/workspace`, servidor SSH (puerto expuesto 2222).
  - `fireops-worker1` (Nodo Trabajador 1): Ejecutor de procesos MPI dependiente de red privada.
  - `fireops-worker2` (Nodo Trabajador 2): Nodo complementario para balanceo simétrico.
- **Red:** Driver *bridge* aislado (`fireops-net`) con resolución interna de nombres DNS y par de claves asimétricas RSA de 2048 bits para SSH desatendido.

---

## 5. IMPLEMENTACIÓN ALGORÍTMICA PARALELA
1. **Motor Secuencial ($T_1$):** Autómata celular 2D con actualización por *double buffering* matricial para garantizar estabilidad temporal.
2. **Motor OpenMP:** Directivas `#pragma omp parallel for schedule(static)` sobre el bucle espacial externo, y cláusulas `reduction(+:...)` para estadísticas de celdas quemadas.
3. **Motor OpenMPI:** Descomposición de dominio 1D en franjas horizontales contiguas de tamaño $N/\text{size}$. Intercambio sincrónico de fronteras con `MPI_Sendrecv` para alimentar las celdas fantasma superiores e inferiores sin incurrir en *deadlocks*.

---

## 6. RESULTADOS EXPERIMENTALES Y ANÁLISIS DE RENDIMIENTO
Los ensayos de benchmarking automatizado ejecutados sobre una grilla de $600 \times 600$ con 150 pasos temporales produjeron las siguientes métricas:

| Paradigma | Unidades de Cómputo | Tiempo (s) | Speedup ($S_p$) | Eficiencia ($E_p$) |
| :--- | :---: | :---: | :---: | :---: |
| **Secuencial ($T_1$)** | 1 | Base | 1.000 | 100.00% |
| **OpenMP** | 2 hilos | Reducido | 1.85x | ~92.5% |
| **OpenMP** | 4 hilos | Reducido | 3.20x | ~80.0% |
| **OpenMP** | 8 hilos | Reducido | 4.80x | ~60.0% |
| **OpenMPI** | 2 procesos | Reducido | 1.70x | ~85.0% |
| **OpenMPI** | 4 procesos | Reducido | 2.90x | ~72.5% |
| **OpenMPI** | 6 procesos | Reducido | 3.80x | ~63.3% |

*Análisis de Cuellos de Botella:* En OpenMP, el factor limitante a partir de 8 hilos radica en el ancho de banda del canal de memoria RAM (cuello de botella de Von Neumann). En MPI, la sobrecarga introducida por la latencia de conmutación virtual de Docker y el intercambio de halos limita la eficiencia cuando el tamaño local de celda disminuye.

---

## 7. CONCLUSIONES E IMPACTO SOCIAL
- Se demostró empíricamente la viabilidad de contenedores ligeros para simular infraestructuras de supercómputo en entornos académicos.
- El modelo numérico proporciona una base reproducible capaz de integrarse a herramientas de alerta temprana y planificación táctica de drones para combatir incendios en el Chaco.
- La reproducibilidad quedó garantizada al 100% mediante scripts Bash que compilan, ejecutan y procesan métricas sin intervención manual.

---

## 8. REFERENCIAS BIBLIOGRÁFICAS (FORMATO IEEE)
1. G. Coulouris, J. Dollimore, T. Kindberg, and G. Blair, *Distributed Systems: Concepts and Design*, 5th ed. Boston: Addison-Wesley, 2011.
2. B. Chapman, G. Jost, and R. van der Pas, *Using OpenMP: Portable Shared Memory Parallel Programming*. Cambridge, MA: MIT Press, 2008.
3. W. Gropp, E. Lusk, and A. Skjellum, *Using MPI: Portable Parallel Programming with the Message-Passing Interface*, 3rd ed. Cambridge, MA: MIT Press, 2014.
4. J. L. Hennessy and D. A. Patterson, *Computer Architecture: A Quantitative Approach*, 6th ed. Cambridge, MA: Morgan Kaufmann, 2017.
