package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
)

// Config содержит конфигурацию приложения
type Config struct {
	Port         string
	KeyDBHost    string
	KeyDBPort    string
	KeyDBPassword string
	AuthUsername string
	AuthPassword string
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

// GetCheckpoint получает данные пункта пропуска по ID (Pipeline: 1 round-trip, 4 команды)
func (k *KeyDBService) GetCheckpoint(id string) (*Checkpoint, error) {
	pipe := k.client.Pipeline()

	infoCmd := pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:info", id))
	statsCmd := pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:stats", id))
	loadCmd := pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:load_data", id))
	metaCmd := pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:meta", id))

	if _, err := pipe.Exec(k.ctx); err != nil && err != redis.Nil {
		return nil, err
	}

	return parseCheckpointFromResults(id, infoCmd.Val(), statsCmd.Val(), loadCmd.Val(), metaCmd.Val()), nil
}

// GetAllCheckpoints получает все пункты пропуска одним Pipeline (решает N+1)
func (k *KeyDBService) GetAllCheckpoints() ([]Checkpoint, error) {
	ids, err := k.GetAllCheckpointIDs()
	if err != nil {
		return nil, err
	}

	if len(ids) == 0 {
		return []Checkpoint{}, nil
	}

	// Один Pipeline = один round-trip для всех checkpoints
	pipe := k.client.Pipeline()

	type checkpointCmds struct {
		info  *redis.StringStringMapCmd
		stats *redis.StringStringMapCmd
		load  *redis.StringStringMapCmd
		meta  *redis.StringStringMapCmd
	}

	cmds := make([]checkpointCmds, len(ids))
	for i, id := range ids {
		cmds[i] = checkpointCmds{
			info:  pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:info", id)),
			stats: pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:stats", id)),
			load:  pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:load_data", id)),
			meta:  pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:meta", id)),
		}
	}

	if _, err := pipe.Exec(k.ctx); err != nil && err != redis.Nil {
		return nil, err
	}

	checkpoints := make([]Checkpoint, 0, len(ids))
	for i, id := range ids {
		cp := parseCheckpointFromResults(id, cmds[i].info.Val(), cmds[i].stats.Val(), cmds[i].load.Val(), cmds[i].meta.Val())
		checkpoints = append(checkpoints, *cp)
	}

	return checkpoints, nil
}

// parseCheckpointFromResults парсит данные checkpoint из результатов HGETALL
func parseCheckpointFromResults(id string, infoData, statsData, loadDataRaw, metaData map[string]string) *Checkpoint {
	checkpoint := &Checkpoint{ID: id}

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

	var loadData []LoadData
	for i := 0; i < len(loadDataRaw); i++ {
		dayDataStr := loadDataRaw[strconv.Itoa(i)]
		var dayData LoadData
		if err := json.Unmarshal([]byte(dayDataStr), &dayData); err == nil {
			loadData = append(loadData, dayData)
		}
	}
	checkpoint.LoadData = loadData

	dataCount, _ := strconv.Atoi(metaData["data_count"])
	checkpoint.Metadata = CheckpointMetadata{
		LastUpdated: metaData["last_updated"],
		URL:         metaData["url"],
		DataCount:   dataCount,
	}

	return checkpoint
}

// GetSummaryStats получает сводную статистику (Pipeline: загружает только stats, не load_data/meta)
func (k *KeyDBService) GetSummaryStats() (*SummaryStats, error) {
	allIDs, err := k.GetAllCheckpointIDs()
	if err != nil {
		return nil, err
	}

	stats := &SummaryStats{
		TotalCheckpoints: len(allIDs),
		LastUpdated:      time.Now().Format(time.RFC3339),
	}

	if len(allIDs) == 0 {
		return stats, nil
	}

	// Pipeline: загружаем ТОЛЬКО stats хэши (не info, load_data, meta)
	pipe := k.client.Pipeline()
	statsCmds := make([]*redis.StringStringMapCmd, len(allIDs))
	for i, id := range allIDs {
		statsCmds[i] = pipe.HGetAll(k.ctx, fmt.Sprintf("checkpoint:%s:stats", id))
	}

	if _, err := pipe.Exec(k.ctx); err != nil && err != redis.Nil {
		return nil, err
	}

	var totalWorkingDays, totalHolidays int
	var avg1MRPSum, avg100MRPSum float64
	var validCheckpoints int

	for _, cmd := range statsCmds {
		statsData := cmd.Val()
		workingDays, _ := strconv.Atoi(statsData["working_days"])
		holidays, _ := strconv.Atoi(statsData["holidays"])
		avg1MRP, _ := strconv.ParseFloat(statsData["avg_1mrp"], 64)
		avg100MRP, _ := strconv.ParseFloat(statsData["avg_100mrp"], 64)

		totalWorkingDays += workingDays
		totalHolidays += holidays

		if avg1MRP > 0 {
			avg1MRPSum += avg1MRP
			validCheckpoints++
		}

		if avg100MRP > 0 {
			avg100MRPSum += avg100MRP
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

// BasicAuthMiddleware middleware для Basic Authentication
func BasicAuthMiddleware(username, password string) gin.HandlerFunc {
	return gin.BasicAuth(gin.Accounts{
		username: password,
	})
}

// loadConfig загружает конфигурацию из переменных окружения
func loadConfig() *Config {
	cfg := &Config{
		Port:          getEnv("PORT", "8080"),
		KeyDBHost:     getEnv("KEYDB_HOST", "localhost"),
		KeyDBPort:     getEnv("KEYDB_PORT", "6379"),
		KeyDBPassword: getEnv("KEYDB_PASSWORD", ""),
		AuthUsername:  os.Getenv("AUTH_USERNAME"),
		AuthPassword:  os.Getenv("AUTH_PASSWORD"),
	}

	if cfg.AuthUsername == "" || cfg.AuthPassword == "" {
		slog.Error("AUTH_USERNAME and AUTH_PASSWORD environment variables are required")
		os.Exit(1)
	}

	return cfg
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
	// Инициализация structured logging (JSON)
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	config := loadConfig()

	// Создаем сервис KeyDB
	keydbService := NewKeyDBService(config.KeyDBHost, config.KeyDBPort, config.KeyDBPassword)

	// Проверяем подключение к KeyDB (не падаем при ошибке)
	if err := keydbService.Ping(); err != nil {
		slog.Warn("Failed to connect to KeyDB", "error", err)
		slog.Info("API will start but KeyDB-dependent endpoints will return errors")
	} else {
		slog.Info("Connected to KeyDB", "host", config.KeyDBHost, "port", config.KeyDBPort)
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

		checkpoints, err := keydbService.GetAllCheckpoints()
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
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

	slog.Info("Server starting", "port", config.Port, "auth_user", config.AuthUsername)

	// HTTP сервер с graceful shutdown
	srv := &http.Server{
		Addr:    ":" + config.Port,
		Handler: r,
	}

	// Запускаем сервер в горутине
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("Failed to start server", "error", err)
			os.Exit(1)
		}
	}()

	// Ожидаем сигнал завершения
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	slog.Info("Shutting down gracefully", "signal", sig.String())

	// Даём 5 секунд на завершение in-flight запросов
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		slog.Warn("Server forced to shutdown", "error", err)
	}

	// Закрываем KeyDB соединение
	if err := keydbService.client.Close(); err != nil {
		slog.Warn("KeyDB connection close error", "error", err)
	}

	slog.Info("Server stopped")
}