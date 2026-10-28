# Security Policy

## Supported versions

Until a stable release exists, only the latest `main` branch and latest tagged prerelease are supported.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature when it is enabled for this repository. If it is not available, open a public issue that says only that you need a private security contact; do **not** include exploit details, secrets, private paths, or user data in that issue.

## Security-sensitive areas

Please treat scanner path handling, process execution, download/install routing, migration adapters, backup/rollback, report privacy, and catalog URL/package-token handling as security-sensitive.

LibreReplace never needs shell command interpolation. Homebrew actions are represented as an executable plus argument array and package tokens are validated before execution.
