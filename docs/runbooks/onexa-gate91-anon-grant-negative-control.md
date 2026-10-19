# Gate 91 — Negative control for anonymous grant escalation

This check deliberately grants SELECT to `anon` on the native work-order table **only inside the disposable GitHub Actions PostgreSQL database**. Gate90 must fail with the expected permission finding; the trap revokes the artificial grant and then reruns Gate90, which must pass. It validates that the grant-matrix checker catches an actual privilege regression rather than simply inspecting source text.

Never execute this destructive grant fixture on hosted production or Staging. It uses no real users or company records.
