.PHONY: build run test fmt vet

build:
	go build -o bin/strata ./cmd/strata

run:
	go run ./cmd/strata

test:
	go test ./...

fmt:
	gofmt -w .

vet:
	go vet ./...
