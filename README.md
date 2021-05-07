# Kindfra project
An easy way to spin up a development kubernetes cluster with Kind.

# What can I do with this?
You will be able to create a multiworker kubernetes cluster with a few commands.
The cluster is configured to do a port-forward from your local machine 80/TCP port to the Kind cluster 80/TCP port or use a LoadBalancer IP behavior in case of Metallb usage.

# Pre-requisites
- Ubuntu OS Linux family
- Make installed

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
- Now you can interact with your cluster with standard kubectl commands.

# How can I delete the k8s cluster?
Just run the following command in the repo directory:
```
make delete-kind-cluster
```

# How can I test the ingress?
Run the following command in the root folder of the repo:
```
make test-ingress
```
