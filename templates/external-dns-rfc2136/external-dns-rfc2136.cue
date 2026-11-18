package template

import (
	"encoding/yaml"

	corev1 "k8s.io/api/core/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
	kustomize "sigs.k8s.io/kustomize/api/types"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
)

#Source: "service" | "gateway-httproute" | "gateway-tcproute" | "gateway-tlsroute"

#Input: {
	repository: string & =~"^https?://.+$" | *"https://kubernetes-sigs.github.io/external-dns/"
	version:    string | *"1.23.0"
	sources: [#Source, ...#Source] | *["service", "gateway-httproute", "gateway-tcproute", "gateway-tlsroute"]
	domainFilters!: [...(string & !="")]
	txtPrefix: string & !="" | *"external-dns-"
	policy:    "upsert-only" | "sync" | *"sync"
	namespaceLabels: {[string]: string} | *{}
	rfc2136: {
		hosts!: [...(string & !="")]
		port: int & >=1 & <=65535 | *53
		zones!: [...(string & !="")]
		tsigKeyName!:        string & !=""
		tsigSecretAlgorithm: "hmac-sha256" | "hmac-sha512" | "hmac-sha384" | "hmac-sha224" | "hmac-sha1" | "hmac-md5" | *"hmac-sha256"
		// Management-cluster Secret in the same organization namespace as the
		// HelmRelease. Only its reference, never its contents, enters the Worktree.
		tsigSecretRef: {
			name: string & !="" | *"external-dns-rfc2136"
			key:  string & !="" | *"tsig-secret"
		}
	}
	gatewayAPICRD: {
		// Leave disabled if another workload (such as Traefik) owns the CRDs.
		install: bool | *false
		tag:     string | *"v1.5.0"
		type:    "standard" | "experimental" | *"experimental"
	}
}

#cluster: dockyardsv1.#Cluster
#cluster: metadata: {
	name: string & !=""
	labels: "dockyards.io/organization-name": string & !=""
}

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

// Kubernetes names cannot contain "/", so organization/cluster is unambiguous.
// Use the organization name, which need not match its management namespace.
_txtOwnerId: #cluster.metadata.labels["dockyards.io/organization-name"] + "/" + #cluster.metadata.name

_sourceSet: {
	for source in #workload.spec.input.sources {
		"\(source)": true
	}
}
_gatewayAPIEnabled: _sourceSet["gateway-httproute"] != _|_

_namespace: corev1.#Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name:   #workload.spec.targetNamespace
		labels: #workload.spec.input.namespaceLabels
	}
}

_prerequisites: kustomize.#Kustomization & {
	apiVersion: "kustomize.config.k8s.io/v1beta1"
	kind:       "Kustomization"
	resources: [
		"namespace.yaml",
		if #workload.spec.input.gatewayAPICRD.install {
			"https://github.com/kubernetes-sigs/gateway-api/releases/download/\(#workload.spec.input.gatewayAPICRD.tag)/\(#workload.spec.input.gatewayAPICRD.type)-install.yaml"
		},
	]
	if #workload.spec.input.gatewayAPICRD.install {
		patches: [{
			target: {
				group:   "apiextensions.k8s.io"
				version: "v1"
				kind:    "CustomResourceDefinition"
			}
			patch: """
				- op: add
				  path: /metadata/annotations/kustomize.toolkit.fluxcd.io~1ssa
				  value: IfNotPresent
				- op: add
				  path: /metadata/annotations/kustomize.toolkit.fluxcd.io~1prune
				  value: disabled
				"""
		}]
	}
}

_helmRepository: sourcev1.#HelmRepository & {
	apiVersion: "source.toolkit.fluxcd.io/v1"
	kind:       sourcev1.#HelmRepositoryKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		interval: "5m"
		url:      #workload.spec.input.repository
	}
}

