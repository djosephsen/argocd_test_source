# Spec & Proof of Concept
## ReleaseChannels API

This Repository contains a reference implementation of the proposed Release-Channels API server, along with the reference specifications for how the API is expected to work.

* [The spec](docs/spec.md)

## The reference Implementation
The POC server reads from a [static, json formatted file in the testdata directory](testdata/testdata.json). This file is a simple array of primitives the spec defines as [a release](docs/spec). 

```
gh repo clone myprizepicks/release-chan-api-poc
cd release-chan-api-poc
go run ./cmd/server/main.go
```
The server will start and read-in the "database", it is hard-coded to listen on port 8089.

```
curl localhost:8089/v1/releases?container=prizepicks-rails-api-utility
```
The only implemented query path is `v1/releases`.  You can query the release db with url params by `container`, `release-channel`, or both. Querying the data by `container` or `release-channel` will yield multiple responses which are formatted in the spec-defined `release` format, and which contain valid `image-path` attributes. 

```
[
  {
    "container": "prizepicks-rails-api-utility",
    "image_path": "ghcr.io/myprizepicks/prizepicks-rails:4.279.3-dev",
    "release_channel": "dev"
  },
  {
    "container": "prizepicks-rails-api-utility",
    "image_path": "ghcr.io/myprizepicks/prizepicks-rails:4.279.3-stage",
    "release_channel": "stage"
  },
  {
    "container": "prizepicks-rails-api-utility",
    "image_path": "ghcr.io/myprizepicks/prizepicks-rails:4.279.3-prod",
    "release_channel": "prod"
  },
  {
    "container": "prizepicks-rails-api-utility",
    "image_path": "ghcr.io/myprizepicks/prizepicks-rails:4.279.3-hotfix",
    "release_channel": "hotfix"
  },
  {
    "container": "prizepicks-rails-api-utility",
    "image_path": "ghcr.io/myprizepicks/prizepicks-rails:4.279.3-prod",
    "release_channel": "davetest"
  }
]

```
This is the API response to the `container` query pasted above. For the `prizepicks-rails-api-utility` container we have 4 valid responses, from four different `release-channel`'s dev, stage, prod, hotfix, and davetest.

In the event no valid response is available for a given query, the server responds with a 404 and an empty list...

```
curl -v localhost:8089/v1/releases?container=foobar 
* Host localhost:8089 was resolved.
* IPv6: ::1
* IPv4: 127.0.0.1
*   Trying [::1]:8089...
* Connected to localhost (::1) port 8089
> GET /v1/releases?container=foobar HTTP/1.1
> Host: localhost:8089
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 404 Not Found
< Content-Type: application/json
< Date: Thu, 27 Mar 2025 22:59:26 GMT
< Content-Length: 3
< 
[]
```
Because an image-path will always be uniquely identified by a container name and a release-channel, in the event both `release_channel` and `container` query params are provided, it is expected the api answer will only contain a single result (though it is still returned in list context). Unit tests should enforce this:

```
curl "localhost:8089/v1/releases?container=prizepicks-rails-api-utility&release_channel=davetest" | jq .
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   142  100   142    0     0   109k      0 --:--:-- --:--:-- --:--:--  138k
[
  {
    "container": "prizepicks-rails-api-utility",
    "image_path": "ghcr.io/myprizepicks/prizepicks-rails:4.279.3-prod",
    "release_channel": "davetest"
  }
]
```

## Automated Releases with Semantic Release

This project uses [semantic-release](https://semantic-release.gitbook.io/) to automate versioning, changelog generation, and releases based on commit messages.

### Usage

**For Development:**
```bash
make dev-run  # Builds with dev-{git-hash} version
```

**For Releases:**
```bash
# Manual release with specific version
make build VERSION=v1.2.3

# Automated release (happens automatically in publish.yml)
git commit -m "feat: add new feature"
git push origin main  # Triggers semantic-release
```

### Configuration Files

- `release.config.js` - Semantic-release configuration
- `.github/workflows/publish.yml` - GitHub Actions workflow
- `.version` - Current version file (managed by semantic-release)
