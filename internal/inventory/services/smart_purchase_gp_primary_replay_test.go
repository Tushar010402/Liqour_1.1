package services

import "testing"

// TestPostProcessGPPrimaryRows_RealFMTowerJob is the end-to-end deterministic
// replay of the post-extraction pipeline over the EXACT 40 rows produced for
// FM Tower job 52714ffc-6366-4edf-bd95-fb49257d4c18 (2026-06-01). It proves,
// on real captured data, that the v1.0.330 + v1.0.332 guards together:
//
//   - drop row 40 (the OCR'd gate-pass "Total 61/2438" footer line), and
//   - unbind row 23 ("SUPERIOR VODKA", mis-matched onto the Royal Stag
//     Superior Whisky product that row 36 owns by an exact match),
//
// while leaving every other real line — including row 39, the genuine M2
// Magic Moments 750ml that shares no product with anything after the footer
// drop — bound and intact.
func TestPostProcessGPPrimaryRows_RealFMTowerJob(t *testing.T) {
	rows := []SmartPurchaseExtractedItem{
		{RowNumber: 1, BrandName: "8PM Gold Blend of Scotch & Indian Grain Whisky", SizeML: 180, QuantityRaw: 2, QuantityBottles: 96, MatchConfidence: 1, ProductID: strPtr("8d20df01-115e-42c9-848a-c84506f6cb07")},
		{RowNumber: 2, BrandName: "ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY", SizeML: 375, QuantityRaw: 2, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("f4519df8-c433-431a-9b15-e60e9711463f")},
		{RowNumber: 3, BrandName: "After Dark Blue Rare Grain Whisky", SizeML: 750, QuantityRaw: 1, QuantityBottles: 12, MatchConfidence: 1, ProductID: strPtr("097bd15c-2de7-4f25-8e4b-a7c86083cb3d")},
		{RowNumber: 4, BrandName: "SEAGRAMS IMPERIAL BLUE DUAL CASK SMOOTH WHISKY", SizeML: 750, QuantityRaw: 1, QuantityBottles: 12, MatchConfidence: 1, ProductID: strPtr("64600c9a-a0de-4a6b-b945-77533cf00a93")},
		{RowNumber: 5, BrandName: "SEAGRAMS IMPERIAL BLUE DUAL CASK SMOOTH WHISKY", SizeML: 180, QuantityRaw: 3, QuantityBottles: 144, MatchConfidence: 1, ProductID: strPtr("b5a4884c-41fd-4e60-8380-d6263ed95395")},
		{RowNumber: 6, BrandName: "SEAGRAMS BLENDERS PRIDE RESERVE COLLECTION EXCLUSIVE WHISKY", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("9d9b3447-8436-422b-bd70-e1fdc0df296f")},
		{RowNumber: 7, BrandName: "ICONIQ WHITE DELUXE INTERNATIONAL GRAIN WHISKY", SizeML: 180, QuantityRaw: 3, QuantityBottles: 144, MatchConfidence: 1, ProductID: strPtr("7d3c6378-826e-4e43-aaa9-ad0dbdfddb07")},
		{RowNumber: 8, BrandName: "M2 Magic Moments Remix Superior Orange Flavoured Vodka", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("c0a49030-ef3c-42d2-9e6b-358492583398")},
		{RowNumber: 9, BrandName: "M2 MAGIC MOMENTS JAMUN SPICYMINT FLAVOURED VODKA", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("cc2f45c9-e728-4b64-81d7-1949a8b72990")},
		{RowNumber: 10, BrandName: "After Dark Blue Rare Grain Whisky", SizeML: 180, QuantityRaw: 3, QuantityBottles: 144, MatchConfidence: 1, ProductID: strPtr("91790fb4-7737-4c50-986d-3207cd99e974")},
		{RowNumber: 11, BrandName: "OFFICERS CHOICE ORIGINAL WHISKY", SizeML: 180, QuantityRaw: 10, QuantityBottles: 480, MatchConfidence: 1, ProductID: strPtr("fbb1e4f2-d1a6-4939-a604-7868699ef2ba")},
		{RowNumber: 12, BrandName: "Royal Green Reserve Blended Whisky", SizeML: 375, QuantityRaw: 1, QuantityBottles: 24, MatchConfidence: 1, ProductID: strPtr("c5863d96-bf62-40e3-8df6-b3cc02f95f09")},
		{RowNumber: 13, BrandName: "M2 Magic Moments Verve Cranberry Tease Premium Flavoured Vodka", SizeML: 375, QuantityRaw: 1, QuantityBottles: 24, MatchConfidence: 1, ProductID: strPtr("e59a2913-2a23-4858-9f23-329ddef27aac")},
		{RowNumber: 14, BrandName: "AMRUT'S PRESTIGE green CLASSIC WHISKY", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: nil},
		{RowNumber: 15, BrandName: "8 PM GOLD BLEND OF SCOTCH & INDIAN GRAIN WHISKY", SizeML: 375, QuantityRaw: 2, QuantityBottles: 48, MatchConfidence: 0.75, ProductID: nil},
		{RowNumber: 16, BrandName: "Moonwalk Green Apple Vodka", SizeML: 180, QuantityRaw: 3, QuantityBottles: 144, MatchConfidence: 1, ProductID: strPtr("677e87d3-7b60-4fa4-96ed-bbb41290ec47")},
		{RowNumber: 17, BrandName: "STERLING RESERVE B-7 SPECIAL BLENDED WHISKY", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: nil},
		{RowNumber: 18, BrandName: "Seagrams Blenders Pride Exclusive Premium Whisky", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("db4b1369-47e1-4f6e-a6ba-a2303e83aa3f")},
		{RowNumber: 19, BrandName: "Royal Green Reserve Blended Whisky", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("6c23cb81-ffe2-42ee-9f85-f6a3b3ca91c7")},
		{RowNumber: 20, BrandName: "After Dark Blue Rare Grain Whisky", SizeML: 375, QuantityRaw: 1, QuantityBottles: 24, MatchConfidence: 1, ProductID: strPtr("87fc97c6-a480-42c2-8652-0cf8eebc34ad")},
		{RowNumber: 21, BrandName: "Seagrams Royal Stag Superior Whisky", SizeML: 750, QuantityRaw: 1, QuantityBottles: 12, MatchConfidence: 1, ProductID: strPtr("17eb3f51-c244-42ab-b47d-332fa0ec247f")},
		{RowNumber: 22, BrandName: "Smirnoff Minty Jamun Triple Distilled Vodka", SizeML: 180, QuantityRaw: 3, QuantityBottles: 144, MatchConfidence: 1, ProductID: strPtr("75cd6f02-ddcd-40ef-be29-4d4e88359a70")},
		{RowNumber: 23, BrandName: "SUPERIOR VODKA", SizeML: 375, QuantityRaw: 1, QuantityBottles: 24, MatchConfidence: 0.95, ProductID: strPtr("00a2cfb9-a751-44d5-8fb4-ec9cbda6fa23")},
		{RowNumber: 24, BrandName: "M2 MAGIC MOMENTS SUPERIOR VODKA", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("451b2a2f-3bff-4a2d-89c6-b6aae23c5695")},
		{RowNumber: 25, BrandName: "M2 MAGIC MOMENTS REMIX SUPERIOR ORANGE FLAVOURED VODKA", SizeML: 375, QuantityRaw: 1, QuantityBottles: 24, MatchConfidence: 1, ProductID: strPtr("f408d575-0de5-4ae6-8103-83ebde913638")},
		{RowNumber: 26, BrandName: "SEAGRAMS IMPERIAL BLUE DUAL CASK SMOOTH WHISKY", SizeML: 375, QuantityRaw: 1, QuantityBottles: 24, MatchConfidence: 1, ProductID: strPtr("1afa95d0-ad1b-441c-a48c-d17ab85b6ccf")},
		{RowNumber: 27, BrandName: "SEAGRAMS ROYAL STAG BARREL SELECT RESERVE WHISKY", SizeML: 750, QuantityRaw: 1, QuantityBottles: 12, MatchConfidence: 1, ProductID: strPtr("bf7b4e1e-a8c6-4ad2-80b2-8d50a793c6a8")},
		{RowNumber: 28, BrandName: "STROKES ROYAL RESERVE WHISKY", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 0.6166666666666666, ProductID: strPtr("13f24db0-074c-4937-a0e5-b4b3bd3343ca")},
		{RowNumber: 29, BrandName: "ROYAL WHISKY", SizeML: 180, QuantityRaw: 3, QuantityBottles: 144, MatchConfidence: 0.95, ProductID: nil},
		{RowNumber: 30, BrandName: "SEAGRAMS ROYAL STAG SUPERIOR WHISKY", SizeML: 180, QuantityRaw: 1, QuantityBottles: 12, MatchConfidence: 1, ProductID: strPtr("dd9e6961-fadf-4373-81b5-6571aca6d5f3")},
		{RowNumber: 31, BrandName: "SEAGRAMS BLENDERS PRIDE EXCLUSIVE PREMIUM WHISKY", SizeML: 750, QuantityRaw: 1, QuantityBottles: 12, MatchConfidence: 1, ProductID: strPtr("a6dc8cab-2e40-4d09-bd7c-ab84b803e7cc")},
		{RowNumber: 32, BrandName: "SMIRNOFF MINTY JAMUN TRIPLE DISTILLED FLAVOURED VODKA", SizeML: 750, QuantityRaw: 1, QuantityBottles: 12, MatchConfidence: 1, ProductID: strPtr("e8a17be8-89c4-4b0a-afed-91c80c764cfc")},
		{RowNumber: 33, BrandName: "M2 MAGIC MOMENTS JAMUN SPICYMINT FLAVOURED VODKA", SizeML: 375, QuantityRaw: 1, QuantityBottles: 24, MatchConfidence: 1, ProductID: strPtr("521fbc7b-56f0-4098-b37e-4d7c3f45d2e1")},
		{RowNumber: 34, BrandName: "DHURANDHAR", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: nil},
		{RowNumber: 35, BrandName: "DHURANDHAR", SizeML: 375, QuantityRaw: 1, QuantityBottles: 24, MatchConfidence: 1, ProductID: nil},
		{RowNumber: 36, BrandName: "SEAGRAMS ROYAL STAG SUPERIOR WHISKY", SizeML: 375, QuantityRaw: 1, QuantityBottles: 96, MatchConfidence: 1, ProductID: strPtr("00a2cfb9-a751-44d5-8fb4-ec9cbda6fa23")},
		{RowNumber: 37, BrandName: "SEAGRAMS ROYAL STAG SUPERIOR WHISKY", SizeML: 90, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("15c0f7b5-7627-4dbb-b36e-35f518e5b8e2")},
		{RowNumber: 38, BrandName: "M2 MAGIC MOMENTS VERVE CRANBERRY TEASE PREMIUM FLAVOURED VODKA", SizeML: 180, QuantityRaw: 1, QuantityBottles: 48, MatchConfidence: 1, ProductID: strPtr("b4b9fe6a-1f46-4379-b8d8-891d9f5d9406")},
		{RowNumber: 39, BrandName: "M2 MAGIC MOMENTS JAMUN SPICYMINT FLAVOURED VODKA", SizeML: 750, QuantityRaw: 1, QuantityBottles: 12, MatchConfidence: 1, ProductID: strPtr("1ef5a296-9f20-4840-b4c3-04e351440ea1")},
		{RowNumber: 40, BrandName: "M2 MAGIC MOMENTS JAMUN SPICYMINT FLAVOURED VODKA", SizeML: 750, QuantityRaw: 91, QuantityBottles: 2438, MatchConfidence: 1, ProductID: strPtr("1ef5a296-9f20-4840-b4c3-04e351440ea1")},
	}

	got := postProcessGPPrimaryRows(rows)

	// 40 in → footer row dropped → 39 out.
	if len(got) != 39 {
		t.Fatalf("want 39 rows after footer drop, got %d", len(got))
	}

	// The footer phantom (2438 bottles) must be gone.
	for _, it := range got {
		if it.QuantityBottles == 2438 || it.QuantityRaw == 91 {
			t.Errorf("footer-total phantom row survived: %q (%d cs / %d btl)", it.BrandName, it.QuantityRaw, it.QuantityBottles)
		}
	}

	// Find the surviving rows by original brand+size to assert their bindings.
	// row 23 SUPERIOR VODKA 375ml must be UNBOUND (mis-bind) + flagged.
	// row 36 ROYAL STAG SUPERIOR WHISKY 375ml must KEEP its product.
	var vodka375, whisky375, m2_750 *SmartPurchaseExtractedItem
	for i := range got {
		switch {
		case got[i].BrandName == "SUPERIOR VODKA" && got[i].SizeML == 375:
			vodka375 = &got[i]
		case got[i].BrandName == "SEAGRAMS ROYAL STAG SUPERIOR WHISKY" && got[i].SizeML == 375:
			whisky375 = &got[i]
		case got[i].BrandName == "M2 MAGIC MOMENTS JAMUN SPICYMINT FLAVOURED VODKA" && got[i].SizeML == 750:
			m2_750 = &got[i]
		}
	}

	if vodka375 == nil || whisky375 == nil || m2_750 == nil {
		t.Fatalf("expected rows missing after post-process: vodka375=%v whisky375=%v m2_750=%v", vodka375 != nil, whisky375 != nil, m2_750 != nil)
	}
	if vodka375.ProductID != nil {
		t.Errorf("SUPERIOR VODKA 375ml should be UNBOUND (mis-bind), still has product %s", *vodka375.ProductID)
	}
	if !vodka375.NeedsReview || !hasWarning(vodka375, "duplicate_product_binding_unbound") {
		t.Errorf("SUPERIOR VODKA 375ml should be flagged for review; needsReview=%v warnings=%v", vodka375.NeedsReview, vodka375.Warnings)
	}
	if whisky375.ProductID == nil || *whisky375.ProductID != "00a2cfb9-a751-44d5-8fb4-ec9cbda6fa23" {
		t.Errorf("ROYAL STAG SUPERIOR WHISKY 375ml (exact match) must keep its product; got %v", whisky375.ProductID)
	}
	// The real M2 750ml (12 btl) must remain bound — only its footer twin died.
	if m2_750.ProductID == nil || *m2_750.ProductID != "1ef5a296-9f20-4840-b4c3-04e351440ea1" {
		t.Errorf("genuine M2 Magic Moments 750ml lost its binding: %v", m2_750.ProductID)
	}
}
