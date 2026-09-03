# Sequence Diagram: Paycrest Order Creation and Polling

This diagram shows the lifecycle of a Paycrest fiat payout order — from creation through
settlement (or failure), including webhook notifications.

```mermaid
sequenceDiagram
    autonumber
    participant App as Frontend /<br/>API Consumer
    participant OrderAPI as POST /api/offramp/<br/>paycrest/order
    participant StatusAPI as GET /api/offramp/<br/>paycrest/order/[id]
    participant IdempotencyDB as Idempotency<br/>Keys (DB)
    participant PaycrestAdapter as PaycrestAdapter
    participant Paycrest as Paycrest<br/>API
    participant BaseClient as BaseClient<br/>(viem)
    participant BaseChain as Base<br/>Chain (EVM)

    App->>OrderAPI: POST {amount, rate, token, network,<br/>  reference, returnAddress, recipient}<br/>Idempotency-Key: order-<uuid>

    OrderAPI->>IdempotencyDB: lookup(idempotencyKey)

    alt Key exists + status == "complete"
        IdempotencyDB-->>OrderAPI: stored response
        OrderAPI-->>App: 200 (replayed)<br/>Idempotency-Status: replayed
    else Key exists + status == "in_progress"
        IdempotencyDB-->>OrderAPI: in_progress
        OrderAPI-->>App: 409 Conflict<br/>(concurrent duplicate request)
    else Key not found
        IdempotencyDB-->>OrderAPI: not found
        OrderAPI->>IdempotencyDB: insert(key, status="in_progress")

        Note over OrderAPI: Validate request body
        alt Validation fails
            OrderAPI-->>App: 400 {error, details}
        else Validation passes
            OrderAPI->>PaycrestAdapter: createOrder(request)
            PaycrestAdapter->>Paycrest: POST /sender/orders<br/>{amount, rate, token, network, recipient, ...}

            alt Paycrest rejects order (4xx)
                Paycrest-->>PaycrestAdapter: 4xx error
                PaycrestAdapter-->>OrderAPI: PaycrestHttpError(status, details)
                OrderAPI-->>App: proxy status + error
            else Paycrest accepts order
                Paycrest-->>PaycrestAdapter: {id: "order-uuid", receiveAddress: "0x..."}
                PaycrestAdapter-->>OrderAPI: {id, receiveAddress}

                OrderAPI->>BaseClient: transferUSDC(<br/>  to: receiveAddress,<br/>  amount: flooredAmount<br/>)
                BaseClient->>BaseChain: ERC-20 transfer(to, amount)
                BaseChain-->>BaseClient: tx confirmed

                OrderAPI->>IdempotencyDB: update(key, status="complete", body=response)
                OrderAPI-->>App: 200 {data: {id, receiveAddress}}<br/>Idempotency-Status: created
            end
        end
    end

    Note over App,Paycrest: Paycrest monitors Base chain for incoming USDC

    loop Poll every 5–10 seconds
        App->>StatusAPI: GET /paycrest/order/order-uuid
        StatusAPI->>PaycrestAdapter: getOrderStatus(orderId)
        PaycrestAdapter->>Paycrest: GET /sender/orders/order-uuid
        Paycrest-->>PaycrestAdapter: {id, status}
        PaycrestAdapter-->>StatusAPI: {id, status}
        StatusAPI-->>App: {data: {id, status}}

        alt status == "settled"
            App-->>App: Stop polling — ✅ Fiat delivered to bank
        else status == "refunded"
            App-->>App: Stop polling — ↩️ Funds returned
        else status == "expired"
            App-->>App: Stop polling — ⏱️ Deposit not received in time
        else status == "pending" or "validated"
            Note over App: Continue polling
        end
    end
```

## Order Status Lifecycle

```
pending → validated → settled    ✅  (success path)
pending → validated → refunded   ↩️  (funds returned to returnAddress)
pending → expired                ⏱️  (deposit not received within timeout)
```

## Notes

- **Idempotency:** The `Idempotency-Key` header protects against double-creates on network retry.  
  Use a stable key per logical operation (e.g., `order-<walletAddress>-<referenceId>`).
- **Amount flooring:** The `amount` passed to Paycrest is **floored** to 6 decimal places —  
  never rounded up — to ensure the deposit is never short.
- **Rate locking:** The `rate` is locked at quote time. If the FX rate changes significantly before  
  the order is submitted, Paycrest may reject it.
- **Base USDC transfer:** The server holds a `BASE_PRIVATE_KEY` that controls the treasury wallet.  
  The `receiveAddress` returned by Paycrest is valid only for the specific order; reusing it for  
  another order will not credit the second order.
- **Webhook alternative to polling:** See [`webhook-handling.md`](./webhook-handling.md) for  
  event-driven order status updates instead of polling.
