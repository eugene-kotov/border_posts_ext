#!/usr/bin/env python3
"""
Пример тестирования Checkpoint API
"""

import requests
import json
import time
from requests.auth import HTTPBasicAuth

# Конфигурация
API_BASE_URL = "http://localhost"
API_USERNAME = "admin"
API_PASSWORD = "checkpoint2025"  # Измените на ваш пароль

def test_health_check():
    """Тест health check endpoint"""
    print("🔍 Тестирование health check...")
    try:
        response = requests.get(f"{API_BASE_URL}/health", timeout=10)
        print(f"Status: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"Response: {json.dumps(data, indent=2, ensure_ascii=False)}")
            return True
        else:
            print(f"Error: {response.text}")
            return False
    except Exception as e:
        print(f"Error: {e}")
        return False

def test_authentication():
    """Тест аутентификации"""
    print("\n🔐 Тестирование аутентификации...")
    try:
        # Тест без авторизации (должен вернуть 401)
        response = requests.get(f"{API_BASE_URL}/api/v1/checkpoints", timeout=10)
        if response.status_code == 401:
            print("✅ Аутентификация работает (401 без авторизации)")
        else:
            print(f"⚠️  Неожиданный статус без авторизации: {response.status_code}")
        
        # Тест с авторизацией
        auth = HTTPBasicAuth(API_USERNAME, API_PASSWORD)
        response = requests.get(f"{API_BASE_URL}/api/v1/checkpoints", auth=auth, timeout=10)
        print(f"Status with auth: {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Аутентификация успешна")
            print(f"Total checkpoints: {data.get('total', 0)}")
            return True
        else:
            print(f"❌ Ошибка аутентификации: {response.text}")
            return False
    except Exception as e:
        print(f"Error: {e}")
        return False

def test_checkpoints_endpoint():
    """Тест получения списка пунктов пропуска"""
    print("\n📋 Тестирование получения списка пунктов пропуска...")
    try:
        auth = HTTPBasicAuth(API_USERNAME, API_PASSWORD)
        response = requests.get(f"{API_BASE_URL}/api/v1/checkpoints", auth=auth, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Получено {data.get('total', 0)} пунктов пропуска")
            
            if data.get('checkpoints'):
                # Показать первый пункт пропуска
                first_checkpoint = data['checkpoints'][0]
                print(f"Пример пункта пропуска:")
                print(f"  ID: {first_checkpoint.get('id', 'N/A')}")
                print(f"  Название: {first_checkpoint.get('name', 'N/A')}")
                print(f"  Страна: {first_checkpoint.get('country', 'N/A')}")
                print(f"  Статус: {first_checkpoint.get('status', 'N/A')}")
            return True
        else:
            print(f"❌ Ошибка: {response.status_code} - {response.text}")
            return False
    except Exception as e:
        print(f"Error: {e}")
        return False

def test_checkpoint_by_id():
    """Тест получения конкретного пункта пропуска"""
    print("\n🔍 Тестирование получения конкретного пункта пропуска...")
    try:
        # Сначала получим список ID
        auth = HTTPBasicAuth(API_USERNAME, API_PASSWORD)
        response = requests.get(f"{API_BASE_URL}/api/v1/checkpoints/ids", auth=auth, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            checkpoint_ids = data.get('ids', [])
            
            if checkpoint_ids:
                # Получим данные первого пункта пропуска
                first_id = checkpoint_ids[0]
                print(f"Получение данных для ID: {first_id}")
                
                response = requests.get(f"{API_BASE_URL}/api/v1/checkpoints/{first_id}", auth=auth, timeout=10)
                if response.status_code == 200:
                    checkpoint_data = response.json()
                    print(f"✅ Получены данные пункта пропуска:")
                    print(f"  ID: {checkpoint_data.get('id', 'N/A')}")
                    print(f"  Название: {checkpoint_data.get('name', 'N/A')}")
                    print(f"  Страна: {checkpoint_data.get('country', 'N/A')}")
                    print(f"  Статус: {checkpoint_data.get('status', 'N/A')}")
                    if 'stats' in checkpoint_data:
                        stats = checkpoint_data['stats']
                        print(f"  Статистика: {stats}")
                    return True
                else:
                    print(f"❌ Ошибка получения данных: {response.status_code}")
                    return False
            else:
                print("⚠️  Нет доступных ID пунктов пропуска")
                return False
        else:
            print(f"❌ Ошибка получения ID: {response.status_code}")
            return False
    except Exception as e:
        print(f"Error: {e}")
        return False

def test_stats_endpoint():
    """Тест получения статистики"""
    print("\n📊 Тестирование получения статистики...")
    try:
        auth = HTTPBasicAuth(API_USERNAME, API_PASSWORD)
        response = requests.get(f"{API_BASE_URL}/api/v1/stats", auth=auth, timeout=10)
        
        if response.status_code == 200:
            data = response.json()
            print(f"✅ Получена статистика:")
            print(f"  Общее количество: {data.get('total_checkpoints', 0)}")
            print(f"  По странам: {data.get('by_country', {})}")
            print(f"  Средняя загрузка: {data.get('average_load', 0)}")
            return True
        else:
            print(f"❌ Ошибка: {response.status_code} - {response.text}")
            return False
    except Exception as e:
        print(f"Error: {e}")
        return False

def test_rate_limiting():
    """Тест rate limiting"""
    print("\n⏱️  Тестирование rate limiting...")
    try:
        auth = HTTPBasicAuth(API_USERNAME, API_PASSWORD)
        
        # Отправляем несколько запросов подряд
        start_time = time.time()
        success_count = 0
        error_count = 0
        
        for i in range(10):
            response = requests.get(f"{API_BASE_URL}/api/v1/checkpoints", auth=auth, timeout=5)
            if response.status_code == 200:
                success_count += 1
            else:
                error_count += 1
                if response.status_code == 429:
                    print(f"✅ Rate limiting работает (429 на запросе {i+1})")
                    break
            time.sleep(0.1)  # Небольшая задержка
        
        elapsed_time = time.time() - start_time
        print(f"Отправлено 10 запросов за {elapsed_time:.2f} секунд")
        print(f"Успешных: {success_count}, Ошибок: {error_count}")
        
        return True
    except Exception as e:
        print(f"Error: {e}")
        return False

def main():
    """Основная функция тестирования"""
    print("🚀 Запуск тестирования Checkpoint API")
    print("=" * 50)
    
    tests = [
        ("Health Check", test_health_check),
        ("Authentication", test_authentication),
        ("Checkpoints List", test_checkpoints_endpoint),
        ("Checkpoint by ID", test_checkpoint_by_id),
        ("Statistics", test_stats_endpoint),
        ("Rate Limiting", test_rate_limiting),
    ]
    
    results = []
    
    for test_name, test_func in tests:
        print(f"\n{'='*20} {test_name} {'='*20}")
        try:
            result = test_func()
            results.append((test_name, result))
        except Exception as e:
            print(f"❌ Критическая ошибка в тесте {test_name}: {e}")
            results.append((test_name, False))
    
    # Итоговый отчет
    print("\n" + "="*50)
    print("📋 ИТОГОВЫЙ ОТЧЕТ")
    print("="*50)
    
    passed = 0
    total = len(results)
    
    for test_name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{test_name:20} {status}")
        if result:
            passed += 1
    
    print(f"\nРезультат: {passed}/{total} тестов пройдено")
    
    if passed == total:
        print("🎉 Все тесты пройдены успешно!")
        return 0
    else:
        print("⚠️  Некоторые тесты не пройдены")
        return 1

if __name__ == "__main__":
    exit(main())


