package main

import (
	"bytes"
	"context"
	"encoding/csv"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
)

// buildMultipartFile composes a multipart/form-data body containing one
// file field. Returns the body reader, the Content-Type header value
// (with boundary), or any error from copy.
func buildMultipartFile(fieldName string, r io.Reader, filename string) (io.Reader, string, error) {
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	fw, err := mw.CreateFormFile(fieldName, filepath.Base(filename))
	if err != nil {
		return nil, "", err
	}
	if _, err := io.Copy(fw, r); err != nil {
		return nil, "", err
	}
	if err := mw.Close(); err != nil {
		return nil, "", err
	}
	return &buf, mw.FormDataContentType(), nil
}

// pipelineBenchRow is one row in the CSV output. Each (job, pipeline) pair
// produces one row so the resulting file is a long-form table that
// spreadsheets can pivot easily.
type pipelineBenchRow struct {
	JobID                string
	Size                 string
	SaleDate             string
	PageCount            int
	Pipeline             string // "current" | "paddle" | "textract"
	ExtractedRowCount    int
	TruthRowCount        int
	RowCoveragePct       float64
	QtyExactPct          float64
	BrandMatchPct        float64
	NeedsReviewPct       float64
	RuntimeSeconds       float64
	EstimatedCostUSD     float64
	Notes                string
}

func runPipelineBench() {
	fs := flag.NewFlagSet("pipeline-bench", flag.ExitOnError)
	jobsArg := fs.String("jobs", "", "comma-separated smart_sale_setup_jobs.id values; empty = chhotu's May 4 set")
	outArg := fs.String("out", "/tmp/pipeline_bench.csv", "output CSV path")
	pipelinesArg := fs.String("pipelines", "current,paddle", "which pipelines to run (current,paddle,textract)")
	cvSidecarArg := fs.String("cv-sidecar", "http://liquorpro-cv-sidecar:8000", "cv-sidecar base URL")
	_ = fs.Parse(os.Args[2:])

	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatalf("bench: config load: %v", err)
	}
	db, err := database.NewDatabase(database.Config{
		Host: cfg.Database.Host, Port: cfg.Database.Port,
		User: cfg.Database.User, Password: cfg.Database.Password,
		DBName: cfg.Database.DBName, SSLMode: cfg.Database.SSLMode, TimeZone: cfg.Database.TimeZone,
	})
	if err != nil {
		log.Fatalf("bench: db: %v", err)
	}
	defer db.Close()

	jobIDs := parseJobIDs(*jobsArg)
	if len(jobIDs) == 0 {
		log.Fatalf("bench: no job ids resolved")
	}
	pipelines := splitTrim(*pipelinesArg)

	log.Printf("bench: %d jobs × %d pipelines = %d runs total", len(jobIDs), len(pipelines), len(jobIDs)*len(pipelines))
	log.Printf("bench: cv-sidecar = %s   out = %s", *cvSidecarArg, *outArg)

	out, err := os.Create(*outArg)
	if err != nil {
		log.Fatalf("bench: open csv: %v", err)
	}
	defer out.Close()
	w := csv.NewWriter(out)
	defer w.Flush()
	_ = w.Write([]string{
		"job_id", "size", "sale_date", "pages", "pipeline",
		"extracted_rows", "truth_rows", "row_coverage_pct",
		"qty_exact_pct", "brand_match_pct", "needs_review_pct",
		"runtime_s", "est_cost_usd", "notes",
	})

	for _, jobID := range jobIDs {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
		jobMeta, err := loadBenchJobMeta(ctx, db, jobID)
		cancel()
		if err != nil {
			log.Printf("bench: skip job %s: %v", jobID, err)
			continue
		}
		log.Printf("bench: job=%s size=%s pages=%d truth_rows=%d", jobID, jobMeta.Size, jobMeta.PageCount, jobMeta.TruthRowCount)

		for _, p := range pipelines {
			row := pipelineBenchRow{
				JobID: jobID.String(), Size: jobMeta.Size,
				SaleDate: jobMeta.SaleDate, PageCount: jobMeta.PageCount,
				Pipeline: p, TruthRowCount: jobMeta.TruthRowCount,
			}
			start := time.Now()
			switch p {
			case "current":
				benchPipelineCurrent(jobMeta, &row)
			case "paddle":
				benchPipelinePaddle(jobMeta, *cvSidecarArg, &row)
			case "textract":
				benchPipelineTextract(jobMeta, &row)
			default:
				row.Notes = "unknown pipeline"
			}
			row.RuntimeSeconds = time.Since(start).Seconds()
			if row.TruthRowCount > 0 {
				row.RowCoveragePct = 100.0 * float64(row.ExtractedRowCount) / float64(row.TruthRowCount)
				if row.RowCoveragePct > 100 {
					row.RowCoveragePct = 100
				}
			}
			writeBenchRow(w, row)
		}
	}
	w.Flush()
	log.Printf("bench: wrote %s", *outArg)
}

