package template

import (
	"encoding/yaml"
	"strings"

	corev1 "k8s.io/api/core/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
	kustomize "sigs.k8s.io/kustomize/api/types"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
)

#Input: {
	chart!:        string
	repository!:   string & =~"^(http?s|oci)://.*$"
	repositoryCA?: string
	version!:      string
	values?: [string]: _
	valuesFrom?: [...helmv2.#ValuesReference]
	namespaceLabels: {[key=string]: string} | *{}

	// Extra manifests to apply in the same workload (e.g. SealedSecret,
	// CRs for the chart, StorageClass). Values are raw YAML.
	// Names that would overlap with internal naming are nulled
	additionalResources: {
		[filename=string]:     string
		"namespace.yaml"?:     _|_
		"kustomization.yaml"?: _|_
	} | *{}

	kustomize?: helmv2.#Kustomize
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

_manifestFiles: {
	"namespace.yaml": '\(yaml.Marshal(_namespace))'
	for filename, contents in #workload.spec.input.additionalResources {
		"\(filename)": '\(contents)'
	}
}

_kustomization: kustomize.#Kustomization & {
	resources: [
		"namespace.yaml",
		for filename, _ in #workload.spec.input.additionalResources {
			"\(filename)"
		},
	]
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
			"kustomization.yaml": '\(yaml.Marshal(_kustomization))'
			for filename, contents in _manifestFiles {
				"\(filename)": contents
			}
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
		if #workload.spec.input.repositoryCA != _|_ {
			certSecretRef:
				name: #workload.spec.input.repositoryCA
		}
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
		if #workload.spec.input.valuesFrom != _|_ {
			valuesFrom: #workload.spec.input.valuesFrom
		}
		if #workload.spec.input.kustomize != _|_ {
			postRenderers: [
				{
					kustomize: #workload.spec.input.kustomize
				},
			]
		}
	}
}
