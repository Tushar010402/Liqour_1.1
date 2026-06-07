package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/service/textract"
	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
)

var _ = ttypes.FeatureTypeTables // keep ttypes import after edits

// v1.0.199 Phase C3 — image-hash cache for Textract responses.
//
// Why on-disk JSON instead of Redis: the inventory container already mounts
// /app/uploads for image storage; one more sub-directory under that mount
// means zero new infra. Cache lookups are O(1) sha256 keying, the JSON files
// are tens of KB at most, and `find -mtime +30 -delete` is the world's
// simplest TTL.
//
// Real-world payoff: operators commonly retry the SAME bill (re-take a blurry
// photo, then re-take it again with different lighting). Each retry that
// hits the cache costs ₹0 and finishes in <100ms instead of the 30-90s
// AnalyzeExpense round-trip.
//
// Gate: TEXTRACT_CACHE=1 to enable (default ON in production after Phase F
// passes). Set TEXTRACT_CACHE=0 to disable globally.

const (
	// /tmp is writable inside the inventory container (the /app/uploads
	// volume is mounted ro). /tmp persists for the container's lifetime
	// which is days-to-weeks in practice, well below the 30-day TTL.
	// On restart the cache cold-starts, which is acceptable — the AWS
	// throughput cap is per-account and we have headroom.
	textractCacheDir         = "/tmp/textract_cache"
	textractCacheTTLHours    = 24 * 30 // 30 days; corrupt entries self-expire
	textractCacheKeyVer      = "v1"    // bump when response shape changes
	textractCacheRegionEnv   = "AWS_REGION"
	textractCacheEnabledFlag = "TEXTRACT_CACHE"
)

func textractCacheEnabled() bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(textractCacheEnabledFlag)))
	switch v {
	case "0", "false", "off", "disabled", "no":
		return false
	}
	return true // default on
}

// textractCacheKey hashes (rawBytes + region + featureSet) into the cache
// filename. featureSet differentiates AnalyzeExpense from AnalyzeDocument
// outputs so a cached "tables" response never gets returned to an
// AnalyzeExpense caller.
func textractCacheKey(raw []byte, featureSet string) string {
	region := os.Getenv(textractCacheRegionEnv)
	if region == "" {
		region = "ap-south-1"
	}
	h := sha256.New()
	h.Write([]byte(textractCacheKeyVer))
	h.Write([]byte("|"))
	h.Write([]byte(region))
	h.Write([]byte("|"))
	h.Write([]byte(featureSet))
	h.Write([]byte("|"))
	h.Write(raw)
	return hex.EncodeToString(h.Sum(nil))
}

func textractCachePath(key string) string {
	// Two-level shard so a busy tenant doesn't end up with 100k flat files.
	return filepath.Join(textractCacheDir, key[:2], key[2:4], key+".json")
}

// readTextractCache returns the cached body bytes when the entry exists and
// is fresh. Returns (nil, false) otherwise — caller proceeds to invoke AWS.
func readTextractCache(key string) ([]byte, bool) {
	if !textractCacheEnabled() {
		return nil, false
	}
	path := textractCachePath(key)
	st, err := os.Stat(path)
	if err != nil {
		return nil, false
	}
	if time.Since(st.ModTime()) > time.Duration(textractCacheTTLHours)*time.Hour {
		// Stale; remove lazily so future writes don't get blocked by a
		// stale entry. Best-effort, no error handling.
		_ = os.Remove(path)
		return nil, false
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return nil, false
	}
	return body, true
}

func writeTextractCache(key string, body []byte) {
	if !textractCacheEnabled() {
		return
	}
	path := textractCachePath(key)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		log.Printf("textract cache: mkdir failed: %v (cache disabled for this call)", err)
		return
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, body, 0o644); err != nil {
		log.Printf("textract cache: write tmp failed: %v", err)
		return
	}
	if err := os.Rename(tmp, path); err != nil {
		log.Printf("textract cache: rename failed: %v", err)
		_ = os.Remove(tmp)
	}
}

