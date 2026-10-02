
## Generación de Datos Sintéticos (Synthea)

Para este laboratorio, se optó por generar un volumen de 20,000 pacientes para evaluar correctamente el consumo de memoria. Los datos fueron generados utilizando Synthea con el siguiente comando de terminal para forzar la salida en formato CSV y deshabilitar exportaciones innecesarias (FHIR):

`java -jar synthea-with-dependencies.jar -p 20000 --exporter.csv.export=true --exporter.fhir.export=false`

Archivos utilizados: `patients.csv`, `encounters.csv` y `observations.csv`.

## 2. Instrucciones para Reproducir el Análisis
Para ejecutar el notebook `analisis_pacientes.ipynb` desde cero sin errores, cualquier usuario debe seguir estos pasos:

1. **Estructura de archivos:** Asegurarse de que los archivos `patients.csv`, `encounters.csv` y `observations.csv` generados por Synthea se encuentren en la misma carpeta que el notebook.
2. **Entorno de Python:** Contar con Python 3.x y tener instaladas las dependencias ejecutando en la terminal:
   `pip install pandas polars pyspark`
3. **Máquina Virtual de Java:** Para que el benchmark de PySpark funcione, el sistema debe contar con Java (JDK 11 o superior) instalado.
4. **Ejecución:** Abrir el archivo en Jupyter Lab, ir al menú superior y seleccionar **Kernel -> Restart Kernel and Run All Cells...** para ejecutar el flujo de datos de principio a fin.

## 3. Comparativa de Motores (Actividad 8)
### 8. Comparativa de Motores: Pandas vs Polars vs PySpark

| Herramienta | Líneas de código | Tiempo (s) | Memoria pico (MB) | Qué costó más |
| :--- | :--- | :--- | :--- | :--- |
| **pandas** | 4 | 19.10 s | 2413.14 MB | **Consumo de RAM y Cuellos de botella:** Cargar el CSV completo en memoria para hacer cruces saturó los recursos, volviéndolo el más lento en ejecución bruta. |
| **Polars** | 4 | 2.17 s | 0.05 MB* | **Curva de aprendizaje:** Sintaxis diferente a Pandas. (*Nota: El consumo de 0.05 MB es el del driver de Python; el consumo real ocurre en Rust, fuera de la vista de `tracemalloc`). |
| **PySpark** | 5 | 9.26 s | 0.73 MB* | **El Overhead y la Configuración:** Exigió afinar la memoria a mano (8GB) para no sufrir un `OutOfMemoryError` en la JVM. Además, el tiempo de inicializar la máquina virtual de Java penaliza el rendimiento en modo local. |

**Hallazgo clave:** Polars demostró ser ~9 veces más rápido que Pandas. PySpark, aunque superó a Pandas gracias a su optimización de consultas (*Catalyst Optimizer*), no justifica su tremenda complejidad de infraestructura para correrse en un solo equipo local.