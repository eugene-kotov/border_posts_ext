import requests
from bs4 import BeautifulSoup
import re
from datetime import datetime
import json
import os
from typing import Dict, List, Optional
import html
import time
import redis
import schedule
import threading

def read_links_from_file(filename: str = 'links.txt') -> List[str]:
    """Чтение ссылок из файла"""
    links = []
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            for line in f:
                link = line.strip()
                if link and link.startswith('http'):
                    links.append(link)
        print(f"Загружено {len(links)} ссылок из {filename}")
        return links
    except FileNotFoundError:
        print(f"Файл {filename} не найден")
        return []
    except Exception as e:
        print(f"Ошибка при чтении файла {filename}: {e}")
        return []

class KeyDBManager:
    """Менеджер для работы с KeyDB"""
    
    def __init__(self, host='localhost', port=6379, db=0, password=None):
        self.host = host
        self.port = port
        self.db = db
        self.password = password
        self.redis_client = None
        self.connect()
    
    def connect(self):
        """Подключение к KeyDB"""
        try:
            self.redis_client = redis.Redis(
                host=self.host,
                port=self.port,
                db=self.db,
                password=self.password,
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5
            )
            # Проверяем подключение
            self.redis_client.ping()
            print(f"✅ Подключение к KeyDB успешно (host: {self.host}, port: {self.port})")
        except Exception as e:
            print(f"❌ Ошибка подключения к KeyDB: {e}")
            self.redis_client = None
    
    def is_connected(self) -> bool:
        """Проверка подключения к KeyDB"""
        if not self.redis_client:
            return False
        try:
            self.redis_client.ping()
            return True
        except (redis.ConnectionError, redis.TimeoutError, OSError):
            return False
    
    def save_checkpoint_data(self, checkpoint_data: Dict) -> bool:
        """Сохранение данных пункта пропуска в KeyDB"""
        if not self.is_connected():
            print("❌ KeyDB не подключен")
            return False
        
        try:
            url = checkpoint_data.get('url', '')
            checkpoint_id = self.extract_checkpoint_id(url)
            
            if not checkpoint_id:
                print(f"❌ Не удалось извлечь ID из URL: {url}")
                return False
            
            # Основные данные пункта пропуска
            key_prefix = f"checkpoint:{checkpoint_id}"
            
            # Сохраняем основную информацию
            basic_info = checkpoint_data.get('basic_info', {})
            if basic_info:
                self.redis_client.hset(f"{key_prefix}:info", mapping=basic_info)
            
            # Сохраняем статистику
            statistics = checkpoint_data.get('statistics', {})
            if statistics:
                self.redis_client.hset(f"{key_prefix}:stats", mapping=statistics)
            
            # Сохраняем данные загруженности
            load_data = checkpoint_data.get('load_data', [])
            if load_data:
                # Очищаем старые данные
                self.redis_client.delete(f"{key_prefix}:load_data")
                # Сохраняем новые данные
                for i, day_data in enumerate(load_data):
                    self.redis_client.hset(f"{key_prefix}:load_data", i, json.dumps(day_data, ensure_ascii=False))
            
            # Метаданные
            metadata = {
                'last_updated': datetime.now().isoformat(),
                'url': url,
                'data_count': len(load_data)
            }
            self.redis_client.hset(f"{key_prefix}:meta", mapping=metadata)
            
            # Добавляем в список всех пунктов пропуска
            self.redis_client.sadd("checkpoints:all", checkpoint_id)
            
            print(f"✅ Данные сохранены в KeyDB: {basic_info.get('name_ru', checkpoint_id)}")
            return True
            
        except Exception as e:
            print(f"❌ Ошибка сохранения в KeyDB: {e}")
            return False
    
    def extract_checkpoint_id(self, url: str) -> str:
        """Извлечение ID пункта пропуска из URL"""
        try:
            # Извлекаем ID из URL вида: .../list/224749863825000000/view
            match = re.search(r'/list/(\d+)/view', url)
            if match:
                return match.group(1)
            return ""
        except (TypeError, AttributeError) as e:
            print(f"⚠️ Ошибка извлечения ID из URL: {e}")
            return ""
    
    def get_all_checkpoints(self) -> List[str]:
        """Получение списка всех ID пунктов пропуска"""
        if not self.is_connected():
            return []
        
        try:
            return list(self.redis_client.smembers("checkpoints:all"))
        except Exception as e:
            print(f"❌ Ошибка получения списка пунктов пропуска: {e}")
            return []
    
    def get_checkpoint_data(self, checkpoint_id: str) -> Optional[Dict]:
        """Получение данных пункта пропуска по ID"""
        if not self.is_connected():
            return None
        
        try:
            key_prefix = f"checkpoint:{checkpoint_id}"
            
            # Получаем основную информацию
            basic_info = self.redis_client.hgetall(f"{key_prefix}:info")
            
            # Получаем статистику
            stats = self.redis_client.hgetall(f"{key_prefix}:stats")
            
            # Получаем данные загруженности
            load_data_raw = self.redis_client.hgetall(f"{key_prefix}:load_data")
            load_data = []
            for i in sorted(load_data_raw.keys(), key=int):
                try:
                    load_data.append(json.loads(load_data_raw[i]))
                except (json.JSONDecodeError, TypeError) as e:
                    print(f"⚠️ Ошибка парсинга load_data[{i}]: {e}")
            
            # Получаем метаданные
            meta = self.redis_client.hgetall(f"{key_prefix}:meta")
            
            return {
                'checkpoint_id': checkpoint_id,
                'basic_info': basic_info,
                'statistics': stats,
                'load_data': load_data,
                'metadata': meta
            }
            
        except Exception as e:
            print(f"❌ Ошибка получения данных пункта пропуска {checkpoint_id}: {e}")
            return None
    
    def get_summary_stats(self) -> Dict:
        """Получение сводной статистики"""
        if not self.is_connected():
            return {}
        
        try:
            all_checkpoints = self.get_all_checkpoints()
            total_checkpoints = len(all_checkpoints)
            
            # Подсчитываем общую статистику
            total_working_days = 0
            total_holidays = 0
            avg_1mrp_sum = 0
            avg_100mrp_sum = 0
            valid_checkpoints = 0
            
            for checkpoint_id in all_checkpoints:
                data = self.get_checkpoint_data(checkpoint_id)
                if data and data.get('statistics'):
                    stats = data['statistics']
                    total_working_days += int(stats.get('working_days', 0))
                    total_holidays += int(stats.get('holidays', 0))
                    
                    if stats.get('avg_1mrp'):
                        avg_1mrp_sum += float(stats['avg_1mrp'])
                        valid_checkpoints += 1
                    
                    if stats.get('avg_100mrp'):
                        avg_100mrp_sum += float(stats['avg_100mrp'])
            
            return {
                'total_checkpoints': total_checkpoints,
                'total_working_days': total_working_days,
                'total_holidays': total_holidays,
                'avg_1mrp_overall': round(avg_1mrp_sum / valid_checkpoints, 1) if valid_checkpoints > 0 else 0,
                'avg_100mrp_overall': round(avg_100mrp_sum / valid_checkpoints, 1) if valid_checkpoints > 0 else 0,
                'last_updated': datetime.now().isoformat()
            }
            
        except Exception as e:
            print(f"❌ Ошибка получения сводной статистики: {e}")
            return {}

