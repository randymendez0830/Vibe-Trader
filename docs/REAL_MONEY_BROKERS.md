# Going Live: Which Broker for Real-Money Automation

**Read this only after your Alpaca Paper POC has earned your trust.** This is the
graduation step — real money, so the bar is "I have watched this work for weeks
and I understand every trade it makes," not "the paper account went up once."

I checked which of Vibe-Trading's built-in brokers can actually place **live**
(real-money) orders, and — since you're trading options — which handle **US
options**. Not all of them do, and that changes the answer.

## What the tool actually supports for live trading

| Broker | Live real-money orders? | US options? | Notes |
|---|---|---|---|
| **Alpaca** | ✅ Yes (`alpaca-live-trade`) | ✅ Yes | US-regulated (SIPC), API-first, free. **Same connector as your paper POC.** |
| **Robinhood** | ✅ Yes (`robinhood-live-mcp`) | ✅ Yes | Real money only (no paper). Integration is via "agentic MCP" — least battle-tested here. |
| **Tiger** | ✅ Yes (`tiger-live-trade`) | ✅ Yes | UP Fintech; Asia-oriented, US options available but more friction for a US user. |
| **Futu / Moomoo** | ✅ Yes (`futu-live-trade`) | ✅ Yes | Moomoo; Asia-oriented, US-available. |
| **Interactive Brokers (IBKR)** | ❌ **Read-only live in this tool** | (great broker) | The pro's choice for options — but this tool only *reads* a live IBKR account; it can place **paper** IBKR orders, not live ones. See caveat below. |
| **Trading 212** | ❌ Read-only | — | Can't place orders live or paper here. |
| **Longbridge** | ❌ Read-only live | — | Only paper places orders. |
| Binance / OKX | ✅ (crypto) | — | Crypto only — not for US options. |

## My recommendation

### #1 — Graduate to Alpaca Live (the obvious path)

Once your paper POC works, **the cleanest move is Alpaca Live**, because it's the
*exact same connector you already trust* — you're not adding a new, unproven
integration at the same moment you add real money. You change two things: swap in
your live keys and grant the mandate (below). Everything else — the agent, the
persona, the safety rails — is identical to what you already validated on paper.

- US-regulated, SIPC-insured, supports equities **and** options
- Free, API-first (built for exactly this)
- The switch is: new keys in `alpaca.json` (`"profile": "live"`), `vibe-trading connector use alpaca-live-trade`, then grant the mandate

### #2 — Robinhood, only if you already live there

If you already trade options on Robinhood and want to keep everything in one
place, it works. But two honest caveats: it's **real money from the first order**
(no paper to fall back to), and its connector here is the least mature. I'd only
pick it once the agent has a long, boring track record on Alpaca paper *and* live.

### The IBKR caveat (worth knowing)

Interactive Brokers is what a lot of serious options traders reach for — deepest
options tooling, best fills, professional-grade. **But in this specific tool,
live IBKR trading is read-only** — it can watch a live IBKR account and place
*paper* orders, but not live ones. So if IBKR is your long-term home, you'd
either keep using it read-only (agent advises, you click the button) or someone
would need to extend the connector. Don't assume "IBKR + full automation" works
out of the box here; it doesn't yet.

### Tiger / Futu (Moomoo)

Both can place live US-options orders and are legitimate, but they're built
around Asian markets. Only worth it if you already have an account there.

## The one-time safety gate for real money: the "mandate"

Every live-trading profile carries `orders.place.requires_mandate`. That means
the agent **flatly refuses to place a real-money order** until you grant an
explicit, signed permission called a **mandate**. This is deliberate — real
trading can never happen by accident or by the agent "deciding" to flip itself
live. You turn it on, on purpose, when you're ready:

```bash
# After configuring live keys and selecting a live profile:
vibe-trading connector use alpaca-live-trade
vibe-trading connector authorize alpaca-live-trade   # grant the mandate (deliberate step)

# The kill switch still works — your instant emergency brake:
vibe-trading connector halt      # block all new orders now
vibe-trading connector resume

# And you can revoke the mandate entirely at any time:
vibe-trading connector revoke    # pull the permission; agent goes back to read/paper only
```

## How to actually go live (do it slowly)

1. **Weeks of clean paper first.** The paper account grows, and every loss lands where the agent said it would.
2. **Fund small.** Start real money with an amount you would be genuinely fine losing to a bug or a bad week. Not your savings.
3. **Cap the size.** Keep the agent's per-trade risk tiny in absolute dollars at first — the persona already sizes to 1–2% of the account, so a small account = small trades.
4. **Watch every trade at first.** Read `connector orders` daily; have the agent explain each position in plain English.
5. **Keep the kill switch one command away**, and know how to `revoke` the mandate.
6. **Scale only on evidence**, never on a good feeling or a hot streak.

**The tool makes full real-money automation possible. Whether you should is
your call — and the honest answer is: only after a long, boring, verified track
record, and never with money you can't afford to lose. Automated options trading
can lose money fast; treat every step toward "hands-off + real funds" as a
decision to make slowly, on purpose.**