type benchJobMeta struct {
	JobID         uuid.UUID
	TenantID      uuid.UUID
	ShopID        uuid.UUID
	Size          string
	SaleDate      string
	PageCount     int
	ImagePaths    []string
	CurrentResult map[string]interface{}
	TruthRowCount int
	TruthItems    []benchTruthItem
}

type benchTruthItem struct {
	BrandName string
	Quantity  int
	UnitPrice float64
}

func loadBenchJobMeta(ctx context.Context, db *database.DB, jobID uuid.UUID) (*benchJobMeta, error) {
	type row struct {
		JobID      uuid.UUID `gorm:"column:id"`
		TenantID   uuid.UUID `gorm:"column:tenant_id"`
		ShopID     uuid.UUID `gorm:"column:shop_id"`
		Size       string    `gorm:"column:size"`
		SaleDate   time.Time `gorm:"column:sale_date"`
		ImageRaw   string    `gorm:"column:image_paths"`
		ResultRaw  string    `gorm:"column:result"`
	}
	var r row
	err := db.Raw(`
		SELECT id, tenant_id, shop_id, size, sale_date,
		       image_paths::text AS image_paths,
		       result::text AS result
		  FROM smart_sale_setup_jobs WHERE id = ?
	`, jobID).Scan(&r).Error
	if err != nil {
		return nil, fmt.Errorf("query job: %w", err)
	}

	var imgs []string
	if err := json.Unmarshal([]byte(r.ImageRaw), &imgs); err != nil {
		return nil, fmt.Errorf("decode image_paths: %w", err)
	}
	var result map[string]interface{}
	if r.ResultRaw != "" {
		_ = json.Unmarshal([]byte(r.ResultRaw), &result)
	}

	// Truth = the operator-approved daily_sales_record items at this shop on
	// this sale_date for this size. Falls back to the AI extraction count
	// when no approved record is found, so the bench still runs on jobs
	// that haven't been approved yet.
	type truthRow struct {
		BrandName string  `gorm:"column:brand"`
		Quantity  int     `gorm:"column:quantity"`
		UnitPrice float64 `gorm:"column:unit_price"`
	}
	var truth []truthRow
	_ = db.Raw(`
		SELECT COALESCE(p.name, dsi.ocr_brand_name, '') AS brand,
		       dsi.quantity_sold AS quantity,
		       dsi.unit_price AS unit_price
		  FROM daily_sales_records dsr
		  JOIN daily_sales_items dsi ON dsi.daily_sales_record_id = dsr.id
		  LEFT JOIN products p ON p.id = dsi.product_id
		 WHERE dsr.tenant_id = ? AND dsr.shop_id = ?
		   AND dsr.record_date::date = ?::date
		   AND dsr.deleted_at IS NULL AND dsi.deleted_at IS NULL
		   AND dsr.status = 'approved'
		   AND dsi.quantity_sold > 0
	`, r.TenantID, r.ShopID, r.SaleDate.Format("2006-01-02")).Scan(&truth)

	tItems := make([]benchTruthItem, 0, len(truth))
	for _, t := range truth {
		tItems = append(tItems, benchTruthItem{BrandName: t.BrandName, Quantity: t.Quantity, UnitPrice: t.UnitPrice})
	}

	return &benchJobMeta{
		JobID: r.JobID, TenantID: r.TenantID, ShopID: r.ShopID,
		Size: r.Size, SaleDate: r.SaleDate.Format("2006-01-02"),
		PageCount:     len(imgs),
		ImagePaths:    imgs,
		CurrentResult: result,
		TruthItems:    tItems,
		TruthRowCount: len(tItems),
	}, nil
}

