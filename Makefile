default: help

CLUSTER_NAME=kind-cluster
LATEST_KUBECTL_VERSION=$$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
LSB_RELEASE=$$(lsb_release -cs)
CLUSTER_CONFIG_PATH=cluster-definitions/multinode-ingress-cluster.yaml
TEST_INGRESS_MANIFEST_PATH=cluster-components/ingress-test
CILIUM_CLUSTER_CONFIG_PATH=cluster-definitions/cilium-multinode-ingress-cluster.yaml
LINKERD_BASE_PATH=cluster-components/linkerd
METALLB_BASE_PATH=cluster-components/metallb

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
	linkerd install > $(LINKERD_BASE_PATH)-kustom/linkerd.yaml
	kubectl apply -k $(LINKERD_BASE_PATH)-kustom
	linkerd check
	rm $(LINKERD_BASE_PATH)-kustom/linkerd.yaml
	curl -sL https://run.linkerd.io/emojivoto.yml | kubectl apply -f -
	kubectl apply -f $(LINKERD_BASE_PATH)
	kubectl get -n emojivoto deploy -o yaml | linkerd inject - | kubectl apply -f -
	linkerd -n emojivoto check --proxy

create-metallb-cluster:
	kind create cluster --name $(CLUSTER_NAME) --config cluster-definitions/metallb-multinode-cluster.yml
	kubectl get configmap kube-proxy -n kube-system -o yaml | sed -e "s/strictARP: false/strictARP: true/" | kubectl diff -f - -n kube-system
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/namespace.yaml
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/metallb.yaml
	kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
	kubectl apply -f $(METALLB_BASE_PATH)
	kubectl run echo --image=inanimate/echo-server --port=8080
	kubectl expose pod echo --type=LoadBalancer
	sleep 10
	LB_IP=$$(kubectl get svc/echo -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
	curl -IL http://$(LB_IP):8080/
	kubectl delete service echo
	kubectl delete pod echo

delete-kind-cluster:
	kind delete cluster --name $(CLUSTER_NAME)

install-requirements: | install-docker install-kubectl install-kind-bin

create-standard-cluster: | create-kind-cluster install-ingress-controller

create-cilium-cluster: | create-cilium-kind-cluster install-cilium-components install-ingress-controller

create-linkerd-cluster: | create-standard-cluster install-linkerd-cli install-linkerd-components-k8s

help:
	@echo "You have to use this makefile with sudo permissions"