class CheckpointWebParser:
    """Парсер для извлечения данных о загруженности пункта пропуска с веб-страницы"""
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'ru-RU,ru;q=0.9,en;q=0.8',
            'Accept-Encoding': 'gzip, deflate, br',
            'Connection': 'keep-alive',
            'Upgrade-Insecure-Requests': '1'
        })
    
    def fetch_page_content(self, url: str, max_retries: int = 3) -> Optional[str]:
        """Загрузка содержимого страницы с повторными попытками"""
        for attempt in range(max_retries):
            try:
                print(f"Попытка {attempt + 1}: Загрузка страницы...")
                # Отключаем SSL проверку для данного запроса
                response = self.session.get(url, timeout=30, verify=False)
                response.raise_for_status()
                
                print(f"Статус ответа: {response.status_code}")
                print(f"Размер контента: {len(response.content)} байт")
                
                # Проверяем кодировку
                if response.encoding:
                    print(f"Кодировка: {response.encoding}")
                else:
                    response.encoding = 'utf-8'
                
                return response.text
                
            except requests.exceptions.SSLError as e:
                print(f"SSL ошибка (попытка {attempt + 1}): {e}")
                print("Попробуйте установить сертификаты или используйте HTTP вместо HTTPS")
                if attempt < max_retries - 1:
                    print("Повторная попытка через 5 секунд...")
                    time.sleep(5)
            except requests.exceptions.RequestException as e:
                print(f"Ошибка при загрузке (попытка {attempt + 1}): {e}")
                if attempt < max_retries - 1:
                    print("Повторная попытка через 5 секунд...")
                    time.sleep(5)
                else:
                    print("Все попытки загрузки исчерпаны")
                    return None
    
    def parse_html_content(self, html_content: str, url: str = None) -> Dict:
        """Парсинг HTML контента"""
        soup = BeautifulSoup(html_content, 'html.parser')
        
        result = {
            'url': url or 'https://cgr.qoldau.kz/ru/registry/checkpoint/list/224749863825000000/view',
            'basic_info': self.parse_basic_info(soup),
            'load_data': self.parse_load_data(soup),
            'parsed_at': datetime.now().isoformat()
        }
        
        # Добавляем статистику
        working_days = [d for d in result['load_data'] if not d.get('is_holiday')]
        holidays = [d for d in result['load_data'] if d.get('is_holiday')]
        
        result['statistics'] = {
            'total_days': len(result['load_data']),
            'working_days': len(working_days),
            'holidays': len(holidays)
        }
        
        if working_days:
            avg_1mrp = sum(d.get('available_1mrp', 0) for d in working_days) / len(working_days)
            avg_100mrp = sum(d.get('available_100mrp', 0) for d in working_days) / len(working_days)
            result['statistics']['avg_1mrp'] = round(avg_1mrp, 1)
            result['statistics']['avg_100mrp'] = round(avg_100mrp, 1)
            result['statistics']['max_1mrp'] = max(d.get('available_1mrp', 0) for d in working_days)
            result['statistics']['min_1mrp'] = min(d.get('available_1mrp', 0) for d in working_days)
            result['statistics']['max_100mrp'] = max(d.get('available_100mrp', 0) for d in working_days)
            result['statistics']['min_100mrp'] = min(d.get('available_100mrp', 0) for d in working_days)
        
        return result
    
    def parse_basic_info(self, soup: BeautifulSoup) -> Dict:
        """Парсинг основной информации"""
        info = {}
        
        try:
            # Названия пункта пропуска
            name_divs = soup.find_all('div', class_='form-control bg-light')
            if len(name_divs) >= 3:
                info['name_ru'] = name_divs[0].get_text(strip=True)
                info['name_kz'] = name_divs[1].get_text(strip=True) 
                info['name_en'] = name_divs[2].get_text(strip=True)
            
            # Статус и страна
            status_divs = soup.find_all('div', class_='form-control bg-light h-100')
            for div in status_divs:
                text = div.get_text(strip=True)
                if 'Активный' in text or 'Действующий' in text:
                    info['status'] = text
                elif any(country in text for country in ['Китай', 'Россия', 'Узбекистан', 'Кыргызстан']):
                    info['border_country'] = text
            
            # Поиск телефона
            phone_pattern = re.compile(r'8-\(\d+\)-\d+-\d+-\d+')
            phone_match = phone_pattern.search(str(soup))
            if phone_match:
                info['phone'] = phone_match.group()
            
            # Дополнительная информация
            labels = soup.find_all('label')
            for label in labels:
                text = label.get_text(strip=True)
                if 'Координаты' in text:
                    next_div = label.find_next('div', class_='form-control bg-light')
                    if next_div:
                        info['coordinates'] = next_div.get_text(strip=True)
                elif 'Режим работы' in text:
                    next_div = label.find_next('div', class_='form-control bg-light')
                    if next_div:
                        info['working_hours'] = next_div.get_text(strip=True)
        
        except Exception as e:
            print(f"Ошибка при парсинге основной информации: {e}")
        
        return info
    
    def parse_load_data(self, soup: BeautifulSoup) -> List[Dict]:
        """Парсинг данных загруженности"""
        load_data = []
        
        try:
            # Ищем контейнер с данными загруженности
            container = soup.find('div', class_='square-chart-container')
            if not container:
                # Альтернативные способы поиска
                container = soup.find('div', id='loadChart') or soup.find('div', class_='chart-container')
            
            if not container:
                print("Контейнер загруженности не найден")
                # Выводим доступные классы для отладки
                all_divs = soup.find_all('div', class_=True)
                classes = set()
                for div in all_divs[:20]:  # Первые 20 для анализа
                    classes.update(div.get('class', []))
                print(f"Найденные CSS классы: {sorted(classes)}")
                return load_data
            
            squares = container.find_all('div', class_='square')
            print(f"Найдено квадратиков: {len(squares)}")
            
            for i, square in enumerate(squares):
                day_data = {'index': i}
                
                # Обработка tooltip
                tooltip = square.get('title', '') or square.get('data-original-title', '') or square.get('data-bs-original-title', '')
                if tooltip:
                    tooltip_decoded = html.unescape(tooltip)
                    day_data.update(self.parse_tooltip(tooltip_decoded))
                
                # Уровень загруженности из CSS классов
                classes = square.get('class', [])
                for cls in classes:
                    if cls.startswith('zag-level-'):
                        try:
                            day_data['load_level'] = int(cls.split('-')[-1])
                        except ValueError:
                            pass
                        break
                    elif cls.startswith('level-'):
                        try:
                            day_data['load_level'] = int(cls.split('-')[-1])
                        except ValueError:
                            pass
                        break
                
                # Цвет для определения загруженности
                style = square.get('style', '')
                if 'background-color' in style:
                    day_data['background_color'] = style
                
                if len(day_data) > 1:  # Если есть данные кроме индекса
                    load_data.append(day_data)
        
        except Exception as e:
            print(f"Ошибка при парсинге загруженности: {e}")
        
        return load_data
    
    def parse_tooltip(self, tooltip: str) -> Dict:
        """Парсинг tooltip с информацией о дне"""
        data = {}
        
        try:
            # Дата
            date_patterns = [
                r'(\d{1,2}\s+\w+\s+\d{4})',  # "1 декабря 2024"
                r'(\d{1,2}\s+\w+)',          # "1 декабря"
                r'(\d{1,2}\.\d{1,2}\.\d{4})', # "01.12.2024"
            ]
            
            for pattern in date_patterns:
                date_match = re.search(pattern, tooltip)
                if date_match:
                    data['date_text'] = date_match.group(1)
                    break
            
            # Проверка на выходной день
            holiday_keywords = ['Выходной день', 'выходной', 'Праздничный день', 'праздник']
            if any(keyword in tooltip for keyword in holiday_keywords):
                data['is_holiday'] = True
                data['available_1mrp'] = 0
                data['available_100mrp'] = 0
            else:
                data['is_holiday'] = False
                
                # Поиск данных о МРП
                mrp_patterns = [
                    (r'за\s*1\s*МРП:\s*(\d+)', 'available_1mrp'),
                    (r'за\s*100\s*МРП:\s*(\d+)', 'available_100mrp'),
                    (r'1\s*МРП.*?(\d+)', 'available_1mrp'),
                    (r'100\s*МРП.*?(\d+)', 'available_100mrp'),
                ]
                
                for pattern, key in mrp_patterns:
                    match = re.search(pattern, tooltip, re.IGNORECASE)
                    if match:
                        data[key] = int(match.group(1))
        
        except Exception as e:
            print(f"Ошибка парсинга tooltip: {e}")
        
        return data
    
    def save_json(self, data: Dict, filename: str = None) -> str:
        """Сохранение данных в JSON файл"""
        if filename is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f'checkpoint_data_{timestamp}.json'
        
        try:
            with open(filename, 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"Данные сохранены в {filename}")
            return filename
        except Exception as e:
            print(f"Ошибка сохранения: {e}")
            return ""
    
    def save_html_backup(self, html_content: str, filename: str = None) -> str:
        """Сохранение HTML для отладки"""
        if filename is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f'checkpoint_backup_{timestamp}.html'
        
        try:
            with open(filename, 'w', encoding='utf-8') as f:
                f.write(html_content)
            print(f"HTML сохранен в {filename}")
            return filename
        except Exception as e:
            print(f"Ошибка сохранения HTML: {e}")
            return ""

