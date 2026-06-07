package resilience

import (
	"context"
	"errors"
	"math"
	"math/rand"
	"time"

	"go.uber.org/zap"
)

// RetryPolicy defines the retry behavior
type RetryPolicy struct {
	MaxAttempts     int
	InitialDelay    time.Duration
	MaxDelay        time.Duration
	BackoffFactor   float64
	Jitter          bool
	RetryableErrors func(error) bool
	OnRetry         func(attempt int, err error)
	Logger          *zap.Logger
}

// DefaultRetryPolicy returns a default retry policy
func DefaultRetryPolicy() *RetryPolicy {
	return &RetryPolicy{
		MaxAttempts:   3,
		InitialDelay:  100 * time.Millisecond,
		MaxDelay:      10 * time.Second,
		BackoffFactor: 2.0,
		Jitter:        true,
		RetryableErrors: func(err error) bool {
			// Default: retry on all errors except context cancellation
			return !errors.Is(err, context.Canceled)
		},
	}
}

// Retry executes a function with retry logic
func Retry(ctx context.Context, policy *RetryPolicy, fn func(context.Context) error) error {
	if policy == nil {
		policy = DefaultRetryPolicy()
	}

	var lastErr error
	delay := policy.InitialDelay

	for attempt := 1; attempt <= policy.MaxAttempts; attempt++ {
		// Execute the function
		err := fn(ctx)

		// Success
		if err == nil {
			if policy.Logger != nil {
				policy.Logger.Debug("Operation succeeded",
					zap.Int("attempt", attempt))
			}
			return nil
		}

		lastErr = err

		// Check if we should retry
		if !policy.RetryableErrors(err) {
			if policy.Logger != nil {
				policy.Logger.Debug("Error not retryable",
					zap.Error(err),
					zap.Int("attempt", attempt))
			}
			return err
		}

		// Last attempt failed
		if attempt == policy.MaxAttempts {
			if policy.Logger != nil {
				policy.Logger.Error("All retry attempts exhausted",
					zap.Error(err),
					zap.Int("attempts", policy.MaxAttempts))
			}
			return lastErr
		}

		// Call retry callback if provided
		if policy.OnRetry != nil {
			policy.OnRetry(attempt, err)
		}

		// Calculate next delay with exponential backoff
		if policy.BackoffFactor > 1 {
			delay = time.Duration(float64(delay) * policy.BackoffFactor)
		}

		// Apply max delay cap
		if delay > policy.MaxDelay {
			delay = policy.MaxDelay
		}

		// Add jitter to prevent thundering herd
		actualDelay := delay
		if policy.Jitter {
			jitter := time.Duration(rand.Float64() * float64(delay) * 0.1)
			actualDelay = delay + jitter
		}

		if policy.Logger != nil {
			policy.Logger.Info("Retrying after delay",
				zap.Int("attempt", attempt),
				zap.Duration("delay", actualDelay),
				zap.Error(err))
		}

		// Wait before retry
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(actualDelay):
			// Continue to next attempt
		}
	}

	return lastErr
}

// RetryWithResult executes a function with retry logic and returns result
func RetryWithResult[T any](ctx context.Context, policy *RetryPolicy, fn func(context.Context) (T, error)) (T, error) {
	var result T
	err := Retry(ctx, policy, func(ctx context.Context) error {
		var fnErr error
		result, fnErr = fn(ctx)
		return fnErr
	})
	return result, err
}

// ExponentialBackoff implements exponential backoff strategy
type ExponentialBackoff struct {
	Initial    time.Duration
	Max        time.Duration
	Multiplier float64
	current    time.Duration
}

// NewExponentialBackoff creates a new exponential backoff
func NewExponentialBackoff(initial, max time.Duration) *ExponentialBackoff {
	return &ExponentialBackoff{
		Initial:    initial,
		Max:        max,
		Multiplier: 2.0,
		current:    initial,
	}
}

// Next returns the next backoff duration
func (eb *ExponentialBackoff) Next() time.Duration {
	defer func() {
		eb.current = time.Duration(float64(eb.current) * eb.Multiplier)
		if eb.current > eb.Max {
			eb.current = eb.Max
		}
	}()
	return eb.current
}

// Reset resets the backoff to initial value
func (eb *ExponentialBackoff) Reset() {
	eb.current = eb.Initial
}

