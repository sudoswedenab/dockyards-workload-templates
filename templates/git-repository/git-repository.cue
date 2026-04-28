package template

import (
	"encoding/yaml"

	"github.com/fluxcd/pkg/apis/meta"

	corev1 "k8s.io/api/core/v1"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
)

#Input: {
	url!:     string & =~"^(http?s|ssh)://.*$"
	ref!:     #Ref
	path:     string | *"."
	interval: string & =~"^([0-9]+(\\.[0-9]+)?(ms|s|m|h))+$" | *"5m"
	timeout?: string & =~"^([0-9]+(\\.[0-9]+)?(ms|s|m|h))+$" | *"60s"

	// This is an optional field to enable the initialization of all
	// submodules within the cloned Git repository, using their default settings.
	// This option defaults to false.
	recurseSubmodules: bool | *false

	// An optional field that allows specifying an OIDC provider used for authentication purposes
	// When provider is not specified, it defaults to generic indicating that mechanisms using
	// secretRef are used for authentication.
	provider: ("generic" | "azure" | "github") | *"generic"

	// This is an optional field to specify list of directories to checkout when cloning the repository.
	// If specified, only the specified directory contents will be present
	// in the artifact produced for this repository.
	sparseCheckout?: [...string]

	// This is the name of the secret used to specify git authentication.
	// It will have to be created manually following the flux format.
	// The secret is stored in the workload cluster namespace in the management cluster.
	// See: https://fluxcd.io/flux/components/source/gitrepositories/#secret-reference
	secretRef?: null | meta.#LocalObjectReference

	// This is the name of the secret used to specify the proxy settings for the git repository.
	// It will have to be created manually following the flux format.
	// The secret is stored in the workload cluster namespace in the management cluster.
	// See: https://fluxcd.io/flux/components/source/gitrepositories/#proxy-secret-reference
	proxySecretRef?: null | meta.#LocalObjectReference

	// This is the name of the secret used to specify the service account for the git repository.
	// It will have to be created manually following the flux format.
	// The secret is stored in the workload cluster namespace in the management cluster.
	// See: https://fluxcd.io/flux/components/source/gitrepositories/#service-account-reference
	serviceAccountName?: null | meta.#LocalObjectReference

	createNamespace: bool | *true
}

#Ref: {branch: string} | {tag: string} | {semver: string} | {name: string} | {commit: string}

#cluster: dockyardsv1.#Cluster

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

if #workload.spec.input.createNamespace == true {
	_namespace: corev1.#Namespace & {
		apiVersion: "v1"
		kind:       "Namespace"
		metadata: name: #workload.spec.targetNamespace
	}

	worktree: dockyardsv1.#Worktree & {
		apiVersion: "dockyards.io/v1alpha3"
		kind:       dockyardsv1.#WorktreeKind
		metadata: {
			name:      #workload.metadata.name + "-namespace"
			namespace: #workload.metadata.namespace
		}
		spec: files: "namespace.yaml": '\(yaml.Marshal(_namespace))'
	}

	kustomizationNamespace: kustomizev1.#Kustomization & {
		apiVersion: "kustomize.toolkit.fluxcd.io/v1"
		kind:       kustomizev1.#KustomizationKind
		metadata: {
			name:      #workload.metadata.name + "-namespace"
			namespace: #workload.metadata.namespace
		}
		spec: {
			interval: "15m"
			kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
			prune: true
			sourceRef: {
				kind: sourcev1.#GitRepositoryKind
				name: worktree.metadata.name
			}
		}
	}
}

gitRepository: sourcev1.#GitRepository & {
	apiVersion: "source.toolkit.fluxcd.io/v1"
	kind:       sourcev1.#GitRepositoryKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		url:      #workload.spec.input.url
		provider: #workload.spec.input.provider
		interval: #workload.spec.input.interval
		if #workload.spec.input.timeout != _|_ {
			timeout: #workload.spec.input.timeout
		}
		recurseSubmodules: #workload.spec.input.recurseSubmodules
		if #workload.spec.input.sparseCheckout != _|_ {
			sparseCheckout: #workload.spec.input.sparseCheckout
		}
		ref: {
			#workload.spec.input.ref
		}

		if #workload.spec.input.secretRef != _|_ {
			secretRef: #workload.spec.input.secretRef
		}
		if #workload.spec.input.proxySecretRef != _|_ {
			proxySecretRef: #workload.spec.input.proxySecretRef
		}
		if #workload.spec.input.serviceAccountName != _|_ {
			serviceAccountName: #workload.spec.input.serviceAccountName
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
		if #workload.spec.input.createNamespace == true {
			dependsOn: [
				{
					name: #workload.metadata.name + "-namespace"
				},
			]
		}
		interval: #workload.spec.input.interval
		if #workload.spec.input.timeout != _|_ {
			timeout: #workload.spec.input.timeout
		}
		kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
		prune:         true
		path:          #workload.spec.input.path
		retryInterval: "1m"
		sourceRef: {
			kind: gitRepository.kind
			name: gitRepository.metadata.name
		}
	}
}
