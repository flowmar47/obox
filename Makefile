.PHONY: help setup dev gpu stop health logs pull-models clean env monitoring validate backup update status

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Start the stack (production mode)
	./scripts/setup.sh

dev: ## Start in development mode (direct 127.0.0.1 ports, no TLS)
	OBOX_DEV=true ./scripts/setup.sh

gpu: ## Start with GPU support
	OBOX_GPU=true ./scripts/setup.sh

stop: ## Stop the stack
	./scripts/stop.sh

health: ## Run health checks
	./scripts/healthcheck.sh

logs: ## Tail all service logs
	docker compose logs -f

pull-models: ## Pull models from .env OLLAMA_MODELS
	./scripts/pull-models.sh

clean: ## Stop and remove all volumes (destructive)
	./scripts/stop.sh
	docker compose down -v

env: ## Create .env from template with generated secrets
	./scripts/setup.sh --env-only

monitoring: ## Show Grafana URLs
	@echo "Grafana (dev):  http://localhost:3001"
	@echo "Grafana (prod): https://\$${OBOX_DOMAIN:-your-domain.com}/grafana/"

validate: ## Run offline configuration and script validation
	./scripts/validate.sh

backup: ## Back up persistent volumes to ./backups/
	./scripts/backup.sh

update: ## Pull latest images and restart the stack
	docker compose pull && ./scripts/setup.sh

status: ## Show running container status
	docker compose ps
