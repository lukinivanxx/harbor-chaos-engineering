#!/bin/bash
set -e

# ============================================
# Chaos-сценарий 1: Задержка между пользователем и приложением
# Внедряем 5с задержки на входящий трафик через Istio Ingress Gateway
# ============================================

# адрес Harbor через Istio Ingress Gateway
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
GW_PORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
GW="http://${NODE_IP}:${GW_PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo " СЦЕНАРИЙ: Задержка user → приложение"
echo "=========================================="

# --- Убедимся, что базовый маршрут активен ---
kubectl apply -f "$SCRIPT_DIR/00-gateway.yaml" >/dev/null
kubectl apply -f "$SCRIPT_DIR/temp-route.yaml" >/dev/null
sleep 5

# --- ШАГ 1: Демонстрация ДО внедрения ошибки ---
echo ""
echo "[1] Работа приложения ДО внедрения ошибки:"
curl -o /dev/null -s -w "    Время ответа: %{time_total}s | HTTP-код: %{http_code}\n" "$GW"

# --- ШАГ 2: Пауза для ручной проверки ---
echo ""
read -p "[2] Нажмите Enter, чтобы внедрить задержку 5с..."

# --- ШАГ 3: Применяем манифест с ошибкой ---
echo ""
echo "[3] Применяю Istio-манифест с задержкой..."
kubectl delete -f "$SCRIPT_DIR/temp-route.yaml" >/dev/null 2>&1 || true
kubectl apply -f "$SCRIPT_DIR/01-delay-user-app.yaml" >/dev/null
echo "    Жду 10 секунд, пока Istio разошлёт правило прокси..."
sleep 10

# --- ШАГ 4: Демонстрация ПОСЛЕ внедрения ошибки ---
echo ""
echo "[4] Работа приложения ПОСЛЕ внедрения ошибки:"
curl -o /dev/null -s -w "    Время ответа: %{time_total}s | HTTP-код: %{http_code}\n" "$GW"

# --- ШАГ 5: Пауза ---
echo ""
read -p "[5] Нажмите Enter, чтобы откатить изменения..."

# --- ШАГ 6: Откат всех изменений ---
echo ""
echo "[6] Откатываю изменения..."
kubectl delete -f "$SCRIPT_DIR/01-delay-user-app.yaml" >/dev/null
kubectl apply -f "$SCRIPT_DIR/temp-route.yaml" >/dev/null
sleep 5
echo "    Проверка после отката:"
curl -o /dev/null -s -w "    Время ответа: %{time_total}s | HTTP-код: %{http_code}\n" "$GW"

echo ""
echo "=========================================="
echo " Сценарий 1 завершён. Приложение в норме."
echo "=========================================="
