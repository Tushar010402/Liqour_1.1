# Authentication API

## Overview

The Authentication API provides endpoints for user authentication, session management, and account operations. LiquorPro uses **OTP-only authentication** - no passwords are required.

**Base URL**: `https://new.v2.floelife.in/api/auth`

---

## Public Endpoints (No Authentication Required)

### Check User

#### POST /check-user

Check if a user exists by phone number.

**Request:**
```http
POST /api/auth/check-user
Content-Type: application/json

{
  "phone": "9876543210"
}
```

**Response (200) - User Exists:**
```json
{
  "success": true,
  "data": {
    "exists": true,
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "John Doe"
  }
}
```

**Response (200) - User Not Found:**
```json
{
  "success": true,
  "data": {
    "exists": false
  }
}
```

---

### Login (Request OTP)

#### POST /login

Initiate login by sending OTP to user's phone. No password required.

**Request:**
```http
POST /api/auth/login
Content-Type: application/json

{
  "phone": "9876543210"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "OTP sent successfully",
    "phone": "9876543210",
    "otp_expires_in": 600
  }
}
```

**Errors:**

| Status | Code | Message |
|--------|------|---------|
| 400 | INVALID_PHONE | Phone number format is invalid |
| 404 | USER_NOT_FOUND | No user found with this phone number |
| 429 | RATE_LIMITED | Too many login attempts. Try after X minutes |

---

### Send OTP

#### POST /send-otp

Request a new OTP for login (resend).

**Request:**
```http
POST /api/auth/send-otp
Content-Type: application/json

{
  "phone": "9876543210"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "OTP sent successfully",
    "otp_expires_in": 600
  }
}
```

---

### Send OTP for Registration

#### POST /send-otp-registration

Request OTP for new user registration flow.

**Request:**
```http
POST /api/auth/send-otp-registration
Content-Type: application/json

{
  "phone": "9876543210"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "OTP sent successfully",
    "otp_expires_in": 600
  }
}
```

---

### Verify OTP

#### POST /verify-otp

Verify OTP and receive authentication tokens. Includes device fingerprinting.

**Request:**
```http
POST /api/auth/verify-otp
Content-Type: application/json

{
  "phone": "9876543210",
  "otp": "123456",
  "device_info": {
    "device_id": "unique-device-id",
    "device_name": "iPhone 15 Pro",
    "device_type": "mobile",
    "os": "iOS 17.2",
    "app_version": "2.0.0"
  }
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "token_type": "Bearer",
    "expires_in": 86400,
    "user": {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "phone": "9876543210",
      "name": "John Doe",
      "email": "john@example.com",
      "role": "manager",
      "role_level": 4,
      "tenant_id": "550e8400-e29b-41d4-a716-446655440001",
      "tenant_name": "ABC Liquors",
      "shops": [
        {
          "id": "shop-uuid-1",
          "name": "Main Street Store"
        }
      ]
    }
  }
}
```

**Errors:**

| Status | Code | Message |
|--------|------|---------|
| 400 | INVALID_OTP | OTP is invalid |
| 401 | OTP_EXPIRED | OTP has expired (10 min validity) |
| 429 | TOO_MANY_ATTEMPTS | Maximum 3 OTP attempts exceeded |

---

### Force Login with OTP (Swiggy-style)

#### POST /force-login-otp

Force login on new device, terminating oldest session if at device limit (2 devices max).

**Request:**
```http
POST /api/auth/force-login-otp
Content-Type: application/json

{
  "phone": "9876543210",
  "otp": "123456",
  "device_info": {
    "device_id": "new-device-id",
    "device_name": "Samsung Galaxy S24",
    "device_type": "mobile",
    "os": "Android 14"
  }
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "terminated_session": {
      "device_name": "Old Phone",
      "last_active": "2025-01-10T08:00:00Z"
    }
  }
}
```

---

### Register

#### POST /register

Register a new tenant and admin user.

