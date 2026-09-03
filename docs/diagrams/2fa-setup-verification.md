# Sequence Diagram: 2FA Setup and Verification

This diagram shows the two-factor authentication flows — TOTP setup and verification,
backup code generation, and SMS 2FA initiation.

## TOTP Setup Flow

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as Frontend
    participant SetupRoute as POST /api/auth/<br/>2fa/setup
    participant TwoFAService as TwoFAService<br/>(server-side)
    participant AuthApp as Authenticator App<br/>(Google Auth, Authy, etc.)

    User->>App: Navigate to Security Settings → Enable 2FA

    App->>SetupRoute: POST {userId: "wallet-address", method: "totp"}

    SetupRoute->>TwoFAService: generateTOTPSecret()
    TwoFAService-->>SetupRoute: base32 secret string

    SetupRoute->>TwoFAService: generateBackupCodes()
    TwoFAService-->>SetupRoute: [10 single-use backup codes]

    SetupRoute->>TwoFAService: generateTOTPURI(secret, userId)
    TwoFAService-->>SetupRoute: otpauth://totp/StellarSpend:<userId>?secret=...

    SetupRoute-->>App: {method: "totp", secret, uri, backupCodes}

    App-->>User: Display QR code (from uri)<br/>+ backup codes to save

    User->>AuthApp: Scan QR code
    AuthApp-->>User: Shows rotating 6-digit TOTP code

    Note over App,User: User saves backup codes securely

    User->>App: Enter current TOTP code to confirm setup

    App->>VerifyRoute: POST {userId, code, method: "totp", secret}
    Note right of App: (See TOTP Verification below)
```

## TOTP Verification Flow

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as Frontend
    participant VerifyRoute as POST /api/auth/<br/>2fa/verify
    participant TwoFAService as TwoFAService

    User->>App: Enter 6-digit TOTP code

    App->>VerifyRoute: POST {<br/>  userId: "wallet-address",<br/>  code: "123456",<br/>  method: "totp",<br/>  secret: "JBSWY3DPEHPK3PXP"<br/>}

    VerifyRoute->>TwoFAService: verifyTOTP(secret, code)
    Note over TwoFAService: Checks current time window<br/>± clock drift tolerance

    alt Code is valid
        TwoFAService-->>VerifyRoute: true
        VerifyRoute-->>App: 200 {success: true, verified: true,<br/>  message: "2FA verified successfully"}
        App-->>User: ✅ 2FA confirmed — access granted
    else Code is invalid or expired
        TwoFAService-->>VerifyRoute: false
        VerifyRoute-->>App: 401 {error: "Invalid TOTP code"}
        App-->>User: ❌ Wrong code — try again
    end
```

## Backup Code Verification Flow

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as Frontend
    participant VerifyRoute as POST /api/auth/<br/>2fa/verify
    participant TwoFAService as TwoFAService

    Note over User: Lost access to authenticator app
    User->>App: Click "Use backup code"

    App->>VerifyRoute: POST {<br/>  userId: "wallet-address",<br/>  code: "abc123",<br/>  method: "backup",<br/>  backupCodes: ["abc123", "def456", ...]<br/>}

    VerifyRoute->>TwoFAService: verifyBackupCode(backupCodes, code)
    TwoFAService-->>VerifyRoute: {isValid: true, remainingCodes: ["def456", ...]}

    alt Backup code valid
        VerifyRoute-->>App: 200 {success: true, verified: true,<br/>  remainingCodes: ["def456", ...]}
        App-->>User: ✅ Verified — code consumed<br/>Update stored backup codes
        Note over App,User: App updates backup codes in localStorage<br/>(consumed code removed)
    else Invalid backup code
        VerifyRoute-->>App: 401 {error: "Invalid backup code"}
        App-->>User: ❌ Code not recognised
    end
```

## SMS 2FA Setup Flow

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant App as Frontend
    participant SetupRoute as POST /api/auth/<br/>2fa/setup

    User->>App: Select "SMS" as 2FA method

    App->>SetupRoute: POST {userId: "wallet-address", method: "sms"}

    SetupRoute-->>App: 200 {<br/>  method: "sms",<br/>  message: "SMS 2FA setup initiated.<br/>  Provide phone number in verification step."<br/>}

    App-->>User: Prompt for phone number<br/>(handled in verification step)
```

## Notes

- **Secret storage:** The TOTP `secret` is generated server-side and returned to the client **once**.  
  The client is responsible for storing it (e.g., in localStorage) and passing it back with each verify request.  
  The server does **not** persist the secret in a database.
- **Backup codes:** Each code is single-use. After successful verification, the `remainingCodes` array  
  (with the used code removed) must be saved by the client.
- **Clock drift:** TOTP is time-based (RFC 6238). `TwoFAService.verifyTOTP` accepts a tolerance  
  window to account for clock skew between the server and the authenticator app.
- **SMS 2FA:** Full SMS delivery is not implemented in the current server — the setup route initiates  
  the flow and defers phone number collection to the verification step.
