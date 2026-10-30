-- Llaves e índices de las tablas de vocabulario, creados DESPUÉS de cargar (más rápido que
-- mantenerlos durante el COPY). Siguen el DDL oficial del CDM v5.4.
-- Una llave primaria también valida que no haya duplicados: si la carga hubiera repetido
-- filas, aquí fallaría.

-- Tablas pequeñas: sólo llave primaria.
ALTER TABLE cdm.vocabulary      ADD CONSTRAINT xpk_vocabulary      PRIMARY KEY (vocabulary_id);
ALTER TABLE cdm.domain          ADD CONSTRAINT xpk_domain          PRIMARY KEY (domain_id);
ALTER TABLE cdm.concept_class   ADD CONSTRAINT xpk_concept_class   PRIMARY KEY (concept_class_id);
ALTER TABLE cdm.relationship    ADD CONSTRAINT xpk_relationship    PRIMARY KEY (relationship_id);

-- concept: PK por concept_id; los demás sirven para buscar por código de origen
-- (vocabulary_id + concept_code, lo que hace el ETL) y para filtrar por dominio/vocabulario.
ALTER TABLE cdm.concept ADD CONSTRAINT xpk_concept PRIMARY KEY (concept_id);
CREATE INDEX idx_concept_code       ON cdm.concept (vocabulary_id, concept_code);
CREATE INDEX idx_concept_domain     ON cdm.concept (domain_id);
CREATE INDEX idx_concept_class      ON cdm.concept (concept_class_id);

-- concept_relationship: el ETL entra por concept_id_1 para seguir 'Maps to'.
ALTER TABLE cdm.concept_relationship
  ADD CONSTRAINT xpk_concept_relationship PRIMARY KEY (concept_id_1, concept_id_2, relationship_id);
CREATE INDEX idx_cr_concept_id_2  ON cdm.concept_relationship (concept_id_2);
CREATE INDEX idx_cr_relationship  ON cdm.concept_relationship (relationship_id);

-- concept_ancestor: se consulta en ambos sentidos (ancestros de X / descendientes de X).
CREATE INDEX idx_ca_ancestor    ON cdm.concept_ancestor (ancestor_concept_id);
CREATE INDEX idx_ca_descendant  ON cdm.concept_ancestor (descendant_concept_id);

CREATE INDEX idx_cs_concept_id  ON cdm.concept_synonym (concept_id);
CREATE INDEX idx_ds_drug        ON cdm.drug_strength (drug_concept_id);

-- Actualiza las estadísticas para que el planificador use los índices recién creados.
ANALYZE;
