package template

import (
"strings" 
helmv2 "github.com/fluxcd/helm-controller/api/v2"
sourcev1 "github.com/fluxcd/source-controller/api/v1"
dockyardsv1	"bitbucket.org/sudosweden/dockyards-backend/pkg/api/v1alpha3"  
)

#Input: {
	chart:         string | *"grafana"
	repository:    string | *"https://grafana.github.io/helm-charts"
	version:       string | *"9.2.9"
	adminUser:     string | *"admin"
	adminPassword: string | *"admin"
	prometheusURL: string | *"http://prometheus-stack-sofia-pro-prometheus.prometheus-stack.svc.cluster.local"
	domain:        string | *".sofia.dockyards-2h8px.trashcloud.xyz"
}

#ingressHost: #workload.spec.input.domain
#cluster:     dockyardsv1.#Cluster

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

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

helmRelease: helmv2.#HelmRelease & {
	apiVersion: "helm.toolkit.fluxcd.io/v2"
	kind:       "HelmRelease"
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: {
		chart: {
			chart: #workload.spec.input.chart
			sourceRef: {
				kind: helmRepository.kind
				name: helmRepository.metadata.name
			}
			version: #workload.spec.input.version
		}
		install: {
			createNamespace: true
			remediation: {
				retries: -1
			}
		}
		interval: "5m"
		kubeConfig: {
			secretRef: {
				name: #cluster.metadata.name + "-kubeconfig"
			}
		}
		storageNamespace: #workload.spec.targetNamespace
		targetNamespace:  #workload.spec.targetNamespace
		values: {
			grafana: {
				enabled: true
				admin: {
					user:     #workload.spec.input.adminUser
					password: #workload.spec.input.adminPassword
				}
				persistence: {
					enabled: true
					size:    "10Gi"
				}
				sidecar: {
					datasources: {
						enabled: true
					}
					dashboards: {
						enabled: true
						label: "grafana_dashboard"
						folder: "default"
					}
				}
				ingress: {
					enabled: true
					annotations: {
						"kubernetes.io/ingress.class": "nginx"
						"cert-manager.io/cluster-issuer": "letsencrypt"
					}
                    hostName: #ingressHost
					tls: [
						{
							hosts: [#ingressHost]
			                secretName: "grafana-ingress"
						}]
                        nginx: {
                            enabled: false
                        }
				}
			}
		}
	}
}

grafanaDatasource: {
	apiVersion: "v1"
	kind:       "ConfigMap"
	metadata: {
		name:      "grafana-datasources"
		namespace: #workload.spec.targetNamespace
		labels: {
			grafana_datasource: "1"
		}
	}
	data: {
		"datasources.yaml": '''
             		{
			"apiVersion": 1,
			"datasources": [
				{
					"name": "Prometheus",
					"type": "prometheus",
					"access": "proxy",
					"url": "%s",
					"isDefault": true
				}
			]
		}
	    '''
	}
}

grafanaDashboard: {
	apiVersion: "v1"
	kind:       "ConfigMap"
	metadata: {
		name:      "grafana-dashboard-prometheus"
		namespace: #workload.spec.targetNamespace
		labels: {
			grafana_dashboard: "1"
		}
	}
	data: {
		"prometheus.json": '''
		{
			"id": null,
			"title": "Prometheus Example",
			"panels": [
				{
					"type": "graph",
					"title": "Pod CPU Usage",
					"targets": [
						{
							"expr": "sum(rate(container_cpu_usage_seconds_total{image!=''}[5m])) by (pod)",
							"legendFormat": "{{pod}}",
							"refId": "A"
						}
					],
					"datasource": "Prometheus",
					"gridPos": {
						"x": 0,
						"y": 0,
						"w": 12,
						"h": 8
					}
				}
			],
			"schemaVersion": 16,
			"version": 0
		}
		'''
	}
}
