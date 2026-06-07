package versioning

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/gin-gonic/gin"
	"go.uber.org/zap"
)

// BackwardCompatibilityManager handles backward compatibility between API versions
type BackwardCompatibilityManager struct {
	transformers map[string]Transformer
	adapters     map[string]RequestAdapter
	validators   map[string]Validator
	logger       *zap.Logger
}

// Transformer transforms responses between versions
type Transformer interface {
	TransformRequest(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error)
	TransformResponse(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error)
}

// RequestAdapter adapts requests between versions
type RequestAdapter interface {
	AdaptRequest(c *gin.Context, version *APIVersion) error
	AdaptResponse(c *gin.Context, data interface{}, version *APIVersion) interface{}
}

// Validator validates data for specific versions
type Validator interface {
	Validate(data interface{}, version *APIVersion) error
}

// NewBackwardCompatibilityManager creates a new backward compatibility manager
func NewBackwardCompatibilityManager(logger *zap.Logger) *BackwardCompatibilityManager {
	bcm := &BackwardCompatibilityManager{
		transformers: make(map[string]Transformer),
		adapters:     make(map[string]RequestAdapter),
		validators:   make(map[string]Validator),
		logger:       logger,
	}

	// Register default transformers
	bcm.RegisterTransformer("product", &ProductTransformer{})
	bcm.RegisterTransformer("user", &UserTransformer{})
	bcm.RegisterTransformer("sale", &SaleTransformer{})
	bcm.RegisterTransformer("inventory", &InventoryTransformer{})

	return bcm
}

// RegisterTransformer registers a transformer for a resource type
func (bcm *BackwardCompatibilityManager) RegisterTransformer(resourceType string, transformer Transformer) {
	bcm.transformers[resourceType] = transformer
}

// RegisterAdapter registers an adapter for a resource type
func (bcm *BackwardCompatibilityManager) RegisterAdapter(resourceType string, adapter RequestAdapter) {
	bcm.adapters[resourceType] = adapter
}

// RegisterValidator registers a validator for a resource type
func (bcm *BackwardCompatibilityManager) RegisterValidator(resourceType string, validator Validator) {
	bcm.validators[resourceType] = validator
}

// TransformMiddleware creates middleware for automatic transformation
func (bcm *BackwardCompatibilityManager) TransformMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Store original response writer
		originalWriter := c.Writer

		// Create response capturer
		capturer := &responseCapturer{
			ResponseWriter: originalWriter,
			body:          []byte{},
			headers:       make(map[string][]string),
		}
		c.Writer = capturer

		// Process request
		c.Next()

		// Get version information
		version := c.MustGet("api_version").(*APIVersion)
		currentVersion := c.MustGet("current_version").(*APIVersion)

		// Check if transformation is needed
		if version.Compare(currentVersion) != 0 {
			// Get resource type from path
			resourceType := bcm.extractResourceType(c.Request.URL.Path)

			// Get appropriate transformer
			if transformer, exists := bcm.transformers[resourceType]; exists {
				// Parse captured response
				var responseData interface{}
				if err := json.Unmarshal(capturer.body, &responseData); err == nil {
					// Transform response
					transformed, err := transformer.TransformResponse(responseData, currentVersion, version)
					if err != nil {
						bcm.logger.Error("Failed to transform response",
							zap.String("resource", resourceType),
							zap.Error(err))
					} else {
						// Write transformed response
						transformedBytes, _ := json.Marshal(transformed)
						originalWriter.Header().Set("Content-Type", "application/json")
						originalWriter.WriteHeader(capturer.statusCode)
						originalWriter.Write(transformedBytes)
						return
					}
				}
			}
		}

		// Write original response if no transformation needed
		for key, values := range capturer.headers {
			for _, value := range values {
				originalWriter.Header().Add(key, value)
			}
		}
		originalWriter.WriteHeader(capturer.statusCode)
		originalWriter.Write(capturer.body)
	}
}

