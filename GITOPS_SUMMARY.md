# GitOps Strategy Summary: Repository Dispatch + ArgoCD Approach

## Problem Statement

You needed a way to keep your `db/db.json` file updated with new container images from multiple source repositories, without slowing down build processes and while maintaining consistency across multiple Kubernetes clusters managed by ArgoCD.

## Solution: Repository Dispatch Events + ArgoCD Deployment

Instead of having source repositories create PRs (which would make builds slower), we implemented a **Repository Dispatch + ArgoCD** strategy where:

1. **Source repos** make a single, fast API call to trigger an update
2. **This repository** handles all the database modification logic
3. **Publish workflow** automatically builds and publishes new API image
4. **ArgoCD** detects changes and deploys updated API instances

## Architecture Overview

```
┌─────────────────┐    Repository    ┌──────────────────────────┐
│   Source Repo   │    Dispatch      │   release-chan-api-poc   │
│                 │    Event         │                          │
│ ┌─────────────┐ │ ───────────────> │ ┌──────────────────────┐ │
│ │Build & Push │ │                  │ │ update-database.yml  │ │
│ │   Workflow  │ │                  │ │                      │ │
│ └─────────────┘ │                  │ │ 1. Validate params   │ │
│        │        │                  │ │ 2. Update db.json    │ │
│        v        │                  │ │ 3. Commit changes    │ │
│ ┌─────────────┐ │                  │ └──────────────────────┘ │
│ │   Trigger   │ │                  │          │               │
│ │   Update    │ │                  │          v               │
│ └─────────────┘ │                  │ ┌──────────────────────┐ │
└─────────────────┘                  │ │   publish.yml        │ │
                                     │ │                      │ │
                                     │ │ 1. Build API image   │ │
                                     │ │ 2. Publish to GHCR   │ │
                                     │ │ 3. Create release    │ │
                                     │ └──────────────────────┘ │
                                     └──────────────────────────┘
                                                 │
                                                 │ Git push triggers
                                                 v
                                    ┌────────────────────────┐
                                    │       ArgoCD           │
                                    │                        │
                                    │  Monitors repository   │
                                    │  Detects changes       │
                                    │  Syncs applications    │
                                    └────────────────────────┘
                                                 │
                                                 v
                          ┌──────────────────────────────────────┐
                          │      Kubernetes Clusters            │
                          │                                      │
                          │  Cluster 1         Cluster 2        │
                          │ ┌──────────────┐  ┌──────────────┐   │
                          │ │ API Pod      │  │ API Pod      │   │
                          │ │ New db.json  │  │ New db.json  │   │
                          │ └──────────────┘  └──────────────┘   │
                          └──────────────────────────────────────┘
```

## Implementation Files

### Core Workflow Files

1. **`.github/workflows/update-database.yml`** (This Repository)
   - Handles repository dispatch events
   - Updates `db/db.json`
   - Commits changes directly to main
   - Triggers publish workflow automatically

2. **`.github/workflows/publish.yml`** (Existing, triggers automatically)
   - Builds and publishes API container image
   - Uses semantic-release for versioning
   - Publishes to GitHub Container Registry

3. **`.github/workflows/source-repo-template.yml`** (Template)
   - Copy to source repositories as `update-release-channel.yml`
   - Triggers repository dispatch on successful builds
   - Determines container names and release channels

### Server Enhancements

4. **`internal/server/server.go`** (Modified)
   - Added file watching capability (optional, for running instances)
   - Auto-reloads database every 30 seconds if needed
   - Added manual reload endpoint: `POST /v1/reload`

5. **`cmd/server/main.go`** (Modified)
   - Passes database file path to server

### Setup and Documentation

6. **`docs/gitops-setup.md`** - Comprehensive setup guide for ArgoCD integration
7. **`scripts/setup-gitops.sh`** - Automated setup script
8. **`test-dispatch.sh`** (Generated) - Manual testing script

## Key Benefits

### ✅ **Performance**
- Source repo builds only make a single API call (~1-2 seconds)
- No checkout, jq installation, or JSON manipulation in source repos
- No PR creation/merge delays

### ✅ **GitOps Compliance** 
- All changes tracked in git
- ArgoCD handles all deployments
- Declarative configuration management
- Automatic sync and self-healing

### ✅ **Reliability**
- Input validation in centralized location
- Atomic database updates
- ArgoCD ensures deployment consistency
- Error handling and notifications

### ✅ **Auditability**
- All changes tracked in git history
- ArgoCD deployment history
- Source repository traceability

## Setup Process

### 1. Run Setup Script
```bash
./scripts/setup-gitops.sh
```

