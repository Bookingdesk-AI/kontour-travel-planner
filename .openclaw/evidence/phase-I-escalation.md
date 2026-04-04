# Phase I Escalation Logic
- platform_blocker_detected_this_run: no
- repeated_platform_blocker_count: 0
- retry_policy_when_blocked: retry publish every 3rd run only after 3 consecutive identical PLATFORM_BLOCKER events
- action_this_run: reset blocker counter and continue normal publish cadence