// extractResourceType extracts resource type from path
func (bcm *BackwardCompatibilityManager) extractResourceType(path string) string {
	parts := strings.Split(strings.Trim(path, "/"), "/")
	for _, part := range parts {
		switch part {
		case "products", "product":
			return "product"
		case "users", "user":
			return "user"
		case "sales", "sale":
			return "sale"
		case "inventory", "stock":
			return "inventory"
		}
	}
	return "generic"
}

// responseCapturer captures response for transformation
type responseCapturer struct {
	gin.ResponseWriter
	body       []byte
	headers    map[string][]string
	statusCode int
}

func (rc *responseCapturer) Write(b []byte) (int, error) {
	rc.body = append(rc.body, b...)
	return len(b), nil
}

func (rc *responseCapturer) WriteHeader(statusCode int) {
	rc.statusCode = statusCode
}

// ProductTransformer handles product transformations
type ProductTransformer struct{}

func (pt *ProductTransformer) TransformRequest(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	// Convert to map for manipulation
	dataMap, err := toMap(data)
	if err != nil {
		return data, err
	}

	// V1 -> V2 request transformation
	if fromVersion.Major == 1 && toVersion.Major == 2 {
		// V2 expects nested structure
		if _, exists := dataMap["metadata"]; !exists {
			dataMap["metadata"] = make(map[string]interface{})
		}

		// Move certain fields to metadata
		fieldsToMove := []string{"supplier", "barcode", "notes"}
		metadata := dataMap["metadata"].(map[string]interface{})
		for _, field := range fieldsToMove {
			if value, exists := dataMap[field]; exists {
				metadata[field] = value
				delete(dataMap, field)
			}
		}
	}

	// V2 -> V1 request transformation
	if fromVersion.Major == 2 && toVersion.Major == 1 {
		// Flatten metadata
		if metadata, exists := dataMap["metadata"].(map[string]interface{}); exists {
			for key, value := range metadata {
				dataMap[key] = value
			}
			delete(dataMap, "metadata")
		}

		// Remove V2-only fields
		v2OnlyFields := []string{"variants", "attributes", "tags"}
		for _, field := range v2OnlyFields {
			delete(dataMap, field)
		}
	}

	return dataMap, nil
}

func (pt *ProductTransformer) TransformResponse(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	// Handle both single and array responses
	if array, ok := data.([]interface{}); ok {
		transformed := make([]interface{}, len(array))
		for i, item := range array {
			t, err := pt.transformSingleProduct(item, fromVersion, toVersion)
			if err != nil {
				return data, err
			}
			transformed[i] = t
		}
		return transformed, nil
	}

	return pt.transformSingleProduct(data, fromVersion, toVersion)
}

func (pt *ProductTransformer) transformSingleProduct(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	dataMap, err := toMap(data)
	if err != nil {
		return data, err
	}

	// V2 -> V1 response transformation
	if fromVersion.Major == 2 && toVersion.Major == 1 {
		// Flatten nested structures
		if details, exists := dataMap["details"].(map[string]interface{}); exists {
			for key, value := range details {
				dataMap[fmt.Sprintf("detail_%s", key)] = value
			}
			delete(dataMap, "details")
		}

		// Remove V2-specific fields
		delete(dataMap, "metadata")
		delete(dataMap, "variants")
		delete(dataMap, "created_by")
		delete(dataMap, "updated_by")

		// Rename fields for V1
		if val, exists := dataMap["product_name"]; exists {
			dataMap["name"] = val
			delete(dataMap, "product_name")
		}
	}

	// V1 -> V2 response transformation
	if fromVersion.Major == 1 && toVersion.Major == 2 {
		// Add V2 default fields
		if _, exists := dataMap["metadata"]; !exists {
			dataMap["metadata"] = make(map[string]interface{})
		}

		if _, exists := dataMap["variants"]; !exists {
			dataMap["variants"] = []interface{}{}
		}

		// Rename fields for V2
		if val, exists := dataMap["name"]; exists {
			dataMap["product_name"] = val
			// Keep "name" for backward compatibility
		}

		// Add timestamps if not present
		if _, exists := dataMap["created_at"]; !exists {
			dataMap["created_at"] = nil
		}
		if _, exists := dataMap["updated_at"]; !exists {
			dataMap["updated_at"] = nil
		}
	}

	return dataMap, nil
}

