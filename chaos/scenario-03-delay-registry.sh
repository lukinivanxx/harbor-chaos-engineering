#!/bin/bash
set -e

# ============================================
# Chaos-сценарий 3: Задержка между registry и остальными компонентами
# Внедряем 5с задержки на трафик к harbor-registry (внутримешевый трафик)
# ============================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Функция проверки registry изнутри mesh
check_registry() {
  kubectl run test-curl-reg --image=curlimages/curl -n harbor --rm -i --restart=Never --quiet -- \
    curl -s -o /dev/null -w "    Время: %{time_total}s | HTTP: %{http_code}\n" http://harbor-registry:5000/ 2>/dev/null
}

echo "=========================================="
echo " СЦЕНАРИЙ 3: Задержка registry ↔ компоненты"
echo "=========================================="

# --- ШАГ 1: Демонстрация ДО внедрения ошибки ---
echo ""
echo "[1] Работа registry ДО внедрения ошибки:"
check_registry

# --- ШАГ 2: Пауза для ручной проверки ---
echo ""
read -p "[2] Нажмите Enter, чтобы внедрить задержку 5с..."

# --- ШАГ 3: Применяем манифест с ошибкой ---
echo ""
echo "[3] Применяю Istio-манифест с задержкой к registry..."
kubectl apply -f "$SCRIPT_DIR/03-delay-registry.yaml" >/dev/null
echo "    Жду 10 секунд, пока Istio разошлёт правило прокси..."
sleep 10

# --- ШАГ 4: Демонстрация ПОСЛЕ внедрения ошибки ---
echo ""
echo "[4] Работа registry ПОСЛЕ внедрения ошибки:"
check_registry

# --- ШАГ 5: Пауза ---
echo ""
read -p "[5] Нажмите Enter, чтобы откатить изменения..."

# --- ШАГ 6: Откат всех изменений ---
echo ""
echo "[6] Откатываю изменения..."
kubectl delete -f "$SCRIPT_DIR/03-delay-registry.yaml" >/dev/null
sleep 5
echo "    Проверка после отката:"
check_registry

echo ""
echo "=========================================="
echo " Сценарий 3 завершён. Приложение в норме."
echo "=========================================="