// LinearBackoff implements linear backoff strategy
type LinearBackoff struct {
	Initial   time.Duration
	Increment time.Duration
	Max       time.Duration
	current   time.Duration
}

// NewLinearBackoff creates a new linear backoff
func NewLinearBackoff(initial, increment, max time.Duration) *LinearBackoff {
	return &LinearBackoff{
		Initial:   initial,
		Increment: increment,
		Max:       max,
		current:   initial,
	}
}

// Next returns the next backoff duration
func (lb *LinearBackoff) Next() time.Duration {
	defer func() {
		lb.current += lb.Increment
		if lb.current > lb.Max {
			lb.current = lb.Max
		}
	}()
	return lb.current
}

// Reset resets the backoff to initial value
func (lb *LinearBackoff) Reset() {
	lb.current = lb.Initial
}

// FibonacciBackoff implements Fibonacci backoff strategy
type FibonacciBackoff struct {
	Unit    time.Duration
	Max     time.Duration
	current int
	prev    int
}

// NewFibonacciBackoff creates a new Fibonacci backoff
func NewFibonacciBackoff(unit, max time.Duration) *FibonacciBackoff {
	return &FibonacciBackoff{
		Unit:    unit,
		Max:     max,
		current: 1,
		prev:    1,
	}
}

// Next returns the next backoff duration
func (fb *FibonacciBackoff) Next() time.Duration {
	duration := time.Duration(fb.current) * fb.Unit
	if duration > fb.Max {
		duration = fb.Max
	}

	// Calculate next Fibonacci number
	next := fb.current + fb.prev
	fb.prev = fb.current
	fb.current = next

	return duration
}

// Reset resets the backoff to initial value
func (fb *FibonacciBackoff) Reset() {
	fb.current = 1
	fb.prev = 1
}

// RetryableError wraps an error to indicate it's retryable
type RetryableError struct {
	Err error
}

func (e RetryableError) Error() string {
	return e.Err.Error()
}

func (e RetryableError) Unwrap() error {
	return e.Err
}

// IsRetryable checks if an error is retryable
func IsRetryable(err error) bool {
	var retryableErr RetryableError
	return errors.As(err, &retryableErr)
}

// MarkRetryable marks an error as retryable
func MarkRetryable(err error) error {
	if err == nil {
		return nil
	}
	return RetryableError{Err: err}
}

// RetryWithCircuitBreaker combines retry with circuit breaker
func RetryWithCircuitBreaker(ctx context.Context, cb *CircuitBreaker, policy *RetryPolicy, fn func(context.Context) error) error {
	return Retry(ctx, policy, func(ctx context.Context) error {
		result, err := cb.Execute(ctx, func(ctx context.Context) (interface{}, error) {
			return nil, fn(ctx)
		})
		_ = result
		return err
	})
}

// AdaptiveRetry adjusts retry policy based on error patterns
type AdaptiveRetry struct {
	basePolicy      *RetryPolicy
	successCount    int
	failureCount    int
	consecutiveFails int
	maxConsecutive  int
}

// NewAdaptiveRetry creates an adaptive retry mechanism
func NewAdaptiveRetry(basePolicy *RetryPolicy, maxConsecutive int) *AdaptiveRetry {
	return &AdaptiveRetry{
		basePolicy:     basePolicy,
		maxConsecutive: maxConsecutive,
	}
}

// Execute runs a function with adaptive retry
func (ar *AdaptiveRetry) Execute(ctx context.Context, fn func(context.Context) error) error {
	// Adjust policy based on recent patterns
	policy := *ar.basePolicy

	if ar.consecutiveFails > ar.maxConsecutive/2 {
		// Increase delays if seeing many failures
		policy.InitialDelay = policy.InitialDelay * 2
		policy.MaxAttempts = int(math.Min(float64(policy.MaxAttempts+1), 5))
	}

	err := Retry(ctx, &policy, fn)

	// Update statistics
	if err != nil {
		ar.failureCount++
		ar.consecutiveFails++
	} else {
		ar.successCount++
		ar.consecutiveFails = 0
	}

	return err
}

// GetStats returns adaptive retry statistics
func (ar *AdaptiveRetry) GetStats() map[string]interface{} {
	return map[string]interface{}{
		"success_count":     ar.successCount,
		"failure_count":     ar.failureCount,
		"consecutive_fails": ar.consecutiveFails,
		"success_rate":      float64(ar.successCount) / float64(ar.successCount+ar.failureCount),
	}
}