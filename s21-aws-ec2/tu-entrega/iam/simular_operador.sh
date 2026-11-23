#!/usr/bin/env bash
# Prueba la política lab21-operador en el simulador de IAM antes (o después) de asignarla.
# No crea ni modifica nada en la cuenta. Uso: bash iam/simular_operador.sh (desde tu-entrega/)
#
# Nota: el contenido se pasa con "$(cat ...)" y no con file:// porque en parámetros de tipo
# lista (--policy-input-list) el AWS CLI no expande file:// y envía la ruta como texto.
set -euo pipefail
export AWS_PROFILE="${AWS_PROFILE:-tesis}" AWS_PAGER=""

P="$(cat "$(dirname "$0")/politica_operador.json")"
A=123456789012   # cuenta ficticia: la política usa * en la cuenta, así que da igual

sim() { # descripción, acción, ARN, [entradas de contexto...]
  local d=$1 act=$2 arn=$3; shift 3
  local r
  r=$(aws iam simulate-custom-policy --policy-input-list "$P" --action-names "$act" \
        --resource-arns "$arn" ${1:+--context-entries "$@"} \
        --query 'EvaluationResults[0].EvalDecision' --output text)
  printf '%-48s %s\n' "$d" "$r"
}
tipo()  { echo "ContextKeyName=ec2:InstanceType,ContextKeyValues=$1,ContextKeyType=string"; }
disco() { echo "ContextKeyName=ec2:VolumeType,ContextKeyValues=$1,ContextKeyType=string ContextKeyName=ec2:VolumeSize,ContextKeyValues=$2,ContextKeyType=numeric"; }
srv()   { echo "ContextKeyName=iam:PassedToService,ContextKeyValues=$1,ContextKeyType=string"; }
I=arn:aws:ec2:us-east-2:$A:instance/i-x
V=arn:aws:ec2:us-east-2:$A:volume/vol-x

echo "== Lanzar (esperado entre paréntesis)"
sim "t3.small en us-east-2 (allowed)"        ec2:RunInstances "$I" $(tipo t3.small)
sim "t3.xlarge en us-east-2 (deny)"          ec2:RunInstances "$I" $(tipo t3.xlarge)
sim "t3.small en us-east-1 (deny)"           ec2:RunInstances "${I/us-east-2/us-east-1}" $(tipo t3.small)
sim "disco gp3 20 GB (allowed)"              ec2:RunInstances "$V" $(disco gp3 20)
sim "disco gp3 100 GB (deny)"                ec2:RunInstances "$V" $(disco gp3 100)
sim "disco gp2 20 GB (deny)"                 ec2:RunInstances "$V" $(disco gp2 20)
sim "AMI en us-east-2 (allowed)"             ec2:RunInstances arn:aws:ec2:us-east-2::image/ami-x
sim "AMI en us-east-1 (deny)"                ec2:RunInstances arn:aws:ec2:us-east-1::image/ami-x
echo "== Operar"
sim "Terminar instancia us-east-2 (allowed)" ec2:TerminateInstances "$I"
sim "Terminar instancia us-west-2 (deny)"    ec2:TerminateInstances "${I/us-east-2/us-west-2}"
sim "PassRole lab21-* a EC2 (allowed)"       iam:PassRole arn:aws:iam::$A:role/lab21-instancia $(srv ec2.amazonaws.com)
sim "PassRole lab21-* a Lambda (deny)"       iam:PassRole arn:aws:iam::$A:role/lab21-instancia $(srv lambda.amazonaws.com)
sim "PassRole rol admin a EC2 (deny)"        iam:PassRole arn:aws:iam::$A:role/AccountFullAccessRole $(srv ec2.amazonaws.com)
sim "Crear alarma us-east-2 (allowed)"       cloudwatch:PutMetricAlarm arn:aws:cloudwatch:us-east-2:$A:alarm:x
sim "Re-etiquetar instancia (deny)"          ec2:CreateTags "$I"

echo "== Session Manager (bono)"
uid() { echo "ContextKeyName=aws:userid,ContextKeyValues=AIDAYO,ContextKeyType=string"; }
DOC=arn:aws:ssm:us-east-2::document/SSM-SessionManagerRunShell
sim "StartSession instancia us-east-2 (allowed)" ssm:StartSession "$I"
sim "StartSession documento shell us-east-2 (allowed)" ssm:StartSession "$DOC"
sim "StartSession instancia us-east-1 (deny)"   ssm:StartSession "${I/us-east-2/us-east-1}"
sim "StartSession con otro documento (deny)"    ssm:StartSession arn:aws:ssm:us-east-2::document/AWS-RunShellScript
sim "Cerrar MI sesion (allowed)"                ssm:TerminateSession arn:aws:ssm:us-east-2:$A:session/AIDAYO-abc $(uid)
sim "Cerrar sesion de OTRA persona (deny)"      ssm:TerminateSession arn:aws:ssm:us-east-2:$A:session/AIDAOTRO-abc $(uid)
sim "Ejecutar comando remoto SendCommand (deny)" ssm:SendCommand "$I"
