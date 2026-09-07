.PHONY: all up down restart logs ps traffic lint clean help

COMPOSE_FILE := deploy/docker-compose/docker-compose.yml

all: help

## 🚀 Local Observability Platform
up: ## Start the complete local LGTM + OTel platform
	@echo "Starting Cloud-Native Observability Stack (Prometheus, Loki, Tempo, OTel, Grafana)..."
	docker compose -f $(COMPOSE_FILE) up -d --build
	@echo "=========================================================================="
	@echo "Observability Stack Active:"
	@echo "  - Grafana (UI):        http://localhost:3000 (admin/admin)"
	@echo "  - Prometheus (Metrics): http://localhost:9090"
	@echo "  - Tempo (Tracing):      http://localhost:3200"
	@echo "  - Loki (Logs):          http://localhost:3100"
	@echo "  - OTel Collector OTLP:  localhost:4317 (gRPC), localhost:4318 (HTTP)"
	@echo "=========================================================================="

down: ## Stop the local observability platform
	@echo "Stopping observability platform..."
	docker compose -f $(COMPOSE_FILE) down -v

restart: down up ## Restart the local platform

logs: ## Tail logs across all observability containers
	docker compose -f $(COMPOSE_FILE) logs -f

ps: ## List running observability containers
	docker compose -f $(COMPOSE_FILE) ps

traffic: ## Run synthetic load test against the local stack
	@echo "Triggering synthetic traffic generator..."
	bash deploy/docker-compose/traffic-generator/traffic.sh

## 🔍 Validation & Linting
lint: ## Validate Kubernetes YAML and Helm values schemas
	@echo "Linting Kubernetes and Alertmanager configurations..."
	@which yamllint > /dev/null 2>&1 && yamllint -d relaxed deploy/ || echo "yamllint not installed, skipping syntax check"

clean: ## Remove temporary containers, networks, and volumes
	docker compose -f $(COMPOSE_FILE) down -v --remove-orphans

help: ## Show this help menu
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'
