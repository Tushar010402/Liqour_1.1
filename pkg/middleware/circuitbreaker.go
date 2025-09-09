package middleware

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// CircuitBreakerState represents the state of a circuit breaker
type CircuitBreakerState int

const (
	StateClosed CircuitBreakerState = iota
	StateOpen
	StateHalfOpen
)

func (s CircuitBreakerState) String() string {
	switch s {
	case StateClosed:
		return "CLOSED"
	case StateOpen:
		return "OPEN"
	case StateHalfOpen:
		return "HALF_OPEN"
	default:
		return "UNKNOWN"
	}
}

// CircuitBreakerConfig holds configuration for circuit breaker
type CircuitBreakerConfig struct {
	Name               string        `yaml:"name" json:"name"`
	MaxFailures        int           `yaml:"max_failures" json:"max_failures"`
	ResetTimeout       time.Duration `yaml:"reset_timeout" json:"reset_timeout"`
	SuccessThreshold   int           `yaml:"success_threshold" json:"success_threshold"`
	Timeout            time.Duration `yaml:"timeout" json:"timeout"`
	OnStateChange      func(name string, from, to CircuitBreakerState)
}

// CircuitBreaker implements the circuit breaker pattern
type CircuitBreaker struct {
	config       CircuitBreakerConfig
	state        CircuitBreakerState
	failures     int
	successes    int
	lastFailTime time.Time
	mutex        sync.RWMutex
	logger       *zap.Logger
}

// NewCircuitBreaker creates a new circuit breaker
func NewCircuitBreaker(config CircuitBreakerConfig, logger *zap.Logger) *CircuitBreaker {
	return &CircuitBreaker{
		config: config,
		state:  StateClosed,
		logger: logger,
	}
}

// Execute executes a function with circuit breaker protection
func (cb *CircuitBreaker) Execute(fn func() error) error {
	if !cb.canExecute() {
		return fmt.Errorf("circuit breaker '%s' is open", cb.config.Name)
	}

	// Create a context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), cb.config.Timeout)
	defer cancel()

	// Execute the function in a goroutine
	errCh := make(chan error, 1)
	go func() {
		errCh <- fn()
	}()

	// Wait for either completion or timeout
	select {
	case err := <-errCh:
		if err != nil {
			cb.onFailure()
			return err
		}
		cb.onSuccess()
		return nil
	case <-ctx.Done():
		cb.onFailure()
		return fmt.Errorf("circuit breaker '%s' timeout exceeded", cb.config.Name)
	}
}

// canExecute checks if the function can be executed
func (cb *CircuitBreaker) canExecute() bool {
	cb.mutex.RLock()
	defer cb.mutex.RUnlock()

	switch cb.state {
	case StateClosed:
		return true
	case StateOpen:
		// Check if reset timeout has passed
		if time.Since(cb.lastFailTime) >= cb.config.ResetTimeout {
			cb.mutex.RUnlock()
			cb.mutex.Lock()
			// Double-check after acquiring write lock
			if cb.state == StateOpen && time.Since(cb.lastFailTime) >= cb.config.ResetTimeout {
				cb.setState(StateHalfOpen)
			}
			cb.mutex.Unlock()
			cb.mutex.RLock()
			return cb.state == StateHalfOpen
		}
		return false
	case StateHalfOpen:
		return true
	default:
		return false
	}
}

// onSuccess handles successful execution
func (cb *CircuitBreaker) onSuccess() {
	cb.mutex.Lock()
	defer cb.mutex.Unlock()

	switch cb.state {
	case StateClosed:
		cb.failures = 0
	case StateHalfOpen:
		cb.successes++
		if cb.successes >= cb.config.SuccessThreshold {
			cb.setState(StateClosed)
			cb.failures = 0
			cb.successes = 0
		}
	}
}

// onFailure handles failed execution
func (cb *CircuitBreaker) onFailure() {
	cb.mutex.Lock()
	defer cb.mutex.Unlock()

	cb.failures++
	cb.lastFailTime = time.Now()

	switch cb.state {
	case StateClosed:
		if cb.failures >= cb.config.MaxFailures {
			cb.setState(StateOpen)
		}
	case StateHalfOpen:
		cb.setState(StateOpen)
		cb.successes = 0
	}
}

// setState changes the circuit breaker state
func (cb *CircuitBreaker) setState(newState CircuitBreakerState) {
	oldState := cb.state
	cb.state = newState

	cb.logger.Info("Circuit breaker state changed",
		zap.String("name", cb.config.Name),
		zap.String("from", oldState.String()),
		zap.String("to", newState.String()),
		zap.Int("failures", cb.failures),
	)

	if cb.config.OnStateChange != nil {
		go cb.config.OnStateChange(cb.config.Name, oldState, newState)
	}
}

