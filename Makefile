default: help

CLUSTER_NAME=kind-cluster
LATEST_KUBECTL_VERSION=$$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)
LSB_RELEASE=$$(lsb_release -cs)
CLUSTER_CONFIG_PATH=cluster-definitions/multinode-ingress-cluster.yaml
TEST_INGRESS_MANIFEST_PATH=cluster-components/ingress-test
CILIUM_CLUSTER_CONFIG_PATH=cluster-definitions/cilium-multinode-ingress-cluster.yaml
CLUSTER_API_CLUSTER_CONFIG_PATH=cluster-definitions/cluster-api-docker-multinode-cluster.yaml
CALICO_CLUSTER_CONFIG_PATH=cluster-definitions/calico-multinode-ingress-cluster.yaml
LINKERD_BASE_PATH=cluster-components/linkerd
METALLB_BASE_PATH=cluster-components/metallb
ISTIO_BASE_PATH=cluster-components/istio
ISTIO_VERSION=1.9.0

install-docker:
	@echo "----- INSTALLING DOCKER -----"
	sudo apt-get -y update
	sudo apt-get -y install \
            apt-transport-https \
	    ca-certificates \
            curl \
            gnupg-agent \
	    software-properties-common \
	    docker.io
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

create-cluster-api-kind-cluster:
	@echo "----- INSTALLING KIND CLUSTER -----"
	kind create cluster --name $(CLUSTER_NAME) --config $(CLUSTER_API_CLUSTER_CONFIG_PATH)

create-calico-cluster:
	@echo "----- INSTALLING KIND CLUSTER -----"
	kind create cluster --name $(CLUSTER_NAME) --config $(CALICO_CLUSTER_CONFIG_PATH)

install-cilium-components:
	@echo "----- INSTALLING CILIUM -----"
	kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.9/install/kubernetes/quick-install.yaml
	kubectl wait pod -l "k8s-app=cilium" --for condition=ready -n kube-system --timeout=300s
	kubectl wait pod -l "k8s-app=kube-dns" --for condition=ready -n kube-system --timeout=300s
	-kubectl create ns cilium-test
	kubectl apply -n cilium-test -f https://raw.githubusercontent.com/cilium/cilium/v1.9/examples/kubernetes/connectivity-check/connectivity-check.yaml
	export CILIUM_NAMESPACE=kube-system
	kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.9/install/kubernetes/quick-hubble-install.yaml
	kubectl apply -f ./cluster-components/hubble
	sleep 3
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
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
	kubectl wait pods -l app=metallb -A --for condition=ready --timeout 300s
	kubectl apply -f $(METALLB_BASE_PATH)

delete-kind-cluster:
	@echo "----- DELETING KIND CLUSTER -----"
	kind delete cluster --name $(CLUSTER_NAME)
	docker system prune -fa

install-istio-cli:
	wget https://github.com/istio/istio/releases/download/$(ISTIO_VERSION)/istio-$(ISTIO_VERSION)-linux-amd64.tar.gz
	tar xvzf istio-$(ISTIO_VERSION)-linux-amd64.tar.gz
	mv istio-$(ISTIO_VERSION)/samples $(ISTIO_BASE_PATH)/
	sudo mv istio-$(ISTIO_VERSION)/bin/istioctl /usr/local/bin/
	rm -rf istio-$(ISTIO_VERSION)-linux-amd64.tar.gz istio-$(ISTIO_VERSION)

install-istio-k8s:
	istioctl install --set profile=demo -y
	kubectl label namespace default istio-injection=enabled
	kubectl apply -f $(ISTIO_BASE_PATH)/samples/bookinfo/platform/kube/bookinfo.yaml
	kubectl apply -f $(ISTIO_BASE_PATH)/samples/bookinfo/networking/bookinfo-gateway.yaml
	sleep 3
	kubectl wait pod -l "app=productpage" --for condition=ready -n default --timeout=300s
	istioctl analyze
	-kubectl apply -f $(ISTIO_BASE_PATH)/samples/addons
	sleep 5
	kubectl apply -f $(ISTIO_BASE_PATH)/samples/addons
	kubectl rollout status deployment/kiali -n istio-system
	rm -rf $(ISTIO_BASE_PATH)/samples istio-$(ISTIO_VERSION)-linux-amd64.tar.gz
	kubectl apply -f $(ISTIO_BASE_PATH)

