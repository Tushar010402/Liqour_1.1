package middleware

import (
	"compress/gzip"
	"io"
	"strings"
	"sync"

	"github.com/gin-gonic/gin"
)

// gzipWriter wraps gin.ResponseWriter to provide gzip compression
type gzipWriter struct {
	gin.ResponseWriter
	writer *gzip.Writer
}

func (g *gzipWriter) Write(data []byte) (int, error) {
	return g.writer.Write(data)
}

func (g *gzipWriter) WriteString(s string) (int, error) {
	return g.writer.Write([]byte(s))
}

var gzipWriterPool = sync.Pool{
	New: func() interface{} {
		return gzip.NewWriter(io.Discard)
	},
}

// GzipMiddleware provides gzip compression for HTTP responses
// Best practice: Only compress responses larger than 1KB
func GzipMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Check if client accepts gzip
		if !strings.Contains(c.Request.Header.Get("Accept-Encoding"), "gzip") {
			c.Next()
			return
		}

		// Don't compress if already compressed
		if c.Writer.Header().Get("Content-Encoding") != "" {
			c.Next()
			return
		}

		// Get gzip writer from pool
		gz := gzipWriterPool.Get().(*gzip.Writer)
		defer gzipWriterPool.Put(gz)

		gz.Reset(c.Writer)
		defer gz.Close()

		// Set headers
		c.Header("Content-Encoding", "gzip")
		c.Header("Vary", "Accept-Encoding")

		// Wrap response writer
		c.Writer = &gzipWriter{
			ResponseWriter: c.Writer,
			writer:         gz,
		}

		c.Next()
	}
}

// SmartCompressionMiddleware only compresses responses above a threshold
// Best practice: Don't compress small responses (overhead not worth it)
func SmartCompressionMiddleware(minSize int) gin.HandlerFunc {
	if minSize <= 0 {
		minSize = 1024 // Default 1KB minimum
	}

	return func(c *gin.Context) {
		// Check if client accepts gzip
		if !strings.Contains(c.Request.Header.Get("Accept-Encoding"), "gzip") {
			c.Next()
			return
		}

		// Custom writer to buffer and check size
		blw := &bodyLogWriter{body: make([]byte, 0), ResponseWriter: c.Writer}
		c.Writer = blw

		c.Next()

		// Only compress if response is large enough
		if len(blw.body) >= minSize {
			// Compress the buffered response
			c.Writer = blw.ResponseWriter
			c.Header("Content-Encoding", "gzip")
			c.Header("Vary", "Accept-Encoding")

			gz := gzip.NewWriter(c.Writer)
			defer gz.Close()

			gz.Write(blw.body)
		} else {
			// Write uncompressed
			c.Writer = blw.ResponseWriter
			c.Writer.Write(blw.body)
		}
	}
}

type bodyLogWriter struct {
	gin.ResponseWriter
	body []byte
}

func (w *bodyLogWriter) Write(b []byte) (int, error) {
	w.body = append(w.body, b...)
	return len(b), nil
}

func (w *bodyLogWriter) WriteString(s string) (int, error) {
	w.body = append(w.body, []byte(s)...)
	return len(s), nil
}
