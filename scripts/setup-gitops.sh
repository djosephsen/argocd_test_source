#!/bin/bash

# GitOps Setup Script for Release Channel API
# This script helps set up the GitOps workflow for automated database updates using Repository Dispatch

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}❌${NC} $1"
}

check_requirements() {
    log_info "Checking requirements..."
    
    # Check for required tools
    for cmd in gh jq curl; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is required but not installed"
            exit 1
        fi
    done
    
    # Check if we're in the right repository
    if [[ ! -f "db/db.json" ]]; then
        log_error "This script must be run from the release-chan-api-poc repository root"
        exit 1
    fi
    
    # Check if the new workflow files exist
    if [[ ! -f ".github/workflows/update-database.yml" ]]; then
        log_error "Missing required workflow file: .github/workflows/update-database.yml"
        exit 1
    fi
    
    if [[ ! -f ".github/workflows/source-repo-template.yml" ]]; then
        log_error "Missing template workflow file: .github/workflows/source-repo-template.yml"
        exit 1
    fi
    
    log_success "Requirements check passed"
}

setup_secrets() {
    log_info "Setting up repository secrets..."
    
    echo ""
    log_info "ArgoCD Integration:"
    log_info "This setup assumes ArgoCD is monitoring this repository."
    log_info "When database changes are committed, the publish workflow will trigger"
    log_info "and ArgoCD will automatically deploy the updated API instances."
    log_info ""
    log_info "No additional secrets are required for basic operation."
}

create_pat_instructions() {
    echo ""
    log_info "Creating Personal Access Token instructions..."
    
    cat > setup-pat.md << 'EOF'
# Personal Access Token Setup

For source repositories to trigger database updates, you need to create a Personal Access Token (PAT).

## Steps:

1. Go to GitHub Settings: https://github.com/settings/tokens
2. Click "Generate new token" > "Generate new token (classic)"
3. Configure the token:
   - **Name**: "Release Channel API Updates"
   - **Expiration**: 90 days (or as per your policy)
   - **Scopes**: Select `repo` (Full control of private repositories)
     - Alternatively, for fine-grained PATs: `metadata:read` + `actions:write`

4. Copy the generated token (starts with `ghp_`)

5. In each source repository, add the token as a secret:
   ```bash
   gh secret set RELEASE_API_PAT --body "ghp_your_token_here"
   ```

## Security Notes:
- Store the token securely
- Rotate regularly according to your security policy
- Consider using fine-grained PATs when available
- Limit the token to only necessary repositories/permissions
- Consider using GitHub Apps for organization-wide access

EOF

    log_success "PAT setup instructions created: setup-pat.md"
}

