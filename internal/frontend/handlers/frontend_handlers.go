package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/liquorpro/go-backend/internal/frontend/services"
)

type FrontendHandlers struct {
	frontendService *services.FrontendService
}

func NewFrontendHandlers(frontendService *services.FrontendService) *FrontendHandlers {
	return &FrontendHandlers{
		frontendService: frontendService,
	}
}

// Authentication handlers
func (h *FrontendHandlers) ShowLogin(c *gin.Context) {
	c.HTML(http.StatusOK, "auth/login.html", gin.H{
		"title": "Login - LiquorPro",
	})
}

func (h *FrontendHandlers) HandleLogin(c *gin.Context) {
	email := c.PostForm("email")
	password := c.PostForm("password")

	if email == "" || password == "" {
		c.HTML(http.StatusBadRequest, "auth/login.html", gin.H{
			"title": "Login - LiquorPro",
			"error": "Email and password are required",
		})
		return
	}

	result, err := h.frontendService.Login(c.Request.Context(), email, password)
	if err != nil {
		c.HTML(http.StatusUnauthorized, "auth/login.html", gin.H{
			"title": "Login - LiquorPro",
			"error": err.Error(),
		})
		return
	}

	// Set session cookie
	if token, ok := result["token"].(string); ok {
		c.SetCookie("auth_token", token, 3600*24*7, "/", "", false, true) // 7 days
	}

	c.Redirect(http.StatusFound, "/dashboard")
}

func (h *FrontendHandlers) HandleLogout(c *gin.Context) {
	c.SetCookie("auth_token", "", -1, "/", "", false, true)
	c.Redirect(http.StatusFound, "/login")
}