def process_single_checkpoint(parser: CheckpointWebParser, keydb_manager: KeyDBManager, url: str, index: int, total: int) -> Dict:
    """Обработка одного пункта пропуска"""
    print(f"\n[{index}/{total}] Обработка: {url}")
    print("-" * 60)
    
    # Загружаем страницу
    html_content = parser.fetch_page_content(url)
    
    if not html_content:
        print(f"❌ Не удалось загрузить страницу {url}")
        return {'url': url, 'error': 'Failed to fetch page', 'success': False}
    
    # Парсим содержимое
    print("Парсинг данных...")
    result = parser.parse_html_content(html_content, url)
    result['success'] = True
    
    # Сохраняем в KeyDB
    if keydb_manager.is_connected():
        saved = keydb_manager.save_checkpoint_data(result)
        if not saved:
            print("⚠️  Не удалось сохранить в KeyDB")
    else:
        print("⚠️  KeyDB не подключен, данные не сохранены")
    
    # Выводим краткие результаты
    basic_info = result.get('basic_info', {})
    if basic_info.get('name_ru'):
        print(f"✅ Пункт пропуска: {basic_info['name_ru']}")
    else:
        print("⚠️  Название не найдено")
    
    stats = result.get('statistics', {})
    print(f"📊 Дней обработано: {stats.get('total_days', 0)} (рабочих: {stats.get('working_days', 0)})")
    
    if stats.get('avg_1mrp'):
        print(f"📈 Среднее за 1 МРП: {stats['avg_1mrp']}")
    
    return result

