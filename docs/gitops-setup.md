# GitOps Setup for Release Channel Updates

This document explains how to set up automated updates to the Release Channel API database using **Repository Dispatch Events** with **ArgoCD deployment**.

## Architecture Overview

```
┌─────────────────┐    Repository    ┌──────────────────────────┐
│   Source Repo   │    Dispatch      │   release-chan-api-poc   │
│                 │    Event         │                          │
│ ┌─────────────┐ │ ───────────────> │ ┌──────────────────────┐ │
│ │Build & Push │ │                  │ │ update-database.yml  │ │
│ │   Workflow  │ │   JSON Payload   │ │                      │ │
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

## How It Works

The GitOps strategy works as follows:

1. **Source repositories** trigger a repository dispatch event when new images are built
2. **This repository** receives the dispatch event and updates `db/db.json` directly
3. **Changes are committed** to the main branch automatically
4. **Publish workflow** automatically triggers and builds/publishes new API image
5. **ArgoCD** detects repository changes and deploys updated API instances
6. **New API instances** load the updated database on startup

## Current Workflow Files

### This Repository
- **`update-database.yml`** - Handles repository dispatch events and updates database
- **`publish.yml`** - Builds and publishes API container image (triggers automatically)
- **`source-repo-template.yml`** - Template for source repositories to copy

### Source Repositories (after setup)
- **`update-release-channel.yml`** - Copied from template, triggers dispatch events

## Setup Steps

### Step 1: Configure This Repository

✅ **Already Done** - This repository has the necessary workflows installed:
- `update-database.yml` handles incoming repository dispatch events
- `publish.yml` builds and publishes the API when database changes
- ArgoCD monitors this repository for deployments

### Step 2: Set Up Source Repository

1. **Copy the workflow template**:
```bash
# In your source repository
mkdir -p .github/workflows
cp /path/to/release-chan-api-poc/.github/workflows/source-repo-template.yml \
   .github/workflows/update-release-channel.yml
```

2. **Customize the workflow**:
   - Update the `workflow_run.workflows` to match your build workflow name
   - Adjust branch-to-channel mapping in the `Determine release parameters` step
   - Modify container name logic if needed

3. **Add the PAT secret**:
```bash
# Create a PAT with 'repo' permissions first, then:
gh secret set RELEASE_API_PAT --body "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Step 3: Test the Setup

1. **Manual test** using workflow dispatch:
```bash
# In your source repository
gh workflow run update-release-channel.yml \
  -f release_channel=dev \
  -f container_name=my-app \
  -f image_tag=v1.2.3
```

2. **Check the workflow run** in this repository's Actions tab
3. **Verify the database was updated** and ArgoCD deployment triggered

## Repository Dispatch Event Structure

The source repositories send this payload:

```json
{
  "event_type": "update-release-channel",
  "client_payload": {
    "container_name": "my-app",
    "release_channel": "dev", 
    "image_path": "ghcr.io/owner/repo:tag",
    "source_repo": "owner/source-repo",
    "source_sha": "abc123...",
    "source_ref": "refs/heads/main",
    "source_workflow_run_id": "123456789"
  }
}
```

## Deployment Flow

### Automatic (Build Triggered)
```
Source Repo Build → Success → Repository Dispatch → Database Update → 
Commit to Main → Publish Workflow → New Image → ArgoCD Sync → Deployment
```

### Manual (Testing)
```
Developer → Workflow Dispatch → Repository Dispatch → Database Update → 
Commit to Main → Publish Workflow → New Image → ArgoCD Sync
```

## Configuration Options

### Branch to Release Channel Mapping

Customize this logic in the source repository workflow:

```yaml
case "${{ github.ref }}" in
  refs/heads/main|refs/heads/master)
    RELEASE_CHANNEL="dev"
    ;;
  refs/heads/staging)
    RELEASE_CHANNEL="stage"
    ;;
  refs/heads/production)
    RELEASE_CHANNEL="prod"
    ;;
  refs/tags/*)
    # Tag-based releases
    if [[ "${{ github.ref }}" == *"-prod" ]]; then
      RELEASE_CHANNEL="prod"
    elif [[ "${{ github.ref }}" == *"-stage" ]]; then
      RELEASE_CHANNEL="stage"
    else
      RELEASE_CHANNEL="dev"
    fi
    ;;
esac
```

### Container Name Mapping

By default, the container name is the repository name. Override with:

```yaml
# Use a different container name
CONTAINER_NAME="my-custom-container-name"

# Or handle multiple containers
for CONTAINER in "app-api" "app-worker" "app-cron"; do
  # Trigger separate dispatch events for each container
done
```

### Image Tag Patterns

Customize image tag generation in the source repository workflow:

```yaml
# Use semantic versioning from tags
if [[ "${{ github.ref }}" == refs/tags/* ]]; then
  IMAGE_TAG="${{ github.ref_name }}"
# Use branch name for development
elif [[ "${{ github.ref }}" == refs/heads/* ]]; then
  BRANCH_NAME=$(echo "${{ github.ref_name }}" | sed 's/[^a-zA-Z0-9.-]/-/g')
  IMAGE_TAG="${BRANCH_NAME}-${{ github.sha }}"
# Use commit SHA for other cases
else
  IMAGE_TAG="${{ github.sha }}"
fi
```

## Testing

### Local Testing of update-database.yml

You can test the database update workflow locally using either the GitHub CLI or curl.

#### Prerequisites
```bash
# Install GitHub CLI if not already installed
# Ubuntu/Debian: sudo apt install gh
# macOS: brew install gh
# Or download from: https://cli.github.com/

# Authenticate with GitHub
gh auth login
```

