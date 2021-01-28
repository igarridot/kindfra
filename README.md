# Kindfra project
An easy way to spin up a development kubernetes cluster with Kind.

# What can I do with this?
You will be able to create a multiworker kubernetes cluster with a few commands.
The cluster is configured to do a port-forward from your local machine 80/TCP port to the Kind cluster 80/TCP port.

# Pre-requisites
- Ubuntu OS Linux family
- Make installed

# Installation steps
- Download this repo
- Move to the root repo directory
- Run the following commands (this process will install docker, kubectl and kind in your pc, you can execute targets individually):
```
make install-requirements
make create-kind-cluster
```
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
