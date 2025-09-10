#!/usr/bin/env python3
"""
Простой пример использования Checkpoint API
"""

import requests
import json
from requests.auth import HTTPBasicAuth

# Конфигурация
API_BASE_URL = "http://localhost"
API_USERNAME = "admin"
API_PASSWORD = "checkpoint2025"  # Измените на ваш пароль

def get_health_status():
    """Получить статус здоровья системы"""
    try:
        response = requests.get(f"{API_BASE_URL}/health", timeout=10)
        if response.status_code == 200:
            return response.json()
        else:
            return None
    except Exception as e:
        print(f"Ошибка получения статуса: {e}")
        return None

def get_all_checkpoints():
    """Получить все пункты пропуска"""
    try:
        auth = HTTPBasicAuth(API_USERNAME, API_PASSWORD)
        response = requests.get(f"{API_BASE_URL}/api/v1/checkpoints", auth=auth, timeout=10)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Ошибка получения данных: {response.status_code}")
            return None
    except Exception as e:
        print(f"Ошибка: {e}")
        return None

def get_checkpoint_by_id(checkpoint_id):
    """Получить данные конкретного пункта пропуска"""
    try:
        auth = HTTPBasicAuth(API_USERNAME, API_PASSWORD)
        response = requests.get(f"{API_BASE_URL}/api/v1/checkpoints/{checkpoint_id}", auth=auth, timeout=10)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Ошибка получения данных для ID {checkpoint_id}: {response.status_code}")
            return None
    except Exception as e:
        print(f"Ошибка: {e}")
        return None

def get_statistics():
    """Получить статистику"""
    try:
        auth = HTTPBasicAuth(API_USERNAME, API_PASSWORD)
        response = requests.get(f"{API_BASE_URL}/api/v1/stats", auth=auth, timeout=10)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f"Ошибка получения статистики: {response.status_code}")
            return None
    except Exception as e:
        print(f"Ошибка: {e}")
        return None

def main():
    """Основная функция"""
    print("🔍 Проверка статуса системы...")
    
    # Проверяем здоровье системы
    health = get_health_status()
    if health:
        print(f"✅ Система работает: {health['status']}")
        print(f"📊 KeyDB: {health['keydb_status']}")
        print(f"🕐 Время: {health['timestamp']}")
    else:
        print("❌ Система недоступна")
        return
    
    print("\n📋 Получение списка пунктов пропуска...")
    
    # Получаем все пункты пропуска
    checkpoints_data = get_all_checkpoints()
    if checkpoints_data:
        total = checkpoints_data.get('total', 0)
        print(f"✅ Найдено {total} пунктов пропуска")
        
        if total > 0:
            # Показываем первые 3 пункта пропуска
            checkpoints = checkpoints_data.get('checkpoints', [])
            print("\n📝 Первые пункты пропуска:")
            for i, checkpoint in enumerate(checkpoints[:3]):
                print(f"  {i+1}. {checkpoint.get('name', 'N/A')} ({checkpoint.get('country', 'N/A')})")
            
            # Получаем детальную информацию о первом пункте пропуска
            if checkpoints:
                first_checkpoint = checkpoints[0]
                checkpoint_id = first_checkpoint.get('id')
                
                print(f"\n🔍 Детальная информация о пункте пропуска: {first_checkpoint.get('name', 'N/A')}")
                detailed_data = get_checkpoint_by_id(checkpoint_id)
                if detailed_data:
                    print(f"  ID: {detailed_data.get('id', 'N/A')}")
                    print(f"  Название: {detailed_data.get('name', 'N/A')}")
                    print(f"  Страна: {detailed_data.get('country', 'N/A')}")
                    print(f"  Статус: {detailed_data.get('status', 'N/A')}")
                    
                    if 'stats' in detailed_data:
                        stats = detailed_data['stats']
                        print(f"  Статистика: {stats}")
        else:
            print("⚠️  Нет данных о пунктах пропуска")
    else:
        print("❌ Не удалось получить данные о пунктах пропуска")
    
    print("\n📊 Получение статистики...")
    
    # Получаем статистику
    stats = get_statistics()
    if stats:
        print("✅ Статистика получена:")
        print(f"  Общее количество: {stats.get('total_checkpoints', 0)}")
        
        by_country = stats.get('by_country', {})
        if by_country:
            print("  По странам:")
            for country, count in by_country.items():
                print(f"    {country}: {count}")
        
        print(f"  Средняя загрузка: {stats.get('average_load', 0)}")
        
        # Показываем топ загруженных пунктов пропуска
        top_loaded = stats.get('top_loaded', [])
        if top_loaded:
            print("  Топ загруженных:")
            for i, checkpoint in enumerate(top_loaded[:3]):
                print(f"    {i+1}. {checkpoint.get('name', 'N/A')}: {checkpoint.get('load', 0)}")
    else:
        print("❌ Не удалось получить статистику")

if __name__ == "__main__":
    main()


