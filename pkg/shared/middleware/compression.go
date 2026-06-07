package middleware

import (
	"compress/gzip"
	"io"
	"strings"
	"sync"

	"github.com/gin-gonic/gin"
)

// gzipWriter wraps gin.ResponseWriter to provide gzip compression.
// On first Write it inspects Content-Type; if the body is already a compressed
// format (xlsx, pdf, image, etc.) it skips gzipping and writes through to the
// underlying writer, preserving the handler's original Content-Length.
type gzipWriter struct {
	gin.ResponseWriter
	writer    *gzip.Writer
	decided   bool
	useGzip   bool
}

func (g *gzipWriter) decide() {
	if g.decided {
		return
	}
	g.decided = true
	if isUncompressibleContentType(g.ResponseWriter.Header().Get("Content-Type")) {
		g.useGzip = false
		return
	}
	g.useGzip = true
	// Compressed body length is unknown until close; the handler's Content-Length
	// (uncompressed) would mismatch and break HTTP/2. Switch to chunked transfer.
	g.ResponseWriter.Header().Del("Content-Length")
	g.ResponseWriter.Header().Set("Content-Encoding", "gzip")
	g.ResponseWriter.Header().Set("Vary", "Accept-Encoding")
}

func (g *gzipWriter) Write(data []byte) (int, error) {
	g.decide()
	if g.useGzip {
		return g.writer.Write(data)
	}
	return g.ResponseWriter.Write(data)
}

func (g *gzipWriter) WriteString(s string) (int, error) {
	g.decide()
	if g.useGzip {
		return g.writer.Write([]byte(s))
	}
	return g.ResponseWriter.WriteString(s)
}

var gzipWriterPool = sync.Pool{
	New: func() interface{} {
		return gzip.NewWriter(io.Discard)
	},
}

// uncompressibleContentTypes are MIME types that are already compressed at the
// payload level (zip-based or media). Re-gzipping them is pointless and — worse —
// the wrapped writer can't update the original Content-Length the handler set,
// so the browser sees a length mismatch and aborts the HTTP/2 stream with
// ERR_HTTP2_PROTOCOL_ERROR. Bail out for these types instead.
var uncompressibleContentTypes = []string{
	"application/vnd.openxmlformats", // xlsx, docx, pptx
	"application/vnd.ms-excel",
	"application/zip",
	"application/x-zip",
	"application/gzip",
	"application/x-gzip",
	"application/octet-stream",
	"application/pdf",
	"image/",
	"audio/",
	"video/",
	"font/woff",
}

func isUncompressibleContentType(ct string) bool {
	if ct == "" {
		return false
	}
	ct = strings.ToLower(ct)
	for _, prefix := range uncompressibleContentTypes {
		if strings.HasPrefix(ct, prefix) {
			return true
		}
	}
	return false
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

		// Wrap response writer with skip-on-binary detection
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
