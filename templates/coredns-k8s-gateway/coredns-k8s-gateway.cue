package template

import (
	"encoding/yaml"

	corev1 "k8s.io/api/core/v1"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
	networkingv1 "k8s.io/api/networking/v1"
)

#Input: {
	repository:   string | *"https://k8s-gateway.github.io/k8s_gateway/"
	chart:        string | *"k8s-gateway"
	version:      string | *"3.2.8"
	replicaCount: int | *1
	cacheTTL:     int | *30
	recordTTL:    int | *60
	enableDebug:  bool | *false
	zone:         string
	resources: [...string] | *["Ingress"]
}

#cluster: dockyardsv1.#Cluster

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

_ingress: networkingv1.#Ingress & {
	apiVersion: "networking.k8s.io/v1"
	kind:       "Ingress"
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.spec.targetNamespace
	}
	spec: {
		rules: [{
			host: "ns1." + #workload.spec.input.zone
			http: {
				paths: [{
					path:     "/"
					pathType: "Prefix"
					backend: {
						service: {
							name: #workload.spec.targetNamespace
							port: {number: 53}
						}
					}
				}]
			}
		}]
	}
}

_namespace: corev1.#Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: name: #workload.spec.targetNamespace
}

worktree: dockyardsv1.#Worktree & {
	apiVersion: "dockyards.io/v1alpha3"
	kind:       dockyardsv1.#WorktreeKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: files: {
		"namespace.yaml": '\(yaml.Marshal(_namespace))'
		"ingress.yaml":   '\(yaml.Marshal(_ingress))'
	}
}

kustomization: kustomizev1.#Kustomization & {
	apiVersion: "kustomize.toolkit.fluxcd.io/v1"
	kind:       kustomizev1.#KustomizationKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		interval: "15m"
		kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
		prune:         true
		retryInterval: "60s"
		sourceRef: {
			kind: sourcev1.#GitRepositoryKind
			name: worktree.metadata.name
		}
		targetNamespace: #workload.spec.targetNamespace
		wait:            true
	}
}

helmRepository: sourcev1.#HelmRepository & {
	apiVersion: "source.toolkit.fluxcd.io/v1"
	kind:       sourcev1.#HelmRepositoryKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		url:      #workload.spec.input.repository
		interval: "5m"
	}
}

helmRelease: helmv2.#HelmRelease & {
	apiVersion: "helm.toolkit.fluxcd.io/v2"
	kind:       helmv2.#HelmReleaseKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		chart: {
			spec: {
				chart:   #workload.spec.input.chart
				version: #workload.spec.input.version
				sourceRef: {
					kind: helmRepository.kind
					name: helmRepository.metadata.name
				}
			}
		}
		install: remediation: retries: -1
		interval: "5m"
		kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
		storageNamespace: #workload.spec.targetNamespace
		targetNamespace:  #workload.spec.targetNamespace
		values:           _values
	}
}

_values: apiextensionsv1.#JSON & {
	fullnameOverride: #workload.spec.targetNamespace
	debug: {
		enabled: #workload.spec.input.enableDebug
	}
	domain:           #workload.spec.input.zone
	replicaCount:     #workload.spec.input.replicaCount
	ttl:              #workload.spec.input.recordTTL
	watchedResources: #workload.spec.input.resources
	extraZonePlugins: [
		{name: "errors"},
		{name: "ready"},
		{name: "log"},
		{name: "loop"},
		{name: "reload"},
		{
			name:       "prometheus"
			parameters: "0.0.0.0:9153"
		},
		{
			configBlock: "lameduck 5s"
			name:        "health"
		},
		{
			name:       "cache"
			parameters: #workload.spec.input.cacheTTL
		},
	]
	service: {
		name: #workload.spec.targetNamespace
		port: 53
		type: "ClusterIP"
	}
}