// UserTransformer handles user transformations
type UserTransformer struct{}

func (ut *UserTransformer) TransformRequest(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	dataMap, err := toMap(data)
	if err != nil {
		return data, err
	}

	// V1 -> V2 transformation
	if fromVersion.Major == 1 && toVersion.Major == 2 {
		// V2 uses "full_name" instead of separate first/last
		if firstName, hasFirst := dataMap["first_name"]; hasFirst {
			if lastName, hasLast := dataMap["last_name"]; hasLast {
				dataMap["full_name"] = fmt.Sprintf("%v %v", firstName, lastName)
				delete(dataMap, "first_name")
				delete(dataMap, "last_name")
			}
		}

		// V2 has enhanced permissions
		if role, exists := dataMap["role"]; exists {
			dataMap["permissions"] = getPermissionsForRole(role.(string))
		}
	}

	// V2 -> V1 transformation
	if fromVersion.Major == 2 && toVersion.Major == 1 {
		// Split full_name back to first/last
		if fullName, exists := dataMap["full_name"].(string); exists {
			parts := strings.SplitN(fullName, " ", 2)
			dataMap["first_name"] = parts[0]
			if len(parts) > 1 {
				dataMap["last_name"] = parts[1]
			} else {
				dataMap["last_name"] = ""
			}
			delete(dataMap, "full_name")
		}

		// Remove V2-only fields
		delete(dataMap, "permissions")
		delete(dataMap, "preferences")
		delete(dataMap, "two_factor_enabled")
	}

	return dataMap, nil
}

func (ut *UserTransformer) TransformResponse(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	dataMap, err := toMap(data)
	if err != nil {
		return data, err
	}

	// Similar logic to TransformRequest but for responses
	return ut.TransformRequest(dataMap, fromVersion, toVersion)
}

// SaleTransformer handles sale transformations
type SaleTransformer struct{}

func (st *SaleTransformer) TransformRequest(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	dataMap, err := toMap(data)
	if err != nil {
		return data, err
	}

	// V1 -> V2 transformation
	if fromVersion.Major == 1 && toVersion.Major == 2 {
		// V2 has detailed payment information
		if paymentType, exists := dataMap["payment_type"]; exists {
			dataMap["payment"] = map[string]interface{}{
				"type":   paymentType,
				"status": "completed",
			}
			delete(dataMap, "payment_type")
		}

		// V2 has line items instead of products
		if products, exists := dataMap["products"]; exists {
			dataMap["line_items"] = products
			delete(dataMap, "products")
		}
	}

	// V2 -> V1 transformation
	if fromVersion.Major == 2 && toVersion.Major == 1 {
		// Extract payment type from payment object
		if payment, exists := dataMap["payment"].(map[string]interface{}); exists {
			if paymentType, hasType := payment["type"]; hasType {
				dataMap["payment_type"] = paymentType
			}
			delete(dataMap, "payment")
		}

		// Rename line_items back to products
		if lineItems, exists := dataMap["line_items"]; exists {
			dataMap["products"] = lineItems
			delete(dataMap, "line_items")
		}

		// Remove V2-only fields
		delete(dataMap, "invoice")
		delete(dataMap, "shipping")
		delete(dataMap, "tracking")
	}

	return dataMap, nil
}

func (st *SaleTransformer) TransformResponse(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	return st.TransformRequest(data, fromVersion, toVersion)
}

// InventoryTransformer handles inventory transformations
type InventoryTransformer struct{}

