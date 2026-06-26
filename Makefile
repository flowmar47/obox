.PHONY: help setup dev gpu stop health logs pull-models clean monitoring

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

setup: ## Start the stack (production mode)
	./scripts/setup.sh

dev: ## Start in development mode (direct ports, no TLS)
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

env: ## Create .env from template
	cp -n .env.example .env 2>/dev/null || true
	@echo ".env ready — edit before production use"

monitoring: ## Open Grafana in browser (dev mode)
	@echo "Grafana: http://localhost:3001/grafana (dev) or https://\$${OBOX_DOMAIN}/grafana"