// benchPipelineCurrent doesn't re-run extraction; it reads the already-stored
// result for this job. That captures what today's pipeline DID return on
// these exact images, which is what we want to compare against.
func benchPipelineCurrent(j *benchJobMeta, out *pipelineBenchRow) {
	if j.CurrentResult == nil {
		out.Notes = "no cached result"
		return
	}
	items, _ := j.CurrentResult["extracted_items"].([]interface{})
	out.ExtractedRowCount = len(items)
	validation, _ := j.CurrentResult["validation"].(map[string]interface{})
	if validation != nil {
		if total, ok := validation["total_items"].(float64); ok && total > 0 {
			if rev, ok2 := validation["needs_review_items"].(float64); ok2 {
				out.NeedsReviewPct = 100.0 * rev / total
			}
		}
	}
	// qty-exact + brand-match against truth
	out.QtyExactPct, out.BrandMatchPct = compareItemsAgainstTruth(items, j.TruthItems)
	out.EstimatedCostUSD = 0 // already paid; sunk cost
}

// benchPipelinePaddle calls the cv-sidecar /sheet endpoint via multipart
// upload. /sheet returns rows + cells with `has_writing`; a row counts as
// "non-blank" when ≥1 of its data cells (open/recv/total/sale/rate/amount/
// closing) has writing. Digit reading is the v1.0.165 build; the bench
// shipped today reports row coverage only on the paddle path.
func benchPipelinePaddle(j *benchJobMeta, sidecarBase string, out *pipelineBenchRow) {
	totalRows := 0
	notes := []string{}
	for pageIdx, imgPath := range j.ImagePaths {
		hostPath := containerToHostPath(imgPath)
		f, err := os.Open(hostPath)
		if err != nil {
			notes = append(notes, fmt.Sprintf("p%d: open %s: %v", pageIdx+1, hostPath, err))
			continue
		}
		body, contentType, err := buildMultipartFile("file", f, hostPath)
		f.Close()
		if err != nil {
			notes = append(notes, fmt.Sprintf("p%d: multipart: %v", pageIdx+1, err))
			continue
		}
		req, _ := http.NewRequest("POST", sidecarBase+"/sheet", body)
		req.Header.Set("Content-Type", contentType)
		client := &http.Client{Timeout: 90 * time.Second}
		resp, err := client.Do(req)
		if err != nil {
			notes = append(notes, fmt.Sprintf("p%d: cv-sidecar: %v", pageIdx+1, err))
			continue
		}
		var sheet struct {
			RowCount int `json:"row_count"`
			Rows     []struct {
				Idx int `json:"idx"`
			} `json:"rows"`
			Cells []struct {
				RowIdx     int    `json:"row_idx"`
				ColName    string `json:"col_name"`
				HasWriting bool   `json:"has_writing"`
			} `json:"cells"`
		}
		_ = json.NewDecoder(resp.Body).Decode(&sheet)
		resp.Body.Close()
		// Count rows where any DATA column has writing. Headers + row-1
		// "S.No / Brand" header rows have no writing in data cells, so
		// they self-filter.
		dataCols := map[string]bool{
			"open": true, "recv": true, "total": true, "sale": true,
			"rate": true, "amount": true, "closing": true,
		}
		writingByRow := map[int]bool{}
		for _, c := range sheet.Cells {
			if !dataCols[c.ColName] {
				continue
			}
			if c.HasWriting {
				writingByRow[c.RowIdx] = true
			}
		}
		nonBlank := len(writingByRow)
		totalRows += nonBlank
		notes = append(notes, fmt.Sprintf("p%d: cv_rows=%d non_blank=%d", pageIdx+1, sheet.RowCount, nonBlank))
	}
	out.ExtractedRowCount = totalRows
	if len(notes) == 0 {
		out.Notes = "no pages processed"
	} else {
		out.Notes = "paddle: " + strings.Join(notes, "; ")
	}
	out.EstimatedCostUSD = 0
}

// containerToHostPath maps the /app/uploads/... paths stored in the DB to
// the host's /var/www/liquorpro/uploads/... bind-mount path. The bench
// harness runs on the host, not inside the container, so it needs the
// translated path.
func containerToHostPath(p string) string {
	const prefix = "/app/uploads/"
	const hostPrefix = "/var/www/liquorpro/uploads/"
	if strings.HasPrefix(p, prefix) {
		return hostPrefix + strings.TrimPrefix(p, prefix)
	}
	return p
}