// GetState returns the current state
func (cb *CircuitBreaker) GetState() CircuitBreakerState {
	cb.mutex.RLock()
	defer cb.mutex.RUnlock()
	return cb.state
}

// GetStats returns circuit breaker statistics
func (cb *CircuitBreaker) GetStats() map[string]interface{} {
	cb.mutex.RLock()
	defer cb.mutex.RUnlock()

	return map[string]interface{}{
		"name":           cb.config.Name,
		"state":          cb.state.String(),
		"failures":       cb.failures,
		"successes":      cb.successes,
		"last_fail_time": cb.lastFailTime,
		"config":         cb.config,
	}
}

// CircuitBreakerManager manages multiple circuit breakers
type CircuitBreakerManager struct {
	breakers map[string]*CircuitBreaker
	mutex    sync.RWMutex
	logger   *zap.Logger
}

// NewCircuitBreakerManager creates a new circuit breaker manager
func NewCircuitBreakerManager(logger *zap.Logger) *CircuitBreakerManager {
	return &CircuitBreakerManager{
		breakers: make(map[string]*CircuitBreaker),
		logger:   logger,
	}
}

// Register registers a new circuit breaker
func (cbm *CircuitBreakerManager) Register(name string, config CircuitBreakerConfig, logger *zap.Logger) {
	cbm.mutex.Lock()
	defer cbm.mutex.Unlock()

	config.Name = name
	cbm.breakers[name] = NewCircuitBreaker(config, logger)
}

// GetBreaker gets a circuit breaker by name
func (cbm *CircuitBreakerManager) GetBreaker(name string) (*CircuitBreaker, error) {
	cbm.mutex.RLock()
	defer cbm.mutex.RUnlock()

	breaker, exists := cbm.breakers[name]
	if !exists {
		return nil, fmt.Errorf("circuit breaker '%s' not found", name)
	}
	return breaker, nil
}

// Execute executes a function with the specified circuit breaker
func (cbm *CircuitBreakerManager) Execute(name string, fn func() error) error {
	breaker, err := cbm.GetBreaker(name)
	if err != nil {
		return err
	}
	return breaker.Execute(fn)
}

// GetAllStats returns statistics for all circuit breakers
func (cbm *CircuitBreakerManager) GetAllStats() map[string]interface{} {
	cbm.mutex.RLock()
	defer cbm.mutex.RUnlock()

	stats := make(map[string]interface{})
	for name, breaker := range cbm.breakers {
		stats[name] = breaker.GetStats()
	}
	return stats
}

// CircuitBreakerMiddleware creates middleware for HTTP circuit breaker
func CircuitBreakerMiddleware(manager *CircuitBreakerManager, breakerName string) gin.HandlerFunc {
	return gin.HandlerFunc(func(c *gin.Context) {
		err := manager.Execute(breakerName, func() error {
			c.Next()
			
			// Consider 5xx errors as failures
			if c.Writer.Status() >= 500 {
				return fmt.Errorf("HTTP %d error", c.Writer.Status())
			}
			return nil
		})

		if err != nil {
			// If circuit breaker is open, return 503
			if errors.Is(err, fmt.Errorf("circuit breaker '%s' is open", breakerName)) {
				c.JSON(503, gin.H{
					"error":   "Service temporarily unavailable",
					"message": "Circuit breaker is open",
					"code":    "CIRCUIT_BREAKER_OPEN",
				})
				c.Abort()
				return
			}
		}
	})
}

// Database circuit breaker wrapper
type DBCircuitBreaker struct {
	manager *CircuitBreakerManager
}

// NewDBCircuitBreaker creates a database circuit breaker
func NewDBCircuitBreaker(manager *CircuitBreakerManager, config CircuitBreakerConfig, logger *zap.Logger) *DBCircuitBreaker {
	manager.Register("database", config, logger)
	return &DBCircuitBreaker{manager: manager}
}

// Execute executes a database operation with circuit breaker protection
func (db *DBCircuitBreaker) Execute(operation func() error) error {
	return db.manager.Execute("database", operation)
}

// Redis circuit breaker wrapper
type RedisCircuitBreaker struct {
	manager *CircuitBreakerManager
}

// NewRedisCircuitBreaker creates a Redis circuit breaker
func NewRedisCircuitBreaker(manager *CircuitBreakerManager, config CircuitBreakerConfig, logger *zap.Logger) *RedisCircuitBreaker {
	manager.Register("redis", config, logger)
	return &RedisCircuitBreaker{manager: manager}
}

// Execute executes a Redis operation with circuit breaker protection
func (r *RedisCircuitBreaker) Execute(operation func() error) error {
	return r.manager.Execute("redis", operation)
}