package utils

import (
	"strings"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// DisplayBoldTarget is a read-only snapshot of one response item's current
// display_name + bold state plus its link to the master saas_brand. Callers
// build a slice of these, pass a Setter that knows how to update the
// underlying response, and ApplyDisplayBoldFallback does the rest.
type DisplayBoldTarget struct {
	SaasBrandID *uuid.UUID
	DisplayName string
	BoldStart   *int
	BoldLength  *int
}

// DisplayBoldSetter is invoked for every target where the master saas_brand
// would supply usable bold indices. Called with i = index into the targets
// slice, so callers can map it back to their own response array.
type DisplayBoldSetter func(i int, displayName string, boldStart, boldLength *int)

// ApplyDisplayBoldFallback copies display_name + display_name_bold_*
// from the linked master saas_brand when the local bold config is absent.
// Batches the saas_brands lookup: a page of N items costs one extra query.
//
// Safety: we only copy master's bold indices onto a target when the string
// they'll style matches the string the indices were configured for — either
// the target has no display_name and we substitute master's, or the target's
// display_name equals master's. This prevents master's indices from slicing
// a different local display_name and highlighting the wrong characters.
func ApplyDisplayBoldFallback(db *gorm.DB, targets []DisplayBoldTarget, set DisplayBoldSetter) {
	if len(targets) == 0 || set == nil {
		return
	}

	idSet := map[uuid.UUID]struct{}{}
	for _, t := range targets {
		if t.SaasBrandID == nil {
			continue
		}
		if t.BoldLength != nil && *t.BoldLength > 0 {
			continue
		}
		idSet[*t.SaasBrandID] = struct{}{}
	}
	if len(idSet) == 0 {
		return
	}
	ids := make([]uuid.UUID, 0, len(idSet))
	for id := range idSet {
		ids = append(ids, id)
	}

	type sbRow struct {
		ID          uuid.UUID `gorm:"column:id"`
		DisplayName string    `gorm:"column:display_name"`
		BoldStart   *int      `gorm:"column:display_name_bold_start"`
		BoldLength  *int      `gorm:"column:display_name_bold_length"`
	}
	var rows []sbRow
	if err := db.Table("saas_brands").
		Select("id, display_name, display_name_bold_start, display_name_bold_length").
		Where("id IN ?", ids).
		Scan(&rows).Error; err != nil {
		return
	}
	byID := make(map[uuid.UUID]sbRow, len(rows))
	for _, r := range rows {
		byID[r.ID] = r
	}

	for i, t := range targets {
		if t.SaasBrandID == nil {
			continue
		}
		if t.BoldLength != nil && *t.BoldLength > 0 {
			continue
		}
		sb, ok := byID[*t.SaasBrandID]
		if !ok {
			continue
		}
		if sb.BoldLength == nil || *sb.BoldLength <= 0 {
			continue
		}
		masterDN := strings.TrimSpace(sb.DisplayName)
		if masterDN == "" {
			continue
		}

		currentDN := strings.TrimSpace(t.DisplayName)
		switch {
		case currentDN == "":
			set(i, masterDN, sb.BoldStart, sb.BoldLength)
		case currentDN == masterDN:
			set(i, masterDN, sb.BoldStart, sb.BoldLength)
		default:
			// Different custom display_name — skip to avoid wrong highlight.
		}
	}
}
