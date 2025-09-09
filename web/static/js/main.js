// LiquorPro Main JavaScript

// Initialize application
document.addEventListener('DOMContentLoaded', function() {
    initializeApp();
});

function initializeApp() {
    // Initialize tooltips
    initializeTooltips();
    
    // Initialize popovers
    initializePopovers();
    
    // Setup AJAX defaults
    setupAjaxDefaults();
    
    // Initialize auto-refresh for critical components
    initializeAutoRefresh();
    
    // Setup form validations
    setupFormValidations();
    
    // Initialize dashboard features
    initializeDashboard();
}

// Tooltip initialization
function initializeTooltips() {
    var tooltipTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="tooltip"]'));
    var tooltipList = tooltipTriggerList.map(function (tooltipTriggerEl) {
        return new bootstrap.Tooltip(tooltipTriggerEl);
    });
}

// Popover initialization
function initializePopovers() {
    var popoverTriggerList = [].slice.call(document.querySelectorAll('[data-bs-toggle="popover"]'));
    var popoverList = popoverTriggerList.map(function (popoverTriggerEl) {
        return new bootstrap.Popover(popoverTriggerEl);
    });
}

// AJAX setup with CSRF token and loading states
function setupAjaxDefaults() {
    // Add loading spinner overlay
    function showLoader() {
        if (!document.querySelector('.spinner-overlay')) {
            const spinnerHtml = `
                <div class="spinner-overlay">
                    <div class="spinner-border text-primary" role="status">
                        <span class="visually-hidden">Loading...</span>
                    </div>
                </div>
            `;
            document.body.insertAdjacentHTML('beforeend', spinnerHtml);
        }
    }
    
    function hideLoader() {
        const spinner = document.querySelector('.spinner-overlay');
        if (spinner) {
            spinner.remove();
        }
    }
    
    // Setup global AJAX handlers
    window.ajaxRequest = function(url, method = 'GET', data = null, successCallback = null, errorCallback = null) {
        showLoader();
        
        const options = {
            method: method,
            headers: {
                'Content-Type': 'application/json',
            }
        };
        
        if (data && method !== 'GET') {
            options.body = JSON.stringify(data);
        }
        
        fetch(url, options)
            .then(response => {
                hideLoader();
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                return response.json();
            })
            .then(data => {
                if (successCallback) {
                    successCallback(data);
                }
            })
            .catch(error => {
                hideLoader();
                console.error('AJAX Error:', error);
                if (errorCallback) {
                    errorCallback(error);
                } else {
                    showNotification('Error: ' + error.message, 'error');
                }
            });
    };
}

// Auto-refresh for critical components
function initializeAutoRefresh() {
    // Refresh money collections every 30 seconds if on finance page
    if (window.location.pathname.includes('/finance/collections')) {
        setInterval(function() {
            refreshMoneyCollections();
        }, 30000);
    }
    
    // Refresh dashboard stats every 5 minutes
    if (window.location.pathname === '/dashboard') {
        setInterval(function() {
            refreshDashboardStats();
        }, 300000);
    }
}

// Form validation setup
function setupFormValidations() {
    // Bootstrap form validation
    var forms = document.querySelectorAll('.needs-validation');
    
    Array.prototype.slice.call(forms).forEach(function (form) {
        form.addEventListener('submit', function (event) {
            if (!form.checkValidity()) {
                event.preventDefault();
                event.stopPropagation();
            }
            
            form.classList.add('was-validated');
        }, false);
    });
    
    // Custom validations
    setupCustomValidations();
}

// Custom form validations
function setupCustomValidations() {
    // Email validation
    const emailInputs = document.querySelectorAll('input[type="email"]');
    emailInputs.forEach(input => {
        input.addEventListener('blur', function() {
            validateEmail(this);
        });
    });
    
    // Phone validation
    const phoneInputs = document.querySelectorAll('input[type="tel"]');
    phoneInputs.forEach(input => {
        input.addEventListener('blur', function() {
            validatePhone(this);
        });
    });
    
    // Currency validation
    const currencyInputs = document.querySelectorAll('input[data-type="currency"]');
    currencyInputs.forEach(input => {
        input.addEventListener('blur', function() {
            validateCurrency(this);
        });
    });
}

// Email validation
function validateEmail(input) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    const isValid = emailRegex.test(input.value);
    
    updateInputValidation(input, isValid, 'Please enter a valid email address');
    return isValid;
}

