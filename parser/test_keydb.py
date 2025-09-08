#!/usr/bin/env python3
"""
Тестовый скрипт для проверки подключения к KeyDB
"""

import redis
from datetime import datetime

def test_keydb_connection():
    """Тестирование подключения к KeyDB"""
    print("🔍 Тестирование подключения к KeyDB...")
    print("=" * 50)
    
    try:
        # Подключение к KeyDB
        client = redis.Redis(
            host='localhost',
            port=6379,
            db=0,
            decode_responses=True,
            socket_connect_timeout=5,
            socket_timeout=5
        )
        
        # Проверяем подключение
        client.ping()
        print("✅ Подключение к KeyDB успешно!")
        
        # Тестируем базовые операции
        test_key = "test:connection"
        test_value = f"Тест подключения - {datetime.now().isoformat()}"
        
        # Записываем тестовое значение
        client.set(test_key, test_value)
        print(f"✅ Запись тестового значения: {test_key}")
        
        # Читаем тестовое значение
        retrieved_value = client.get(test_key)
        print(f"✅ Чтение тестового значения: {retrieved_value}")
        
        # Проверяем совпадение
        if retrieved_value == test_value:
            print("✅ Значения совпадают - KeyDB работает корректно!")
        else:
            print("❌ Значения не совпадают!")
        
        # Удаляем тестовое значение
        client.delete(test_key)
        print("✅ Тестовое значение удалено")
        
        # Показываем информацию о сервере
        info = client.info()
        print(f"\n📊 Информация о KeyDB сервере:")
        print(f"- Версия: {info.get('redis_version', 'Неизвестно')}")
        print(f"- Режим: {info.get('redis_mode', 'Неизвестно')}")
        print(f"- Использованная память: {info.get('used_memory_human', 'Неизвестно')}")
        print(f"- Подключенные клиенты: {info.get('connected_clients', 'Неизвестно')}")
        
        return True
        
    except redis.ConnectionError as e:
        print(f"❌ Ошибка подключения к KeyDB: {e}")
        print("💡 Убедитесь, что KeyDB запущен на localhost:6379")
        return False
        
    except Exception as e:
        print(f"❌ Неожиданная ошибка: {e}")
        return False

if __name__ == "__main__":
    success = test_keydb_connection()
    
    if success:
        print("\n🎉 KeyDB готов к работе!")
        print("Теперь можно запускать основной парсер: python new_checkpoint_data.py")
    else:
        print("\n💡 Для запуска KeyDB:")
        print("1. Установите KeyDB: https://docs.keydb.dev/docs/installation/")
        print("2. Запустите сервер: keydb-server")
        print("3. Повторите тест: python test_keydb.py")
