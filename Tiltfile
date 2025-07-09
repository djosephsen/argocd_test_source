# Tiltfile for Release Channels API
# This enables fast development cycles with live code updates

# Load extensions
load('ext://restart_process', 'docker_build_with_restart')

# Configuration
k8s_yaml('deployment/k8s-deployment.yaml')

# Build the Docker image with live update capabilities
docker_build_with_restart(
    'ghcr.io/myprizepicks/release-channels-api',
    '.',
    entrypoint=['/app/server'],
    dockerfile='./Dockerfile',
    only=[
        './go.mod',
        './go.sum',
        './cmd/',
        './internal/',
        './db/',
    ],
    live_update=[
        # Sync source code changes
        sync('./cmd/', '/app/cmd/'),
        sync('./internal/', '/app/internal/'),
        sync('./db/', '/app/db/'),
        sync('./go.mod', '/app/go.mod'),
        sync('./go.sum', '/app/go.sum'),
        
        # Rebuild when Go files change
        run('cd /app && go build -o server ./cmd/server', trigger=['./cmd/', './internal/']),
    ],
)

# Configure Kubernetes resource
k8s_resource(
    'release-channels-api',
    port_forwards=[
        # Forward port 8089 from the service to local port 8089
        port_forward(8089, 8089, name='api-server'),
    ],
    # Set resource dependencies
    resource_deps=[],
    # Labels for organization
    labels=['api', 'backend'],
)

# Watch for additional files that should trigger updates
watch_file('./go.mod')
watch_file('./go.sum')
watch_file('./Dockerfile')

# Local development helpers
local_resource(
    'go-compile-check',
    'go build -o /tmp/server-check ./cmd/server',
    deps=['./cmd/', './internal/', './go.mod', './go.sum'],
    labels=['development'],
    auto_init=False,  # Don't run automatically, only when triggered
)

# Tests as a local resource for quick feedback
local_resource(
    'go-test',
    'go test ./...',
    deps=['./cmd/', './internal/', './go.mod', './go.sum'],
    labels=['testing'],
    auto_init=True,
    trigger_mode=TRIGGER_MODE_MANUAL,  # Run tests manually
)

# Print helpful information
print("""
🚀 Release Channels API Development Environment

Available services:
  • API Server: http://localhost:8089
  • Health Check: http://localhost:8089/v1/releases

Development workflow:
  1. Edit Go files in ./cmd/ or ./internal/
  2. Tilt will automatically:
     - Sync your changes to the container
     - Rebuild the binary
     - Restart the server
  3. Test your changes at http://localhost:8089

Useful Tilt commands:
  • tilt up              - Start development environment
  • tilt down            - Stop and clean up
  • tilt trigger go-test - Run tests manually
  • tilt logs            - View application logs

Happy coding! 🎉
""")

# Configuration for different environments
config.define_string('namespace', args=False, usage='Kubernetes namespace to deploy to')
cfg = config.parse()

# Use custom namespace if provided
if cfg.get('namespace'):
    k8s_namespace(cfg.get('namespace')) 
