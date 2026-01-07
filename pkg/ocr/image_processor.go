package ocr

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"image"
	"image/jpeg"
	"image/png"

	_ "image/gif"  // Register GIF decoder
	_ "golang.org/x/image/webp" // Register WebP decoder
)

// ImageProcessor handles image manipulation operations
type ImageProcessor struct {
	paddingPercent float64 // Extra padding to add around crops (default 5%)
	jpegQuality    int     // JPEG output quality (default 85)
}

// BoundingBox represents a region in the image as percentages (0-100)
type BoundingBox struct {
	X      float64 `json:"x"`      // Left edge as percentage
	Y      float64 `json:"y"`      // Top edge as percentage
	Width  float64 `json:"width"`  // Width as percentage
	Height float64 `json:"height"` // Height as percentage
}

// CropResult contains the cropped image data
type CropResult struct {
	ImageData    []byte  // Cropped image as bytes
	Base64Image  string  // Cropped image as base64
	OriginalSize image.Point
	CroppedSize  image.Point
	MimeType     string
}

// NewImageProcessor creates a new image processor with default settings
func NewImageProcessor() *ImageProcessor {
	return &ImageProcessor{
		paddingPercent: 5.0, // 5% padding by default
		jpegQuality:    85,
	}
}

// NewImageProcessorWithOptions creates an image processor with custom settings
func NewImageProcessorWithOptions(paddingPercent float64, jpegQuality int) *ImageProcessor {
	if paddingPercent < 0 {
		paddingPercent = 0
	}
	if paddingPercent > 20 {
		paddingPercent = 20 // Max 20% padding
	}
	if jpegQuality < 50 {
		jpegQuality = 50
	}
	if jpegQuality > 100 {
		jpegQuality = 100
	}

	return &ImageProcessor{
		paddingPercent: paddingPercent,
		jpegQuality:    jpegQuality,
	}
}

// CropImage crops the image based on the bounding box (percentages)
func (p *ImageProcessor) CropImage(imageData []byte, bbox BoundingBox) (*CropResult, error) {
	// Decode the image
	img, format, err := image.Decode(bytes.NewReader(imageData))
	if err != nil {
		return nil, fmt.Errorf("failed to decode image: %w", err)
	}

	bounds := img.Bounds()
	imgWidth := bounds.Max.X - bounds.Min.X
	imgHeight := bounds.Max.Y - bounds.Min.Y

	fmt.Printf("📐 [ImageProcessor] Original image: %dx%d (%s)\n", imgWidth, imgHeight, format)

	// Convert percentage bbox to pixel coordinates
	x := int(bbox.X * float64(imgWidth) / 100)
	y := int(bbox.Y * float64(imgHeight) / 100)
	width := int(bbox.Width * float64(imgWidth) / 100)
	height := int(bbox.Height * float64(imgHeight) / 100)

	// Add padding (but don't exceed image boundaries)
	paddingX := int(p.paddingPercent * float64(imgWidth) / 100)
	paddingY := int(p.paddingPercent * float64(imgHeight) / 100)

	x = max(0, x-paddingX)
	y = max(0, y-paddingY)
	width = min(imgWidth-x, width+2*paddingX)
	height = min(imgHeight-y, height+2*paddingY)

	fmt.Printf("✂️  [ImageProcessor] Cropping region: x=%d, y=%d, w=%d, h=%d (with %.1f%% padding)\n",
		x, y, width, height, p.paddingPercent)

	// Create the cropped image
	cropRect := image.Rect(x, y, x+width, y+height)
	croppedImg := cropImageRect(img, cropRect)

	// Encode the cropped image
	var buf bytes.Buffer
	var mimeType string

	// Use JPEG for photos (smaller file size)
	if format == "jpeg" || format == "jpg" {
		if err := jpeg.Encode(&buf, croppedImg, &jpeg.Options{Quality: p.jpegQuality}); err != nil {
			return nil, fmt.Errorf("failed to encode cropped image as JPEG: %w", err)
		}
		mimeType = "image/jpeg"
	} else if format == "png" {
		if err := png.Encode(&buf, croppedImg); err != nil {
			return nil, fmt.Errorf("failed to encode cropped image as PNG: %w", err)
		}
		mimeType = "image/png"
	} else {
		// Default to JPEG for other formats
		if err := jpeg.Encode(&buf, croppedImg, &jpeg.Options{Quality: p.jpegQuality}); err != nil {
			return nil, fmt.Errorf("failed to encode cropped image: %w", err)
		}
		mimeType = "image/jpeg"
	}

	imageBytes := buf.Bytes()
	fmt.Printf("📦 [ImageProcessor] Cropped image: %dx%d, %d bytes\n",
		width, height, len(imageBytes))

	return &CropResult{
		ImageData:    imageBytes,
		Base64Image:  base64.StdEncoding.EncodeToString(imageBytes),
		OriginalSize: image.Point{X: imgWidth, Y: imgHeight},
		CroppedSize:  image.Point{X: width, Y: height},
		MimeType:     mimeType,
	}, nil
}

// CropImageMultiple crops multiple regions from a single image
func (p *ImageProcessor) CropImageMultiple(imageData []byte, bboxes []BoundingBox) ([]*CropResult, error) {
	results := make([]*CropResult, 0, len(bboxes))

	for i, bbox := range bboxes {
		result, err := p.CropImage(imageData, bbox)
		if err != nil {
			fmt.Printf("⚠️ [ImageProcessor] Failed to crop region %d: %v\n", i, err)
			continue
		}
		results = append(results, result)
	}

	if len(results) == 0 {
		return nil, fmt.Errorf("failed to crop any regions")
	}

	return results, nil
}

// SplitImageHorizontally splits an image into left and right halves
func (p *ImageProcessor) SplitImageHorizontally(imageData []byte) ([]*CropResult, error) {
	bboxes := []BoundingBox{
		{X: 0, Y: 0, Width: 50, Height: 100},  // Left half
		{X: 50, Y: 0, Width: 50, Height: 100}, // Right half
	}
	return p.CropImageMultiple(imageData, bboxes)
}

// SplitImageVertically splits an image into top and bottom halves
func (p *ImageProcessor) SplitImageVertically(imageData []byte) ([]*CropResult, error) {
	bboxes := []BoundingBox{
		{X: 0, Y: 0, Width: 100, Height: 50},  // Top half
		{X: 0, Y: 50, Width: 100, Height: 50}, // Bottom half
	}
	return p.CropImageMultiple(imageData, bboxes)
}

// GetImageDimensions returns the dimensions of an image without fully decoding it
func (p *ImageProcessor) GetImageDimensions(imageData []byte) (width, height int, format string, err error) {
	config, fmt, err := image.DecodeConfig(bytes.NewReader(imageData))
	if err != nil {
		return 0, 0, "", err
	}
	return config.Width, config.Height, fmt, nil
}

// Helper function to crop an image to a rectangle
func cropImageRect(img image.Image, rect image.Rectangle) image.Image {
	type subImager interface {
		SubImage(r image.Rectangle) image.Image
	}

	if si, ok := img.(subImager); ok {
		return si.SubImage(rect)
	}

	// Fallback: create a new image manually
	rgba := image.NewRGBA(rect)
	for y := rect.Min.Y; y < rect.Max.Y; y++ {
		for x := rect.Min.X; x < rect.Max.X; x++ {
			rgba.Set(x, y, img.At(x, y))
		}
	}
	return rgba
}

// Helper functions
func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
