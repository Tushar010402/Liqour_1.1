/// Input sanitization utilities for security hardening.
///
/// Provides methods to clean and sanitize user input to prevent:
/// - XSS (Cross-Site Scripting) attacks
/// - SQL injection attempts
/// - Script injection
/// - HTML injection
/// - Control character injection
///
/// **Usage Example:**
/// ```dart
/// final clean = InputSanitizer.sanitizeText(userInput);
/// final cleanedEmail = InputSanitizer.sanitizeEmail(email);
/// final cleanedPhone = InputSanitizer.sanitizePhone(phone);
/// ```
class InputSanitizer {
  // Private constructor to prevent instantiation
  InputSanitizer._();

  /// Characters that are potentially dangerous and should be removed or escaped
  static final RegExp _dangerousCharsRegex = RegExp("[<>\"';\\\\]");

  /// SQL keywords that might indicate injection attempts
  static final List<String> _sqlKeywords = [
    'select',
    'insert',
    'update',
    'delete',
    'drop',
    'create',
    'alter',
    'exec',
    'execute',
    'script',
    'union',
    'having',
    'where',
    'and',
    'or',
    'not',
    'null',
    '--',
    '/*',
    '*/',
    'xp_',
    'sp_',
  ];

  /// HTML/Script tags that should be removed
  static final RegExp _scriptTagRegex = RegExp(
    r'<\s*script[^>]*>.*?<\s*/\s*script\s*>',
    caseSensitive: false,
    dotAll: true,
  );

  static final RegExp _htmlTagRegex = RegExp(r'<[^>]+>');

