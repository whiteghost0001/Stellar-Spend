# Sequence Diagram: Complete Off-Ramp Flow (Stellar → Bank)

This diagram shows the full end-to-end flow of converting Stellar USDC to fiat currency
and delivering it to a beneficiary bank account.

```mermaid
sequenceDiagram
    autonumber
    actor User as User (Browser)
    participant App as Stellar-Spend<br/>Frontend
    participant API as Stellar-Spend<br/>API Server
    participant Allbridge as Allbridge<br/>Bridge
    participant Soroban as Stellar<br/>Soroban RPC
    participant Base as Base<br/>Chain (EVM)
    participant Paycrest as Paycrest<br/>Settlement

    User->>App: Select fiat currency & enter amount

    App->>API: GET /api/offramp/currencies
    API-->>App: [{code:"NGN", name:"Nigerian Naira"}, ...]

    App->>API: GET /api/offramp/institutions/NGN
    API-->>App: [{code:"ACCESS", name:"Access Bank"}, ...]

    User->>App: Enter bank account details

    App->>API: POST /api/offramp/verify-account<br/>{institution, accountIdentifier}
    API->>Paycrest: verifyAccount()
    Paycrest-->>API: {accountName: "John Doe"}
    API-->>App: {accountName: "John Doe"}

    App->>API: POST /api/offramp/quote<br/>{amount, currency, feeMethod}
    API->>Paycrest: getRate(token, amount, currency)
    Paycrest-->>API: FX rate
    API-->>App: {destinationAmount, rate, expiresIn}

    User->>App: Confirm transaction details

    App->>API: GET /api/offramp/bridge/gas-fee-options
    API->>Allbridge: getFeeOptions()
    Allbridge-->>API: {native: {...}, stablecoin: {...}}
    API-->>App: feeOptions (cached 60s)

    App->>API: POST /api/offramp/bridge/build-tx<br/>{amount, fromAddress, toAddress, feePaymentMethod}
    API->>Allbridge: buildSwapAndBridgeTx()
    Allbridge-->>API: Soroban XDR (unsigned)
    API-->>App: {xdr, sourceToken, destinationToken}

    App->>User: Request wallet signature
    User->>App: Sign XDR (Freighter / Lobstr)

    App->>API: POST /api/offramp/bridge/submit-soroban<br/>{signedXdr}
    API->>Soroban: sendTransaction(signedXdr)
    Soroban-->>API: {status: "PENDING", hash: "abc123"}
    API-->>App: {status: "PENDING", hash: "abc123"}

    loop Poll until SUCCESS
        App->>API: GET /api/offramp/bridge/tx-status/abc123
        API->>Soroban: getTransaction(hash)
        Soroban-->>API: {status: "SUCCESS"}
        API-->>App: {status: "SUCCESS", hash}
    end

    App->>API: POST /api/offramp/paycrest/order<br/>{amount, rate, token, network, recipient, ...}<br/>Idempotency-Key: order-<uuid>
    API->>Paycrest: createOrder(request)
    Paycrest-->>API: {id: "order-uuid", receiveAddress: "0x..."}
    API-->>App: {data: {id, receiveAddress}}

    Note over API,Base: Server executes Base USDC transfer<br/>to Paycrest receiveAddress
    API->>Base: transfer USDC → receiveAddress
    Base-->>API: EVM tx confirmed

    loop Poll until settled
        App->>API: GET /api/offramp/bridge/status/abc123
        API->>Allbridge: getTransferStatus(hash)
        Allbridge-->>API: {status: "completed"}
        API-->>App: {data: {status: "completed"}}

        App->>API: GET /api/offramp/paycrest/order/order-uuid
        API->>Paycrest: getOrderStatus(orderId)
        Paycrest-->>API: {status: "settled"}
        API-->>App: {data: {status: "settled"}}
    end

    App-->>User: ✅ Transfer complete — funds sent to bank
```

## Notes

- **Step 14 (sign XDR):** The private key never leaves the user's wallet. The server only sees the signed XDR.
- **Idempotency:** The Paycrest order creation at step 20 uses an `Idempotency-Key` so safe retries on network failure won't create duplicate orders.
- **Terminal states for polling:**
  - Bridge: `completed`, `failed`, `expired`
  - Paycrest order: `settled`, `refunded`, `expired`
- **Recommended polling interval:** 5–10 seconds.
- The `receiveAddress` from step 20 is the Paycrest deposit address on Base. The bridge delivers USDC there automatically once the Stellar transaction confirms.
