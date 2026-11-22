#!/usr/bin/env bash
# Prueba la política de permisos del rol lab21-instancia en el simulador de IAM.
# No crea ni modifica nada. Uso (desde tu-entrega/): bash iam/simular_rol.sh
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-tesis}" AWS_PAGER=""

P="$(cat "$(dirname "$0")/rol_permisos.json")"   # "$(cat)" y no file:// (ver simular_operador.sh)
B=arn:aws:s3:::omop-tesis-jhr-2026

sim() { # descripción, acción, ARN, [prefijo para ListBucket]
  local ctx=()
  [[ $# -eq 4 ]] && ctx=(--context-entries "ContextKeyName=s3:prefix,ContextKeyValues=$4,ContextKeyType=string")
  printf '%-52s %s\n' "$1" "$(aws iam simulate-custom-policy --policy-input-list "$P" \
    --action-names "$2" --resource-arns "$3" "${ctx[@]}" \
    --query 'EvaluationResults[0].EvalDecision' --output text)"
}

echo "== Lo que el pipeline necesita (esperado: allowed)"
sim "Listar curated/synthea/observations/"        s3:ListBucket "$B" "curated/synthea/observations/"
sim "Leer observations/anio=2025/part-0.parquet"  s3:GetObject  "$B/curated/synthea/observations/anio=2025/part-0.parquet"
sim "Escribir results/auditoria_obs/..."          s3:PutObject  "$B/results/auditoria_obs/ejecucion=X/auditoria.parquet"
sim "Listar results/auditoria_obs/"               s3:ListBucket "$B" "results/auditoria_obs/"
echo "== Lo que NO debe poder hacer (esperado: implicitDeny)"
sim "Listar la raíz del bucket"                   s3:ListBucket "$B" ""
sim "Listar raw/"                                 s3:ListBucket "$B" "raw/"
sim "Leer raw/ (PII simulada en patients.csv)"    s3:GetObject  "$B/raw/synthea/fecha_carga=2026-11-17/patients.csv"
sim "Leer otra tabla de curated/"                 s3:GetObject  "$B/curated/synthea/conditions/anio=2025/part-0.parquet"
sim "Escribir en results/ de otro pipeline"       s3:PutObject  "$B/results/otro/x.parquet"
sim "Escribir en curated/ (alterar la fuente)"    s3:PutObject  "$B/curated/synthea/observations/anio=2025/x.parquet"
sim "Borrar un resultado"                         s3:DeleteObject "$B/results/auditoria_obs/ejecucion=X/auditoria.parquet"
sim "Leer otro bucket"                            s3:GetObject  "arn:aws:s3:::otro-bucket/x"
