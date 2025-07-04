package template

import (
	"strings"

	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	dockyardsv1 "bitbucket.org/sudosweden/dockyards-backend/pkg/api/v1alpha3"
)

#Path: {
	path:     string | *"/"
	pathType: string | *"ImplementationSpecific"
}

#Host: {
	host!: string
	paths: [...#Path]
}

#TLS: {
  secretName: string | *"podinfo-tls"
  hosts!: [...string]
}

#Input: {
	url:     string | *"oci://ghcr.io/stefanprodan/charts"
	chart:   string | *"podinfo"
	version: string | *"6.9.0"
	values: {
		certificate?: {
		  create: bool | *false
			dnsNames!: [...string]
			issuerRef: {
			  kind: "ClusterIssuer"
				name!: string
			}
		}
		ingress?: {
			enabled: bool | *false
			hosts: [...#Host]
			className: string |*"nginx"
			tls: [...#TLS]
		}
		replicaCount: int | *1
	}
}

#cluster: dockyardsv1.#Cluster

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

helmRepository: sourcev1.#HelmRepository & {
	apiVersion: "source.toolkit.fluxcd.io/v1"
	kind:       sourcev1.#HelmRepositoryKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		url:      #workload.spec.input.url
		interval: "60m"

		if strings.HasPrefix(#workload.spec.input.url, "oci://") {
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
				kind: sourcev1.#HelmRepositoryKind
				name: helmRepository.metadata.name
			}
			version: #workload.spec.input.version
		}
		install: createNamespace: true
		interval: "5m"
		kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
		releaseName:      "podinfo"
		storageNamespace: #workload.spec.targetNamespace
		targetNamespace:  #workload.spec.targetNamespace
		values:           #workload.spec.input.values
	}
}
