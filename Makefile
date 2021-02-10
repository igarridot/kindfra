default: help

CLUSTER_NAME=kind-cluster
LATEST_KUBECTL_VERSION=$$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
LSB_RELEASE=$$(lsb_release -cs)
CLUSTER_CONFIG_PATH=cluster-definitions/multinode-ingress-cluster.yaml
TEST_INGRESS_MANIFEST_PATH=cluster-components/ingress-test
CILIUM_CLUSTER_CONFIG_PATH=cluster-definitions/cilium-multinode-ingress-cluster.yaml

install-docker:
	@echo "----- INSTALLING DOCKER -----"
	sudo apt-get -y update
	sudo apt-get -y install \
            apt-transport-https \
	    ca-certificates \
            curl \
            gnupg-agent \
	    software-properties-common
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(LSB_RELEASE) stable"
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo apt-get -y update
	sudo apt-get -y install docker-ce docker-ce-cli containerd.io
	-sudo groupadd docker
	sudo usermod -aG docker ${USER}

install-kubectl:
	@echo "----- INSTALLING KUBECTL -----"
	curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(LATEST_KUBECTL_VERSION)/bin/linux/amd64/kubectl"
	chmod +x ./kubectl
	sudo mv ./kubectl /usr/local/bin/kubectl
	kubectl version --client

install-kind-bin:
	@echo "----- INSTALLING KIND -----"
	curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.9.0/kind-linux-amd64
	chmod +x ./kind
	sudo mv ./kind /usr/local/bin/

create-kind-cluster:
	@echo "----- INSTALLING KIND CLUSTER -----"
	kind create cluster --name $(CLUSTER_NAME) --config $(CLUSTER_CONFIG_PATH)

install-ingress-controller:
	@echo "----- INSTALLING INGRESS CONTROLLER -----"
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx \
	  --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=controller \
	  --timeout=300s

create-cilium-kind-cluster:
	@echo "----- INSTALLING KIND CLUSTER -----"
	kind create cluster --name $(CLUSTER_NAME) --config $(CILIUM_CLUSTER_CONFIG_PATH)

install-cilium-components:
	kubectl create -f https://raw.githubusercontent.com/cilium/cilium/v1.9/install/kubernetes/quick-install.yaml
	kubectl wait pod -l "k8s-app=cilium" --for condition=ready -n kube-system --timeout=300s
	kubectl wait pod -l "k8s-app=kube-dns" --for condition=ready -n kube-system --timeout=300s
	kubectl create ns cilium-test
	kubectl apply -n cilium-test -f https://raw.githubusercontent.com/cilium/cilium/v1.9/examples/kubernetes/connectivity-check/connectivity-check.yaml
	export CILIUM_NAMESPACE=kube-system
	kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.9/install/kubernetes/quick-hubble-install.yaml
	kubectl apply -f ./cluster-components/hubble
	kubectl wait pod -l "k8s-app=hubble-ui" --for condition=ready -n kube-system --timeout=300s

test-ingress:
	@echo "----- CREATING TEST INGRESS STACK -----"
	@kubectl apply -f $(TEST_INGRESS_MANIFEST_PATH)
	@sleep 10
	@echo ----- TEST INGRESS -----
	curl -IL localhost/foo
	curl -IL localhost/bar
	@echo ----- DELETE TEST INGRESS -----
	@kubectl delete -f $(TEST_INGRESS_MANIFEST_PATH)

install-linkerd-cli:
	curl -sL https://run.linkerd.io/install | sh
	sudo mv ~/.linkerd2/bin/linkerd-stable-2.9.3 /usr/local/bin/linkerd
	rm -rf ~/.linkerd2
	linkerd version
	linkerd check --pre

install-linkerd-components-k8s:
	linkerd install > cluster-components/linkerd/linkerd.yaml
	kubectl kustomize build cluster-components/linkerd/ | kubectl apply -f -
	linkerd check

delete-kind-cluster:
	kind delete cluster --name $(CLUSTER_NAME)

install-requirements: | install-docker install-kubectl install-kind-bin

create-standard-cluster: | create-kind-cluster install-ingress-controller

create-cilium-cluster: | create-cilium-kind-cluster install-cilium-components install-ingress-controller

help:
	@echo "You have to use this makefile with sudo permissions"

