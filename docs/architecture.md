# ASML-X architecture

An AI agent that trades real tokens on X Layer and cannot exceed the limit you set.

Every diagram below describes what is deployed and running, not a plan.

---

## What a person does

```mermaid
flowchart LR
    U([You]) -->|"1. connect"| W[Wallet<br/>browser or QR]
    W -->|"2. deposit + set a cap"| V[AgentVault<br/>chain 196]
    V -->|"3. trades under the cap"| A[Agent]
    V -->|"4. withdraw, any time"| U

    A -.->|"cannot exceed"| CAP{{Your cap}}
    CAP -.->|"only ever lowered"| CAP

    style V fill:#10B981,stroke:#10B981,color:#09090B
    style CAP fill:#F59E0B,stroke:#F59E0B,color:#09090B
```

The cap is stored on chain. Raising it is not difficult, it is impossible: `RiskGuard` has no
code path that increases a limit, and withdrawal is not gated on the agent being healthy.

---

## The decision loop

```mermaid
flowchart TD
    subgraph perceive["Perceive — real market only"]
        D[OKX depth ladder<br/>8 venues, real slippage]
        P[Token + index prices<br/>two independent sources]
        S[Smart money + sentiment]
    end

    subgraph decide["Decide"]
        G[Generate candidates<br/>from real depth]
        SC[Score: edge, variance,<br/>capital cost, execution risk]
    end

    subgraph gate["Gate — the only way out"]
        R{Risk engine}
    end

    subgraph act["Act"]
        X[RouterExecutor]
        POOLS[(Real X Layer pools)]
    end

    D --> G
    P --> SC
    S --> SC
    G --> SC
    SC --> R
    R -->|approved| X
    R -->|refused| J[[Refusal, with its reason]]
    X --> POOLS

    style R fill:#F59E0B,stroke:#F59E0B,color:#09090B
    style J fill:#EF4444,stroke:#EF4444,color:#FAFAFA
    style POOLS fill:#3B82F6,stroke:#3B82F6,color:#FAFAFA
```

96% of considered trades are refused. That is the system working, not failing.

---

## Why the agent cannot cheat

```mermaid
flowchart TB
    L[Learning layer] -->|"adjusts scoring weights"| SC[Scoring]
    L -.->|"NO TYPE CONNECTS THESE"| LIM[Limits]

    SC --> GATE{"Risk gate"}
    LIM --> GATE
    GATE -->|"issues"| RA["RiskApproved&lt;T&gt;<br/>sealed, unforgeable"]
    RA --> EXEC[Execution]

    BAD[Code that trades<br/>without approval] -.->|"does not compile"| EXEC

    style RA fill:#10B981,stroke:#10B981,color:#09090B
    style BAD fill:#EF4444,stroke:#EF4444,color:#FAFAFA
    style LIM fill:#F59E0B,stroke:#F59E0B,color:#09090B
```

Three structural guarantees, each proved rather than asserted:

| Guarantee | How it is enforced | Proof |
|---|---|---|
| Limits only tighten | `RiskGuard` has no widening path | Halmos symbolic execution |
| Learning cannot widen limits | `Learner` has no type mentioning `Limits` | Compile-time |
| Agent cannot skip the gate | `RiskApproved<T>` is sealed in `risk-engine` | Fails to compile |
| Pause never blocks withdrawal | Withdrawal is not gated on agent state | Halmos |

---

## Where the data comes from

```mermaid
flowchart LR
    subgraph okx["OKX Onchain OS — signed, server side"]
        M[market price / index / kline]
        T[token info / liquidity / holders]
        SEC[security scan]
        SIG[smart money + sentiment]
        DEFI[DeFi products]
    end

    FS[feed_server.py<br/>signs, caches, ages]
    UI[Browser]
    CHAIN[(X Layer 196)]

    M --> FS
    T --> FS
    SEC --> FS
    SIG --> FS
    DEFI --> FS
    FS -->|"JSON + age"| UI
    CHAIN -->|"balances, limits"| UI

    style FS fill:#3B82F6,stroke:#3B82F6,color:#FAFAFA
    style CHAIN fill:#10B981,stroke:#10B981,color:#09090B
```

The browser never holds the API secret. Signing happens server-side; the page receives results
with the age of each one attached, so nothing is presented as live that is not.

---

## Agent-to-agent payments

```mermaid
sequenceDiagram
    participant E as External agent
    participant A as ASML-X /quote
    participant R as Risk engine

    E->>A: POST /quote
    A-->>E: 402 + challenge<br/>(amount, asset, network, payTo)
    E->>E: sign with its own wallet
    E->>A: POST /quote + PAYMENT-SIGNATURE
    A->>R: same gate as an internal decision
    R-->>A: approved or refused
    A-->>E: 200, a risk-gated quote
```

Payment buys the quote. It does not buy a larger one: the risk gate runs identically whether or
not payment was made.

---

## Deployed on X Layer mainnet, chain 196

| Contract | Role |
|---|---|
| `AgentVault` | Holds deposits. Withdrawal works while paused |
| `RiskGuard` | On-chain limits. Only ever tighten |
| `RouterExecutor` | Routes swaps through OKX, verifies the balance delta, reverts on shortfall |
| `BatchExecutor` | Submits approved actions, and only approved actions |
| `RwaVault` / `RwaRiskGuard` | RWA-specific refusals, including the price-divergence band |
| `FeeCollector` | Usage fee, capped at 100 bps by the contract |

Addresses are in the app footer, each linked to the public explorer.
