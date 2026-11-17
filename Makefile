COMPOSE ?= docker compose

.DEFAULT_GOAL := help

.PHONY: help build run test fmt vet \
	infra-up infra-down infra-restart infra-ps infra-logs infra-pull infra-clean \
	redpanda-topics valkey-cli seaweedfs-status

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-18s %s\n", $$1, $$2}'

## Go

build: ## Build bin/strata
	go build -o bin/strata ./cmd/strata

run: ## Run strata
	go run ./cmd/strata

test: ## Run the tests
	go test ./...

fmt: ## Format the code
	gofmt -w .

vet: ## Run go vet
	go vet ./...

## Infrastructure (compose.yaml)

infra-up: ## Start seaweedfs, redpanda and valkey; wait until they are healthy
	$(COMPOSE) up -d --wait

infra-down: ## Stop the services (keeps the data volumes)
	$(COMPOSE) down

infra-restart: infra-down infra-up ## Restart the services

infra-ps: ## Show service status
	$(COMPOSE) ps

infra-logs: ## Follow logs (SERVICE=name for one service)
	$(COMPOSE) logs -f $(SERVICE)

infra-pull: ## Pull the pinned images
	$(COMPOSE) pull

infra-clean: ## Stop the services and DELETE their data volumes
	$(COMPOSE) down -v

redpanda-topics: ## List Redpanda topics
	$(COMPOSE) exec redpanda rpk topic list

valkey-cli: ## Open valkey-cli
	$(COMPOSE) exec valkey valkey-cli

seaweedfs-status: ## Show the SeaweedFS cluster status
	curl -s http://127.0.0.1:9333/cluster/status; echo