install-clusterctl:
	curl -L https://github.com/kubernetes-sigs/cluster-api/releases/download/v0.3.16/clusterctl-linux-amd64 -o clusterctl
	chmod +x ./clusterctl
	sudo mv ./clusterctl /usr/local/bin/clusterctl
	clusterctl version

initialize-mgmt-cluster:
	clusterctl init --infrastructure docker
	sleep 60

create-cluster-api-workload-cluster:
	clusterctl config cluster capi-quickstart --flavor development \
	--kubernetes-version v1.19.7 \
	--control-plane-machine-count=3 \
	--worker-machine-count=3 \
	| kubectl apply -f -
	sleep 90
	clusterctl describe cluster capi-quickstart
	clusterctl get kubeconfig capi-quickstart > capi-quickstart.kubeconfig

install-cni-cluster-api-cluster:
	kubectl --kubeconfig=./capi-quickstart.kubeconfig \
	apply -f https://docs.projectcalico.org/v3.15/manifests/calico.yaml
	sleep 60
	kubectl --kubeconfig=./capi-quickstart.kubeconfig get nodes

install-calico-cluster:
	kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.4/manifests/calico.yaml
	kubectl wait pods -l k8s-app=calico-node -A --for condition=ready --timeout 300s

delete-cluster-api-cluster:
	kubectl delete cluster capi-quickstart
	sleep 60

install-kafka:
	kubectl create namespace kafka
	kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka
	kubectl wait pod -l "strimzi.io/kind=cluster-operator" --for condition=ready -n kafka --timeout=300s
	kubectl apply -f cluster-components/kafka/kafka-cluster.yml
	kubectl wait kafka/kafka-kind-cluster --for=condition=Ready --timeout=300s -n kafka 
	@echo "Generate messages: kubectl -n kafka run kafka-producer -ti --image=quay.io/strimzi/kafka:0.25.0-kafka-2.8.0 --rm=true --restart=Never -- bin/kafka-console-producer.sh --broker-list kafka-kind-cluster-kafka-bootstrap:9092 --topic my-topic"
	@echo "Consume messages: kubectl -n kafka run kafka-consumer -ti --image=quay.io/strimzi/kafka:0.25.0-kafka-2.8.0 --rm=true --restart=Never -- bin/kafka-console-consumer.sh --bootstrap-server kafka-kind-cluster-kafka-bootstrap:9092 --topic my-topic --from-beginning"
	@echo "Follow the status of the pods with the following command: kubectl get pod -n kafka --watch"
	@echo "Follow operator logs: kubectl logs deployment/strimzi-cluster-operator -n kafka -f"

install-requirements: | install-docker install-kubectl install-kind-bin

create-standard-cluster: | create-kind-cluster install-ingress-controller

create-cilium-cluster: | create-cilium-kind-cluster install-cilium-components install-ingress-controller

create-linkerd-cluster: | create-standard-cluster install-linkerd-cli install-linkerd-components-k8s

create-metallb-ingress-cluster: | create-kind-cluster install-metallb-k8s install-ingress-controller

create-metallb-istio-ingress-cluster: | create-metallb-ingress-cluster install-istio-cli install-istio-k8s

create-cluster-api-cluster: | create-cluster-api-kind-cluster install-clusterctl initialize-mgmt-cluster create-cluster-api-workload-cluster install-cni-cluster-api-cluster

create-calico-ingress-cluster: | create-calico-cluster install-calico-cluster install-ingress-controller

delete-cluster-api-env: | delete-cluster-api-cluster delete-kind-cluster

help:
	@echo "You have to use this makefile with sudo permissions"

