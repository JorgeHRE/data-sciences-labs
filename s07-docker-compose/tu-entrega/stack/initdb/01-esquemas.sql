-- 01-esquemas.sql
-- Postgres ejecuta los archivos de /docker-entrypoint-initdb.d en ORDEN
-- ALFABÉTICO, por eso el prefijo numérico: los esquemas deben existir antes
-- de crear tablas dentro de ellos (eso lo hace 02-tablas-prueba.sql).
--
-- Importante: esto se ejecuta SOLO la primera vez, cuando el volumen de datos
-- está vacío. Con datos ya existentes, Postgres ignora esta carpeta.

-- cdm: datos clínicos ya estandarizados (Common Data Model, estilo OMOP).
CREATE SCHEMA IF NOT EXISTS cdm;

-- results: salidas de los análisis, separadas de los datos de origen.
CREATE SCHEMA IF NOT EXISTS results;
