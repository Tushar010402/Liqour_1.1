package main

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/textract"
	ttypes "github.com/aws/aws-sdk-go-v2/service/textract/types"
)

// textractRow is the cell-aligned row data extracted from a Textract response.
// Used by the bench harness for end-to-end matching tests.
type textractRow struct {
	Brand    string
	Open     int
	Recv     int
	Total    int
	Quantity int
	Rate     float64
	Amount   float64
	Closing  int
	RowConf  float64
}

// runTextractOnPageDetailed submits one page to Textract and returns per-row
// cell-aligned data plus cost. Used by both the legacy row-counter benchPath
// and the new matching benchPath.
func runTextractOnPageDetailed(client *textract.Client, raw []byte) ([]textractRow, float64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	resp, err := client.AnalyzeDocument(ctx, &textract.AnalyzeDocumentInput{
		Document:     &ttypes.Document{Bytes: raw},
		FeatureTypes: []ttypes.FeatureType{ttypes.FeatureTypeTables},
	})
	if err != nil {
		return nil, 0, err
	}
	const costPerPage = 0.015
	byID := map[string]ttypes.Block{}
	for _, b := range resp.Blocks {
		if b.Id != nil {
			byID[*b.Id] = b
		}
	}
	var bestTable *ttypes.Block
	bestCellCount := 0
	for i, b := range resp.Blocks {
		if b.BlockType != ttypes.BlockTypeTable {
			continue
		}
		cells := 0
		for _, rel := range b.Relationships {
			if rel.Type == ttypes.RelationshipTypeChild {
				cells += len(rel.Ids)
			}
		}
		if cells > bestCellCount {
			bestCellCount = cells
			bestTable = &resp.Blocks[i]
		}
	}
	if bestTable == nil {
		return nil, costPerPage, nil
	}
	rowsByIdx := map[int32]map[int32]ttypes.Block{}
	for _, rel := range bestTable.Relationships {
		if rel.Type != ttypes.RelationshipTypeChild {
			continue
		}
		for _, cid := range rel.Ids {
			cell, ok := byID[cid]
			if !ok || cell.BlockType != ttypes.BlockTypeCell || cell.RowIndex == nil || cell.ColumnIndex == nil {
				continue
			}
			r := *cell.RowIndex
			c := *cell.ColumnIndex
			if rowsByIdx[r] == nil {
				rowsByIdx[r] = map[int32]ttypes.Block{}
			}
			rowsByIdx[r][c] = cell
		}
	}
	keys := make([]int32, 0, len(rowsByIdx))
	for k := range rowsByIdx {
		keys = append(keys, k)
	}
	for i := 1; i < len(keys); i++ {
		for j := i; j > 0 && keys[j-1] > keys[j]; j-- {
			keys[j-1], keys[j] = keys[j], keys[j-1]
		}
	}
	out := make([]textractRow, 0, len(rowsByIdx))
	for _, r := range keys {
		cells := rowsByIdx[r]
		brandText := strings.TrimSpace(joinCellTextHelper(cells[2], byID))
		if r == 1 {
			up := strings.ToUpper(brandText)
			if strings.Contains(up, "BRAND") || strings.Contains(up, "ITEM") || strings.Contains(up, "PARTICULAR") {
				continue
			}
		}
		open := atoiTolerant(joinCellTextHelper(cells[3], byID))
		recv := atoiTolerant(joinCellTextHelper(cells[4], byID))
		totl := atoiTolerant(joinCellTextHelper(cells[5], byID))
		sale := atoiTolerant(joinCellTextHelper(cells[6], byID))
		rate := atofTolerant(joinCellTextHelper(cells[7], byID))
		amt := atofTolerant(joinCellTextHelper(cells[8], byID))
		clos := atoiTolerant(joinCellTextHelper(cells[9], byID))
		// Skip rows that are completely empty (no brand, no qty)
		if brandText == "" && sale == 0 && open == 0 && rate == 0 {
			continue
		}
		conf := 0.0
		count := 0
		for _, b := range cells {
			if b.Confidence != nil {
				conf += float64(*b.Confidence) / 100.0
				count++
			}
		}
		if count > 0 {
			conf = conf / float64(count)
		}
		out = append(out, textractRow{
			Brand: brandText, Open: open, Recv: recv, Total: totl,
			Quantity: sale, Rate: rate, Amount: amt, Closing: clos,
			RowConf: conf,
		})
	}
	return out, costPerPage, nil
}

