#!/usr/bin/env bash
kubectl get pods --all-namespaces -o json | jq -r '[.items[] | .spec.containers[] | {(.name): .image}] | add | to_entries | map({container: .key, releaseChannel: "dev", imagePath: .value})'