### 2. Configure ArgoCD
```yaml
# ArgoCD Application example
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: release-channel-api
spec:
  source:
    repoURL: https://github.com/myprizepicks/release-chan-api-poc
    targetRevision: HEAD
    path: deployment
  destination:
    server: https://kubernetes.default.svc
    namespace: release-api
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 3. Configure Source Repositories
```bash
# In each source repository:
cp .github/workflows/source-repo-template.yml .github/workflows/update-release-channel.yml

# Add PAT secret
gh secret set RELEASE_API_PAT --body "ghp_your_token_here"
```

### 4. Test the Integration
```bash
# Manual test
./test-dispatch.sh YOUR_PAT my-app dev ghcr.io/test/app:v1.0.0

# Or via workflow dispatch in source repo
gh workflow run update-release-channel.yml -f release_channel=dev
```

## Event Flow

### Automatic (Build Triggered)
```
Source Repo Build → Success → Repository Dispatch → Database Update → Commit to Main → Publish Workflow → New Image → ArgoCD Sync → Deployment
```

### Manual (Testing)
```
Developer → Workflow Dispatch → Repository Dispatch → Database Update → Commit to Main → Publish Workflow → New Image → ArgoCD Sync
```

## Configuration Examples

### Release Channel Mapping
```yaml
# In source repository workflow
case "${{ github.ref }}" in
  refs/heads/main)     RELEASE_CHANNEL="dev" ;;
  refs/heads/staging)  RELEASE_CHANNEL="stage" ;;
  refs/heads/production) RELEASE_CHANNEL="prod" ;;
  refs/tags/*)         RELEASE_CHANNEL="prod" ;;
esac
```

### Multiple Containers
```yaml
# Support multiple containers from one repo
for CONTAINER in "app-api" "app-worker" "app-cron"; do
  # Trigger separate dispatch for each
done
```

### Custom Image Tags
```yaml
# Tag strategy examples
if [[ "${{ github.ref }}" == refs/tags/* ]]; then
  IMAGE_TAG="${{ github.ref_name }}"      # Use git tag
else
  IMAGE_TAG="${{ github.sha }}"           # Use commit SHA
fi
```

## Monitoring and Debugging

### Check Workflow Status
- Monitor at: https://github.com/myprizepicks/release-chan-api-poc/actions
- Failed updates will show in workflow logs

### Check ArgoCD Status
```bash
# ArgoCD CLI
argocd app get release-channel-api
argocd app sync release-channel-api

# ArgoCD UI
# Check application dashboard for sync status
```

### Test API Health
```bash
curl http://localhost:8089/v1/health
curl http://localhost:8089/v1/releases?container=my-app
```

### View Recent Changes
```bash
git log --oneline -n 10 -- db/db.json
jq '.releases[] | select(.container=="my-app")' db/db.json
```

## Migration from PR-Based Approach

If you were using the old PR-based approach:

- ✅ **Remove** branch protection requirements
- ✅ **Replace** old workflow templates  
- ✅ **Keep** the same PAT (permissions are compatible)
- ✅ **Configure** ArgoCD to monitor this repository
- ✅ **Benefit** from much faster builds and GitOps compliance

## Security Considerations

- **PAT Scope**: Only needs `repo` or `actions:write` permissions
- **Repository Access**: Only trusted repos should have dispatch access
- **ArgoCD Security**: Ensure proper RBAC and monitoring
- **Audit Trail**: All changes logged in git history and ArgoCD

## Performance Impact

### Before (PR-based)
- Source build time: +2-3 minutes (checkout, jq, PR creation)
- Update latency: 5-10 minutes (PR review/merge)
- Deployment: Manual or separate process
- Complexity: High (distributed logic)

### After (Repository Dispatch + ArgoCD)
- Source build time: +5-10 seconds (single API call)
- Update latency: 1-2 minutes (immediate processing)
- Deployment: Automatic via ArgoCD
- Complexity: Low (centralized logic)

## ArgoCD Integration Benefits

### Deployment Consistency
- **Declarative**: All configuration in git
- **Automatic**: Continuous sync with git state
- **Self-healing**: Automatically corrects drift
- **Rollback**: Easy rollback via git history

### Operational Benefits
- **Multi-cluster**: Deploy to multiple clusters from single source
- **Health monitoring**: Built-in application health checks
- **Sync status**: Clear visibility into deployment state
- **Policy enforcement**: GitOps policies automatically enforced

## Next Steps

1. **Setup**: Run `./scripts/setup-gitops.sh`
2. **ArgoCD**: Configure ArgoCD application to monitor this repository
3. **Test**: Use `test-dispatch.sh` to verify functionality
4. **Deploy**: Copy template to source repositories
5. **Monitor**: Watch workflow runs, ArgoCD sync status, and API logs
6. **Scale**: Add more source repositories as needed

The solution provides a clean, fast, and GitOps-compliant way to keep your release channel database updated across all your Kubernetes clusters! 🚀 