// joinCellTextHelper inlined helper avoiding type collision with the existing
// joinCellText (different signature elsewhere in package).
func joinCellTextHelper(cell ttypes.Block, byID map[string]ttypes.Block) string {
	var parts []string
	for _, rel := range cell.Relationships {
		if rel.Type != ttypes.RelationshipTypeChild {
			continue
		}
		for _, id := range rel.Ids {
			child, ok := byID[id]
			if !ok {
				continue
			}
			if child.BlockType == ttypes.BlockTypeWord && child.Text != nil {
				parts = append(parts, *child.Text)
			}
		}
	}
	return strings.Join(parts, " ")
}

func atoiTolerant(t string) int {
	t = strings.TrimSpace(t)
	if t == "" {
		return 0
	}
	t = strings.ReplaceAll(t, ",", "")
	t = strings.Map(func(r rune) rune {
		if (r >= '0' && r <= '9') || r == '-' {
			return r
		}
		return -1
	}, t)
	if t == "" {
		return 0
	}
	n := 0
	for i, c := range t {
		if i == 0 && c == '-' {
			continue
		}
		if c < '0' || c > '9' {
			return 0
		}
		n = n*10 + int(c-'0')
	}
	if t[0] == '-' {
		n = -n
	}
	return n
}

func atofTolerant(t string) float64 {
	t = strings.TrimSpace(t)
	if t == "" {
		return 0
	}
	t = strings.ReplaceAll(t, ",", "")
	t = strings.Map(func(r rune) rune {
		if (r >= '0' && r <= '9') || r == '.' || r == '-' {
			return r
		}
		return -1
	}, t)
	if t == "" {
		return 0
	}
	v, _ := parseFloat64(t)
	return v
}

func parseFloat64(s string) (float64, error) {
	// minimal copy of strconv.ParseFloat, kept local to avoid pulling strconv
	// in just for the bench. Falls back to 0 on parse error.
	var n float64
	dot := -1
	for i, c := range s {
		if c == '.' {
			if dot >= 0 {
				return 0, fmt.Errorf("bad float")
			}
			dot = i
			continue
		}
		if c < '0' || c > '9' {
			return 0, fmt.Errorf("bad char")
		}
		n = n*10 + float64(c-'0')
	}
	if dot >= 0 {
		decimals := len(s) - dot - 1
		div := 1.0
		for i := 0; i < decimals; i++ {
			div *= 10
		}
		n /= div
	}
	return n, nil
}

