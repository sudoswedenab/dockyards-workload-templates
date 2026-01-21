package template

import (
	"strings"
	"encoding/yaml"

	corev1 "k8s.io/api/core/v1"
	antreav1 "antrea.io/antrea/pkg/apis/crd/v1beta1"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
)

#ExternalIPPool: {
	name: string
	cidr: string
	nodeSelectorLabels: {[key= string]: string}
}

#bgpPolicy: {
	name: string
	bgpPeers: [...#bgpPeer]
	listenPort: int
	localASN:   int
	nodeSelectorLabels: {[key=string]: string}
}

#bgpPeer: {
	name:                       string
	address:                    string
	asn:                        int
	gracefulRestartTimeSeconds: int
	multihopTTL:                int
	port:                       int
}

#Input: {
	chart:      string | *"antrea"
	repository: string & =~"^(http?s|oci)://.*$" | *"https://charts.antrea.io"
	version:    string | *"2.5.0"
	agentFeatureGates: {[key=string]: bool} | *{}
	controllerFeatureGates: {[key=string]: bool} | *{}
	externalIPPools: [...#ExternalIPPool] | *[]
	BGPPolicies: [...#bgpPolicy] | *[]
}

#cluster: dockyardsv1.#Cluster

#workload: dockyardsv1.#Workload

#workload: spec: input: #Input

_config_agent: {
	featureGates: #workload.spec.input.agentFeatureGates
}

_config_controller: {
	featureGates: #workload.spec.input.controllerFeatureGates
}

_namespace: corev1.#Namespace & {
	apiVersion: "v1"
	kind:       "Namespace"
	metadata: {
		name: #workload.spec.targetNamespace
		labels: {
			"pod-security.kubernetes.io/audit":           "privileged"
			"pod-security.kubernetes.io/audit-version":   "latest"
			"pod-security.kubernetes.io/enforce":         "privileged"
			"pod-security.kubernetes.io/enforce-version": "latest"
			"pod-security.kubernetes.io/warn":            "privileged"
			"pod-security.kubernetes.io/warn-version":    "latest"
		}
	}
}

_configMap: corev1.#ConfigMap & {
	apiVersion: "v1"
	kind:       "ConfigMap"
	metadata: {
		name:      "antrea-config"
		namespace: #workload.spec.targetNamespace
	}
	data: {
		if #workload.spec.input.agentFeatureGates != _|_ {
			"antrea-agent.conf": "\(yaml.Marshal(_config_agent))"
		}
		if #workload.spec.input.controllerFeatureGates != _|_ {
			"antrea-controller.conf": "\(yaml.Marshal(_config_controller))"
		}
	}
}

_externalIPPoolList: [
	for externalIPPool in #workload.spec.input.externalIPPools {
		antreav1.#ExternalIPPool
		apiVersion: "crd.antrea.io/v1beta1"
		kind:       "ExternalIPPool"
		metadata: name: externalIPPool.name
		spec: {
			ipRanges: [
				{
					cidr: externalIPPool.cidr
				},
			]
			nodeSelector: matchLabels: {
				for k, v in externalIPPool.nodeSelectorLabels {
					(k): v
				}
			}
		}
	},
]

_bgpPolicyList: [
	for bgpPolicy in #workload.spec.input.BGPPolicies {
		// using a generic list as the published antrea module
		// does not include bgpPolicy at the time of writing
		apiVersion: "crd.antrea.io/v1beta1"
		kind:       "BGPPolicy"
		metadata: name: bgpPolicy.name
		spec: {
			advertisements: {
				egress: {}
				service: ipTypes: ["LoadBalancerIP"]
			}
			bgpPeers:   bgpPolicy.bgpPeers
			listenPort: bgpPolicy.listenPort
			localASN:   bgpPolicy.localASN
			nodeSelector: matchLabels: {
				for k, v in bgpPolicy.nodeSelectorLabels {
					(k): v
				}
			}
		}
	},
]

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
			// "configmap.yaml": '\(yaml.Marshal(_configMap))'
			if _externalIPPoolList != [] {
				"externalippools.yaml": '\(strings.Join([
							for externalIPPool in _externalIPPoolList {
						"\(yaml.Marshal(externalIPPool))"
					},
				], "\n---\n"))'
			}
			if _bgpPolicyList != [] {
				"bgppolicies.yaml": '\(strings.Join([
							for bgpPolicy in _bgpPolicyList {
						"\(yaml.Marshal(bgpPolicy))"
					},
				], "\n---\n"))'
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
		if strings.HasPrefix(#workload.spec.input.repository, "oci://") {
			type: "oci"
		}
	}
}

_values: apiextensionsv1.#JSON & {
	agent: {
		dontLoadKernelModules: true
		installCNI: securityContext: capabilities: []
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
			chart:   #workload.spec.input.chart
			version: #workload.spec.input.version
			sourceRef: {
				kind: helmRepository.kind
				name: helmRepository.metadata.name
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
