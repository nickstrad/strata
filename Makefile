COMPOSE ?= docker compose

.DEFAULT_GOAL := help

.PHONY: help build run test race noassert fmt vet check fuzz cover \
	infra-up infra-down infra-restart infra-ps infra-logs infra-pull infra-clean \
	redpanda-topics valkey-cli seaweedfs-status psql

help: ## List the targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-18s %s\n", $$1, $$2}'

## Go

build: ## Build bin/strata
	go build -o bin/strata ./cmd/strata

run: ## Run strata
	go run ./cmd/strata

test: ## Run the tests
	go test ./...

race: ## Run the tests with the race detector
	go test -race ./...

noassert: ## Vet and test with assertions compiled out
	go vet -tags noassert ./... && go test -tags noassert ./...

fmt: ## Format the code
	gofmt -w .

vet: ## Run go vet
	go vet ./...

check: vet race noassert ## The gate before done: gofmt, vet, race tests, noassert tests
	@test -z "$$(gofmt -l .)" || (echo "needs gofmt:"; gofmt -l .; exit 1)

fuzz: ## Run one fuzz target: make fuzz F=FuzzName P=./internal/pkg [T=30s]
	go test -run='^$$' -fuzz=$(F) -fuzztime=$(or $(T),30s) $(P)

cover: ## Coverage per function and total
	go test -coverpkg=./... -coverprofile=coverage.out ./... && go tool cover -func=coverage.out | tail -1

## Infrastructure (compose.yaml)

infra-up: ## Start postgres, seaweedfs, redpanda and valkey; wait until they are healthy
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

psql: ## Open psql on the strata database
	$(COMPOSE) exec postgres psql -U strata -d strata

valkey-cli: ## Open valkey-cli
	$(COMPOSE) exec valkey valkey-cli

seaweedfs-status: ## Show the SeaweedFS cluster status
	curl -s http://127.0.0.1:9333/cluster/status; echo