#### Method 1: Using curl (Recommended)

1. **Trigger a test dispatch event**:
```bash
curl -X POST \
  -H "Authorization: token $(gh auth token)" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/myprizepicks/release-chan-api-poc/dispatches" \
  -d '{"event_type":"update-release-channel","client_payload":{"container_name":"test-app","release_channel":"dev","image_path":"ghcr.io/test/app:v1.2.3","source_repo":"manual-test","source_sha":"abc123"}}'
```

2. **Monitor the workflow**:
```bash
# Watch workflow runs
gh run list --limit 5

# View specific run details (replace <run-id> with actual ID)
gh run view <run-id>

# Follow logs in real-time
gh run watch <run-id>
```

3. **Verify the results**:
```bash
# Check if database was updated
git pull
jq '.releases[] | select(.container=="test-app")' db/db.json

# Check git history
git log --oneline -n 5 -- db/db.json
```

#### Method 2: Using JSON file

1. **Create a test file**:
```bash
cat > test-dispatch.json << 'EOF'
{
  "event_type": "update-release-channel",
  "client_payload": {
    "container_name": "test-app",
    "release_channel": "dev", 
    "image_path": "ghcr.io/test/app:v1.2.3",
    "source_repo": "manual-test",
    "source_sha": "abc123"
  }
}
EOF
```

2. **Send the dispatch event**:
```bash
gh api repos/myprizepicks/release-chan-api-poc/dispatches --method POST --input test-dispatch.json
```

3. **Clean up**:
```bash
rm test-dispatch.json
```

#### Test Different Scenarios

```bash
# Test updating existing entry
curl -X POST \
  -H "Authorization: token $(gh auth token)" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/myprizepicks/release-chan-api-poc/dispatches" \
  -d '{"event_type":"update-release-channel","client_payload":{"container_name":"test-app","release_channel":"dev","image_path":"ghcr.io/test/app:v2.0.0","source_repo":"update-test"}}'

# Test new container
curl -X POST \
  -H "Authorization: token $(gh auth token)" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/myprizepicks/release-chan-api-poc/dispatches" \
  -d '{"event_type":"update-release-channel","client_payload":{"container_name":"new-service","release_channel":"stage","image_path":"ghcr.io/test/new-service:v1.0.0","source_repo":"new-service-test"}}'

# Test production release
curl -X POST \
  -H "Authorization: token $(gh auth token)" \
  -H "Content-Type: application/json" \
  "https://api.github.com/repos/myprizepicks/release-chan-api-poc/dispatches" \
  -d '{"event_type":"update-release-channel","client_payload":{"container_name":"critical-app","release_channel":"prod","image_path":"ghcr.io/prod/critical-app:v3.1.4","source_repo":"critical-deployment"}}'
```

#### Testing from Source Repositories

To test the complete flow as it would work in production:

1. **Create or use an existing source repository**
2. **Copy the template workflow**:
```bash
# In your source repository
mkdir -p .github/workflows
cp /path/to/release-chan-api-poc/.github/workflows/source-repo-template.yml \
   .github/workflows/update-release-channel.yml
```
3. **Add the PAT secret** in the source repository
4. **Test via workflow dispatch**:
```bash
# In the source repository
gh workflow run update-release-channel.yml \
  -f release_channel=dev \
  -f container_name=my-app \
  -f image_tag=v1.2.3
```

#### Validate JSON Structure

```bash
# Validate database structure after changes
jq empty db/db.json && echo "✅ Valid JSON" || echo "❌ Invalid JSON"

# Check for required fields
jq '.releases[] | select(has("container") and has("releaseChannel") and has("imagePath") | not)' db/db.json

# Look for duplicates
jq -r '.releases[] | "\(.container)/\(.releaseChannel)"' db/db.json | sort | uniq -d
```

#### Cleanup Test Data

```bash
# Remove test entries (if needed)
jq 'del(.releases[] | select(.container | startswith("test-")))' db/db.json > db/db.json.tmp
mv db/db.json.tmp db/db.json

# Commit cleanup
git add db/db.json
git commit -m "Clean up test data"
git push
```

## Troubleshooting

### Common Issues

1. **Repository dispatch not triggering**:
   - Check PAT permissions (needs `repo` or `actions:write`)
   - Verify the repository name in `RELEASE_API_REPO` env var
   - Check GitHub Actions logs in source repository

2. **Database update failing**:
   - Check workflow logs in this repository's Actions tab
   - Verify JSON format of input parameters
   - Look for image path format validation errors

3. **Publish workflow not triggering**:
   - Ensure the update workflow successfully commits to main
   - Check that publish.yml is configured correctly
   - Verify semantic-release configuration

4. **ArgoCD not deploying**:
   - Check ArgoCD application sync status
   - Verify ArgoCD is monitoring the correct repository/branch
   - Check ArgoCD logs for sync errors

### Debugging Commands

```bash
# Test manual repository dispatch
gh api repos/myprizepicks/release-chan-api-poc/dispatches \
  --method POST \
  --field event_type=update-release-channel \
  --field client_payload='{"container_name":"debug","release_channel":"dev","image_path":"ghcr.io/debug/app:latest"}'

# Check database file
jq empty db/db.json && echo "Valid JSON" || echo "Invalid JSON"

# View recent database changes
git log --oneline -n 10 -- db/db.json

# Check ArgoCD application status (if ArgoCD CLI is available)
argocd app get release-channel-api

# Check API health
curl http://localhost:8089/v1/health