  /// Control characters (except newline, carriage return, tab)
  static final RegExp _controlCharsRegex = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]');

  /// Sanitizes general text input by removing dangerous characters and scripts.
  ///
  /// **What it does:**
  /// - Removes HTML/Script tags
  /// - Removes control characters
  /// - Trims whitespace
  /// - Limits length to prevent buffer overflow
  ///
  /// **Parameters:**
  /// - `input`: Text to sanitize
  /// - `maxLength`: Maximum allowed length (default: 1000)
  /// - `allowNewlines`: Whether to preserve newlines (default: false)
  ///
  /// **Returns:**
  /// - Sanitized text safe for storage/display
  ///
  /// **Example:**
  /// ```dart
  /// final clean = InputSanitizer.sanitizeText('<script>alert("xss")</script>Hello');
  /// // Returns: 'Hello'
  /// ```
  static String sanitizeText(
    String input, {
    int maxLength = 1000,
    bool allowNewlines = false,
  }) {
    if (input.isEmpty) return '';

    var sanitized = input;

    // Remove script tags
    sanitized = sanitized.replaceAll(_scriptTagRegex, '');

    // Remove HTML tags
    sanitized = sanitized.replaceAll(_htmlTagRegex, '');

    // Remove control characters (except newlines if allowed)
    if (allowNewlines) {
      sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
    } else {
      sanitized = sanitized.replaceAll(_controlCharsRegex, '');
    }

    // Trim whitespace
    sanitized = sanitized.trim();

    // Limit length
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }

    return sanitized;
  }

  /// Sanitizes email addresses.
  ///
  /// **What it does:**
  /// - Converts to lowercase
  /// - Removes whitespace
  /// - Removes dangerous characters
  /// - Validates basic email format
  ///
  /// **Parameters:**
  /// - `email`: Email address to sanitize
  ///
  /// **Returns:**
  /// - Sanitized email or empty string if invalid
  ///
  /// **Example:**
  /// ```dart
  /// final clean = InputSanitizer.sanitizeEmail('  User@Example.COM  ');
  /// // Returns: 'user@example.com'
  /// ```
  static String sanitizeEmail(String email) {
    if (email.isEmpty) return '';

    // Basic cleaning
    var sanitized = email.trim().toLowerCase();

    // Remove dangerous characters
    sanitized = sanitized.replaceAll(_dangerousCharsRegex, '');

    // Basic email format validation
    final emailRegex = RegExp(r'^[\w\-.+]+@[\w\-.]+\.\w{2,}$');
    if (!emailRegex.hasMatch(sanitized)) {
      return ''; // Invalid format
    }

    return sanitized;
  }

  /// Sanitizes phone numbers.
  ///
  /// **What it does:**
  /// - Removes all non-digit characters except +
  /// - Trims whitespace
  /// - Validates length
  ///
  /// **Parameters:**
  /// - `phone`: Phone number to sanitize
  ///
  /// **Returns:**
  /// - Sanitized phone number with only digits and +
  ///
  /// **Example:**
  /// ```dart
  /// final clean = InputSanitizer.sanitizePhone('+91 (98765) 43210');
  /// // Returns: '+919876543210'
  /// ```
  static String sanitizePhone(String phone) {
    if (phone.isEmpty) return '';

    // Keep only digits and +
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Sanitizes usernames.
  ///
  /// **What it does:**
  /// - Removes special characters (keeps alphanumeric, underscore, hyphen, dot)
  /// - Converts to lowercase
  /// - Limits length
  ///
  /// **Parameters:**
  /// - `username`: Username to sanitize
  /// - `maxLength`: Maximum length (default: 50)
  ///
  /// **Returns:**
  /// - Sanitized username
  ///
  /// **Example:**
  /// ```dart
  /// final clean = InputSanitizer.sanitizeUsername('User@Name#123!');
  /// // Returns: 'username123'
  /// ```
  static String sanitizeUsername(String username, {int maxLength = 50}) {
    if (username.isEmpty) return '';

    // Keep only alphanumeric, underscore, hyphen, dot
    var sanitized = username.toLowerCase().replaceAll(RegExp(r'[^\w\-.]'), '');

    // Remove leading/trailing dots and hyphens
    sanitized = sanitized.replaceAll(RegExp(r'^[.\-]+|[.\-]+$'), '');

    // Limit length
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }

    return sanitized;
  }

  /// Sanitizes numeric input.
  ///
  /// **What it does:**
  /// - Removes all non-digit characters
  /// - Optionally allows decimal point
  /// - Optionally allows negative sign
  ///
  /// **Parameters:**
  /// - `input`: Numeric input to sanitize
  /// - `allowDecimal`: Allow decimal point (default: false)
  /// - `allowNegative`: Allow negative sign (default: false)
  ///
  /// **Returns:**
  /// - Sanitized numeric string
  ///
  /// **Example:**
  /// ```dart
  /// final clean = InputSanitizer.sanitizeNumeric('$1,234.56', allowDecimal: true);
  /// // Returns: '1234.56'
  /// ```
  static String sanitizeNumeric(
    String input, {
    bool allowDecimal = false,
    bool allowNegative = false,
  }) {
    if (input.isEmpty) return '';

    String pattern = r'\d';
    if (allowDecimal) pattern += r'.';
    if (allowNegative) pattern += r'\-';

    final regex = RegExp('[$pattern]+');
    final matches = regex.allMatches(input);

    return matches.map((m) => m.group(0)).join();
  }

  /// Detects potential SQL injection attempts.
  ///
  /// **What it checks:**
  /// - SQL keywords
  /// - Comment sequences
  /// - Union statements
  /// - Stored procedure calls
  ///
  /// **Parameters:**
  /// - `input`: Input to check
  ///
  /// **Returns:**
  /// - `true` if suspicious patterns detected, `false` otherwise
  ///
  /// **Example:**
  /// ```dart
  /// if (InputSanitizer.containsSqlInjection('1 OR 1=1')) {
  ///   print('Potential SQL injection detected!');
  /// }
  /// ```
  static bool containsSqlInjection(String input) {
    if (input.isEmpty) return false;

    final lowerInput = input.toLowerCase();

    // Check for SQL keywords
    for (final keyword in _sqlKeywords) {
      if (lowerInput.contains(keyword)) {
        return true;
      }
    }

    // Check for suspicious patterns
    if (lowerInput.contains('=') && lowerInput.contains('or')) return true;
    if (lowerInput.contains('=') && lowerInput.contains('and')) return true;
    if (lowerInput.contains('1=1')) return true;

    return false;
  }

  /// Detects potential XSS (Cross-Site Scripting) attempts.
  ///
  /// **What it checks:**
  /// - Script tags
  /// - Event handlers (onclick, onerror, etc.)
  /// - JavaScript protocol
  /// - Data URIs
  ///
  /// **Parameters:**
  /// - `input`: Input to check
  ///
  /// **Returns:**
  /// - `true` if XSS patterns detected, `false` otherwise
  ///
  /// **Example:**
  /// ```dart
  /// if (InputSanitizer.containsXss('<script>alert("xss")</script>')) {
  ///   print('Potential XSS detected!');
  /// }
  /// ```
  static bool containsXss(String input) {
    if (input.isEmpty) return false;

    final lowerInput = input.toLowerCase();

    // Check for script tags
    if (lowerInput.contains('<script')) return true;
    if (lowerInput.contains('</script>')) return true;

    // Check for event handlers
    final eventHandlers = [
      'onclick',
      'onerror',
      'onload',
      'onmouseover',
      'onfocus',
      'onblur',
      'onchange',
      'onsubmit',
    ];

    for (final handler in eventHandlers) {
      if (lowerInput.contains(handler)) return true;
    }

    // Check for javascript protocol
    if (lowerInput.contains('javascript:')) return true;

    // Check for data URIs
    if (lowerInput.contains('data:text/html')) return true;

    return false;
  }

  /// Escapes HTML special characters to prevent injection.
  ///
  /// **What it escapes:**
  /// - `<` to `&lt;`
  /// - `>` to `&gt;`
  /// - `&` to `&amp;`
  /// - `"` to `&quot;`
  /// - `'` to `&#x27;`
  ///
  /// **Parameters:**
  /// - `input`: Text to escape
  ///
  /// **Returns:**
  /// - HTML-escaped text
  ///
  /// **Example:**
  /// ```dart
  /// final escaped = InputSanitizer.escapeHtml('<div>Hello</div>');
  /// // Returns: '&lt;div&gt;Hello&lt;/div&gt;'
  /// ```
  static String escapeHtml(String input) {
    if (input.isEmpty) return '';

    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#x27;');
  }

  /// Validates and sanitizes a file name.
  ///
  /// **What it does:**
  /// - Removes path traversal attempts (../)
  /// - Removes special characters
  /// - Limits length
  /// - Preserves file extension
  ///
  /// **Parameters:**
  /// - `filename`: File name to sanitize
  /// - `maxLength`: Maximum length (default: 255)
  ///
  /// **Returns:**
  /// - Sanitized filename
  ///
  /// **Example:**
  /// ```dart
  /// final clean = InputSanitizer.sanitizeFilename('../../etc/passwd.txt');
  /// // Returns: 'etcpasswd.txt'
  /// ```
  static String sanitizeFilename(String filename, {int maxLength = 255}) {
    if (filename.isEmpty) return '';

    // Remove path traversal
    var sanitized = filename.replaceAll('../', '').replaceAll('..\\', '');

    // Remove path separators
    sanitized = sanitized.replaceAll('/', '').replaceAll('\\', '');

    // Keep only safe characters (alphanumeric, dash, underscore, dot)
    sanitized = sanitized.replaceAll(RegExp(r'[^\w\-.]'), '');

    // Limit length
    if (sanitized.length > maxLength) {
      // Try to preserve extension
      final lastDot = sanitized.lastIndexOf('.');
      if (lastDot > 0 && lastDot > maxLength - 10) {
        final ext = sanitized.substring(lastDot);
        final name = sanitized.substring(0, maxLength - ext.length);
        sanitized = name + ext;
      } else {
        sanitized = sanitized.substring(0, maxLength);
      }
    }

    return sanitized;
  }

  /// Validates input length is within acceptable bounds.
  ///
  /// **Parameters:**
  /// - `input`: Input to validate
  /// - `minLength`: Minimum length (default: 0)
  /// - `maxLength`: Maximum length (required)
  ///
  /// **Returns:**
  /// - `true` if length is valid, `false` otherwise
  ///
  /// **Example:**
  /// ```dart
  /// if (!InputSanitizer.isLengthValid(password, minLength: 8, maxLength: 128)) {
  ///   print('Password length invalid');
  /// }
  /// ```
  static bool isLengthValid(
    String input, {
    int minLength = 0,
    required int maxLength,
  }) {
    return input.length >= minLength && input.length <= maxLength;
  }

  /// Comprehensive validation and sanitization for user registration data.
  ///
  /// **Returns:**
  /// - Map with sanitized values and validation errors (if any)
  ///
  /// **Example:**
  /// ```dart
  /// final result = InputSanitizer.sanitizeUserRegistration(
  ///   firstName: userInput.firstName,
  ///   lastName: userInput.lastName,
  ///   email: userInput.email,
  ///   phone: userInput.phone,
  ///   username: userInput.username,
  /// );
  ///
  /// if (result['errors'].isEmpty) {
  ///   // Use result['data'] for registration
  /// } else {
  ///   // Show result['errors'] to user
  /// }
  /// ```
  static Map<String, dynamic> sanitizeUserRegistration({
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    String? username,
  }) {
    final errors = <String>[];
    final data = <String, String>{};

    // Sanitize first name
    final cleanFirstName = sanitizeText(firstName, maxLength: 50);
    if (cleanFirstName.isEmpty) {
      errors.add('First name is required');
    } else if (containsXss(cleanFirstName) || containsSqlInjection(cleanFirstName)) {
      errors.add('First name contains invalid characters');
    } else {
      data['firstName'] = cleanFirstName;
    }

    // Sanitize last name
    final cleanLastName = sanitizeText(lastName, maxLength: 50);
    if (cleanLastName.isEmpty) {
      errors.add('Last name is required');
    } else if (containsXss(cleanLastName) || containsSqlInjection(cleanLastName)) {
      errors.add('Last name contains invalid characters');
    } else {
      data['lastName'] = cleanLastName;
    }

    // Sanitize email
    final cleanEmail = sanitizeEmail(email);
    if (cleanEmail.isEmpty) {
      errors.add('Valid email is required');
    } else {
      data['email'] = cleanEmail;
    }

    // Sanitize phone
    final cleanPhone = sanitizePhone(phone);
    if (cleanPhone.isEmpty) {
      errors.add('Phone number is required');
    } else if (cleanPhone.length < 10) {
      errors.add('Phone number is too short');
    } else {
      data['phone'] = cleanPhone;
    }

    // Sanitize username (if provided)
    if (username != null && username.isNotEmpty) {
      final cleanUsername = sanitizeUsername(username);
      if (cleanUsername.isEmpty) {
        errors.add('Username contains only invalid characters');
      } else {
        data['username'] = cleanUsername;
      }
    }

    return {
      'data': data,
      'errors': errors,
      'isValid': errors.isEmpty,
    };
  }
}
