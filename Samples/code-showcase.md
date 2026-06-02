# Code, beautifully highlighted

Marklens ships highlight.js's common-languages bundle — about thirty
languages, ~50 KB, fully offline. No external requests, no network round
trips. Below: a quick tour of how a few of them render.

## Swift — a tiny SwiftUI view

```swift
import SwiftUI

struct ProfileCard: View {
    let user: User

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: user.avatarURL) { $0.resizable() }
                placeholder: { Color.secondary.opacity(0.2) }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

            VStack(alignment: .leading) {
                Text(user.name).font(.headline)
                Text("@\(user.handle)").foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
```

## Python — pulling a histogram out of a CSV

```python
import pandas as pd
from collections import Counter

df = pd.read_csv("requests.log", parse_dates=["ts"])
df = df[df["status"] >= 500]

by_route = Counter(df["route"])
for route, n in by_route.most_common(10):
    print(f"{n:>5}  {route}")
```

## Rust — a streaming line counter

```rust
use std::io::{self, BufRead};

fn main() -> io::Result<()> {
    let stdin = io::stdin();
    let mut lines = 0usize;
    let mut bytes = 0usize;

    for line in stdin.lock().lines() {
        let line = line?;
        lines += 1;
        bytes += line.len() + 1;
    }

    println!("{lines} lines, {bytes} bytes");
    Ok(())
}
```

## TypeScript — a debounced search hook

```typescript
import { useEffect, useState } from "react";

export function useDebounced<T>(value: T, ms = 200): T {
    const [debounced, setDebounced] = useState(value);

    useEffect(() => {
        const id = setTimeout(() => setDebounced(value), ms);
        return () => clearTimeout(id);
    }, [value, ms]);

    return debounced;
}
```

## Go — a worker pool over a channel

```go
func process(jobs <-chan Job, results chan<- Result) {
    for j := range jobs {
        results <- Result{ID: j.ID, Body: strings.ToUpper(j.Body)}
    }
}

func main() {
    jobs := make(chan Job, 100)
    results := make(chan Result, 100)

    for i := 0; i < runtime.NumCPU(); i++ {
        go process(jobs, results)
    }
    // ...
}
```

> Inline code like `Bundle.module.url(forResource:)` and shell commands
> like `xcrun simctl list devices` get the same treatment.