// cachedAnalyzeExpense wraps the Textract sync call with the disk cache.
// Returns the response (deserialized from cached bytes when hit) plus a
// boolean indicating whether the cache served the request (for logs).
//
// Why we re-deserialize the AWS response shape: the AnalyzeExpenseOutput
// has unexported fields (the AWS SDK stamps a metadata struct on every
// response) that don't survive JSON marshal/unmarshal cleanly. To dodge
// that, we cache the *parsed* shape after json.Marshal of a slimmed-down
// projection that the caller-side mappers consume.
func cachedAnalyzeExpense(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
) (*textract.AnalyzeExpenseOutput, bool, error) {
	key := textractCacheKey(raw, "expense")
	if body, ok := readTextractCache(key); ok {
		var out textract.AnalyzeExpenseOutput
		if err := json.Unmarshal(body, &out); err == nil {
			log.Printf("textract cache HIT expense key=%s bytes=%d", key[:12], len(body))
			return &out, true, nil
		}
		log.Printf("textract cache: stale entry %s — re-fetching", key[:12])
	}
	// Retry-with-backoff for ProvisionedThroughputExceededException.
	// AWS sync TPS in ap-south-1 is ~2/account by default; bursts during
	// per-page parallelism (errgroup SetLimit) trip the throttle even at
	// 2 concurrent calls when the GP path also fires AnalyzeExpense.
	// 4 attempts, 200ms / 600ms / 1.5s / 3s backoff = ~5s worst case.
	var resp *textract.AnalyzeExpenseOutput
	var err error
	backoffs := []time.Duration{0, 200 * time.Millisecond, 600 * time.Millisecond, 1500 * time.Millisecond, 3 * time.Second}
	for attempt, wait := range backoffs {
		if wait > 0 {
			select {
			case <-ctx.Done():
				return nil, false, ctx.Err()
			case <-time.After(wait):
			}
		}
		resp, err = client.AnalyzeExpense(ctx, &textract.AnalyzeExpenseInput{
			Document: &ttypes.Document{Bytes: raw},
		})
		if err == nil {
			break
		}
		// Only retry on throttling — other errors (auth, malformed input)
		// won't be helped by waiting.
		if !isThrottleError(err) {
			break
		}
		log.Printf("textract cache: ProvisionedThroughput retry %d/%d after %v", attempt+1, len(backoffs)-1, wait)
	}
	if err != nil {
		return nil, false, err
	}
	if body, mErr := json.Marshal(resp); mErr == nil {
		writeTextractCache(key, body)
	}
	return resp, false, nil
}

// isThrottleError sniffs an AWS error for the throughput exception. AWS SDK
// v2 wraps the error with stack info but the substring is preserved.
func isThrottleError(err error) bool {
	if err == nil {
		return false
	}
	s := err.Error()
	return strings.Contains(s, "ProvisionedThroughputExceededException") ||
		strings.Contains(s, "ThrottlingException") ||
		strings.Contains(s, "Provisioned rate exceeded")
}

// cachedAnalyzeDocument wraps the AnalyzeDocument(TABLES) call with the same
// disk cache. featureSet identifies which feature combination was requested
// so cache lookups don't return TABLES-only output to a TABLES+QUERIES caller.
func cachedAnalyzeDocument(
	ctx context.Context,
	client *textract.Client,
	raw []byte,
	input *textract.AnalyzeDocumentInput,
	featureSet string,
) (*textract.AnalyzeDocumentOutput, bool, error) {
	key := textractCacheKey(raw, featureSet)
	if body, ok := readTextractCache(key); ok {
		var out textract.AnalyzeDocumentOutput
		if err := json.Unmarshal(body, &out); err == nil {
			log.Printf("textract cache HIT %s key=%s bytes=%d", featureSet, key[:12], len(body))
			return &out, true, nil
		}
	}
	resp, err := client.AnalyzeDocument(ctx, input)
	if err != nil {
		return nil, false, err
	}
	if body, err := json.Marshal(resp); err == nil {
		writeTextractCache(key, body)
	}
	return resp, false, nil
}

// PruneTextractCache removes cache entries older than TTL. Designed to be
// called by a cron / scheduled job; safe to no-op when the cache directory
// doesn't exist yet.
func PruneTextractCache() error {
	root := textractCacheDir
	if _, err := os.Stat(root); err != nil {
		return nil
	}
	cutoff := time.Now().Add(-time.Duration(textractCacheTTLHours) * time.Hour)
	pruned := 0
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // best-effort; keep walking
		}
		if info.IsDir() {
			return nil
		}
		if !strings.HasSuffix(info.Name(), ".json") {
			return nil
		}
		if info.ModTime().Before(cutoff) {
			if rmErr := os.Remove(path); rmErr == nil {
				pruned++
			}
		}
		return nil
	})
	if pruned > 0 {
		log.Printf("textract cache: pruned %d stale entries (>%dh old)", pruned, textractCacheTTLHours)
	}
	return err
}

// init registers a no-op so callers know the package compiled with cache
// support. Real init/cleanup happens lazily on first call.
func init() {
	_ = fmt.Sprintf("textract cache module loaded ttl=%dh", textractCacheTTLHours)
}
