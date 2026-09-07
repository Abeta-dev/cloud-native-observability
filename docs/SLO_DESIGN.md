# Site Reliability Engineering (SRE) SLO & Error Budget Framework

This document outlines the architectural mathematical framework used to define Service Level Indicators (SLIs), Service Level Objectives (SLOs), and Error Budget Burn Rate alerting across our microservices platform.

---

## 1. Fundamentals

- **SLI (Service Level Indicator)**: A quantifiable metric of service performance observed in real time (e.g., proportion of successful HTTP requests).
- **SLO (Service Level Objective)**: The target reliability reliability agreed upon by engineering and product (e.g., 99.9% successful requests over a rolling 30-day window).
- **SLA (Service Level Agreement)**: The contractual commitment with customers with financial penalties if breached.
- **Error Budget**: The allowable unreliability:
  $$\text{Error Budget} = 1 - \text{SLO}$$
  For a **99.9% SLO**, the monthly error budget is **0.1% (0.001)**. Over 30 days (43,200 minutes), this equals **43.2 minutes** of allowable downtime.

---

## 2. Why Simple Threshold Alerting Fails

| Anti-Pattern | Symptom | Impact |
|---|---|---|
| Alerting on raw error count (`errors > 10`) | Alerts fire on low-traffic hours with few errors | Alert fatigue |
| Alerting on single 5-minute rate | Temporary spikes page engineers even if system self-heals | Flapping & wake-up pages |
| Alerting on 30-day rolling rate | Slow reaction time (takes days to detect an outage) | SLA breach |

---

## 3. The Google SRE Multiwindow Multi-Burn-Rate Strategy

To achieve **high precision** (no false positives) and **high recall** (no missed outages) while reacting in time to prevent SLA breaches, we adopt Google's **Multiwindow Multi-Burn-Rate** alerting standard (Google SRE Book, Chapter 5).

### Burn Rate Definition

A **Burn Rate of 1.0** consumes exactly 100% of the monthly error budget over 30 days.
- **Burn Rate 14.4**: Consumes **100% of budget in 50 hours**, or **2% of budget in 1 hour**.
- **Burn Rate 6.0**: Consumes **100% of budget in 120 hours**, or **5% of budget in 6 hours**.
- **Burn Rate 1.0**: Consumes **100% of budget in 720 hours (30 days)**.

### The Multiwindow Matrix

To avoid false alarms from short temporary bursts, two sliding windows must simultaneously breach the threshold:

| Alert Name | Alert Tier | Short Window | Long Window | Burn Rate | % Budget Consumed | Notification Channel |
|---|---|:---:|:---:|:---:|:---:|:---:|
| `ServiceErrorBudgetBurnRateHigh1h` | **Critical Pager** | 5 minutes | 1 hour | **14.4x** | 2% in 1 hour | PagerDuty (Immediate Page) |
| `ServiceErrorBudgetBurnRateHigh6h` | **Critical Pager** | 30 minutes | 6 hours | **6.0x** | 5% in 6 hours | PagerDuty (Immediate Page) |
| `ServiceErrorBudgetBurnRateSlow3d` | **Warning Ticket** | 6 hours | 3 days | **1.0x** | 10% in 3 days | Slack / Jira Ticket |

---

## 4. PromQL Implementation

```promql
# Precomputed Recording Rule:
# record: job:http_requests:error_rate_1h
# expr: sum(rate(http_requests_total{status=~"5.."}[1h])) by (service, namespace) / sum(rate(http_requests_total[1h])) by (service, namespace)

# Window 1: 14.4x burn rate over 1h AND 5m
(
  job:http_requests:error_rate_1h > (1 - 0.999) * 14.4
)
and
(
  job:http_requests:error_rate_5m > (1 - 0.999) * 14.4
)
```

The dual `and` clause guarantees that:
1. The 1-hour window confirms significant budget consumption.
2. The 5-minute window confirms that the incident is **still actively happening right now** (preventing pages for incidents that already resolved).
