#!/bin/bash
set -euo pipefail

CLUSTER_NAME="ECS Instance - beep-beep-processor-cluster"

echo "🔎 Procurando instâncias com Name = '$CLUSTER_NAME'..."

# Pega os IDs das instâncias
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$CLUSTER_NAME" "Name=instance-state-name,Values=running,pending,stopped,stopping" \
  --query "Reservations[].Instances[].InstanceId" \
  --region us-east-2 \
  --output text)

if [ -z "$INSTANCE_IDS" ]; then
  echo "✅ Nenhuma instância encontrada com esse nome."
  exit 0
fi

echo "⚠️  Instâncias encontradas: $INSTANCE_IDS"
echo "⏳ Terminando instâncias..."

aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region us-east-2

echo "🚀 Terminação solicitada com sucesso!"