**Request:**
```http
POST /api/auth/register
Content-Type: application/json

{
  "phone": "9876543210",
  "otp": "123456",
  "name": "John Doe",
  "email": "john@example.com",
  "tenant_name": "ABC Liquors",
  "device_info": {
    "device_id": "device-id",
    "device_name": "iPhone 15",
    "device_type": "mobile"
  }
}
```

**Response (201):**
```json
{
  "success": true,
  "data": {
    "user": {
      "id": "user-uuid",
      "name": "John Doe",
      "phone": "9876543210",
      "role": "admin"
    },
    "tenant": {
      "id": "tenant-uuid",
      "name": "ABC Liquors"
    },
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  }
}
```

---

## Protected Endpoints (Authentication Required)

All protected endpoints require:
```http
Authorization: Bearer <access_token>
X-Tenant-ID: <tenant_id>
```

### Get Profile

#### GET /profile

Get current user's profile information.

**Request:**
```http
GET /api/auth/profile
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "phone": "9876543210",
    "name": "John Doe",
    "email": "john@example.com",
    "role": "manager",
    "role_level": 4,
    "profile_image": "https://storage.example.com/profiles/user.jpg",
    "tenant": {
      "id": "tenant-uuid",
      "name": "ABC Liquors"
    },
    "shops": [
      {
        "id": "shop-uuid-1",
        "name": "Main Street Store",
        "is_manager": true
      }
    ],
    "created_at": "2024-01-01T00:00:00Z",
    "last_login": "2025-01-11T10:00:00Z"
  }
}
```

---

### Update Profile

#### PUT /profile

Update current user's profile.

**Request:**
```http
PUT /api/auth/profile
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "name": "John Smith",
  "email": "john.smith@example.com"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "name": "John Smith",
    "email": "john.smith@example.com",
    "updated_at": "2025-01-11T12:00:00Z"
  }
}
```

---

### Change Password

#### PUT /change-password

Change current user's password (if password-based auth is enabled for tenant).

**Request:**
```http
PUT /api/auth/change-password
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "current_password": "OldPass123",
  "new_password": "NewPass456"
}
```

---

### Refresh Token

#### POST /refresh

Refresh access token using refresh token.

**Request:**
```http
POST /api/auth/refresh
Content-Type: application/json

{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 86400
  }
}
```

---

### Logout

#### POST /logout

Logout current session.

**Request:**
```http
POST /api/auth/logout
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Logged out successfully"
  }
}
```

---

## Session Management (2-Device Limit)

LiquorPro enforces a maximum of 2 concurrent device sessions per user (similar to Swiggy/Zomato).

### List Active Sessions

#### GET /sessions

List all active sessions for current user.

**Request:**
```http
GET /api/auth/sessions
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "success": true,
  "data": [
    {
      "id": "session-uuid-1",
      "device_id": "device-123",
      "device_type": "mobile",
      "device_name": "iPhone 15 Pro",
      "os": "iOS 17.2",
      "ip_address": "192.168.1.100",
      "last_activity": "2025-01-11T10:00:00Z",
      "created_at": "2025-01-10T08:00:00Z",
      "is_current": true
    },
    {
      "id": "session-uuid-2",
      "device_id": "device-456",
      "device_type": "mobile",
      "device_name": "Samsung Galaxy S24",
      "os": "Android 14",
      "ip_address": "192.168.1.101",
      "last_activity": "2025-01-10T18:00:00Z",
      "created_at": "2025-01-09T09:00:00Z",
      "is_current": false
    }
  ]
}
```

---

### Logout Specific Device

#### DELETE /sessions/:session_id

Terminate a specific session.

**Request:**
```http
DELETE /api/auth/sessions/session-uuid-2
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Session terminated successfully"
  }
}
```

---

### Logout All Devices

#### DELETE /sessions

Terminate all sessions except current.

