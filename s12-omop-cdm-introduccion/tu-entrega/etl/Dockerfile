# Entorno R para ETL-Synthea (lab 12). Adaptado del de proyecto-rag-omop, que ya
# corrió este mismo ETL con Synthea v3.3.0; aquí se copia y no se comparte.
#
# rocker/r-ver fija el CRAN a una fecha según la versión de R, así que las
# versiones de los paquetes son reproducibles. Los paquetes OHDSI van fijados a
# un tag de release (ver abajo).
FROM rocker/r-ver:4.5.3

# - openjdk: DatabaseConnector habla con Postgres por JDBC, que necesita Java.
# - postgresql-client: la carga masiva (bulkLoad = TRUE) ejecuta `psql \copy`.
# - lib*-dev: dependencias de compilación de rJava y de los paquetes HTTP.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        openjdk-17-jdk-headless \
        postgresql-client \
        libxml2-dev libssl-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/* \
    && R CMD javareconf

# Tags fijos (upgrade = "never" evita que remotes actualice dependencias):
# - CommonDataModel v5.4.3 -> DDL oficial del CDM v5.4
# - ETL-Synthea v2.1.1     -> última versión que soporta Synthea v3.3.0
RUN install2.r --error --skipinstalled remotes rJava \
    && Rscript -e 'remotes::install_github("OHDSI/CommonDataModel@v5.4.3", upgrade = "never")' \
    && Rscript -e 'remotes::install_github("OHDSI/ETL-Synthea@v2.1.1", upgrade = "never")' \
    && Rscript -e 'DatabaseConnector::downloadJdbcDrivers("postgresql", pathToDriver = "/opt/jdbc")'

# DatabaseConnector busca el driver JDBC en esta carpeta y psql en POSTGRES_PATH.
ENV DATABASECONNECTOR_JAR_FOLDER=/opt/jdbc \
    POSTGRES_PATH=/usr/bin

# El script del ETL NO se copia a la imagen: se monta desde el host en /etl
# (compose.yml), para poder editarlo sin reconstruir.
WORKDIR /etl
CMD ["Rscript", "/etl/run_etl_synthea.R"]