// Phone validation
function validatePhone(input) {
    const phoneRegex = /^[\+]?[1-9][\d]{0,15}$/;
    const isValid = phoneRegex.test(input.value.replace(/\s/g, ''));
    
    updateInputValidation(input, isValid, 'Please enter a valid phone number');
    return isValid;
}

// Currency validation
function validateCurrency(input) {
    const currencyRegex = /^\d+(\.\d{1,2})?$/;
    const isValid = currencyRegex.test(input.value);
    
    updateInputValidation(input, isValid, 'Please enter a valid amount');
    return isValid;
}

// Update input validation state
function updateInputValidation(input, isValid, message) {
    const feedback = input.parentNode.querySelector('.invalid-feedback');
    
    if (isValid) {
        input.classList.remove('is-invalid');
        input.classList.add('is-valid');
    } else {
        input.classList.remove('is-valid');
        input.classList.add('is-invalid');
        if (feedback) {
            feedback.textContent = message;
        }
    }
}

// Dashboard specific functionality
function initializeDashboard() {
    if (window.location.pathname === '/dashboard') {
        // Initialize countdown timers for money collections
        initializeCountdownTimers();
        
        // Setup quick action buttons
        setupQuickActions();
    }
}

// Countdown timers for urgent items
function initializeCountdownTimers() {
    const timerElements = document.querySelectorAll('.collection-timer');
    
    if (timerElements.length > 0) {
        setInterval(function() {
            timerElements.forEach(updateTimer);
        }, 1000);
    }
}

function updateTimer(element) {
    const deadline = new Date(element.dataset.deadline);
    const now = new Date();
    const timeLeft = deadline - now;
    
    if (timeLeft <= 0) {
        element.textContent = 'EXPIRED';
        element.className = 'badge bg-danger collection-timer';
        return;
    }
    
    const minutes = Math.floor(timeLeft / (1000 * 60));
    const seconds = Math.floor((timeLeft % (1000 * 60)) / 1000);
    
    element.textContent = `${minutes}:${seconds.toString().padStart(2, '0')} left`;
    
    // Update color based on time left
    if (minutes <= 2) {
        element.className = 'badge bg-danger collection-timer';
    } else if (minutes <= 5) {
        element.className = 'badge bg-warning collection-timer';
    } else {
        element.className = 'badge bg-info collection-timer';
    }
}

// Quick action buttons setup
function setupQuickActions() {
    // Add loading states to quick action buttons
    const quickActionBtns = document.querySelectorAll('.btn[href]');
    quickActionBtns.forEach(btn => {
        btn.addEventListener('click', function() {
            this.classList.add('loading');
        });
    });
}

// Notification system
function showNotification(message, type = 'info', duration = 5000) {
    const alertClass = `alert-${type}`;
    const iconClass = getIconClass(type);
    
    const alertHtml = `
        <div class="alert ${alertClass} alert-dismissible fade show" role="alert">
            <i class="${iconClass} me-2"></i>${message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    `;
    
    // Add to notification container or create one
    let container = document.getElementById('notification-container');
    if (!container) {
        container = document.createElement('div');
        container.id = 'notification-container';
        container.style.position = 'fixed';
        container.style.top = '80px';
        container.style.right = '20px';
        container.style.zIndex = '9999';
        container.style.maxWidth = '400px';
        document.body.appendChild(container);
    }
    
    container.insertAdjacentHTML('afterbegin', alertHtml);
    
    // Auto-remove after duration
    if (duration > 0) {
        setTimeout(() => {
            const alert = container.querySelector('.alert');
            if (alert) {
                const bsAlert = new bootstrap.Alert(alert);
                bsAlert.close();
            }
        }, duration);
    }
}

function getIconClass(type) {
    const icons = {
        'success': 'fas fa-check-circle',
        'error': 'fas fa-exclamation-triangle',
        'warning': 'fas fa-exclamation-circle',
        'info': 'fas fa-info-circle',
        'danger': 'fas fa-exclamation-triangle'
    };
    return icons[type] || icons['info'];
}

// Data refresh functions
function refreshMoneyCollections() {
    ajaxRequest('/api/money-collections', 'GET', null, 
        function(data) {
            updateCollectionsTable(data);
        },
        function(error) {
            console.error('Failed to refresh collections:', error);
        }
    );
}

