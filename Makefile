default: help

CLUSTER_NAME=kind-cluster
LATEST_KUBECTL_VERSION=$$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
LSB_RELEASE=$$(lsb_release -cs)
CLUSTER_CONFIG_PATH=cluster-definitions/multinode-ingress-cluster.yaml
TEST_INGRESS_MANIFEST_PATH=cluster-components/ingress-test
CILIUM_CLUSTER_CONFIG_PATH=cluster-definitions/cilium-multinode-ingress-cluster.yaml
LINKERD_BASE_PATH=cluster-components/linkerd
METALLB_BASE_PATH=cluster-components/metallb
ISTIO_BASE_PATH=cluster-components/istio

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
	@echo "----- INSTALLING CILIUM -----"
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
	@echo "----- INSTALLING LINKERD CLI -----"
	curl -sL https://run.linkerd.io/install | sh
	sudo mv ~/.linkerd2/bin/linkerd-stable-2.9.3 /usr/local/bin/linkerd
	rm -rf ~/.linkerd2
	linkerd version
	linkerd check --pre

install-linkerd-components-k8s:
	@echo "----- INSTALLING LINKERD LINKERD -----"
	linkerd install > $(LINKERD_BASE_PATH)-kustom/linkerd.yaml
	kubectl apply -k $(LINKERD_BASE_PATH)-kustom
	linkerd check
	rm $(LINKERD_BASE_PATH)-kustom/linkerd.yaml
	curl -sL https://run.linkerd.io/emojivoto.yml | kubectl apply -f -
	kubectl apply -f $(LINKERD_BASE_PATH)
	kubectl get -n emojivoto deploy -o yaml | linkerd inject - | kubectl apply -f -
	linkerd -n emojivoto check --proxy

install-metallb-k8s:
	@echo "----- INSTALLING LINKERD METALLB -----"
	kubectl get configmap kube-proxy -n kube-system -o yaml | sed -e "s/strictARP: false/strictARP: true/" | kubectl apply -f - -n kube-system
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/namespace.yaml
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.5/manifests/metallb.yaml
	kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"
	kubectl apply -f $(METALLB_BASE_PATH)

delete-kind-cluster:
	@echo "----- DELETING KIND CLUSTER -----"
	kind delete cluster --name $(CLUSTER_NAME)

install-istio-cli:
	wget https://github.com/istio/istio/releases/download/1.9.0/istio-1.9.0-linux-amd64.tar.gz
	tar xvzf istio-1.9.0-linux-amd64.tar.gz
	mv  istio-1.9.0 cluster-components/
	sudo mv cluster-components/istio-1.9.0/bin/istioctl /usr/local/bin/

install-istio-k8s:
	istioctl install --set profile=demo -y
	kubectl label namespace default istio-injection=enabled
	kubectl apply -f cluster-components/istio-1.9.0/samples/bookinfo/platform/kube/bookinfo.yaml
	kubectl apply -f cluster-components/istio-1.9.0/samples/bookinfo/networking/bookinfo-gateway.yaml
	kubectl wait pod -l "app=productpage" --for condition=ready -n default --timeout=300s
	istioctl analyze
    kubectl apply -f cluster-components/istio-1.9.0/samples/addons
	wait 5
    kubectl apply -f cluster-components/istio-1.9.0/samples/addons
    kubectl rollout status deployment/kiali -n istio-system
	kubectl apply -f $(ISTIO_BASE_PATH)

install-requirements: | install-docker install-kubectl install-kind-bin

create-standard-cluster: | create-kind-cluster install-ingress-controller

create-cilium-cluster: | create-cilium-kind-cluster install-cilium-components install-ingress-controller

create-linkerd-cluster: | create-standard-cluster install-linkerd-cli install-linkerd-components-k8s

create-metallb-ingress-cluster: | create-kind-cluster install-metallb-k8s install-ingress-controller

help:
	@echo "You have to use this makefile with sudo permissions"

