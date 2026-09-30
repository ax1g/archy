---
description: Run exhaustive 10-phase Linux workstation audit (read-only first, evidence-based).
agent: build
---

Use the `linux-audit` skill. Start with Phase 1 system inventory using small read-only batches. Detect distro, kernel, DE, compositor, shell, hardware, package managers, filesystems, and boot config before making claims. Mark sudo commands explicitly. Warn about redaction (hostname, IPs, MACs, serials, keys). Wait for Phase 1 output before system-specific claims. Never make changes without explicit approval. $ARGUMENTS
