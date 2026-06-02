# Diagrams that just work

Marklens bundles Mermaid 11 locally — no CDN, no JavaScript console
errors, no flash of unstyled diagram. Drop a fenced code block tagged
`mermaid` and it renders inline alongside your prose.

## A deploy pipeline

```mermaid
flowchart LR
    PR[Open PR] --> CI[CI: lint + test]
    CI -->|green| Review[Code review]
    CI -->|red| Fix[Fix locally]
    Fix --> PR
    Review --> Merge[Merge to main]
    Merge --> Build[Build artifact]
    Build --> Staging[Deploy → staging]
    Staging --> QA{QA passed?}
    QA -->|yes| Prod[Deploy → prod]
    QA -->|no| Rollback[Revert merge]
```

## An OAuth handshake

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant App
    participant Auth as Auth Server
    participant API

    User->>App: tap "Sign in"
    App->>Auth: GET /authorize?client_id=…
    Auth-->>User: login page
    User->>Auth: credentials + consent
    Auth-->>App: redirect with auth code
    App->>Auth: POST /token (code, secret)
    Auth-->>App: access_token, refresh_token
    App->>API: GET /me  (Bearer access_token)
    API-->>App: profile JSON
    App-->>User: signed in
```

## Order lifecycle

```mermaid
stateDiagram-v2
    [*] --> Cart
    Cart --> Checkout: review
    Checkout --> Pending: pay
    Pending --> Paid: webhook ok
    Pending --> Failed: webhook fail
    Paid --> Shipped: fulfilment
    Shipped --> Delivered: courier scan
    Failed --> Cart: retry
    Delivered --> [*]
```

## A simple bar chart

```mermaid
xychart-beta
    title "Active users by week"
    x-axis [W1, W2, W3, W4, W5, W6, W7, W8]
    y-axis "Users" 0 --> 5000
    bar [820, 1240, 1880, 2310, 2920, 3450, 3980, 4520]
```

Diagrams pick up the system theme automatically — light when your Mac is
in light mode, dark when it isn't.
