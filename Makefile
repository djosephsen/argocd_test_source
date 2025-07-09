# Variables
PROJECT_NAME = releases-api
DOCKER_REGISTRY = ghcr.io/myprizepicks
IMAGE_NAME = $(DOCKER_REGISTRY)/$(PROJECT_NAME)
VERSION ?= $(shell cat .version 2>/dev/null || echo "latest")
BUILD_DIR = bin
SERVER_BINARY = $(BUILD_DIR)/server

# Go related variables
GOCMD = go
GOBUILD = $(GOCMD) build
GOTEST = $(GOCMD) test
GOCLEAN = $(GOCMD) clean
GOMOD = $(GOCMD) mod

# Docker related variables
DOCKER = docker

.PHONY: help test build clean docker-build docker-push docker-login deps deploy deploy-all

# Default target
help: ## Show this help message
	@echo 'Usage: make <target>'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Test target - runs all tests
test: ## Run all tests
	@echo "Running tests..."
	$(GOTEST) -v ./...

# Build target - builds the project locally after running tests
build: test ## Build the project locally (runs tests first)
	@echo "Creating build directory..."
	@mkdir -p $(BUILD_DIR)
	@echo "Building server binary with version $(VERSION)..."
	$(GOBUILD) -ldflags "-X main.Version=$(VERSION)" -o $(SERVER_BINARY) ./cmd/server
	@echo "Build complete: $(SERVER_BINARY)"

# Clean target - removes build artifacts
clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	$(GOCLEAN)
	@rm -rf $(BUILD_DIR)
	@echo "Clean complete"

# Docker build target - builds docker image after running tests
docker-build: test ## Build Docker image (runs tests first)
	@echo "Building Docker image: $(IMAGE_NAME):$(VERSION)"
	$(DOCKER) build -t $(IMAGE_NAME):$(VERSION) .
	@echo "Docker image built: $(IMAGE_NAME):$(VERSION)"

# Docker push target - pushes the image to registry
docker-push: docker-build ## Push Docker image to registry (builds image first)
	@echo "Pushing Docker image: $(IMAGE_NAME):$(VERSION)"
	$(DOCKER) push $(IMAGE_NAME):$(VERSION)
	@echo "Docker image pushed: $(IMAGE_NAME):$(VERSION)"

# Docker login helper target
docker-login: ## Login to GitHub Container Registry
	@echo "Logging in to $(DOCKER_REGISTRY)..."
	@echo "Please ensure GITHUB_TOKEN environment variable is set"
	@echo $$GITHUB_TOKEN | $(DOCKER) login $(DOCKER_REGISTRY) -u $(shell git config user.name) --password-stdin

# Dependencies target - downloads, tidies, and vendors go modules
deps: ## Download, tidy, and vendor Go module dependencies
	@echo "Downloading dependencies..."
	$(GOMOD) download
	$(GOMOD) tidy
	@echo "Vendoring dependencies..."
	$(GOMOD) vendor
	@echo "Dependencies updated and vendored"

# Development targets
dev-run: ## Build and run the server locally with dev version
	@echo "Building and starting server with dev version..."
	$(GOBUILD) -ldflags "-X main.Version=dev-$(shell git rev-parse --short HEAD)" -o $(SERVER_BINARY) ./cmd/server
	./$(SERVER_BINARY)

dev-test-watch: ## Run tests in watch mode (requires entr)
	@echo "Running tests in watch mode (save any .go file to re-run tests)..."
	find . -name "*.go" | entr -c make test

# Docker development targets
docker-run: docker-build ## Build and run Docker container locally
	@echo "Running Docker container on port 8089..."
	$(DOCKER) run --rm -p 8089:8089 $(IMAGE_NAME):$(VERSION)

# Kubernetes deployment target
deploy: ## Deploy to Kubernetes using kubectl
	@echo "Deploying to Kubernetes..."
	kubectl apply -f deployment/k8s-deployment.yaml
	@echo "Deployment applied successfully"

# Version management
version: ## Show current version
	@echo "Current version: $(VERSION)"

set-version: ## Set version (usage: make set-version VERSION=v1.0.0)
ifndef VERSION
	@echo "Please specify VERSION: make set-version VERSION=v1.0.0"
	@exit 1
endif
	@echo "Version set to: $(VERSION)"

# All-in-one targets
all: clean deps test build ## Clean, download deps, test, and build
docker-all: clean deps docker-build docker-push ## Clean, download deps, build and push Docker image
deploy-all: docker-push deploy ## Build, push Docker image, and deploy to Kubernetes 