function refreshDashboardStats() {
    ajaxRequest('/api/dashboard/stats', 'GET', null,
        function(data) {
            updateDashboardStats(data);
        },
        function(error) {
            console.error('Failed to refresh dashboard stats:', error);
        }
    );
}

// Update functions for dynamic content
function updateCollectionsTable(data) {
    // Update collections table with new data
    // This would be implemented based on the actual API response structure
}

function updateDashboardStats(data) {
    // Update dashboard statistics
    // This would be implemented based on the actual API response structure
}

// Utility functions
function formatCurrency(amount) {
    return new Intl.NumberFormat('en-IN', {
        style: 'currency',
        currency: 'INR'
    }).format(amount);
}

function formatDate(dateString) {
    return new Date(dateString).toLocaleDateString('en-IN');
}

function formatDateTime(dateString) {
    return new Date(dateString).toLocaleString('en-IN');
}

// Daily sales entry specific functionality
if (window.location.pathname.includes('/sales/daily/entry')) {
    document.addEventListener('DOMContentLoaded', function() {
        setupDailySalesEntry();
    });
}

function setupDailySalesEntry() {
    // Add product row functionality
    const addRowBtn = document.getElementById('add-product-row');
    if (addRowBtn) {
        addRowBtn.addEventListener('click', addProductRow);
    }
    
    // Setup autocomplete for products
    setupProductAutocomplete();
    
    // Calculate totals automatically
    setupAutoCalculation();
}

function addProductRow() {
    const container = document.getElementById('product-rows-container');
    const rowCount = container.children.length;
    
    const rowHtml = `
        <div class="product-entry-row" data-row="${rowCount}">
            <div class="row">
                <div class="col-md-4">
                    <input type="text" class="form-control product-search" name="products[${rowCount}][name]" placeholder="Search product..." required>
                </div>
                <div class="col-md-2">
                    <input type="number" class="form-control quantity" name="products[${rowCount}][quantity]" placeholder="Qty" min="1" required>
                </div>
                <div class="col-md-2">
                    <input type="number" class="form-control unit-price" name="products[${rowCount}][unit_price]" placeholder="Price" step="0.01" required>
                </div>
                <div class="col-md-2">
                    <input type="number" class="form-control total-price" name="products[${rowCount}][total_price]" placeholder="Total" readonly>
                </div>
                <div class="col-md-2">
                    <button type="button" class="btn btn-danger btn-sm remove-row">
                        <i class="fas fa-trash"></i>
                    </button>
                </div>
            </div>
        </div>
    `;
    
    container.insertAdjacentHTML('beforeend', rowHtml);
    
    // Setup event listeners for the new row
    const newRow = container.lastElementChild;
    setupRowEventListeners(newRow);
}

function setupRowEventListeners(row) {
    // Remove row functionality
    const removeBtn = row.querySelector('.remove-row');
    removeBtn.addEventListener('click', function() {
        row.remove();
        calculateGrandTotal();
    });
    
    // Auto-calculate row total
    const quantityInput = row.querySelector('.quantity');
    const priceInput = row.querySelector('.unit-price');
    const totalInput = row.querySelector('.total-price');
    
    [quantityInput, priceInput].forEach(input => {
        input.addEventListener('input', function() {
            const quantity = parseFloat(quantityInput.value) || 0;
            const price = parseFloat(priceInput.value) || 0;
            const total = quantity * price;
            
            totalInput.value = total.toFixed(2);
            calculateGrandTotal();
        });
    });
}

function setupProductAutocomplete() {
    // This would implement product search/autocomplete functionality
    // Integration with the products API
}

function setupAutoCalculation() {
    // Setup automatic calculation of totals
    document.addEventListener('input', function(e) {
        if (e.target.classList.contains('quantity') || e.target.classList.contains('unit-price')) {
            calculateGrandTotal();
        }
    });
}

function calculateGrandTotal() {
    const totalInputs = document.querySelectorAll('.total-price');
    let grandTotal = 0;
    
    totalInputs.forEach(input => {
        grandTotal += parseFloat(input.value) || 0;
    });
    
    const grandTotalElement = document.getElementById('grand-total');
    if (grandTotalElement) {
        grandTotalElement.textContent = formatCurrency(grandTotal);
    }
}

// Export functions for global use
window.LiquorPro = {
    showNotification,
    formatCurrency,
    formatDate,
    formatDateTime,
    ajaxRequest
};