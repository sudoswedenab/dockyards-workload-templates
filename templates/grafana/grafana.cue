package template

import (
	"strings"
	"encoding/yaml"

	helmv2 "github.com/fluxcd/helm-controller/api/v2"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	corev1 "k8s.io/api/core/v1"
	dockyardsv1 "bitbucket.org/sudosweden/dockyards-backend/pkg/api/v1alpha3"
	apiextensionsv1 "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
)

#Input: {
	chart:         string | *"grafana"
	repository:    string | *"https://grafana.github.io/helm-charts"
	version:       string | *"9.2.9"
	adminUser:     string | *"admin"
	adminPassword: string | *"admin"
	prometheusURL: string | *"http://prometheus-stack-sofia-pro-prometheus.prometheus-stack.svc.cluster.local"
	defaultDomain: string | *"grafana.sofia.dockyards-2h8px.trashcloud.xyz"
	cpuRequest:    string | *"100m"
	cpuLimit:      string | *"200m"
	memoryRequest: string | *"128Mi"
	memoryLimit:   string | *"256Mi"
}

#cluster:  dockyardsv1.#Cluster
#workload: dockyardsv1.#Workload
#workload: spec: input: #Input
#ingressHost: #workload.spec.input.defaultDomain

helmRepository: sourcev1.#HelmRepository & {
	apiVersion: "source.toolkit.fluxcd.io/v1"
	kind:       "HelmRepository"
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
	spec: {
		files: {
			"namespace.yaml": '\(yaml.Marshal(_namespace))'
		}
	}
}

_values: apiextensionsv1.#JSON & {
	nameOverride:     "gfn"
	fullnameOverride: "grafana"

	ingress: {
		enabled:          true
		ingressClassName: "nginx"
		annotations: {
			"kubernetes.io/ingress.class":    "nginx"
			"cert-manager.io/cluster-issuer": "letsencrypt"
		}
		hosts: [#ingressHost]
		path:     "/"
		pathType: "Prefix"
		tls: [{
			hosts: [#ingressHost]
			secretName: "grafana-ingress"
		}]
	}

	persistence: {
		enabled:           false
		storageClassName?: string
		size?:             string
	}

	sidecar: {
		datasources: {
			enabled: true
		}
		dashboards: {
			enabled: true
			label:   "grafana_dashboard"
			folder:  "default"
		}
	}

	resources: {
		limits: {
			cpu:    #workload.spec.input.cpuLimit
			memory: #workload.spec.input.memoryLimit
		}
		requests: {
			cpu:    #workload.spec.input.cpuRequest
			memory: #workload.spec.input.memoryRequest
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

// grafanaDatasource: {
// 	apiVersion: "v1"
// 	kind:       "ConfigMap"
// 	metadata: {
// 		name:      "grafana-datasources"
// 		namespace: #workload.spec.targetNamespace
// 		labels: {
// 			grafana_datasource: "1"
// 		}
// 	}
// 	data: {
// 		"datasources.json": '''
// 			{
// 			  "apiVersion": 1,
// 			  "datasources": [
// 			    {
// 			      "name": "Prometheus",
// 			      "type": "prometheus",
// 			      "access": "proxy",
// 			      "url": "%s",
// 			      "isDefault": true
// 			    }
// 			  ]
// 			}
// 			'''
// 	}
// }
// 
// grafanaDashboard: {
// 	apiVersion: "v1"
// 	kind:       "ConfigMap"
// 	metadata: {
// 		name:      "grafana-dashboard-prometheus"
// 		namespace: #workload.spec.targetNamespace
// 		labels: {
// 			grafana_dashboard: "1"
// 		}
// 	}
// 	data: {
// 		"prometheus.json": '''
// 			{
// 				"id": null,
// 				"title": "Prometheus Example",
// 				"panels": [
// 					{
// 						"type": "graph",
// 						"title": "Pod CPU Usage",
// 						"targets": [
// 							{
// 								"expr": "sum(rate(container_cpu_usage_seconds_total{image!=''}[5m])) by (pod)",
// 								"legendFormat": "{{pod}}",
// 								"refId": "A"
// 							}
// 						],
// 						"datasource": "Prometheus",
// 						"gridPos": {
// 							"x": 0,
// 							"y": 0,
// 							"w": 12,
// 							"h": 8
// 						}
// 					}
// 				],
// 				"schemaVersion": 16,
// 				"version": 0
// 			}
// 			'''
// 	}
// }
