# ReleaseChannel API Spec

This document lays out the (hopefully) final specification for the "ReleaseChannels API" -- a critical component of PrizePicks infrastructure that will eventually control what version of prizepicks applications get installed in which environments company-wide.

## Design

The ReleaseChannel API may eventually reside on or off cluster. Here it is depicted running on cluster, adjacent to the image-updater service, which will query it to derive and cache the proper image-path for each container in a given application's deployment at deployment-time.  
![design](/img/design1.png "")
The image-updater operator works by registering a "mutating admission webhook" with the k8s API. When new deployment requests are received by the k8s API, the image-updater webhook is called. This hook checks the incoming manifest for podspec's with container definitions matching the pattern of a replacement macro. When the macro is found, the IU webhook searches its local cache for a `Release` matching the requirements detailed by the macro. When it cannot find one locally, it queries through to the ReleaseChannel API, and caches the result locally for next time.

## Release

``` go
type Release struct{
Container      string
ImagePath      string
ReleaseChannel string
}
```

A `Release`, as defined in this spec, is the combination of three variables that uniquely identify a tagged software release.

### The Container Name

An application's deployment manifest in k8s may have a podspec containing more than one container, each of which contains a single `Image` attribute. Therefore, an OCI image cannot be uniquely identified by the name of the App, nor by any deployment-level attribute. In the API, we specifically choose to use the core/v1 `container.name` to specify the application to which a given image belongs. The `Container` field in the `Release` will be looked up in the API by the core/v1 container.name listed in the deployment manifest.

### The Release Channel

The Release-Channel classically identifies the "environment" to which a given release belongs, like `prod` or `dev`. However, in the near future release-channels will become more ephemeral in nature, as we expose the tools necessary for engineering to create their own release-channels in order to define personal, short-lived environments made up of hand-picked releases of the Prizepicks stack.

### The Image Path

The ReleaseChannel API response includes the fully-qualified path to the OCI image which matches the combination of Container and Release-Channel in the query. This is a departure from gitops and other style schemes currently in use, where we describe a version number alone in the manifest and expect cluster automation to _construct_ the fully qualified path to the OCI Image.  The intent here is myriad:

* Decouple image names from applications
* Provide a unique, explicit value in the deployment manifest that maps to any arbitrary image
* Minimize assumptions about image names in the cluster automation and toolchain
* Make it safe and easy to support multiple simultaneous image registries
* Make changing between registries a matter of routine API operations rather than k8s cluster surgery.

### Example release

Here is an example release for the [prizepicks-rails-api](https://github.com/myprizepicks/prizepicks-rails) app.

```
  {
    "container": "prizepicks-rails-api",
    "release_channel": "dev"
    "image_path": "ghcr.io/myprizepicks/prizepicks-rails:4.279.3-dev",
  }
```

The container attribute maps to the [container name specified in the deployment manifest](https://github.com/myprizepicks/app-ops/blob/main/apps/rails-api/base/deployment.yaml#L25) for the rails api app. The release-channel specified for this image is `dev`, and the image_path is specified as the fully-qualified name of the image at rest in the github container registry.

## Query Interface

### Request

The server should be queryable via http/GET, using query-parameters eg.. `https://server_url:port/v1/releases?container=foo&release_channel=bar`. The dataset should be queryable by container name, release_channel, or a combination of both.

### Response

The response is a valid http status code accompanied by a JSON-formatted list of `release`'s, which matched the query. All responses must be in list context. In the event of a 404, the server should include an empty list `[]`.

### Example "found" response

```
curl -v "localhost:8089/v1/releases?container=prizepicks-rails-api&release_channel=davetest" 
> GET /v1/releases?container=prizepicks-rails-api&release_channel=davetest HTTP/1.1
> Host: localhost:8089
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 200 OK
< Content-Type: application/json
< Date: Fri, 28 Mar 2025 14:15:37 GMT
< Content-Length: 134
< 
[{"container":"prizepicks-rails-api","image_path":"ghcr.io/myprizepicks/prizepicks-rails:4.279.3-prod","release_channel":"davetest"}]
```

### Example "not found" response

```
curl -v "localhost:8089/v1/releases?container=prizepicks-rails-api&release_channel=notfound" 
> GET /v1/releases?container=prizepicks-rails-api&release_channel=notfound HTTP/1.1
> Host: localhost:8089
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 404 Not Found
< Content-Type: application/json
< Date: Fri, 28 Mar 2025 14:17:13 GMT
< Content-Length: 3
< 
[]
```
