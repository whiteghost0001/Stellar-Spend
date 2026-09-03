# Sequence Diagram: API Key Authentication Flow

This diagram shows the full lifecycle of programmatic API keys — creation by an admin,
authentication on protected routes, rotation, and revocation.

## API Key Creation (Admin)

```mermaid
sequenceDiagram
    autonumber
    actor Admin
    participant AdminClient as Admin Client<br/>(curl / script)
    participant ApiKeysRoute as POST /api/api-keys
    participant DB as PostgreSQL<br/>(api_keys table)

    Admin->>AdminClient: Create API key for partner integration

    AdminClient->>ApiKeysRoute: POST {name, rateLimitMaxRequests, rateLimitWindowMs}<br/>Authorization: Bearer <API_KEY_ADMIN_TOKEN>

    ApiKeysRoute->>ApiKeysRoute: Verify bearer token == API_KEY_ADMIN_TOKEN

    alt Invalid or missing admin token
        ApiKeysRoute-->>AdminClient: 401 {error: "Unauthorized"}
    else Valid admin token
        ApiKeysRoute->>ApiKeysRoute: Generate secure random key<br/>prefix = first 12 chars<br/>key = "ssp_live_<prefix>.<secret>"

        ApiKeysRoute->>DB: INSERT {name, keyHash: sha256(key), keyPrefix,<br/>  status: "active", rateLimitMaxRequests,<br/>  rateLimitWindowMs, createdAt}
        DB-->>ApiKeysRoute: {id: "uuid"}

        ApiKeysRoute-->>AdminClient: 201 {data: {id, name, keyPrefix,<br/>  status, plaintextKey}}<br/>⚠️ plaintextKey shown ONCE — store it now
    end
```

## API Key Authentication on Protected Route

```mermaid
sequenceDiagram
    autonumber
    participant Client as API Consumer
    participant Middleware as API Key<br/>Auth Middleware
    participant DB as PostgreSQL<br/>(api_keys table)
    participant Handler as Route Handler<br/>(e.g. POST /api/v1/offramp/quote)

    Client->>Middleware: Request to /api/v1/*<br/>X-API-Key: ssp_live_abc123.secret<br/>(or Authorization: Bearer ssp_live_abc123.secret)

    Middleware->>Middleware: Extract key from X-API-Key or Authorization header

    alt No key provided (except /api/v1/health)
        Middleware-->>Client: 401 {error: "API key required"}
    else Key provided
        Middleware->>Middleware: Compute sha256(key)

        Middleware->>DB: SELECT * FROM api_keys<br/>WHERE key_hash = sha256(key)
        DB-->>Middleware: row or null

        alt Key not found in DB
            Middleware-->>Client: 401 {error: "Invalid API key"}
        else Key found
            alt status == "revoked" or "rotated"
                Middleware-->>Client: 401 {error: "API key revoked/rotated"}
            else status == "active"
                Middleware->>Middleware: Check per-key rate limit<br/>(rateLimitMaxRequests / rateLimitWindowMs)

                alt Rate limit exceeded
                    Middleware-->>Client: 429 {error: "Too many requests"}<br/>Retry-After: <seconds>
                else Within rate limit
                    Middleware->>DB: UPDATE last_used_at, increment usage_count
                    Middleware->>Handler: forward request<br/>x-api-key-id: <id> (internal header)
                    Handler-->>Client: 200 response<br/>X-API-Key-Id: <id>
                end
            end
        end
    end
```

## API Key Rotation

```mermaid
sequenceDiagram
    autonumber
    actor Admin
    participant AdminClient as Admin Client
    participant RotateRoute as POST /api/api-keys/<br/>[id]/rotate
    participant DB as PostgreSQL

    Admin->>AdminClient: Rotate key (scheduled or after suspected leak)

    AdminClient->>RotateRoute: POST (empty body)<br/>Authorization: Bearer <API_KEY_ADMIN_TOKEN>

    RotateRoute->>DB: SELECT key WHERE id = <id> AND status = "active"

    alt Key not found or not active
        RotateRoute-->>AdminClient: 404 {error: "Key not found"}
    else Key found
        RotateRoute->>RotateRoute: Generate new key + hash

        RotateRoute->>DB: INSERT new key {status: "active", ...}
        RotateRoute->>DB: UPDATE old key {status: "rotated"}

        RotateRoute-->>AdminClient: 200 {data: {id: newId, plaintextKey: "ssp_live_..."}}<br/>⚠️ plaintextKey shown ONCE
    end

    Note over Admin,AdminClient: Update all integrations with new key.<br/>Old key immediately stops working.
```

## API Key Revocation

```mermaid
sequenceDiagram
    autonumber
    actor Admin
    participant AdminClient as Admin Client
    participant RevokeRoute as POST /api/api-keys/<br/>[id]/revoke
    participant DB as PostgreSQL

    Admin->>AdminClient: Revoke key (leaked, decommissioned, etc.)

    AdminClient->>RevokeRoute: POST {reason: "Key leaked during rotation"}<br/>Authorization: Bearer <API_KEY_ADMIN_TOKEN>

    RevokeRoute->>DB: UPDATE api_keys SET status = "revoked",<br/>  revokedAt = NOW(), revokedReason = reason<br/>WHERE id = <id>
    DB-->>RevokeRoute: ok

    RevokeRoute-->>AdminClient: 200 {success: true}

    Note over Admin,DB: All subsequent requests using the revoked key<br/>receive 401 immediately.
```

## Notes

- **One-time plaintext:** The `plaintextKey` is returned only at creation and rotation time.  
  It is **never stored** — only the `sha256` hash lives in the database. If lost, rotate the key.
- **Key prefix:** The `keyPrefix` (first 12 characters) is stored in plaintext for identification  
  in logs and the admin UI without exposing the full secret.
- **Public route exception:** `GET /api/v1/health` is publicly accessible without an API key.
- **Rate limits:** Each key has its own `rateLimitMaxRequests` and `rateLimitWindowMs`.  
  Global IP-based rate limits still apply on top of per-key limits.
- **Usage tracking:** Every authenticated request updates `last_used_at` and is recorded in the  
  usage log (accessible via `GET /api/api-keys/[id]/usage`).
