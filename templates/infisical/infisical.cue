package template

import (
	"encoding/yaml"

	corev1 "k8s.io/api/core/v1"
	dockyardsv1 "bitbucket.org/sudosweden/dockyards-backend/pkg/api/v1alpha3"
	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
)

#Input: {
	repository:    string | *"https://dl.cloudsmith.io/public/infisical/helm-charts/helm/charts/"
	chart:         string | *"infisical-standalone"
	version:       string | *"1.5.0"
	domain:        string | *".strimzi-kafka.dockyards-mvqp2.trashcloud.xyz"
	storageClass:  string | *"cephfs"
	storageSize:   string | *"2Gi"
	encryptionKey: string & len(_) == 32 | *"YLWpsmyvSjWys7tVjITvUex4lcOtUXrW"
	authSecret:    string & len(_) == 32 | *"ZIeiNKkzh4gKs4uArrAKmW9dNTdM9lMz"
}

#ingressHost: #workload.spec.targetNamespace + #workload.spec.input.domain
#cluster:     dockyardsv1.#Cluster

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

_namespace: corev1.#Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name: #workload.spec.targetNamespace
		labels: {
			"pod-security.kubernetes.io/enforce":         "privileged"
			"pod-security.kubernetes.io/enforce-version": "latest"
		}
	}
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
		"secrets.yaml":   '\(yaml.Marshal(_infisicalSecret))'
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
		url:      #workload.spec.input.repository
		interval: "5m"
	}
}

_values: apiextensionsv1.#JSON & {
	infisical: {
		fullnameOverride: "infisical"
		replicaCount:     1
	}
	backend: {
		database: type: "postgresql"
		replicaCount: 2
	}
	ingress: {
		enabled: true
		annotations: {
			"cert-manager.io/cluster-issuer": "letsencrypt"
		}
		hostName: #ingressHost
		tls: [{
			hosts: [#ingressHost]
			secretName: "infisical-ingress"
		}]
		nginx: enabled: false
	}
	postgresql: {
		enabled: true
		primary: persistence: {
			enabled:      true
			size:         #workload.spec.input.storageSize
			storageClass: #workload.spec.input.storageClass
		}
	}
	redis: master: persistence: {
		enabled:      true
		size:         #workload.spec.input.storageSize
		storageClass: #workload.spec.input.storageClass
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
		releaseName: "infisical"
		chart: spec: {
			chart:   #workload.spec.input.chart
			version: #workload.spec.input.version
			sourceRef: {
				kind: helmRepository.kind
				name: helmRepository.metadata.name
			}
		}
		interval: "5m"
		install: remediation: retries: -1
		kubeConfig: secretRef: name:   #cluster.metadata.name + "-kubeconfig"
		targetNamespace:  #workload.spec.targetNamespace
		storageNamespace: #workload.spec.targetNamespace
		values:           _values
	}
}

_infisicalSecret: {
	apiVersion: "v1"
	kind:       "Secret"
	metadata: {
		name:      "infisical-secrets"
		namespace: #workload.spec.targetNamespace
		labels: {
			"app.kubernetes.io/name":      "infisical"
			"app.kubernetes.io/component": "secrets"
			"dockyards.io/managed-by":     "flux"
		}
	}
	type:      "Opaque"
	immutable: true

	_authSecret:    #workload.spec.input.authSecret
	_encryptionKey: #workload.spec.input.encryptionKey

	stringData: {
		AUTH_SECRET:    _authSecret
		ENCRYPTION_KEY: _encryptionKey
		SITE_URL:       "https://\(#ingressHost)"
	}
}
