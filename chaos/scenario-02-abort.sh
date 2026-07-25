#!/bin/bash
set -e

# ============================================
# Chaos-сценарий 2: Ошибка HTTP 500 между компонентами
# Внедряем abort 500 на трафик к harbor-portal через Istio Gateway
# ============================================

# адрес Harbor через Istio Ingress Gateway
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
GW_PORT=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}')
GW="http://${NODE_IP}:${GW_PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo " СЦЕНАРИЙ 2: Ошибка 500 (portal)"
echo "=========================================="

# --- Убедимся, что базовый маршрут активен ---
kubectl apply -f "$SCRIPT_DIR/00-gateway.yaml" >/dev/null
kubectl apply -f "$SCRIPT_DIR/temp-route.yaml" >/dev/null
sleep 5

# --- ШАГ 1: Демонстрация ДО внедрения ошибки ---
echo ""
echo "[1] Работа приложения ДО внедрения ошибки:"
curl -s -o /dev/null -w "    HTTP-код: %{http_code}\n" "$GW"

# --- ШАГ 2: Пауза для ручной проверки ---
echo ""
read -p "[2] Нажмите Enter, чтобы внедрить ошибку 500..."

# --- ШАГ 3: Применяем манифест с ошибкой ---
echo ""
echo "[3] Применяю Istio-манифест с abort 500..."
kubectl delete -f "$SCRIPT_DIR/temp-route.yaml" >/dev/null 2>&1 || true
kubectl apply -f "$SCRIPT_DIR/02-abort-portal.yaml" >/dev/null
echo "    Жду 10 секунд, пока Istio разошлёт правило прокси..."
sleep 10

# --- ШАГ 4: Демонстрация ПОСЛЕ внедрения ошибки ---
echo ""
echo "[4] Работа приложения ПОСЛЕ внедрения ошибки:"
curl -s -o /dev/null -w "    HTTP-код: %{http_code}\n" "$GW"
echo "    Тело ответа (подпись Istio):"
echo -n "    "; curl -s "$GW"; echo ""

# --- ШАГ 5: Пауза ---
echo ""
read -p "[5] Нажмите Enter, чтобы откатить изменения..."

# --- ШАГ 6: Откат всех изменений ---
echo ""
echo "[6] Откатываю изменения..."
kubectl delete -f "$SCRIPT_DIR/02-abort-portal.yaml" >/dev/null
kubectl apply -f "$SCRIPT_DIR/temp-route.yaml" >/dev/null
sleep 5
echo "    Проверка после отката:"
curl -s -o /dev/null -w "    HTTP-код: %{http_code}\n" "$GW"

echo ""
echo "=========================================="
echo " Сценарий 2 завершён. Приложение в норме."
echo "=========================================="
