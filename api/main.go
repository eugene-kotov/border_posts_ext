package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
	"golang.org/x/time/rate"
)

// Config содержит конфигурацию приложения
type Config struct {
	Port         string
	KeyDBHost    string
	KeyDBPort    string
	KeyDBPassword string
	AuthUsername string
	AuthPassword string
	RateLimit    int
}

// CheckpointInfo основная информация о пункте пропуска
type CheckpointInfo struct {
	NameRU        string `json:"name_ru"`
	NameKZ        string `json:"name_kz"`
	NameEN        string `json:"name_en"`
	Status        string `json:"status"`
	BorderCountry string `json:"border_country"`
	Phone         string `json:"phone"`
	Coordinates   string `json:"coordinates"`
	WorkingHours  string `json:"working_hours"`
}

// CheckpointStats статистика пункта пропуска
type CheckpointStats struct {
	TotalDays   int     `json:"total_days"`
	WorkingDays int     `json:"working_days"`
	Holidays    int     `json:"holidays"`
	Avg1MRP     float64 `json:"avg_1mrp"`
	Avg100MRP   float64 `json:"avg_100mrp"`
	Max1MRP     int     `json:"max_1mrp"`
	Min1MRP     int     `json:"min_1mrp"`
	Max100MRP   int     `json:"max_100mrp"`
	Min100MRP   int     `json:"min_100mrp"`
}

// LoadData данные загруженности за день
type LoadData struct {
	Index         int    `json:"index"`
	DateText      string `json:"date_text"`
	IsHoliday     bool   `json:"is_holiday"`
	Available1MRP int    `json:"available_1mrp"`
	Available100MRP int  `json:"available_100mrp"`
	LoadLevel     int    `json:"load_level"`
}

// CheckpointMetadata метаданные пункта пропуска
type CheckpointMetadata struct {
	LastUpdated string `json:"last_updated"`
	URL         string `json:"url"`
	DataCount   int    `json:"data_count"`
}

// Checkpoint полная информация о пункте пропуска
type Checkpoint struct {
	ID       string              `json:"id"`
	Info     CheckpointInfo      `json:"info"`
	Stats    CheckpointStats     `json:"stats"`
	LoadData []LoadData          `json:"load_data"`
	Metadata CheckpointMetadata  `json:"metadata"`
}

// SummaryStats сводная статистика
type SummaryStats struct {
	TotalCheckpoints    int     `json:"total_checkpoints"`
	TotalWorkingDays    int     `json:"total_working_days"`
	TotalHolidays       int     `json:"total_holidays"`
	Avg1MRPOverall      float64 `json:"avg_1mrp_overall"`
	Avg100MRPOverall    float64 `json:"avg_100mrp_overall"`
	LastUpdated         string  `json:"last_updated"`
}

// HealthResponse ответ health check
type HealthResponse struct {
	Status    string `json:"status"`
	Timestamp string `json:"timestamp"`
	KeyDB     string `json:"keydb_status"`
}

// KeyDBService сервис для работы с KeyDB
type KeyDBService struct {
	client *redis.Client
	ctx    context.Context
}

// NewKeyDBService создает новый сервис KeyDB
func NewKeyDBService(host, port, password string) *KeyDBService {
	rdb := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", host, port),
		Password: password,
		DB:       0,
	})

	return &KeyDBService{
		client: rdb,
		ctx:    context.Background(),
	}
}

// Ping проверяет подключение к KeyDB
func (k *KeyDBService) Ping() error {
	return k.client.Ping(k.ctx).Err()
}

// isConnected проверяет, подключен ли сервис к KeyDB
func (k *KeyDBService) isConnected() bool {
	return k.client != nil && k.Ping() == nil
}

// GetAllCheckpointIDs получает все ID пунктов пропуска
func (k *KeyDBService) GetAllCheckpointIDs() ([]string, error) {
	return k.client.SMembers(k.ctx, "checkpoints:all").Result()
}

