# ---------------------------------------------------------------------------
# three-tier-platform - local, cloud-free Kubernetes platform on Kind
#   make up      -> full environment from zero
#   make down    -> delete everything
# ---------------------------------------------------------------------------
CLUSTER_NAME   ?= three-tier
NAMESPACE      ?= three-tier
BACKEND_IMAGE  ?= three-tier-backend:local
FRONTEND_IMAGE ?= three-tier-frontend:local
INGRESS_NGINX_VERSION ?= controller-v1.12.1
KPS_CHART_VERSION     ?=

export CLUSTER_NAME NAMESPACE

.DEFAULT_GOAL := help
.PHONY: help up down preflight cluster ingress images monitoring deploy secrets smoke status logs lint

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: preflight cluster ingress images monitoring deploy smoke ## Build the whole environment (idempotent)
	@echo ""
	@echo "🚀 App:     http://localhost"
	@echo "📊 Grafana: http://grafana.localtest.me  (admin / prom-operator)"

preflight: ## Check required tools
	@./scripts/preflight.sh

cluster: ## Create the Kind cluster (skips if it exists)
	@kind get clusters | grep -qx "$(CLUSTER_NAME)" \
	    && echo "✓ cluster $(CLUSTER_NAME) already exists" \
	    || kind create cluster --config kind-config.yaml
	@kubectl cluster-info --context kind-$(CLUSTER_NAME) >/dev/null

ingress: ## Install NGINX Ingress Controller (pinned version)
	kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/$(INGRESS_NGINX_VERSION)/deploy/static/provider/kind/deploy.yaml
	kubectl -n ingress-nginx wait --for=condition=ready pod \
	    --selector=app.kubernetes.io/component=controller --timeout=180s

images: ## Build images locally and side-load them into Kind (no registry)
	docker build -t $(BACKEND_IMAGE) app/backend
	docker build -t $(FRONTEND_IMAGE) app/frontend
	kind load docker-image $(BACKEND_IMAGE) $(FRONTEND_IMAGE) --name $(CLUSTER_NAME)

monitoring: ## Install kube-prometheus-stack (Prometheus + Grafana, dashboard 1860)
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
	helm repo update prometheus-community >/dev/null
	helm upgrade --install kps prometheus-community/kube-prometheus-stack \
	    --namespace monitoring --create-namespace \
	    $(if $(KPS_CHART_VERSION),--version $(KPS_CHART_VERSION)) \
	    -f k8s/monitoring/values.yaml --wait --timeout 10m

secrets: ## Create the MongoDB Secret (random password, not stored in git)
	kubectl apply -f k8s/00-namespace.yaml
	./scripts/create-secrets.sh

deploy: secrets ## Apply all application manifests
	@for i in 1 2 3; do \
		kubectl apply -k k8s/ && break || sleep 3; \
	done
	kubectl -n $(NAMESPACE) rollout status statefulset/mongodb --timeout=300s
	kubectl -n $(NAMESPACE) wait --for=condition=ready pod -l app.kubernetes.io/name=mongodb --timeout=300s
	kubectl -n $(NAMESPACE) rollout status deployment/backend --timeout=300s
	kubectl -n $(NAMESPACE) rollout status deployment/frontend --timeout=300s

smoke: ## End-to-end smoke test through the ingress
	@./scripts/smoke-test.sh

status: ## Pods, services, ingress, PVCs
	kubectl -n $(NAMESPACE) get pods,svc,ingress,pvc -o wide
	kubectl -n monitoring get pods

logs: ## Tail backend logs
	kubectl -n $(NAMESPACE) logs -l app.kubernetes.io/name=backend -f --tail=50

lint: ## Validate manifests offline (needs kubeconform)
	kubectl kustomize k8s/ | kubeconform -strict -ignore-missing-schemas -summary

down: ## Delete the cluster and everything in it
	@./scripts/teardown.sh