create_example_dispatch() {
    echo ""
    log_info "Creating example repository dispatch script..."
    
    cat > test-dispatch.sh << 'EOF'
#!/bin/bash

# Test script to manually trigger a repository dispatch event
# Usage: ./test-dispatch.sh YOUR_PAT container_name release_channel image_path

set -e

if [[ $# -lt 4 ]]; then
    echo "Usage: $0 <PAT_TOKEN> <container_name> <release_channel> <image_path>"
    echo "Example: $0 ghp_xxx... my-app dev ghcr.io/owner/repo:v1.0.0"
    exit 1
fi

PAT_TOKEN="$1"
CONTAINER_NAME="$2"
RELEASE_CHANNEL="$3"
IMAGE_PATH="$4"

echo "🚀 Triggering repository dispatch event..."
echo "  Container: $CONTAINER_NAME"
echo "  Release Channel: $RELEASE_CHANNEL"
echo "  Image Path: $IMAGE_PATH"

curl -X POST \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Authorization: token $PAT_TOKEN" \
  -H "Content-Type: application/json" \
  https://api.github.com/repos/myprizepicks/release-chan-api-poc/dispatches \
  -d "{
    \"event_type\": \"update-release-channel\",
    \"client_payload\": {
      \"container_name\": \"$CONTAINER_NAME\",
      \"release_channel\": \"$RELEASE_CHANNEL\",
      \"image_path\": \"$IMAGE_PATH\",
      \"source_repo\": \"manual-test\",
      \"source_sha\": \"test-$(date +%s)\"
    }
  }"

echo ""
echo "✅ Repository dispatch event sent!"
echo "📋 Monitor the workflow at:"
echo "   https://github.com/myprizepicks/release-chan-api-poc/actions"
EOF

    chmod +x test-dispatch.sh
    log_success "Test dispatch script created: test-dispatch.sh"
}

test_setup() {
    log_info "Testing setup..."
    
    # Test database validation
    if jq empty db/db.json; then
        log_success "Database file is valid JSON"
    else
        log_error "Database file has invalid JSON"
        return 1
    fi
    
    # Test server startup (if Go is available)
    if command -v go &> /dev/null; then
        log_info "Testing server startup..."
        timeout 10s go run cmd/server/main.go &
        SERVER_PID=$!
        sleep 3
        
        if curl -f http://localhost:8089/v1/health > /dev/null 2>&1; then
            log_success "Server started successfully"
        else
            log_warning "Server health check failed (may be normal in some environments)"
        fi
        
        kill $SERVER_PID 2>/dev/null || true
        wait $SERVER_PID 2>/dev/null || true
    else
        log_info "Go not available, skipping server test"
    fi
    
    # Test workflow file syntax (basic check)
    if command -v yamllint &> /dev/null; then
        if yamllint .github/workflows/update-database.yml > /dev/null 2>&1; then
            log_success "Workflow YAML syntax is valid"
        else
            log_warning "Workflow YAML may have syntax issues"
        fi
    fi
}

show_next_steps() {
    echo ""
    log_info "Setup complete! Next steps:"
    echo ""
    echo "1. 📖 Read the documentation: docs/gitops-setup.md"
    echo "2. 🔑 Set up Personal Access Token using: setup-pat.md"
    echo "3. 📋 Copy workflow template to source repositories:"
    echo "   cp .github/workflows/source-repo-template.yml <source-repo>/.github/workflows/update-release-channel.yml"
    echo "4. ⚙️  Customize the workflow for each source repository"
    echo "5. 🧪 Test with: ./test-dispatch.sh YOUR_PAT container-name dev ghcr.io/test/app:latest"
    echo "6. 🔄 Monitor workflow runs at: https://github.com/myprizepicks/release-chan-api-poc/actions"
    echo "7. 🚀 Ensure ArgoCD is configured to monitor this repository"
    echo ""
    echo "🎯 Benefits of this ArgoCD approach:"
    echo "   • Much faster source repository builds (single API call)"
    echo "   • Centralized database update logic"
    echo "   • GitOps compliance with ArgoCD deployments"
    echo "   • Automatic publish and deploy pipeline"
    echo "   • Simplified maintenance"
    echo ""
    log_success "ArgoCD GitOps setup is ready!"
}

show_migration_info() {
    echo ""
    log_info "Migration from PR-based approach:"
    echo ""
    echo "If you were using the old PR-based approach, note that:"
    echo "• The new approach is much simpler and faster"
    echo "• Old workflow files are deprecated:"
    echo "  - auto-merge-releases.yml (no longer needed)"
    echo "  - update-release-channel-template.yml (replaced by source-repo-template.yml)"
    echo "• No branch protection rules or auto-merge settings needed"
    echo "• Direct commits to main branch instead of PRs"
    echo ""
}

main() {
    echo "🚀 Release Channel API - ArgoCD GitOps Setup"
    echo "============================================="
    echo ""
    
    check_requirements
    setup_secrets
    create_pat_instructions
    create_example_dispatch
    test_setup
    show_migration_info
    show_next_steps
}

# Allow script to be sourced for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 