// GetCheckpoint получает данные пункта пропуска по ID
func (k *KeyDBService) GetCheckpoint(id string) (*Checkpoint, error) {
	checkpoint := &Checkpoint{ID: id}

	// Получаем основную информацию
	infoData, err := k.client.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:info", id)).Result()
	if err != nil {
		return nil, err
	}
	
	checkpoint.Info = CheckpointInfo{
		NameRU:        infoData["name_ru"],
		NameKZ:        infoData["name_kz"],
		NameEN:        infoData["name_en"],
		Status:        infoData["status"],
		BorderCountry: infoData["border_country"],
		Phone:         infoData["phone"],
		Coordinates:   infoData["coordinates"],
		WorkingHours:  infoData["working_hours"],
	}

	// Получаем статистику
	statsData, err := k.client.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:stats", id)).Result()
	if err != nil {
		return nil, err
	}

	totalDays, _ := strconv.Atoi(statsData["total_days"])
	workingDays, _ := strconv.Atoi(statsData["working_days"])
	holidays, _ := strconv.Atoi(statsData["holidays"])
	avg1MRP, _ := strconv.ParseFloat(statsData["avg_1mrp"], 64)
	avg100MRP, _ := strconv.ParseFloat(statsData["avg_100mrp"], 64)
	max1MRP, _ := strconv.Atoi(statsData["max_1mrp"])
	min1MRP, _ := strconv.Atoi(statsData["min_1mrp"])
	max100MRP, _ := strconv.Atoi(statsData["max_100mrp"])
	min100MRP, _ := strconv.Atoi(statsData["min_100mrp"])

	checkpoint.Stats = CheckpointStats{
		TotalDays:   totalDays,
		WorkingDays: workingDays,
		Holidays:    holidays,
		Avg1MRP:     avg1MRP,
		Avg100MRP:   avg100MRP,
		Max1MRP:     max1MRP,
		Min1MRP:     min1MRP,
		Max100MRP:   max100MRP,
		Min100MRP:   min100MRP,
	}

	// Получаем данные загруженности
	loadDataRaw, err := k.client.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:load_data", id)).Result()
	if err != nil {
		return nil, err
	}

	var loadData []LoadData
	for i := 0; i < len(loadDataRaw); i++ {
		dayDataStr := loadDataRaw[strconv.Itoa(i)]
		var dayData LoadData
		if err := json.Unmarshal([]byte(dayDataStr), &dayData); err == nil {
			loadData = append(loadData, dayData)
		}
	}
	checkpoint.LoadData = loadData

	// Получаем метаданные
	metaData, err := k.client.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:meta", id)).Result()
	if err != nil {
		return nil, err
	}

	dataCount, _ := strconv.Atoi(metaData["data_count"])
	checkpoint.Metadata = CheckpointMetadata{
		LastUpdated: metaData["last_updated"],
		URL:         metaData["url"],
		DataCount:   dataCount,
	}

	return checkpoint, nil
}

// GetSummaryStats получает сводную статистику
func (k *KeyDBService) GetSummaryStats() (*SummaryStats, error) {
	allIDs, err := k.GetAllCheckpointIDs()
	if err != nil {
		return nil, err
	}

	stats := &SummaryStats{
		TotalCheckpoints: len(allIDs),
		LastUpdated:      time.Now().Format(time.RFC3339),
	}

	var totalWorkingDays, totalHolidays int
	var avg1MRPSum, avg100MRPSum float64
	var validCheckpoints int

	for _, id := range allIDs {
		checkpoint, err := k.GetCheckpoint(id)
		if err != nil {
			continue
		}

		totalWorkingDays += checkpoint.Stats.WorkingDays
		totalHolidays += checkpoint.Stats.Holidays

		if checkpoint.Stats.Avg1MRP > 0 {
			avg1MRPSum += checkpoint.Stats.Avg1MRP
			validCheckpoints++
		}

		if checkpoint.Stats.Avg100MRP > 0 {
			avg100MRPSum += checkpoint.Stats.Avg100MRP
		}
	}

	stats.TotalWorkingDays = totalWorkingDays
	stats.TotalHolidays = totalHolidays

	if validCheckpoints > 0 {
		stats.Avg1MRPOverall = avg1MRPSum / float64(validCheckpoints)
		stats.Avg100MRPOverall = avg100MRPSum / float64(validCheckpoints)
	}

	return stats, nil
}

// RateLimiterMiddleware middleware для ограничения скорости запросов
func RateLimiterMiddleware(requestsPerMinute int) gin.HandlerFunc {
	limiter := rate.NewLimiter(rate.Limit(requestsPerMinute/60.0), requestsPerMinute)
	
	return func(c *gin.Context) {
		if !limiter.Allow() {
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error": "Rate limit exceeded",
				"limit": requestsPerMinute,
			})
			c.Abort()
			return
		}
		c.Next()
	}
}

