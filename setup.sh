#!/bin/bash
set -e

# ============================================================
# setup.sh — Полная автоматическая установка:
#   k3s + Istio + Harbor + подготовка chaos-сценариев
# Требования: Ubuntu 22.04, пользователь в группе sudo
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo " УСТАНОВКА: k3s + Istio + Harbor"
echo "=========================================="

# ------------------------------------------------------------
# ШАГ 1: Установка k3s (однонодовый Kubernetes, без traefik)
# ------------------------------------------------------------
echo ""
echo "[1/6] Устанавливаю k3s..."
if ! command -v k3s >/dev/null 2>&1; then
  curl -sfL https://get.k3s.io | sh -s - --disable traefik
else
  echo "    k3s уже установлен, пропускаю."
fi

# Настройка доступа к kubectl для текущего пользователя
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
export KUBECONFIG=~/.kube/config
if ! grep -q "KUBECONFIG" ~/.bashrc; then
  echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
fi

# Ждём готовности ноды
echo "    Жду готовности ноды k3s..."
until kubectl get nodes 2>/dev/null | grep -q " Ready "; do
  sleep 3
done
echo "    k3s готов."

# Определяем IP ноды (для externalURL Harbor)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "    IP ноды: $NODE_IP"

# ------------------------------------------------------------
# ШАГ 2: Установка istioctl
# ------------------------------------------------------------
echo ""
echo "[2/6] Устанавливаю Istio..."
if ! command -v istioctl >/dev/null 2>&1 && [ ! -d "$HOME"/istio-* ]; then
  cd "$HOME"
  curl -L https://istio.io/downloadIstio | sh -
fi
ISTIO_DIR=$(ls -d "$HOME"/istio-* | head -1)
export PATH="$ISTIO_DIR/bin:$PATH"
if ! grep -q "istio-" ~/.bashrc; then
  echo "export PATH=\"$ISTIO_DIR/bin:\$PATH\"" >> ~/.bashrc
fi

# ------------------------------------------------------------
# ШАГ 3: Установка Istio в кластер (профиль demo)
# ------------------------------------------------------------
echo ""
echo "[3/6] Разворачиваю Istio в кластере..."
istioctl install --set profile=demo -y

# ------------------------------------------------------------
# ШАГ 4: Namespace для Harbor + включение sidecar injection
# ------------------------------------------------------------
echo ""
echo "[4/6] Готовлю namespace harbor..."
kubectl create namespace harbor --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace harbor istio-injection=enabled --overwrite

# ------------------------------------------------------------
# ШАГ 5: Установка Harbor через Helm (версия чарта 1.18.0 = Harbor 2.14.0)
# ------------------------------------------------------------
echo ""
echo "[5/6] Устанавливаю Harbor..."
if ! command -v helm >/dev/null 2>&1; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm repo add harbor https://helm.goharbor.io 2>/dev/null || true
helm repo update

# Генерируем values с актуальным IP ноды
sed "s|__NODE_IP__|$NODE_IP|g" "$SCRIPT_DIR/harbor-values.yaml" > /tmp/harbor-values-rendered.yaml

helm upgrade --install harbor harbor/harbor \
  --namespace harbor \
  --version 1.18.0 \
  -f /tmp/harbor-values-rendered.yaml

echo "    Жду готовности подов Harbor (может занять несколько минут)..."
kubectl wait --for=condition=ready pod --all -n harbor --timeout=600s || true

# ------------------------------------------------------------
# ШАГ 6: Применяем базовый Istio Gateway + маршрут
# ------------------------------------------------------------
echo ""
echo "[6/6] Настраиваю Istio Gateway..."
kubectl apply -f "$SCRIPT_DIR/chaos/00-gateway.yaml"
kubectl apply -f "$SCRIPT_DIR/chaos/temp-route.yaml"

# Определяем порт ingress gateway
GW_PORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')

echo ""
echo "=========================================="
echo " УСТАНОВКА ЗАВЕРШЕНА!"
echo "=========================================="
echo " Harbor доступен внутри ВМ:  http://$NODE_IP:30002"
echo " Через Istio Gateway:        http://$NODE_IP:$GW_PORT"
echo " Логин: admin / Harbor12345"
echo ""
echo " Проверка здоровья:"
echo "   curl http://$NODE_IP:30002/api/v2.0/health"
echo "=========================================="
