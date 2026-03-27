package template

import (
	"encoding/yaml"
	"strings"

	corev1 "k8s.io/api/core/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
)

#Input: {
	chart!:      string
	repository!: string & =~"^(http?s|oci)://.*$"
	version!:    string
	values?: [string]: _
	namespaceLabels: {[key=string]: string} | *{}
}

#cluster: dockyardsv1.#Cluster

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

_namespace: corev1.#Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name:   #workload.spec.targetNamespace
		labels: #workload.spec.input.namespaceLabels
	}
}

worktree: dockyardsv1.#Worktree & {
	apiVersion: "dockyards.io/v1alpha3"
	kind:       dockyardsv1.#WorktreeKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		files: {
			"namespace.yaml": '\(yaml.Marshal(_namespace))'
		}
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
		interval: "5m"
		kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
		prune: true
		sourceRef: {
			kind: sourcev1.#GitRepositoryKind
			name: #workload.metadata.name
		}
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
		interval: "5m"
		url:      #workload.spec.input.repository
		if strings.HasPrefix(#workload.spec.input.repository, "oci://") {
			type: "oci"
		}
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
		chart: spec: {
			chart: #workload.spec.input.chart
			sourceRef: {
				kind: helmRepository.kind
				name: helmRepository.metadata.name
			}
			version: #workload.spec.input.version
		}
		install: {
			remediation: retries: -1
		}
		interval: "5m"
		kubeConfig: {
			secretRef: name: #cluster.metadata.name + "-kubeconfig"
		}
		storageNamespace: #workload.spec.targetNamespace
		targetNamespace:  #workload.spec.targetNamespace
		if #workload.spec.input.values != _|_ {
			values: #workload.spec.input.values
		}
	}
}