// BasicAuthMiddleware middleware для Basic Authentication
func BasicAuthMiddleware(username, password string) gin.HandlerFunc {
	return gin.BasicAuth(gin.Accounts{
		username: password,
	})
}

// loadConfig загружает конфигурацию из переменных окружения
func loadConfig() *Config {
	return &Config{
		Port:         getEnv("PORT", "8080"),
		KeyDBHost:    getEnv("KEYDB_HOST", "localhost"),
		KeyDBPort:    getEnv("KEYDB_PORT", "6379"),
		KeyDBPassword: getEnv("KEYDB_PASSWORD", ""),
		AuthUsername: getEnv("AUTH_USERNAME", "admin"),
		AuthPassword: getEnv("AUTH_PASSWORD", "password"),
		RateLimit:    getEnvInt("RATE_LIMIT", 3000),
	}
}

// getEnv получает переменную окружения или возвращает значение по умолчанию
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

// getEnvInt получает переменную окружения как int или возвращает значение по умолчанию
func getEnvInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

func main() {
	config := loadConfig()

	// Создаем сервис KeyDB
	keydbService := NewKeyDBService(config.KeyDBHost, config.KeyDBPort, config.KeyDBPassword)

	// Проверяем подключение к KeyDB (не падаем при ошибке)
	if err := keydbService.Ping(); err != nil {
		log.Printf("⚠️  Warning: Failed to connect to KeyDB: %v", err)
		log.Println("🔄 API will start but KeyDB-dependent endpoints will return errors")
	} else {
		log.Println("✅ Connected to KeyDB successfully")
	}

	// Настраиваем Gin
	gin.SetMode(gin.ReleaseMode)
	r := gin.Default()

	// Health check endpoint (без авторизации)
	r.GET("/health", func(c *gin.Context) {
		keydbStatus := "connected"
		if err := keydbService.Ping(); err != nil {
			keydbStatus = "disconnected"
		}

		c.JSON(http.StatusOK, HealthResponse{
			Status:    "healthy",
			Timestamp: time.Now().Format(time.RFC3339),
			KeyDB:     keydbStatus,
		})
	})

	// API endpoints с авторизацией
	api := r.Group("/api/v1")
	api.Use(RateLimiterMiddleware(config.RateLimit))
	api.Use(BasicAuthMiddleware(config.AuthUsername, config.AuthPassword))

	// Получить все пункты пропуска
	api.GET("/checkpoints", func(c *gin.Context) {
		if !keydbService.isConnected() {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error": "KeyDB service unavailable",
				"message": "Database connection is not available",
			})
			return
		}

		ids, err := keydbService.GetAllCheckpointIDs()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		var checkpoints []Checkpoint
		for _, id := range ids {
			checkpoint, err := keydbService.GetCheckpoint(id)
			if err != nil {
				log.Printf("Error getting checkpoint %s: %v", id, err)
				continue
			}
			checkpoints = append(checkpoints, *checkpoint)
		}

		c.JSON(http.StatusOK, gin.H{
			"checkpoints": checkpoints,
			"total":       len(checkpoints),
		})
	})

	// Получить конкретный пункт пропуска
	api.GET("/checkpoints/:id", func(c *gin.Context) {
		if !keydbService.isConnected() {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error": "KeyDB service unavailable",
				"message": "Database connection is not available",
			})
			return
		}

		id := c.Param("id")
		checkpoint, err := keydbService.GetCheckpoint(id)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "Checkpoint not found"})
			return
		}

		c.JSON(http.StatusOK, checkpoint)
	})

	// Получить сводную статистику
	api.GET("/stats", func(c *gin.Context) {
		if !keydbService.isConnected() {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error": "KeyDB service unavailable",
				"message": "Database connection is not available",
			})
			return
		}

		stats, err := keydbService.GetSummaryStats()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, stats)
	})

	// Получить список ID пунктов пропуска
	api.GET("/checkpoints/ids", func(c *gin.Context) {
		if !keydbService.isConnected() {
			c.JSON(http.StatusServiceUnavailable, gin.H{
				"error": "KeyDB service unavailable",
				"message": "Database connection is not available",
			})
			return
		}

		ids, err := keydbService.GetAllCheckpointIDs()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"ids":   ids,
			"total": len(ids),
		})
	})

	log.Printf("🚀 Server starting on port %s", config.Port)
	log.Printf("📊 Rate limit: %d requests per minute", config.RateLimit)
	log.Printf("🔐 Basic auth: %s", config.AuthUsername)
	
	if err := r.Run(":" + config.Port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