**Request:**
```http
DELETE /api/auth/sessions
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "All other sessions terminated",
    "terminated_count": 1
  }
}
```

---

### Force Login

#### POST /sessions/force-login

Force login by explicitly removing a session when at device limit.

**Request:**
```http
POST /api/auth/sessions/force-login
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "session_id_to_terminate": "session-uuid-2"
}
```

---

## Account Deletion (App Store Compliance 5.1.1v)

### Request Deletion OTP

#### POST /account/delete/request-otp

Request OTP to confirm account deletion.

**Request:**
```http
POST /api/auth/account/delete/request-otp
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Deletion OTP sent to your phone",
    "otp_expires_in": 600
  }
}
```

---

### Delete Account

#### DELETE /account

Confirm account deletion with OTP.

**Request:**
```http
DELETE /api/auth/account
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "otp": "123456",
  "reason": "No longer using the service"
}
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Account scheduled for deletion",
    "deletion_date": "2025-02-10T00:00:00Z",
    "grace_period_days": 30
  }
}
```

---

### Cancel Account Deletion

#### POST /account/delete/cancel

Cancel pending account deletion within grace period.

**Request:**
```http
POST /api/auth/account/delete/cancel
Authorization: Bearer <access_token>
```

**Response (200):**
```json
{
  "success": true,
  "data": {
    "message": "Account deletion cancelled"
  }
}
```

---

## Admin Endpoints

### Public Validation (No Auth)

#### GET /admin/validate/phone

Check if phone number is available for registration.

```http
GET /api/admin/validate/phone?phone=9876543210
```

#### GET /admin/validate/email

Check if email is available.

```http
GET /api/admin/validate/email?email=john@example.com
```

#### GET /admin/validate/tenant

Check if tenant name is available.

```http
GET /api/admin/validate/tenant?name=ABC%20Liquors
```

---

### User Management (Admin/Manager Only)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/admin/users` | GET | List all users in tenant |
| `/api/admin/users` | POST | Create new user |
| `/api/admin/users/:id` | GET | Get user by ID |
| `/api/admin/users/:id` | PUT | Update user |
| `/api/admin/users/:id` | DELETE | Delete user (Admin only) |

### Shop Management (Admin/Manager Only)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/admin/shops` | GET | List all shops |
| `/api/admin/shops` | POST | Create new shop |
| `/api/admin/shops/:id` | GET | Get shop by ID |
| `/api/admin/shops/:id` | PUT | Update shop |

### Salesman Management (Admin/Manager Only)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/admin/salesmen` | GET | List all salesmen |
| `/api/admin/salesmen` | POST | Create new salesman |
| `/api/admin/salesmen/:id` | GET | Get salesman by ID |
| `/api/admin/salesmen/:id` | PUT | Update salesman |

---

## OTP Specifications

| Parameter | Value |
|-----------|-------|
| **Length** | 6 digits |
| **Validity** | 10 minutes |
| **Max Attempts** | 3 per OTP |
| **Hashing** | SHA-256 |
| **Resend Cooldown** | 60 seconds |
| **Master OTP** | 011001 (dev only) |

---

## Token Expiration

| Token Type | Expiration |
|------------|------------|
| Access Token | 24 hours |
| Refresh Token | 7 days |
| OTP | 10 minutes |

---

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| /login | 10 requests per minute |
| /send-otp | 5 requests per minute |
| /send-otp-registration | 5 requests per minute |
| /verify-otp | 10 requests per minute |
| /register | 5 requests per minute |
| /refresh | 20 requests per minute |
| /check-user | 10 requests per minute |
| All other endpoints | 100 requests per minute |

---

## Role Hierarchy

| Role | Level | Can Manage |
|------|-------|------------|
| salesman | 1 | - |
| executive | 2 | - |
| assistant_manager | 3 | - |
| manager | 4 | Users, Shops, Salesmen |
| admin | 5 | Everything (tenant-level) |
| owner | 6 | Everything + Platform |
