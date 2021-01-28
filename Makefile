default: help

CLUSTER_NAME=kind-cluster
LATEST_KUBECTL_VERSION=$$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
LSB_RELEASE=$$(lsb_release -cs)
CLUSTER_CONFIG_PATH=cluster-definitions/multinode-ingress-cluster.yaml
TEST_INGRESS_MANIFEST_PATH=cluster-components/ingress-test.yaml

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
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/master/deploy/static/provider/kind/deploy.yaml
	kubectl wait --namespace ingress-nginx \
	  --for=condition=ready pod \
	  --selector=app.kubernetes.io/component=controller \
	  --timeout=90s

test-ingress:
	@echo "----- CREATING TEST INGRESS STACK -----"
	@kubectl apply -f $(TEST_INGRESS_MANIFEST_PATH)
	@sleep 10
	@echo ----- TEST INGRESS -----
	curl -IL localhost/foo
	curl -IL localhost/bar
	@echo ----- DELETE TEST INGRESS -----
	@kubectl delete -f $(TEST_INGRESS_MANIFEST_PATH)

delete-kind-cluster:
	kind delete cluster --name $(CLUSTER_NAME)

install-requirements: | install-docker install-kubectl install-kind-bin

help:
	@echo "You have to use this makefile with sudo permissions"
