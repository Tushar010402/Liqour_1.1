package services

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"strings"
	"time"
)

// v1.0.226 — PDF→PNG client for cv-sidecar's /pdf-to-pages endpoint.
//
// The Purcha-gate upload accepts multi-page PDFs (operators commonly
// scan their handwritten Purcha booklet to a single PDF). cv-sidecar
// renders pages via PyMuPDF; Go pulls the base64-encoded PNGs and
// passes each page to the existing Claude brand-extractor.
//
// Best-effort: any failure surfaces as (nil, err) so the handler can
// reject the upload with a clean 422 instead of returning a misleading
// "no brands found" result.

// CVPDFPage is one rendered PDF page.
type CVPDFPage struct {
	Index    int    `json:"index"`
	Width    int    `json:"width"`
	Height   int    `json:"height"`
	PNGBytes []byte // decoded server-side from PngBase64
}

type cvPDFWireResponse struct {
	OK        bool `json:"ok"`
	PageCount int  `json:"page_count"`
	Pages     []struct {
		Index     int    `json:"index"`
		Width     int    `json:"width"`
		Height    int    `json:"height"`
		PNGBase64 string `json:"png_base64"`
	} `json:"pages"`
	Detail string `json:"detail,omitempty"`
}

// RenderPDFViaCVSidecar POSTs `pdfBytes` to cv-sidecar /pdf-to-pages and
// returns one CVPDFPage per rendered page (decoded to raw PNG bytes).
//
// CV_SIDECAR_URL defaults to http://cv-sidecar:8000 inside the docker
// network. Timeout is intentionally generous (30s) because a 10-page
// Purcha PDF at 200 DPI can take 3-5s to render.
func RenderPDFViaCVSidecar(ctx context.Context, pdfBytes []byte) ([]CVPDFPage, error) {
	if len(pdfBytes) == 0 {
		return nil, fmt.Errorf("RenderPDFViaCVSidecar: empty pdf bytes")
	}
	url := strings.TrimSpace(os.Getenv("CV_SIDECAR_URL"))
	if url == "" {
		url = "http://cv-sidecar:8000"
	}
	body := &bytes.Buffer{}
	w := multipart.NewWriter(body)
	part, err := w.CreateFormFile("file", "purcha.pdf")
	if err != nil {
		return nil, fmt.Errorf("multipart form: %w", err)
	}
	if _, err := part.Write(pdfBytes); err != nil {
		return nil, fmt.Errorf("multipart write: %w", err)
	}
	// Default 200 DPI — Claude reads liquor brand text reliably at 150+,
	// and 200 keeps response size manageable.
	if err := w.WriteField("dpi", "200"); err != nil {
		return nil, fmt.Errorf("multipart dpi: %w", err)
	}
	w.Close()
	req, err := http.NewRequestWithContext(ctx, "POST", url+"/pdf-to-pages", body)
	if err != nil {
		return nil, fmt.Errorf("request build: %w", err)
	}
	req.Header.Set("Content-Type", w.FormDataContentType())
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("cv-sidecar /pdf-to-pages request failed: %w", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 40*1024*1024)) // 40MB cap
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("cv-sidecar /pdf-to-pages %d: %s", resp.StatusCode, string(raw))
	}
	var wire cvPDFWireResponse
	if err := json.Unmarshal(raw, &wire); err != nil {
		return nil, fmt.Errorf("cv-sidecar /pdf-to-pages JSON decode: %w", err)
	}
	if !wire.OK || len(wire.Pages) == 0 {
		return nil, fmt.Errorf("cv-sidecar /pdf-to-pages returned no pages")
	}
	pages := make([]CVPDFPage, 0, len(wire.Pages))
	for _, p := range wire.Pages {
		pngBytes, err := base64.StdEncoding.DecodeString(p.PNGBase64)
		if err != nil {
			return nil, fmt.Errorf("decode page %d png_base64: %w", p.Index, err)
		}
		pages = append(pages, CVPDFPage{
			Index:    p.Index,
			Width:    p.Width,
			Height:   p.Height,
			PNGBytes: pngBytes,
		})
	}
	return pages, nil
}

// IsPDFContentType returns true when the given content-type / first
// magic bytes indicate a PDF upload. Used by the Purcha-gate handler
// to branch between "image" and "PDF render then loop" paths.
func IsPDFContentType(contentType string, firstBytes []byte) bool {
	if strings.Contains(strings.ToLower(contentType), "pdf") {
		return true
	}
	if len(firstBytes) >= 4 && string(firstBytes[:4]) == "%PDF" {
		return true
	}
	return false
}
