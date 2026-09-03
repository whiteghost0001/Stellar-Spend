# Sequence Diagram: Bridge Transaction Building (Stellar → Base)

This diagram shows the detailed flow of building, signing, and submitting a
Soroban XDR transaction that bridges USDC from Stellar to Base via Allbridge.

```mermaid
sequenceDiagram
    autonumber
    actor User as User (Browser)
    participant App as Frontend
    participant BuildTx as POST /api/offramp/<br/>bridge/build-tx
    participant Submit as POST /api/offramp/<br/>bridge/submit-soroban
    participant TxStatus as GET /api/offramp/<br/>bridge/tx-status/[hash]
    participant AllbridgeSDK as AllbridgeAdapter<br/>(server-side)
    participant SorobanRPC as Stellar<br/>Soroban RPC
    participant Wallet as Freighter /<br/>Lobstr Wallet

    Note over App,AllbridgeSDK: Step 1 — Fetch fee options (see gas-fee-options diagram)
    App->>BuildTx: POST {amount, fromAddress, toAddress, feePaymentMethod}

    BuildTx->>AllbridgeSDK: initializeAllbridgeSdk()
    alt SDK not initialized (cold start or after cache invalidation)
        AllbridgeSDK->>AllbridgeSDK: dynamic import('@allbridge/bridge-core-sdk')
        AllbridgeSDK->>SorobanRPC: chainDetailsMap() — fetch chain/token info
        SorobanRPC-->>AllbridgeSDK: chain details (cached 5 min)
    end
    AllbridgeSDK-->>BuildTx: sdk instance

    BuildTx->>AllbridgeSDK: resolveTokens(sdk)<br/>find USDC on SRB (Stellar) & BAS (Base)
    AllbridgeSDK-->>BuildTx: {sourceToken, destinationToken}

    BuildTx->>AllbridgeSDK: getBridgeFeeForMethod(feeOptions, method)<br/>select native (XLM) or stablecoin (USDC) fee params
    AllbridgeSDK-->>BuildTx: {gasAmount, feeTokenAmount}

    BuildTx->>AllbridgeSDK: sdk.buildSwapAndBridgeTx(<br/>  sourceToken, destinationToken,<br/>  fromAddress, toAddress,<br/>  amount, selectedFee<br/>)
    AllbridgeSDK->>SorobanRPC: simulate transaction (Soroban contract call)
    SorobanRPC-->>AllbridgeSDK: simulation result / XDR

    alt Simulation failed (e.g., insufficient balance)
        AllbridgeSDK-->>BuildTx: Error: "token transfer failed during simulation"
        BuildTx-->>App: 500 {error: "..."}
        App-->>User: Show error — check balance
    else Simulation succeeded
        AllbridgeSDK-->>BuildTx: unsigned XDR string
        BuildTx-->>App: 200 {xdr, sourceToken, destinationToken}
    end

    App->>Wallet: signTransaction(xdr, {network: "mainnet"})
    Wallet-->>User: Prompt: "Approve bridge transaction?"
    User->>Wallet: Approve
    Wallet-->>App: signedXdr

    App->>Submit: POST {signedXdr}
    Submit->>SorobanRPC: sendTransaction(signedXdr) — JSON-RPC
    SorobanRPC-->>Submit: {status, hash}

    alt status == "ERROR" or "TRY_AGAIN_LATER"
        Submit-->>App: 400 {error: "Transaction rejected by RPC"}
        App-->>User: Show error
    else status == "PENDING" or "SUCCESS" or "DUPLICATE"
        Submit-->>App: 200 {status: "PENDING", hash: "abc123"}
    end

    loop Poll every 5–10 seconds until terminal state
        App->>TxStatus: GET /tx-status/abc123
        TxStatus->>SorobanRPC: getTransaction(hash)
        SorobanRPC-->>TxStatus: current status

        alt status == "SUCCESS"
            TxStatus-->>App: {status: "SUCCESS", hash}
            App-->>User: ✅ Stellar transaction confirmed
        else status == "FAILED"
            TxStatus-->>App: {status: "FAILED", hash}
            App-->>User: ❌ Transaction failed on-chain
        else status == "NOT_FOUND"
            TxStatus-->>App: {status: "NOT_FOUND", hash}
            Note over App: Not yet indexed — keep polling
        end
    end
```

## Notes

- **Fee methods:** `stablecoin` (USDC fee, no extra XLM needed) is the default and safest option.  
  `native` (XLM fee) can fail if the account is near the Stellar minimum reserve.
- **SDK singleton:** The `AllbridgeAdapter` maintains a module-level SDK instance and a 5-minute TTL  
  cache for chain details. Only the first request after a cold start pays the initialization cost.
- **Duplicate submissions:** If `submit-soroban` returns `DUPLICATE`, the transaction was already  
  submitted. Treat it as `PENDING` and poll `tx-status` with the existing hash.
- **Diagnostic events:** On `ERROR` status from Soroban RPC, diagnostic events are logged server-side.  
  Check server logs for `Diagnostic events:` entries when debugging.