func benchPipelineTextract(j *benchJobMeta, out *pipelineBenchRow) {
	runBenchTextract(j, out)
}

func compareItemsAgainstTruth(items []interface{}, truth []benchTruthItem) (qtyExactPct, brandMatchPct float64) {
	if len(truth) == 0 || len(items) == 0 {
		return 0, 0
	}
	// Build maps keyed by lowercased trimmed brand prefix so AI-vs-truth
	// brand-name normalization differences don't tank the match.
	mapBrand := func(s string) string {
		s = strings.ToLower(strings.TrimSpace(s))
		if len(s) > 24 {
			s = s[:24]
		}
		return s
	}
	truthByBrand := make(map[string]benchTruthItem, len(truth))
	for _, t := range truth {
		truthByBrand[mapBrand(t.BrandName)] = t
	}
	matched := 0
	qtyExact := 0
	for _, raw := range items {
		it, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		brand := ""
		if v, ok := it["brand_name"].(string); ok {
			brand = v
		}
		qty := 0
		if v, ok := it["quantity"].(float64); ok {
			qty = int(v)
		}
		if t, hit := truthByBrand[mapBrand(brand)]; hit {
			matched++
			if t.Quantity == qty {
				qtyExact++
			}
		}
	}
	brandMatchPct = 100.0 * float64(matched) / float64(len(truth))
	if matched > 0 {
		qtyExactPct = 100.0 * float64(qtyExact) / float64(matched)
	}
	return
}

func writeBenchRow(w *csv.Writer, r pipelineBenchRow) {
	_ = w.Write([]string{
		r.JobID, r.Size, r.SaleDate, fmt.Sprintf("%d", r.PageCount), r.Pipeline,
		fmt.Sprintf("%d", r.ExtractedRowCount), fmt.Sprintf("%d", r.TruthRowCount),
		fmt.Sprintf("%.1f", r.RowCoveragePct),
		fmt.Sprintf("%.1f", r.QtyExactPct), fmt.Sprintf("%.1f", r.BrandMatchPct),
		fmt.Sprintf("%.1f", r.NeedsReviewPct),
		fmt.Sprintf("%.1f", r.RuntimeSeconds),
		fmt.Sprintf("%.4f", r.EstimatedCostUSD),
		r.Notes,
	})
}

func parseJobIDs(arg string) []uuid.UUID {
	if strings.TrimSpace(arg) == "" {
		// Default = chhotu's 14 May-4 jobs (the ones we've been triaging).
		defaultIDs := []string{
			"a6f866c0-165f-4b5e-a988-98b4756727cb",
			"ebaf5ad4-ecf4-4d1e-92e8-ec0165c3f5f3",
			"a224f793-05af-4e2f-910b-6af7679b094e",
			"c628059a-5b63-46ee-94ad-584867228d2c",
			"36825a94-b9e3-4ad4-8b39-58d22efd2a13",
			"409815a0-d4cf-4548-a5b8-1dea1e740b04",
			"b9eb5c3d-a246-43ed-946d-03724265946c",
			"833ef82c-daed-42ee-b655-58096cbb27d6",
			"b460f4f9-69ae-4158-a91c-0aa180d4f821",
			"00bf7866-f73c-4e57-9f5d-a8b1d4f4cd8d",
			"ac49ca99-3fdb-4ea2-9d44-e6b833b3db5a",
			"b0dc9d54-2495-4790-87f6-9fd26b330a7b",
			"e3af582a-8fea-447a-89ab-3bdc91c12f36",
			"d0e2dc9f-f574-4deb-a9cb-95f456c8359c",
			"6974d30d-d84d-4a56-9ba1-4c237d95b872",
		}
		out := make([]uuid.UUID, 0, len(defaultIDs))
		for _, s := range defaultIDs {
			if id, err := uuid.Parse(s); err == nil {
				out = append(out, id)
			}
		}
		return out
	}
	out := []uuid.UUID{}
	for _, s := range strings.Split(arg, ",") {
		if id, err := uuid.Parse(strings.TrimSpace(s)); err == nil {
			out = append(out, id)
		}
	}
	return out
}

func splitTrim(arg string) []string {
	parts := strings.Split(arg, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if t := strings.TrimSpace(p); t != "" {
			out = append(out, t)
		}
	}
	return out
}
