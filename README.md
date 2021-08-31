# Kindfra project
An easy way to spin up a development kubernetes cluster with Kind.

# What can I do with this?
You will be able to create a multiworker kubernetes cluster with a few commands.
The cluster is configured to do a port-forward from your local machine 80/TCP port to the Kind cluster 80/TCP port or use a LoadBalancer IP behavior in case of Metallb usage.

And, if you want to go a bit further, you can also spin up a K8s cluster using your docker daemon using cluster-api.

# Pre-requisites
- Make installed
- Ubuntu OS Linux family (or Kind already available and running)

# Installation steps
- Download this repo
- Move to the root repo directory
- Run the following command (this process will install docker, kubectl and kind in your pc, you can execute targets individually):

```
make install-requirements
```

- Run one of the following commands based on the scenario you want to test:
  - create-standard-cluster: standard kind cluster + nginx ingress controller
  - create-cilium-cluster: standard kind cluster + cilium + nginx ingress controller
  - create-linkerd-cluster: standard kind cluster + linkerd + nginx ingress controller
  - create-metallb-ingress-cluster: standard kind cluster + metallb + nginx ingress controller
  - create-metallb-istio-ingress-cluster: standard kind cluster + metallb + istio + nginx ingress controller
  - create-cluster-api-cluster: create a new kind cluster with access to your local docker sock file, with cluster-api, transforms the kind k8s cluster into the management cluster and spins up a k8s workload cluster. (No other content is deployed inside the worker cluster automatically, but you can run manually the desired Makefile targets)
- Now you can interact with your cluster with standard kubectl commands.

# How can I delete the k8s cluster?
Just run the following command in the repo directory (WARNING: This command will perform a docker system clean up command):
```
make delete-kind-cluster
```

In case of cluster-api you can use the following command to clean properly the management-cluster objects and the docker containers:
```
make delete-cluster-api-env
```

# How can I test the ingress?
Run the following command in the root folder of the repo:
```
make test-ingress
```