// runTextractOnPage submits one page image to Textract AnalyzeDocument with
// FeatureTypes=TABLES and returns (data_row_count, brands_read, brands_total,
// cost_usd, error). Cost ~$0.015/page (the synchronous TABLES feature price).
func runTextractOnPage(client *textract.Client, raw []byte) (int, int, int, float64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	resp, err := client.AnalyzeDocument(ctx, &textract.AnalyzeDocumentInput{
		Document:     &ttypes.Document{Bytes: raw},
		FeatureTypes: []ttypes.FeatureType{ttypes.FeatureTypeTables},
	})
	if err != nil {
		return 0, 0, 0, 0, err
	}
	const costPerPage = 0.015
	blockByID := map[string]ttypes.Block{}
	for _, b := range resp.Blocks {
		if b.Id != nil {
			blockByID[*b.Id] = b
		}
	}
	bestRows := map[int32]bool{}
	bestCellCount := 0
	brandsRead, brandsTotal := 0, 0
	for _, b := range resp.Blocks {
		if b.BlockType != ttypes.BlockTypeTable {
			continue
		}
		rowSet := map[int32]bool{}
		cellCount := 0
		thisBrandsRead, thisBrandsTotal := 0, 0
		for _, rel := range b.Relationships {
			if rel.Type != ttypes.RelationshipTypeChild {
				continue
			}
			for _, cid := range rel.Ids {
				cell, ok := blockByID[cid]
				if !ok || cell.BlockType != ttypes.BlockTypeCell {
					continue
				}
				if cell.RowIndex != nil {
					rowSet[*cell.RowIndex] = true
					cellCount++
				}
				// chhotu's registers: col 1 = S.No, col 2 = Brand
				if cell.ColumnIndex != nil && *cell.ColumnIndex == 2 {
					thisBrandsTotal++
					if strings.TrimSpace(joinCellText(cell, blockByID)) != "" {
						thisBrandsRead++
					}
				}
			}
		}
		if cellCount > bestCellCount {
			bestCellCount = cellCount
			bestRows = rowSet
			brandsRead, brandsTotal = thisBrandsRead, thisBrandsTotal
		}
	}
	dataRows := len(bestRows)
	if dataRows > 0 {
		dataRows-- // header row
	}
	return dataRows, brandsRead, brandsTotal, costPerPage, nil
}

// joinCellText concatenates the text of a CELL's child WORD blocks.
func joinCellText(cell ttypes.Block, blockByID map[string]ttypes.Block) string {
	var parts []string
	for _, rel := range cell.Relationships {
		if rel.Type != ttypes.RelationshipTypeChild {
			continue
		}
		for _, id := range rel.Ids {
			child, ok := blockByID[id]
			if !ok {
				continue
			}
			if child.BlockType == ttypes.BlockTypeWord && child.Text != nil {
				parts = append(parts, *child.Text)
			}
		}
	}
	return strings.Join(parts, " ")
}

// runBenchTextract is what pipeline_bench.go's benchPipelineTextract dispatches
// to. Lives in this separate file so the AWS SDK import surface is isolated.
func runBenchTextract(j *benchJobMeta, out *pipelineBenchRow) {
	if os.Getenv("AWS_ACCESS_KEY_ID") == "" || os.Getenv("AWS_SECRET_ACCESS_KEY") == "" {
		out.Notes = "textract skipped: no AWS credentials in env"
		return
	}
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "ap-south-1"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	cfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	cancel()
	if err != nil {
		out.Notes = "textract config: " + err.Error()
		return
	}
	client := textract.NewFromConfig(cfg)

	totalRows, totalBrandsRead, totalBrandsTotal := 0, 0, 0
	totalCost := 0.0
	notes := []string{}
	for pageIdx, imgPath := range j.ImagePaths {
		hostPath := containerToHostPath(imgPath)
		raw, err := os.ReadFile(hostPath)
		if err != nil {
			notes = append(notes, fmt.Sprintf("p%d: open: %v", pageIdx+1, err))
			continue
		}
		rows, br, bt, cost, err := runTextractOnPage(client, raw)
		if err != nil {
			notes = append(notes, fmt.Sprintf("p%d: textract: %v", pageIdx+1, err))
			continue
		}
		totalRows += rows
		totalBrandsRead += br
		totalBrandsTotal += bt
		totalCost += cost
		notes = append(notes, fmt.Sprintf("p%d: rows=%d brands=%d/%d", pageIdx+1, rows, br, bt))
	}
	out.ExtractedRowCount = totalRows
	out.EstimatedCostUSD = totalCost
	if totalBrandsTotal > 0 {
		out.BrandMatchPct = 100.0 * float64(totalBrandsRead) / float64(totalBrandsTotal)
	}
	if len(notes) > 0 {
		out.Notes = "textract: " + strings.Join(notes, "; ")
	}
}
