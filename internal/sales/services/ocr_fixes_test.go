package services

import (
	"fmt"
	"testing"
)

// Test Fix 1: Dynamic Receipt Type Detection
func TestDetectReceiptType(t *testing.T) {
	tests := []struct {
		name     string
		rawText  string
		expected string
	}{
		{
			name:     "90ml Receipt",
			rawText:  "KERALA STATE BEVERAGES\nSTOCK REGISTER FOR 90 M.L (NIPS)\nSERIAL BRAND NAME OPENING",
			expected: "90ml",
		},
		{
			name:     "180ml Receipt",
			rawText:  "STOCK REGISTER FOR 180 M.L\nBRAND NAME OPENING RECEIPT",
			expected: "180ml",
		},
		{
			name:     "375ml Receipt",
			rawText:  "STOCK REGISTER FOR 375 M.L\nBRAND NAME OPENING",
			expected: "375ml",
		},
		{
			name:     "750ml Receipt",
			rawText:  "STOCK REGISTER FOR 750 M.L\nBRAND NAME",
			expected: "750ml",
		},
		{
			name:     "Default 180ml",
			rawText:  "BEVERAGE STOCK REGISTER\nBRAND NAME OPENING",
			expected: "180ml",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := detectReceiptType(tt.rawText)
			if result != tt.expected {
				t.Errorf("detectReceiptType() = %v, want %v", result, tt.expected)
			} else {
				fmt.Printf("✅ %s: Detected %s correctly\n", tt.name, result)
			}
		})
	}
}

// Test Fix 2: Multi-Brand Detection
func TestDetectMultipleBrands(t *testing.T) {
	tests := []struct {
		name          string
		brandName     string
		expectMerged  bool
		expectedBrands []string
	}{
		{
			name:         "Valid Single Brand",
			brandName:    "Royal Stag Whisky",
			expectMerged: false,
		},
		{
			name:         "Merged: 8PM + Royal Stag",
			brandName:    "8 P.M. Black Royal Stag",
			expectMerged: true,
		},
		{
			name:         "Merged: Royal Challenge + Imperial Blue",
			brandName:    "Royal Challenge Imperial Blue",
			expectMerged: true,
		},
		{
			name:         "Merged: McDowell + Officers Choice",
			brandName:    "McDowell's No.1 Officers Choice",
			expectMerged: true,
		},
		{
			name:         "Valid Blenders Pride",
			brandName:    "Blenders Pride Reserve",
			expectMerged: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			isMerged, reason := detectMultipleBrands(tt.brandName)
			if isMerged != tt.expectMerged {
				t.Errorf("detectMultipleBrands(%s) = %v, want %v (reason: %s)",
					tt.brandName, isMerged, tt.expectMerged, reason)
			} else if tt.expectMerged {
				fmt.Printf("✅ %s: Correctly detected merged brands - %s\n", tt.name, reason)
			} else {
				fmt.Printf("✅ %s: Correctly identified as single brand\n", tt.name)
			}
		})
	}
}

// Test Fix 4: Size-Aware Price Validation
func TestValidatePriceWithSize(t *testing.T) {
	tests := []struct {
		name        string
		price       float64
		sizeText    string
		brandName   string
		expectValid bool
		description string
	}{
		{
			name:        "90ml Valid Price",
			price:       120.00,
			sizeText:    "90ml",
			brandName:   "Royal Stag",
			expectValid: true,
			description: "₹120 is valid for 90ml",
		},
		{
			name:        "90ml Too Low",
			price:       25.00,
			sizeText:    "90ml",
			brandName:   "Royal Stag",
			expectValid: false,
			description: "₹25 is too low for 90ml (min ₹40)",
		},
		{
			name:        "180ml Valid Price",
			price:       280.00,
			sizeText:    "180ml",
			brandName:   "Royal Stag",
			expectValid: true,
			description: "₹280 is valid for 180ml",
		},
		{
			name:        "180ml Too Low",
			price:       50.00,
			sizeText:    "180ml",
			brandName:   "Blenders Pride",
			expectValid: false,
			description: "₹50 is too low for 180ml (min ₹80)",
		},
		{
			name:        "750ml Valid Price",
			price:       800.00,
			sizeText:    "750ml",
			brandName:   "Blenders Pride",
			expectValid: true,
			description: "₹800 is valid for 750ml",
		},
		{
			name:        "750ml Too Low",
			price:       150.00,
			sizeText:    "750ml",
			brandName:   "Royal Stag",
			expectValid: false,
			description: "₹150 is too low for 750ml (min ₹300)",
		},
		{
			name:        "Premium Brand High Price OK",
			price:       5500.00,
			sizeText:    "750ml",
			brandName:   "Johnnie Walker Blue Label",
			expectValid: true,
			description: "₹5500 is valid for premium brand",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			isValid, reason := validatePriceWithSize(tt.price, tt.sizeText, tt.brandName)
			if isValid != tt.expectValid {
				t.Errorf("validatePriceWithSize(%v, %s, %s) = %v, want %v (reason: %s)",
					tt.price, tt.sizeText, tt.brandName, isValid, tt.expectValid, reason)
			} else if tt.expectValid {
				fmt.Printf("✅ %s: %s\n", tt.name, tt.description)
			} else {
				fmt.Printf("✅ %s: Correctly flagged - %s\n", tt.name, reason)
			}
		})
	}
}

// Test Fix 1: Dynamic Column Mapping
func TestGetColumnMapping(t *testing.T) {
	tests := []struct {
		name        string
		receiptType string
		numCount    int
		expectRate  int
	}{
		{
			name:        "Standard 7-column 180ml",
			receiptType: "180ml",
			numCount:    7,
			expectRate:  4,
		},
		{
			name:        "Compact 6-column 180ml",
			receiptType: "180ml",
			numCount:    6,
			expectRate:  3,
		},
		{
			name:        "Standard 7-column 90ml",
			receiptType: "90ml",
			numCount:    7,
			expectRate:  4,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			colMap := getColumnMapping(tt.receiptType, tt.numCount)
			ratePos := colMap["rate"]
			if ratePos != tt.expectRate {
				t.Errorf("getColumnMapping(%s, %d)['rate'] = %d, want %d",
					tt.receiptType, tt.numCount, ratePos, tt.expectRate)
			} else {
				fmt.Printf("✅ %s: Rate column at position %d\n", tt.name, ratePos)
			}
		})
	}
}
