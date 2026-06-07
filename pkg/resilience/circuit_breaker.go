package resilience

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"

	"go.uber.org/zap"
)

// State represents the circuit breaker state
type State int

const (
	StateClosed State = iota
	StateOpen
	StateHalfOpen
)

var (
	ErrCircuitOpen     = errors.New("circuit breaker is open")
	ErrTooManyRequests = errors.New("too many requests in half-open state")
	ErrTimeout         = errors.New("request timeout")
)

// CircuitBreaker implements the circuit breaker pattern
type CircuitBreaker struct {
	name            string
	maxFailures     int
	resetTimeout    time.Duration
	halfOpenMax     int
	timeout         time.Duration
	onStateChange   func(from, to State)

	mu              sync.RWMutex
	state           State
	failures        int
	lastFailureTime time.Time
	halfOpenCount   int
	successCount    int
	totalRequests   int64
	totalFailures   int64
	logger          *zap.Logger
}

// CircuitBreakerConfig contains configuration for a circuit breaker
type CircuitBreakerConfig struct {
	Name          string
	MaxFailures   int
	ResetTimeout  time.Duration
	HalfOpenMax   int
	Timeout       time.Duration
	OnStateChange func(from, to State)
	Logger        *zap.Logger
}

// NewCircuitBreaker creates a new circuit breaker
func NewCircuitBreaker(config CircuitBreakerConfig) *CircuitBreaker {
	cb := &CircuitBreaker{
		name:          config.Name,
		maxFailures:   config.MaxFailures,
		resetTimeout:  config.ResetTimeout,
		halfOpenMax:   config.HalfOpenMax,
		timeout:       config.Timeout,
		onStateChange: config.OnStateChange,
		state:         StateClosed,
		logger:        config.Logger,
	}

	if cb.maxFailures == 0 {
		cb.maxFailures = 5
	}
	if cb.resetTimeout == 0 {
		cb.resetTimeout = 60 * time.Second
	}
	if cb.halfOpenMax == 0 {
		cb.halfOpenMax = 1
	}
	if cb.timeout == 0 {
		cb.timeout = 10 * time.Second
	}

	return cb
}

// Execute runs a function through the circuit breaker
func (cb *CircuitBreaker) Execute(ctx context.Context, fn func(context.Context) (interface{}, error)) (interface{}, error) {
	if err := cb.canExecute(); err != nil {
		return nil, err
	}

	// Add timeout to context if not already present
	execCtx := ctx
	if cb.timeout > 0 {
		var cancel context.CancelFunc
		execCtx, cancel = context.WithTimeout(ctx, cb.timeout)
		defer cancel()
	}

	// Execute the function
	result, err := fn(execCtx)

	// Update circuit breaker state based on result
	cb.recordResult(err)

	return result, err
}

// ExecuteAsync runs a function asynchronously through the circuit breaker
func (cb *CircuitBreaker) ExecuteAsync(ctx context.Context, fn func(context.Context) (interface{}, error)) <-chan Result {
	resultChan := make(chan Result, 1)

	go func() {
		result, err := cb.Execute(ctx, fn)
		resultChan <- Result{Value: result, Error: err}
		close(resultChan)
	}()

	return resultChan
}

// Result represents an async execution result
type Result struct {
	Value interface{}
	Error error
}

// canExecute checks if the circuit breaker allows execution
func (cb *CircuitBreaker) canExecute() error {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	cb.totalRequests++

	switch cb.state {
	case StateClosed:
		return nil

	case StateOpen:
		// Check if we should transition to half-open
		if time.Since(cb.lastFailureTime) > cb.resetTimeout {
			cb.changeState(StateHalfOpen)
			cb.halfOpenCount = 0
			cb.successCount = 0
			return nil
		}
		return ErrCircuitOpen

	case StateHalfOpen:
		if cb.halfOpenCount >= cb.halfOpenMax {
			return ErrTooManyRequests
		}
		cb.halfOpenCount++
		return nil

	default:
		return fmt.Errorf("unknown circuit breaker state: %d", cb.state)
	}
}

// recordResult records the result of an execution
func (cb *CircuitBreaker) recordResult(err error) {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	if err != nil {
		cb.recordFailure()
	} else {
		cb.recordSuccess()
	}
}

// recordFailure records a failure
func (cb *CircuitBreaker) recordFailure() {
	cb.failures++
	cb.totalFailures++
	cb.lastFailureTime = time.Now()

	switch cb.state {
	case StateClosed:
		if cb.failures >= cb.maxFailures {
			cb.changeState(StateOpen)
			cb.logger.Error("Circuit breaker opened",
				zap.String("name", cb.name),
				zap.Int("failures", cb.failures))
		}

	case StateHalfOpen:
		cb.changeState(StateOpen)
		cb.logger.Warn("Circuit breaker reopened from half-open",
			zap.String("name", cb.name))
	}
}

// recordSuccess records a success
func (cb *CircuitBreaker) recordSuccess() {
	cb.failures = 0

	switch cb.state {
	case StateHalfOpen:
		cb.successCount++
		// Need multiple successes to fully close
		if cb.successCount >= cb.halfOpenMax {
			cb.changeState(StateClosed)
			cb.logger.Info("Circuit breaker closed",
				zap.String("name", cb.name))
		}
	}
}

// changeState changes the circuit breaker state
func (cb *CircuitBreaker) changeState(newState State) {
	oldState := cb.state
	cb.state = newState

	if cb.onStateChange != nil {
		cb.onStateChange(oldState, newState)
	}

	cb.logger.Info("Circuit breaker state changed",
		zap.String("name", cb.name),
		zap.String("from", cb.stateString(oldState)),
		zap.String("to", cb.stateString(newState)))
}

// GetState returns the current state
func (cb *CircuitBreaker) GetState() State {
	cb.mu.RLock()
	defer cb.mu.RUnlock()
	return cb.state
}

// GetMetrics returns circuit breaker metrics
func (cb *CircuitBreaker) GetMetrics() Metrics {
	cb.mu.RLock()
	defer cb.mu.RUnlock()

	return Metrics{
		Name:          cb.name,
		State:         cb.stateString(cb.state),
		TotalRequests: cb.totalRequests,
		TotalFailures: cb.totalFailures,
		CurrentFailures: cb.failures,
		SuccessRate:   cb.calculateSuccessRate(),
	}
}

// Metrics contains circuit breaker metrics
type Metrics struct {
	Name            string  `json:"name"`
	State           string  `json:"state"`
	TotalRequests   int64   `json:"total_requests"`
	TotalFailures   int64   `json:"total_failures"`
	CurrentFailures int     `json:"current_failures"`
	SuccessRate     float64 `json:"success_rate"`
}

// calculateSuccessRate calculates the success rate
func (cb *CircuitBreaker) calculateSuccessRate() float64 {
	if cb.totalRequests == 0 {
		return 1.0
	}
	return float64(cb.totalRequests-cb.totalFailures) / float64(cb.totalRequests)
}

// stateString returns the string representation of a state
func (cb *CircuitBreaker) stateString(state State) string {
	switch state {
	case StateClosed:
		return "closed"
	case StateOpen:
		return "open"
	case StateHalfOpen:
		return "half-open"
	default:
		return "unknown"
	}
}

// Reset resets the circuit breaker
func (cb *CircuitBreaker) Reset() {
	cb.mu.Lock()
	defer cb.mu.Unlock()

	cb.state = StateClosed
	cb.failures = 0
	cb.halfOpenCount = 0
	cb.successCount = 0

	cb.logger.Info("Circuit breaker reset", zap.String("name", cb.name))
}