_helmRelease: helmv2.#HelmRelease & {
	apiVersion: "helm.toolkit.fluxcd.io/v2"
	kind:       helmv2.#HelmReleaseKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		chart: spec: {
			chart:   "external-dns"
			version: #workload.spec.input.version
			sourceRef: {
				kind: sourcev1.#HelmRepositoryKind
				name: _helmRepository.metadata.name
			}
		}
		interval: "10m"
		install: remediation: retries: 10
		upgrade: remediation: retries: 10
		kubeConfig: secretRef: name:   #cluster.metadata.name + "-kubeconfig"
		releaseName:      "external-dns"
		storageNamespace: #workload.spec.targetNamespace
		targetNamespace:  #workload.spec.targetNamespace
		valuesFrom: [{
			kind:       "Secret"
			name:       #workload.spec.input.rfc2136.tsigSecretRef.name
			valuesKey:  #workload.spec.input.rfc2136.tsigSecretRef.key
			targetPath: "env[0].value"
			optional:   false
		}]
		values: {
			provider: name: "rfc2136"
			sources:       #workload.spec.input.sources
			policy:        #workload.spec.input.policy
			registry:      "txt"
			txtOwnerId:    _txtOwnerId
			txtPrefix:     #workload.spec.input.txtPrefix
			domainFilters: #workload.spec.input.domainFilters
			extraArgs: {
				"rfc2136-host":                    #workload.spec.input.rfc2136.hosts
				"rfc2136-port":                    "\(#workload.spec.input.rfc2136.port)"
				"rfc2136-zone":                    #workload.spec.input.rfc2136.zones
				"rfc2136-tsig-keyname":            #workload.spec.input.rfc2136.tsigKeyName
				"rfc2136-tsig-secret-alg":         #workload.spec.input.rfc2136.tsigSecretAlgorithm
				"rfc2136-axfr":                    true
				"rfc2136-load-balancing-strategy": "disabled"
			}
			env: [{
				name: "EXTERNAL_DNS_RFC2136_TSIG_SECRET"
				// Filled by valuesFrom at reconciliation time, not in generated Git.
				value: ""
			}]
		}
	}
}

_release: kustomize.#Kustomization & {
	apiVersion: "kustomize.config.k8s.io/v1beta1"
	kind:       "Kustomization"
	resources: ["helmrepository.yaml", "helmrelease.yaml"]
}

worktree: dockyardsv1.#Worktree & {
	apiVersion: "dockyards.io/v1alpha3"
	kind:       dockyardsv1.#WorktreeKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: files: {
		"00-prerequisites/kustomization.yaml": '\(yaml.Marshal(_prerequisites))'
		"00-prerequisites/namespace.yaml":     '\(yaml.Marshal(_namespace))'
		"10-external-dns/kustomization.yaml":  '\(yaml.Marshal(_release))'
		"10-external-dns/helmrepository.yaml": '\(yaml.Marshal(_helmRepository))'
		"10-external-dns/helmrelease.yaml":    '\(yaml.Marshal(_helmRelease))'
	}
}

// Both stages run in the management cluster. Only prerequisites are applied
// directly to the target cluster; the second stage creates a remote HelmRelease.
prerequisitesKustomization: kustomizev1.#Kustomization & {
	apiVersion: "kustomize.toolkit.fluxcd.io/v1"
	kind:       kustomizev1.#KustomizationKind
	metadata: {
		name:      #workload.metadata.name + "-prerequisites"
		namespace: #workload.metadata.namespace
	}
	spec: {
		interval:      "5m"
		retryInterval: "60s"
		timeout:       "5m"
		kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
		path:  "./00-prerequisites"
		prune: true
		sourceRef: {
			kind: sourcev1.#GitRepositoryKind
			name: worktree.metadata.name
		}
		// Unlike wait:true, explicit checks also cover CRDs owned by Traefik.
		healthChecks: [
			{
				apiVersion: "v1"
				kind:       "Namespace"
				name:       #workload.spec.targetNamespace
			},
			for crdName in ["gateways.gateway.networking.k8s.io", "httproutes.gateway.networking.k8s.io"]
			if _gatewayAPIEnabled || #workload.spec.input.gatewayAPICRD.install {
				{
					apiVersion: "apiextensions.k8s.io/v1"
					kind:       "CustomResourceDefinition"
					name:       crdName
				}
			},
		]
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
		dependsOn: [{
			name:      prerequisitesKustomization.metadata.name
			namespace: prerequisitesKustomization.metadata.namespace
		}]
		interval:      "5m"
		retryInterval: "60s"
		timeout:       "5m"
		path:          "./10-external-dns"
		prune:         true
		wait:          true
		sourceRef: {
			kind: sourcev1.#GitRepositoryKind
			name: worktree.metadata.name
		}
	}
}
