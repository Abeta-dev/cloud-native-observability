# Security Policy

## Supported Versions

`cloud-native-observability` provides security updates for the current minor release series:

| Version Series | Security Updates       | Status               |
| -------------- | ---------------------- | -------------------- |
| 0.2.x          | :white_check_mark: Yes | **Active / Current** |
| 0.1.x          | :white_check_mark: Yes | Maintenance          |
| < 0.1.0        | :x: No                 | End-of-Life          |

---

## Reporting a Vulnerability

The maintainers take security and infrastructure integrity seriously. If you discover a potential security vulnerability in any manifest, configuration, container definition, or telemetry pipeline, **please do not open a public GitHub issue**. Public disclosure could expose production observability pipelines or credentials to risk.

Instead, report vulnerabilities through one of the following confidential channels:

### 1. GitHub Private Vulnerability Reporting (Preferred)
Submit a confidential advisory directly via GitHub:
- Navigate to the **Security** tab of `github.com/umesh0492/cloud-native-observability`.
- Click **"Report a vulnerability"** to open a private advisory draft.
- Include a description, affected component(s) (e.g. Helm values, ArgoCD sync-waves, Terraform modules, or Docker Compose), reproduction steps, and potential impact.

### 2. Direct Security Contact
If you cannot use GitHub Security Advisories, email the maintainer directly:
- **Email**: [umesh0492@gmail.com](mailto:umesh0492@gmail.com)
- **Subject**: `[SECURITY] cloud-native-observability Vulnerability Report: <Component>`
- Please include reproduction steps and deployment target details.

---

## Security Architecture & Best Practices

This repository adheres to strict cloud-native security principles:

1. **Zero Hardcoded Secrets**: All production credentials (Grafana admin passwords, Slack/PagerDuty webhook URLs, Thanos S3/GCS keys, Mimir auth tokens) must be injected via Kubernetes Secrets, environment variables, or secret stores (HashiCorp Vault / AWS Secrets Manager).
2. **GitOps Sync-Wave Ordering**: Secrets and CRDs are provisioned in sync-wave `-1` before workload ingestion in sync-wave `0`, preventing race conditions and unauthenticated exposure during bootstrapping.
3. **Immutable Image Supply Chain**: Container base images are pinned to explicit versions and digests.
4. **Least-Privilege RBAC**: Prometheus and OpenTelemetry Collector ServiceAccounts have read-only cluster inspection permissions (`get`, `list`, `watch` on Pods, Services, Endpoints, and Nodes).
5. **Container Hardening**: All demo and tooling containers run with `readOnlyRootFilesystem: true`, non-root execution (`runAsNonRoot: true`), and dropped capabilities (`drop: ["ALL"]`).
6. **CI/CD Action Hardening**: All GitHub Actions automation workflows pin actions to immutable commit SHAs with minimum `permissions: read-all` scopes to defend against pipeline supply-chain compromise.

---

## Response SLA

As a focused maintainer team, we commit to the following response timeline:

- **Initial Acknowledgement**: Within **48 hours** of report receipt.
- **Assessment & Triage**: Within **5 business days**, confirming severity and scope.
- **Fix & Patch Release**: Targeted within **14 business days** depending on complexity.
- **Coordinated Disclosure**: Coordinated with the reporter via a GitHub Security Advisory and published alongside a patch release.
