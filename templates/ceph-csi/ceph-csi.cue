package template

import (
	"encoding/yaml"
	"encoding/base64"
	"encoding/json"

	dockyardsv1 "bitbucket.org/sudosweden/dockyards-backend/pkg/api/v1alpha3"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
	storagev1 "k8s.io/api/storage/v1"
	corev1 "k8s.io/api/core/v1"
	kustomize "sigs.k8s.io/kustomize/api/types"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
)

#Input: {
	monitors: [...string]
	cephfs: {
		clusterID: string
		fsName:    string
		pool:      string
		provisioner: {
			id:  string
			key: string
		}
		node: {
			id:  string
			key: string
		}
		subvolumeGroup: string
	}
	rbd: {
		clusterID: string
		fstype:    "ext4" | "xfs" | *"ext4"
		pool:      string
		node: {
			id:  string
			key: string
		}
		provisioner: {
			id:  string
			key: string
		}
		radosNamespace: string
	}
}

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

#cluster: dockyardsv1.#Cluster

_config: [
	{
		clusterID: #workload.spec.input.cephfs.clusterID
		monitors:  #workload.spec.input.monitors
		cephFS: subvolumeGroup: #workload.spec.input.cephfs.subvolumeGroup
	},
	{
		clusterID: #workload.spec.input.rbd.clusterID
		monitors:  #workload.spec.input.monitors
		rbd: radosNamespace: #workload.spec.input.rbd.radosNamespace
	},
]

_configMap: [...corev1.#ConfigMap] & [
	{
		apiVersion: "v1"
		data: "config.json": "\(json.Marshal(_config))"
		kind: "ConfigMap"
		metadata: name: "ceph-csi-config"
	},
	{
		apiVersion: "v1"
		kind:       "ConfigMap"
		metadata: name: "ceph-csi-encryption-kms-config"
	},
]

_secret: [...corev1.#Secret] & [
	{
		apiVersion: "v1"
		data: {
			userID:  '\(base64.Encode(null, #workload.spec.input.cephfs.node.id))'
			userKey: '\(base64.Encode(null, #workload.spec.input.cephfs.node.key))'
		}
		kind: "Secret"
		metadata: name: "csi-cephfs-node"
	},
	{
		apiVersion: "v1"
		data: {
			userID:  '\(base64.Encode(null, #workload.spec.input.cephfs.provisioner.id))'
			userKey: '\(base64.Encode(null, #workload.spec.input.cephfs.provisioner.key))'
		}
		kind: "Secret"
		metadata: name: "csi-cephfs-provisioner"
	},
	{
		apiVersion: "v1"
		data: {
			userID:  '\(base64.Encode(null, #workload.spec.input.rbd.node.id))'
			userKey: '\(base64.Encode(null, #workload.spec.input.rbd.node.key))'
		}
		kind: "Secret"
		metadata: name: "csi-rbd-node"
	},
	{
		apiVersion: "v1"
		data: {
			userID:  '\(base64.Encode(null, #workload.spec.input.rbd.provisioner.id))'
			userKey: '\(base64.Encode(null, #workload.spec.input.rbd.provisioner.key))'
		}
		kind: "Secret"
		metadata: name: "csi-rbd-provisioner"
	},
]

_storageClass: [...storagev1.#StorageClass] & [
	{
		apiVersion: "storage.k8s.io/v1"
		kind:       "StorageClass"
		metadata: name: "cephfs"
		provisioner: "cephfs.csi.ceph.com"
		parameters: {
			clusterID:                                         #workload.spec.input.cephfs.clusterID
			fsName:                                            #workload.spec.input.cephfs.fsName
			"csi.storage.k8s.io/node-stage-secret-name":       "csi-cephfs-node"
			"csi.storage.k8s.io/node-stage-secret-namespace":  #workload.spec.targetNamespace
			"csi.storage.k8s.io/provisioner-secret-name":      "csi-cephfs-provisioner"
			"csi.storage.k8s.io/provisioner-secret-namespace": #workload.spec.targetNamespace
			pool:                                              #workload.spec.input.cephfs.pool
		}
		reclaimPolicy: corev1.#PersistentVolumeReclaimDelete
	},
	{
		apiVersion: "storage.k8s.io/v1"
		kind:       "StorageClass"
		metadata: name: "rbd"
		provisioner: "rbd.csi.ceph.com"
		parameters: {
			clusterID:                                         #workload.spec.input.rbd.clusterID
			"csi.storage.k8s.io/node-stage-secret-name":       "csi-rbd-node"
			"csi.storage.k8s.io/node-stage-secret-namespace":  #workload.spec.targetNamespace
			"csi.storage.k8s.io/provisioner-secret-name":      "csi-rbd-provisioner"
			"csi.storage.k8s.io/provisioner-secret-namespace": #workload.spec.targetNamespace
			"csi.storage.k8s.io/fstype":                       #workload.spec.input.rbd.fstype
			pool:                                              #workload.spec.input.rbd.pool
		}
		reclaimPolicy: corev1.#PersistentVolumeReclaimDelete
	},
]

_kustomization: kustomize.#Kustomization & {
	patches: [
		{
			patch: """
				- op: replace
				  path: /spec/replicas
				  value: 2
				"""
			target: {
				kind: "Deployment"
			}
		},
	]
	resources: [
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/cephfs/kubernetes/csidriver.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/cephfs/kubernetes/csi-provisioner-rbac.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/cephfs/kubernetes/csi-nodeplugin-rbac.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/cephfs/kubernetes/csi-cephfsplugin-provisioner.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/cephfs/kubernetes/csi-cephfsplugin.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/rbd/kubernetes/csidriver.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/rbd/kubernetes/csi-provisioner-rbac.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/rbd/kubernetes/csi-nodeplugin-rbac.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/rbd/kubernetes/csi-rbdplugin-provisioner.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/rbd/kubernetes/csi-rbdplugin.yaml",
		"https://raw.githubusercontent.com/ceph/ceph-csi/refs/tags/v3.14.0/deploy/ceph-conf.yaml",
		"configmap.yaml",
		"secret.yaml",
		"storageclass.yaml",
	]
}

worktree: dockyardsv1.#Worktree & {
	apiVersion: "dockyards.io/v1alpha3"
	kind:       dockyardsv1.#WorktreeKind
	metadata: {
		name:      #workload.metadata.name
		namespace: #workload.metadata.namespace
	}
	spec: files: {
		"configmap.yaml":     '\(yaml.MarshalStream(_configMap))'
		"kustomization.yaml": '\(yaml.Marshal(_kustomization))'
		"secret.yaml":        '\(yaml.MarshalStream(_secret))'
		"storageclass.yaml":  '\(yaml.MarshalStream(_storageClass))'
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
		interval: "15m"
		kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
		prune:         true
		retryInterval: "60s"
		sourceRef: {
			kind: sourcev1.#GitRepositoryKind
			name: worktree.metadata.name
		}
		targetNamespace: #workload.spec.targetNamespace
		wait:            true
	}
}