def update_all_checkpoints(keydb_host='localhost', keydb_port=6379, keydb_password=None):
    """Обновление всех пунктов пропуска"""
    print("\n" + "=" * 60)
    print("🔄 ОБНОВЛЕНИЕ ДАННЫХ ПУНКТОВ ПРОПУСКА")
    print("=" * 60)
    
    parser = CheckpointWebParser()
    keydb_manager = KeyDBManager(host=keydb_host, port=keydb_port, password=keydb_password)
    
    # Читаем ссылки из файла
    links = read_links_from_file('links.txt')
    
    if not links:
        print("❌ Не найдено ссылок для обработки")
        return
    
    print(f"Найдено {len(links)} ссылок для обработки")
    print(f"Время начала: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    # Результаты обработки
    successful = 0
    failed = 0
    
    # Обрабатываем каждую ссылку
    for i, url in enumerate(links, 1):
        try:
            result = process_single_checkpoint(parser, keydb_manager, url, i, len(links))
            
            if result.get('success'):
                successful += 1
            else:
                failed += 1
                
        except Exception as e:
            print(f"❌ Критическая ошибка при обработке {url}: {e}")
            failed += 1
        
        # Небольшая пауза между запросами
        if i < len(links):
            print("⏳ Пауза 2 секунды...")
            time.sleep(2)
    
    # Итоговая статистика
    print("\n" + "=" * 60)
    print("📊 ИТОГОВАЯ СТАТИСТИКА ОБНОВЛЕНИЯ")
    print("=" * 60)
    print(f"✅ Успешно обработано: {successful}")
    print(f"❌ Ошибок: {failed}")
    print(f"📊 Всего ссылок: {len(links)}")
    print(f"Время завершения: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    # Показываем сводную статистику из KeyDB
    if keydb_manager.is_connected():
        summary_stats = keydb_manager.get_summary_stats()
        if summary_stats:
            print(f"\n📈 СВОДНАЯ СТАТИСТИКА ИЗ KEYDB:")
            print(f"- Всего пунктов пропуска: {summary_stats.get('total_checkpoints', 0)}")
            print(f"- Общее количество рабочих дней: {summary_stats.get('total_working_days', 0)}")
            print(f"- Общее количество выходных: {summary_stats.get('total_holidays', 0)}")
            print(f"- Среднее по всем пунктам за 1 МРП: {summary_stats.get('avg_1mrp_overall', 0)}")
            print(f"- Среднее по всем пунктам за 100 МРП: {summary_stats.get('avg_100mrp_overall', 0)}")

def run_scheduler(keydb_host='localhost', keydb_port=6379, keydb_password=None):
    """Запуск планировщика"""
    print("⏰ Планировщик запущен. Обновление каждые 7 минут...")
    
    # Планируем обновление каждые 7 минут
    schedule.every(7).minutes.do(update_all_checkpoints, keydb_host, keydb_port, keydb_password)
    
    # Первое обновление сразу
    print("🚀 Выполняем первое обновление...")
    update_all_checkpoints(keydb_host, keydb_port, keydb_password)
    
    # Запускаем планировщик
    while True:
        schedule.run_pending()
        time.sleep(1)

def main():
    print("Парсер пунктов пропуска CGR с KeyDB")
    print("=" * 50)
    
    # Получаем настройки из переменных окружения
    keydb_host = os.getenv('KEYDB_HOST', 'localhost')
    keydb_port = int(os.getenv('KEYDB_PORT', '6379'))
    keydb_password = os.getenv('KEYDB_PASSWORD', None)
    
    print(f"🔗 Подключение к KeyDB: {keydb_host}:{keydb_port}")
    
    # Проверяем подключение к KeyDB
    keydb_manager = KeyDBManager(host=keydb_host, port=keydb_port, password=keydb_password)
    
    if not keydb_manager.is_connected():
        print("❌ Не удалось подключиться к KeyDB!")
        print("Убедитесь, что KeyDB запущен на localhost:6379")
        return
    
    print("✅ KeyDB подключен успешно")
    print("🔄 Запуск автоматического обновления каждые 7 минут...")
    print("Для остановки нажмите Ctrl+C")
    print()
    
    try:
        # Запускаем планировщик в отдельном потоке
        scheduler_thread = threading.Thread(target=run_scheduler, args=(keydb_host, keydb_port, keydb_password), daemon=True)
        scheduler_thread.start()
        
        # Основной поток ждет
        while True:
            time.sleep(1)
            
    except KeyboardInterrupt:
        print("\n🛑 Остановка парсера...")
        print("👋 До свидания!")

if __name__ == "__main__":
    main()