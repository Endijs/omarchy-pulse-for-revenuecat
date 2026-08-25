# Security

## Credential boundary

Pulse for RevenueCat never stores RevenueCat credentials in plugin settings, QML,
`shell.json`, its Git repository, or its sanitized metrics cache.

The interactive `revenuecat-control manage` flow sends each project's API key to the
desktop Secret Service over stdin. Fetches retrieve it with `secret-tool` and
pass it to `curl` through a stdin configuration stream, keeping it out of the
process command line. API calls use HTTPS and request only aggregate chart and
overview data.

For the developer preview, users should create one dedicated API v2 key per
project with only:

- `project_configuration:projects:read`
- `charts_metrics:overview:read`
- `charts_metrics:charts:read`

The helper rejects keys that do not use RevenueCat's `sk_` prefix, validates
project IDs and currency before building request URLs, and reports missing
permissions separately. Remote project names are normalized before they reach
terminal or QML display sinks. Remote project images are not loaded because no
stable RevenueCat image-host allowlist is documented; the panel renders a local
project initial instead.
Secrets are indexed by project ID in Secret Service; the multi-project
configuration and cache contain no credentials.

Project removal changes local configuration only after Secret Service confirms
that the matching key was deleted or was already absent. Logout clears the
plugin's complete Secret Service namespace before removing local state; if the
keyring cannot confirm deletion, configuration and caches are retained so the
operation can be retried safely.

Secret Service protects the credential at rest and while the login keyring is
locked. Like other user-session applications, it cannot protect a credential
from malicious code already executing as the same logged-in user while that
keyring is unlocked.

## Reporting a vulnerability

Please use GitHub private vulnerability reporting once a public repository is
available. Do not open a public issue containing API keys, project identifiers,
or RevenueCat response data.
