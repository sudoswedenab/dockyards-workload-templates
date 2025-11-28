package template

import (
	"strings"

	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
)

#StorageClass:    "cephfs" | "rbd"
#StorageQuantity: string & =~"^([0-9]+(\\.[0-9]+)?)(Ki|Mi|Gi|Ti|Pi|Ei|k|M|G|T|P|E)?$"

#Input: {
	chart:      string | *"kite"
	repository: string & =~"^(http?s|oci)://.*$" | *"https://zxh326.github.io/kite"
	version:    string | *"v0.6.7"
	domain!:    string
	persistence: {
		enabled:      bool | *false
		storageClass: #StorageClass | *"cephfs"
	}
	ingress: {
		enabled: bool | *true
		tls: {
			enabled:        bool | *false
			useCertManager: bool | *false
		}
	}
}

#cluster: dockyardsv1.#Cluster

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

#ingressHost: #workload.spec.targetNamespace + #workload.spec.input.domain

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
			createNamespace: true
			remediation: retries: -1
		}
		interval: "5m"
		kubeConfig: {
			secretRef: name: #cluster.metadata.name + "-kubeconfig"
		}
		storageNamespace: #workload.spec.targetNamespace
		targetNamespace:  #workload.spec.targetNamespace

		values: {
			if #workload.spec.input.persistence.enabled {
				db: sqlite: persistence: pvc: {
					storageClass: #workload.spec.input.persistence.storageClass
					enabled:      #workload.spec.input.persistence.enabled
				}
			}
			ingress: {
				if #workload.spec.input.ingress.enabled {
					enabled: #workload.spec.input.ingress.enabled
					if #workload.spec.input.ingress.tls.enabled {
						tls: [{
							hosts: [#ingressHost]
							secretName: #workload.metadata.name + "-ingress"
						}]
						if #workload.spec.input.ingress.tls.useCertManager {
							annotations: {
								"cert-manager.io/cluster-issuer": "letsencrypt"
							}
						}
					}
					hosts:
					[
						{
							host: #ingressHost
							paths:
							[
								{
									path:     "/"
									pathType: "Prefix"
								},
							]
						},
					]
				}
			}
		}
	}
}