// Dashboard handlers
func (h *FrontendHandlers) ShowDashboard(c *gin.Context) {
	token := h.getAuthToken(c)
	if token == "" {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get user info
	user, err := h.frontendService.GetCurrentUser(c.Request.Context(), token)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get dashboard data
	dashboardData, err := h.frontendService.GetDashboardData(c.Request.Context(), token)
	if err != nil {
		dashboardData = make(map[string]interface{})
	}

	c.HTML(http.StatusOK, "dashboard/index.html", gin.H{
		"title": "Dashboard - LiquorPro",
		"user":  user,
		"data":  dashboardData,
	})
}

// Sales handlers
func (h *FrontendHandlers) ShowDailySales(c *gin.Context) {
	token := h.getAuthToken(c)
	if token == "" {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	user, err := h.frontendService.GetCurrentUser(c.Request.Context(), token)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get query parameters for pagination
	page := c.DefaultQuery("page", "1")
	limit := c.DefaultQuery("limit", "20")
	
	params := map[string]string{
		"limit":  limit,
		"offset": h.calculateOffset(page, limit),
	}

	// Get daily sales records
	salesData, err := h.frontendService.GetDailySalesRecords(c.Request.Context(), token, params)
	if err != nil {
		c.HTML(http.StatusInternalServerError, "error.html", gin.H{
			"title": "Error",
			"error": err.Error(),
		})
		return
	}

	c.HTML(http.StatusOK, "sales/daily.html", gin.H{
		"title":     "Daily Sales - LiquorPro",
		"user":      user,
		"salesData": salesData,
	})
}

func (h *FrontendHandlers) ShowDailySalesEntry(c *gin.Context) {
	token := h.getAuthToken(c)
	if token == "" {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	user, err := h.frontendService.GetCurrentUser(c.Request.Context(), token)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get products for the entry form
	products, err := h.frontendService.GetProducts(c.Request.Context(), token, map[string]string{
		"limit": "1000", // Get all products for dropdown
	})
	if err != nil {
		products = make(map[string]interface{})
	}

	c.HTML(http.StatusOK, "sales/daily-entry.html", gin.H{
		"title":    "Daily Sales Entry - LiquorPro",
		"user":     user,
		"products": products,
	})
}

func (h *FrontendHandlers) ShowSales(c *gin.Context) {
	token := h.getAuthToken(c)
	if token == "" {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	user, err := h.frontendService.GetCurrentUser(c.Request.Context(), token)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get query parameters
	page := c.DefaultQuery("page", "1")
	limit := c.DefaultQuery("limit", "20")
	
	params := map[string]string{
		"limit":  limit,
		"offset": h.calculateOffset(page, limit),
	}

	// Get sales data
	salesData, err := h.frontendService.GetSales(c.Request.Context(), token, params)
	if err != nil {
		c.HTML(http.StatusInternalServerError, "error.html", gin.H{
			"title": "Error",
			"error": err.Error(),
		})
		return
	}

	c.HTML(http.StatusOK, "sales/list.html", gin.H{
		"title":     "Sales - LiquorPro",
		"user":      user,
		"salesData": salesData,
	})
}

// Inventory handlers
func (h *FrontendHandlers) ShowProducts(c *gin.Context) {
	token := h.getAuthToken(c)
	if token == "" {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	user, err := h.frontendService.GetCurrentUser(c.Request.Context(), token)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get query parameters
	page := c.DefaultQuery("page", "1")
	limit := c.DefaultQuery("limit", "20")
	search := c.Query("search")
	categoryID := c.Query("category_id")
	brandID := c.Query("brand_id")
	
	params := map[string]string{
		"limit":  limit,
		"offset": h.calculateOffset(page, limit),
	}
	
	if search != "" {
		params["search"] = search
	}
	if categoryID != "" {
		params["category_id"] = categoryID
	}
	if brandID != "" {
		params["brand_id"] = brandID
	}

	// Get products data
	productsData, err := h.frontendService.GetProducts(c.Request.Context(), token, params)
	if err != nil {
		c.HTML(http.StatusInternalServerError, "error.html", gin.H{
			"title": "Error",
			"error": err.Error(),
		})
		return
	}

	// Get categories and brands for filters
	categories, _ := h.frontendService.GetCategories(c.Request.Context(), token)
	brands, _ := h.frontendService.GetBrands(c.Request.Context(), token)

	c.HTML(http.StatusOK, "inventory/products.html", gin.H{
		"title":        "Products - LiquorPro",
		"user":         user,
		"productsData": productsData,
		"categories":   categories,
		"brands":       brands,
		"search":       search,
		"categoryID":   categoryID,
		"brandID":      brandID,
	})
}

func (h *FrontendHandlers) ShowStock(c *gin.Context) {
	token := h.getAuthToken(c)
	if token == "" {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	user, err := h.frontendService.GetCurrentUser(c.Request.Context(), token)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get query parameters
	shopID := c.Query("shop_id")
	lowStock := c.Query("low_stock")
	
	params := map[string]string{}
	if shopID != "" {
		params["shop_id"] = shopID
	}
	if lowStock == "true" {
		params["low_stock"] = "true"
	}

	// Get stock data
	stockData, err := h.frontendService.GetStocks(c.Request.Context(), token, params)
	if err != nil {
		c.HTML(http.StatusInternalServerError, "error.html", gin.H{
			"title": "Error",
			"error": err.Error(),
		})
		return
	}

	c.HTML(http.StatusOK, "inventory/stock.html", gin.H{
		"title":     "Stock - LiquorPro",
		"user":      user,
		"stockData": stockData,
		"shopID":    shopID,
		"lowStock":  lowStock == "true",
	})
}

// Finance handlers
func (h *FrontendHandlers) ShowExpenses(c *gin.Context) {
	token := h.getAuthToken(c)
	if token == "" {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	user, err := h.frontendService.GetCurrentUser(c.Request.Context(), token)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get query parameters
	page := c.DefaultQuery("page", "1")
	limit := c.DefaultQuery("limit", "20")
	
	params := map[string]string{
		"limit":  limit,
		"offset": h.calculateOffset(page, limit),
	}

	// Get expenses data
	expensesData, err := h.frontendService.GetExpenses(c.Request.Context(), token, params)
	if err != nil {
		c.HTML(http.StatusInternalServerError, "error.html", gin.H{
			"title": "Error",
			"error": err.Error(),
		})
		return
	}

	c.HTML(http.StatusOK, "finance/expenses.html", gin.H{
		"title":        "Expenses - LiquorPro",
		"user":         user,
		"expensesData": expensesData,
	})
}

func (h *FrontendHandlers) ShowMoneyCollections(c *gin.Context) {
	token := h.getAuthToken(c)
	if token == "" {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	user, err := h.frontendService.GetCurrentUser(c.Request.Context(), token)
	if err != nil {
		c.Redirect(http.StatusFound, "/login")
		return
	}

	// Get query parameters
	status := c.Query("status")
	includeOverdue := c.Query("include_overdue")
	
	params := map[string]string{}
	if status != "" {
		params["status"] = status
	}
	if includeOverdue == "true" {
		params["include_overdue"] = "true"
	}

	// Get money collections data
	collectionsData, err := h.frontendService.GetMoneyCollections(c.Request.Context(), token, params)
	if err != nil {
		c.HTML(http.StatusInternalServerError, "error.html", gin.H{
			"title": "Error",
			"error": err.Error(),
		})
		return
	}

	c.HTML(http.StatusOK, "finance/money-collections.html", gin.H{
		"title":           "Money Collections - LiquorPro",
		"user":            user,
		"collectionsData": collectionsData,
		"status":          status,
		"includeOverdue":  includeOverdue == "true",
	})
}

// Helper methods
func (h *FrontendHandlers) getAuthToken(c *gin.Context) string {
	token, err := c.Cookie("auth_token")
	if err != nil {
		return ""
	}
	return token
}

func (h *FrontendHandlers) calculateOffset(pageStr, limitStr string) string {
	page, err := strconv.Atoi(pageStr)
	if err != nil || page < 1 {
		page = 1
	}

	limit, err := strconv.Atoi(limitStr)
	if err != nil || limit < 1 {
		limit = 20
	}

	offset := (page - 1) * limit
	return strconv.Itoa(offset)
}

// Error handler
func (h *FrontendHandlers) ShowError(c *gin.Context) {
	c.HTML(http.StatusInternalServerError, "error.html", gin.H{
		"title": "Error",
		"error": "An unexpected error occurred",
	})
}