# Ralph Loop Pre-check Snapshot (20260405T005922Z)

## 1) skills.sh listing
- URL: https://skills.sh/bookingdesk-ai/kontour-travel-planner/kontour-travel-planner
- Listing version: not exposed in rendered listing payload (`null` from HTML parse)
- Security cards: Agent Trust Hub = Pass; Socket = Warn; Snyk = Pass

## 2) Agent Trust Hub
- URL: https://skills.sh/bookingdesk-ai/kontour-travel-planner/kontour-travel-planner/security/agent-trust-hub
- Risk level: `SAFECOMMAND_EXECUTION`
- Key reason: command-execution surface acknowledged, with input whitelist in `plan.sh` reducing shell injection risk.

## 3) Socket
- URL: https://skills.sh/bookingdesk-ai/kontour-travel-planner/kontour-travel-planner/security/socket
- Verdict: `Anomaly` (LOW)
- Key reason text: standalone `Socket pass: True` style evidence creates ambiguity; requested code-level review for hidden network behavior.

## 4) Snyk
- URL: https://skills.sh/bookingdesk-ai/kontour-travel-planner/kontour-travel-planner/security/snyk
- Verdict: Pass
- Risk level: LOW
- Analysis: no issues detected.

## 5) ClawHub listing
- URL: https://clawhub.ai/skylinehk/kontour-travel-planner
- Listing version: `1.1.59`
- Static scan: `clean`
- Moderation flag: suspicious (`suspicious.llm_suspicious`)
- License string in listing payload: `MIT-0`
