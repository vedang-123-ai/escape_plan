# S11.42 — Server settings: token rotation reaches every install, bad addresses refused

- **Who:** P3 (Lane D)
- **Date(s):** 2026-10-04
- **Status when I stopped:** done on branch s11-42-server-settings; AUD-009 fixed.

## What happened
- `APIClient`: token override flag (`APIClient.bearerTokenOverridden`); precedence launch argument > saved override >
  bundled. `overrideBearerToken`, `clearBearerTokenOverride`, `resetToDefaults`. `validatedBaseURL` (URLComponents:
  https + host; http only for localhost/127.0.0.1 and only when allowed; no userinfo).
- Settings: Advanced, its footnote and Developer are `#if DEBUG`; save validates and shows the error (warning colour,
  VoiceOver announcement); "Saved" only on success; empty token field clears the override; "Reset to default" added.
- Migration: a stored token with no flag (every install that ever tapped Save) is treated as not overridden, so the
  bundled token, including a rotated one, wins on the next launch.
- Reviewers found that Release still honoured a stored URL, a stored token and launch arguments with no UI to fix them.
  Fixed with `honorOverrides` (false in Release), and `currentBaseURL` validates what it reads.
- Launch arguments are read from the argument domain explicitly, so the 8+ UI tests keep working and nothing persists.

## Decisions / surprises
- URL needs no flag (unit suites seed it directly); only the token does. See decisions.md 2026-10-04 S11.42.
- Mutation checks (broke the code, saw the test fail, restored): (1) honour a stored token without the flag
  -> migration test failed; (2) persist launch-argument token -> launch-argument test failed; (3) allow http for any
  localhost regardless of the flag -> validation test failed; (4) disable `honorOverrides` -> Release test failed.
- Not run on Release configuration at runtime (no device); Release behaviour is tested through the `honorOverrides`
  parameter, and `typecheck-ios.sh` compiles the release variant.

## Questions for teammates
- @owner: device check after the token is rotated (BLOCKERS S11.42).

## Next steps
- None for this session.
