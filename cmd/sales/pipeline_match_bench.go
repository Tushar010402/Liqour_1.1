package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"strings"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/textract"
	"github.com/google/uuid"
	"github.com/liquorpro/go-backend/pkg/shared/config"
	"github.com/liquorpro/go-backend/pkg/shared/database"
)

// runTextractMatchBench is the v1.0.165 end-to-end accuracy test:
// per-job, runs Textract on every page image, builds the row-locked
// extracted-row list, matches each row's brand against the FM-Tower
// product catalog (size-filtered), then compares to the operator's
// approved truth. Output CSV columns:
//
//   job_id, size, sale_date, pages, truth_rows, textract_rows,
//   row_coverage_pct, brand_extract_pct, brand_match_pct, qty_match_pct,
//   amount_match_pct, runtime_s, est_cost_usd, notes
//
// "100% accuracy" = textract_rows ≥ truth_rows AND brand_match_pct=100
// AND qty_match_pct=100. Use this to prove the row-locked pipeline is
// ready before flipping the live tenant flag.
func runTextractMatchBench() {
	fs := flag.NewFlagSet("textract-match", flag.ExitOnError)
	jobsArg := fs.String("jobs", "", "comma-separated job ids; empty = chhotu's May 4 set")
	outArg := fs.String("out", "/tmp/textract_match_bench.csv", "output CSV")
	tenantArg := fs.String("tenant", "68ffde63-191d-4845-b1c9-bf7c76ecbc93", "tenant uuid")
	_ = fs.Parse(os.Args[2:])

	cfg, err := config.LoadConfig("config")
	if err != nil {
		log.Fatalf("match-bench: config: %v", err)
	}
	db, err := database.NewDatabase(database.Config{
		Host: cfg.Database.Host, Port: cfg.Database.Port,
		User: cfg.Database.User, Password: cfg.Database.Password,
		DBName: cfg.Database.DBName, SSLMode: cfg.Database.SSLMode, TimeZone: cfg.Database.TimeZone,
	})
	if err != nil {
		log.Fatalf("match-bench: db: %v", err)
	}
	defer db.Close()

	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "ap-south-1"
	}
	ctx := context.Background()
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		log.Fatalf("match-bench: aws config: %v", err)
	}
	tx := textract.NewFromConfig(awsCfg)

	tenantID := uuid.MustParse(*tenantArg)

	// Catalog: every active product for the tenant.
	var catalog []matchCatRow
	if err := db.Raw(`SELECT id, LOWER(name) AS name, COALESCE(size,'') AS size
	                  FROM products WHERE tenant_id = ? AND deleted_at IS NULL`,
		tenantID).Scan(&catalog).Error; err != nil {
		log.Fatalf("match-bench: load catalog: %v", err)
	}
	log.Printf("match-bench: catalog=%d products", len(catalog))

	jobIDs := parseJobIDs(*jobsArg)
	out, err := os.Create(*outArg)
	if err != nil {
		log.Fatalf("match-bench: open csv: %v", err)
	}
	defer out.Close()
	fmt.Fprintln(out, "job_id,size,sale_date,pages,truth_rows,textract_rows,row_coverage_pct,brand_extract_pct,brand_match_pct,qty_match_pct,amount_match_pct,runtime_s,est_cost_usd,notes")

	totalCost := 0.0
	for _, jobID := range jobIDs {
		jctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
		meta, mErr := loadBenchJobMeta(jctx, db, jobID)
		cancel()
		if mErr != nil {
			log.Printf("skip %s: %v", jobID, mErr)
			continue
		}

		// Truth keyed by lowercased brand name → (qty, amount=qty*rate).
		truthByLower := map[string]int{}
		truthAmount := map[string]float64{}
		for _, t := range meta.TruthItems {
			k := strings.ToLower(strings.TrimSpace(t.BrandName))
			truthByLower[k] = t.Quantity
			truthAmount[k] = float64(t.Quantity) * t.UnitPrice
		}

		started := time.Now()
		var allRows []textractRow
		for _, imgPath := range meta.ImagePaths {
			raw, rErr := os.ReadFile(containerToHostPath(imgPath))
			if rErr != nil {
				continue
			}
			rows, cost, tErr := runTextractOnPageDetailed(tx, raw)
			totalCost += cost
			if tErr != nil {
				log.Printf("  textract err on %s: %v", imgPath, tErr)
				continue
			}
			allRows = append(allRows, rows...)
		}
		runtime := time.Since(started).Seconds()

		brandExtracted := 0
		brandMatched := 0
		qtyMatched := 0
		amountMatched := 0
		for _, r := range allRows {
			if strings.TrimSpace(r.Brand) == "" {
				continue
			}
			brandExtracted++
			matched, matchedKey := matchBrandToCatalog(r.Brand, catalog, meta.Size)
			if !matched {
				continue
			}
			brandMatched++
			// Compare qty + amount against truth using best-jaccard truth key.
			best := 0.0
			var bestTruth string
			lo := strings.ToLower(strings.TrimSpace(r.Brand))
			toks := tokenizeStr(lo)
			for k := range truthByLower {
				s := jaccardOnTokens(toks, tokenizeStr(k))
				if s > best {
					best = s
					bestTruth = k
				}
			}
			if best < 0.4 {
				// Fall back to matched catalog name → reverse jaccard against truth keys.
				toks2 := tokenizeStr(matchedKey)
				for k := range truthByLower {
					s := jaccardOnTokens(toks2, tokenizeStr(k))
					if s > best {
						best = s
						bestTruth = k
					}
				}
			}
			if best >= 0.4 {
				if truthByLower[bestTruth] == r.Quantity {
					qtyMatched++
				}
				rowAmt := r.Amount
				if rowAmt == 0 && r.Quantity > 0 {
					rowAmt = float64(r.Quantity) * r.Rate
				}
				if absDiff(rowAmt, truthAmount[bestTruth]) < 1.0 {
					amountMatched++
				}
			}
		}

		rowCovPct := 0.0
		if meta.TruthRowCount > 0 {
			rowCovPct = 100.0 * float64(len(allRows)) / float64(meta.TruthRowCount)
			if rowCovPct > 100 {
				rowCovPct = 100
			}
		}
		brExtPct := 0.0
		if len(allRows) > 0 {
			brExtPct = 100.0 * float64(brandExtracted) / float64(len(allRows))
		}
		brMatchPct := 0.0
		if brandExtracted > 0 {
			brMatchPct = 100.0 * float64(brandMatched) / float64(brandExtracted)
		}
		qtyMatchPct := 0.0
		amountMatchPct := 0.0
		if brandMatched > 0 {
			qtyMatchPct = 100.0 * float64(qtyMatched) / float64(brandMatched)
			amountMatchPct = 100.0 * float64(amountMatched) / float64(brandMatched)
		}
		fmt.Fprintf(out, "%s,%s,%s,%d,%d,%d,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.4f,%s\n",
			meta.JobID, meta.Size, meta.SaleDate, meta.PageCount,
			meta.TruthRowCount, len(allRows), rowCovPct,
			brExtPct, brMatchPct, qtyMatchPct, amountMatchPct,
			runtime, 0.015*float64(meta.PageCount), "")
		log.Printf("done %s size=%s rows=%d/%d brExt=%.0f%% brMatch=%.0f%% qty=%.0f%% amt=%.0f%% (%.1fs)",
			meta.JobID, meta.Size, len(allRows), meta.TruthRowCount,
			brExtPct, brMatchPct, qtyMatchPct, amountMatchPct, runtime)
	}
	log.Printf("match-bench done. total est cost = $%.2f csv=%s", totalCost, *outArg)
}