func (it *InventoryTransformer) TransformRequest(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	dataMap, err := toMap(data)
	if err != nil {
		return data, err
	}

	// V1 -> V2 transformation
	if fromVersion.Major == 1 && toVersion.Major == 2 {
		// V2 has separate stock levels
		if quantity, exists := dataMap["quantity"]; exists {
			dataMap["stock_levels"] = map[string]interface{}{
				"available": quantity,
				"reserved":  0,
				"total":     quantity,
			}
			delete(dataMap, "quantity")
		}

		// V2 has location tracking
		if shopID, exists := dataMap["shop_id"]; exists {
			dataMap["location"] = map[string]interface{}{
				"shop_id": shopID,
				"zone":    "default",
			}
		}
	}

	// V2 -> V1 transformation
	if fromVersion.Major == 2 && toVersion.Major == 1 {
		// Extract quantity from stock_levels
		if stockLevels, exists := dataMap["stock_levels"].(map[string]interface{}); exists {
			if available, hasAvailable := stockLevels["available"]; hasAvailable {
				dataMap["quantity"] = available
			}
			delete(dataMap, "stock_levels")
		}

		// Extract shop_id from location
		if location, exists := dataMap["location"].(map[string]interface{}); exists {
			if shopID, hasShop := location["shop_id"]; hasShop {
				dataMap["shop_id"] = shopID
			}
			delete(dataMap, "location")
		}

		// Remove V2-only fields
		delete(dataMap, "movements")
		delete(dataMap, "adjustments")
		delete(dataMap, "forecasts")
	}

	return dataMap, nil
}

func (it *InventoryTransformer) TransformResponse(data interface{}, fromVersion, toVersion *APIVersion) (interface{}, error) {
	return it.TransformRequest(data, fromVersion, toVersion)
}

// Helper functions

func toMap(data interface{}) (map[string]interface{}, error) {
	// If already a map, return it
	if m, ok := data.(map[string]interface{}); ok {
		return m, nil
	}

	// Convert struct to map via JSON
	jsonBytes, err := json.Marshal(data)
	if err != nil {
		return nil, err
	}

	var result map[string]interface{}
	if err := json.Unmarshal(jsonBytes, &result); err != nil {
		return nil, err
	}

	return result, nil
}

func getPermissionsForRole(role string) []string {
	switch strings.ToUpper(role) {
	case "SUPER_ADMIN":
		return []string{"*"}
	case "ADMIN":
		return []string{"users.*", "products.*", "sales.*", "inventory.*", "reports.*"}
	case "MANAGER":
		return []string{"products.read", "products.write", "sales.*", "inventory.*", "reports.read"}
	case "SALESMAN":
		return []string{"products.read", "sales.create", "sales.read", "inventory.read"}
	default:
		return []string{"products.read"}
	}
}

// FieldMapper maps fields between versions
type FieldMapper struct {
	mappings map[string]map[string]string // version -> field mappings
}

// NewFieldMapper creates a new field mapper
func NewFieldMapper() *FieldMapper {
	fm := &FieldMapper{
		mappings: make(map[string]map[string]string),
	}

	// Define field mappings between versions
	fm.mappings["v1->v2"] = map[string]string{
		"name":         "product_name",
		"payment_type": "payment.type",
		"products":     "line_items",
		"quantity":     "stock_levels.available",
	}

	fm.mappings["v2->v1"] = map[string]string{
		"product_name":        "name",
		"payment.type":        "payment_type",
		"line_items":          "products",
		"stock_levels.available": "quantity",
	}

	return fm
}

// MapFields maps fields between versions
func (fm *FieldMapper) MapFields(data map[string]interface{}, fromVersion, toVersion string) map[string]interface{} {
	mappingKey := fmt.Sprintf("%s->%s", fromVersion, toVersion)
	mappings, exists := fm.mappings[mappingKey]
	if !exists {
		return data
	}

	result := make(map[string]interface{})

	for key, value := range data {
		if newKey, hasmapping := mappings[key]; hasmapping {
			// Handle nested field mapping
			if strings.Contains(newKey, ".") {
				setNestedField(result, newKey, value)
			} else {
				result[newKey] = value
			}
		} else {
			// Keep unmapped fields as-is
			result[key] = value
		}
	}

	return result
}

func setNestedField(data map[string]interface{}, path string, value interface{}) {
	parts := strings.Split(path, ".")
	current := data

	for i, part := range parts[:len(parts)-1] {
		if _, exists := current[part]; !exists {
			current[part] = make(map[string]interface{})
		}
		if next, ok := current[part].(map[string]interface{}); ok {
			current = next
		} else {
			// Can't navigate further, create new map
			newMap := make(map[string]interface{})
			current[part] = newMap
			current = newMap
		}
		_ = i
	}

	current[parts[len(parts)-1]] = value
}

// SchemaEvolution tracks schema changes across versions
type SchemaEvolution struct {
	changes map[string][]SchemaChange
	logger  *zap.Logger
}

// SchemaChange represents a schema change
type SchemaChange struct {
	Version     string
	Type        string // added, removed, renamed, type_changed
	Field       string
	OldField    string // for renames
	Description string
}

// NewSchemaEvolution creates a new schema evolution tracker
func NewSchemaEvolution(logger *zap.Logger) *SchemaEvolution {
	se := &SchemaEvolution{
		changes: make(map[string][]SchemaChange),
		logger:  logger,
	}

	// Document schema changes
	se.DocumentChanges()

	return se
}

// DocumentChanges documents all schema changes between versions
func (se *SchemaEvolution) DocumentChanges() {
	// Product schema changes
	se.changes["product"] = []SchemaChange{
		{Version: "v2", Type: "added", Field: "metadata", Description: "Added metadata field for extensibility"},
		{Version: "v2", Type: "added", Field: "variants", Description: "Added support for product variants"},
		{Version: "v2", Type: "renamed", Field: "product_name", OldField: "name", Description: "Renamed for clarity"},
		{Version: "v2", Type: "removed", Field: "supplier", Description: "Moved to metadata"},
	}

	// User schema changes
	se.changes["user"] = []SchemaChange{
		{Version: "v2", Type: "added", Field: "full_name", Description: "Combined first and last name"},
		{Version: "v2", Type: "removed", Field: "first_name", Description: "Replaced by full_name"},
		{Version: "v2", Type: "removed", Field: "last_name", Description: "Replaced by full_name"},
		{Version: "v2", Type: "added", Field: "permissions", Description: "Granular permissions system"},
	}
}

// GetChanges returns schema changes for a resource
func (se *SchemaEvolution) GetChanges(resource string, fromVersion, toVersion string) []SchemaChange {
	changes, exists := se.changes[resource]
	if !exists {
		return []SchemaChange{}
	}

	// Filter changes between versions
	var relevantChanges []SchemaChange
	for _, change := range changes {
		if se.isRelevantChange(change, fromVersion, toVersion) {
			relevantChanges = append(relevantChanges, change)
		}
	}

	return relevantChanges
}

func (se *SchemaEvolution) isRelevantChange(change SchemaChange, fromVersion, toVersion string) bool {
	// Simple version comparison logic
	// In production, use proper version comparison
	return true
}

// MigrationGuide generates migration guide between versions
func (se *SchemaEvolution) GenerateMigrationGuide(resource string, fromVersion, toVersion string) string {
	changes := se.GetChanges(resource, fromVersion, toVersion)

	var guide strings.Builder
	guide.WriteString(fmt.Sprintf("# Migration Guide: %s %s -> %s\n\n", resource, fromVersion, toVersion))

	for _, change := range changes {
		switch change.Type {
		case "added":
			guide.WriteString(fmt.Sprintf("## New Field: %s\n", change.Field))
			guide.WriteString(fmt.Sprintf("- %s\n", change.Description))
			guide.WriteString("- Action: Provide default value or make optional\n\n")

		case "removed":
			guide.WriteString(fmt.Sprintf("## Removed Field: %s\n", change.Field))
			guide.WriteString(fmt.Sprintf("- %s\n", change.Description))
			guide.WriteString("- Action: Stop using this field\n\n")

		case "renamed":
			guide.WriteString(fmt.Sprintf("## Renamed Field: %s -> %s\n", change.OldField, change.Field))
			guide.WriteString(fmt.Sprintf("- %s\n", change.Description))
			guide.WriteString("- Action: Update field references\n\n")

		case "type_changed":
			guide.WriteString(fmt.Sprintf("## Type Changed: %s\n", change.Field))
			guide.WriteString(fmt.Sprintf("- %s\n", change.Description))
			guide.WriteString("- Action: Update data handling logic\n\n")
		}
	}

	return guide.String()
}