type matchCatRow struct {
	ID   uuid.UUID `gorm:"column:id"`
	Name string    `gorm:"column:name"`
	Size string    `gorm:"column:size"`
}

func matchBrandToCatalog(ocr string, catalog []matchCatRow, sizeFilter string) (bool, string) {
	target := strings.ToLower(strings.TrimSpace(ocr))
	if target == "" {
		return false, ""
	}
	tokens := tokenizeStr(target)
	bestScore := 0.0
	var bestName string
	for _, p := range catalog {
		if sizeFilter != "" && !sizeMatchesNorm(p.Size, sizeFilter) {
			continue
		}
		score := jaccardOnTokens(tokens, tokenizeStr(p.Name))
		if strings.Contains(p.Name, target) || strings.Contains(target, p.Name) {
			score += 0.20
			if score > 1 {
				score = 1
			}
		}
		if score > bestScore {
			bestScore = score
			bestName = p.Name
		}
	}
	return bestScore >= 0.5, bestName
}

func tokenizeStr(s string) map[string]struct{} {
	out := map[string]struct{}{}
	for _, t := range strings.Fields(s) {
		t = strings.TrimFunc(t, func(r rune) bool {
			return !(r >= 'a' && r <= 'z') && !(r >= '0' && r <= '9')
		})
		if len(t) >= 2 {
			out[t] = struct{}{}
		}
	}
	return out
}

func jaccardOnTokens(a, b map[string]struct{}) float64 {
	if len(a) == 0 || len(b) == 0 {
		return 0
	}
	inter := 0
	for k := range a {
		if _, ok := b[k]; ok {
			inter++
		}
	}
	un := len(a) + len(b) - inter
	if un == 0 {
		return 0
	}
	return float64(inter) / float64(un)
}

func sizeMatchesNorm(catSize, sizeFilter string) bool {
	return normSizeStr(catSize) == normSizeStr(sizeFilter)
}

func normSizeStr(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	for _, suffix := range []string{"(quarter)", "(half)", "(full)", "(nip)"} {
		s = strings.TrimSpace(strings.ReplaceAll(s, suffix, ""))
	}
	s = strings.ReplaceAll(s, "ml", "")
	return strings.TrimSpace(s)
}

func absDiff(a, b float64) float64 {
	if a > b {
		return a - b
	}
	return b - a
}
