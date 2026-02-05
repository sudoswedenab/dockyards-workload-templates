package template

import (
	"encoding/yaml"
	"strings"

	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
	kustomizev1 "github.com/fluxcd/kustomize-controller/api/v1"
	sourcev1 "github.com/fluxcd/source-controller/api/v1"
	rbacv1 "k8s.io/api/rbac/v1"
)

#RoleBinding: {
	bindingName: string
	roleRef:     rbacv1.#RoleRef
	subjects: [...rbacv1.#Subject]
	namespace: string
}

#Input: {
	clusterRoleBindings: [...#RoleBinding] | *[]
	roleBindings: [...#RoleBinding] | *[]
}

#cluster:  dockyardsv1.#Cluster
#workload: dockyardsv1.#Workload

#workload: spec: input: #Input

_clusterRoleBindingList: [
	for clusterRoleBinding in #workload.spec.input.clusterRoleBindings {
		rbacv1.#ClusterRoleBinding
		apiVersion: "rbac.authorization.k8s.io/v1"
		kind:       "ClusterRoleBinding"
		metadata: {
			name: clusterRoleBinding.bindingName
		}
		roleRef:  clusterRoleBinding.roleRef
		subjects: clusterRoleBinding.subjects
	},
]

_roleBindingList: [
	for roleBinding in #workload.spec.input.roleBindings {
		apiVersion: "rbac.authorization.k8s.io/v1"
		kind:       "RoleBinding"
		metadata: {
			name:      roleBinding.bindingName
			namespace: roleBinding.namespace
		}
		roleRef:  roleBinding.roleRef
		subjects: roleBinding.subjects
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
			if _clusterRoleBindingList != [] {
				"clusterrolebindings.yaml": '\(strings.Join([
								for clusterRoleBinding in _clusterRoleBindingList {
						"\(yaml.Marshal(clusterRoleBinding))"
					},
				], "\n---\n"))'
			}
			if _roleBindingList != [] {
				"rolebindings.yaml": '\(strings.Join([
							for roleBinding in _roleBindingList {
						"\(yaml.Marshal(roleBinding))"
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
		interval:      "1m"
		wait:          true
		retryInterval: "15s"
		kubeConfig: secretRef: name: #cluster.metadata.name + "-kubeconfig"
		targetNamespace: #workload.spec.targetNamespace
		prune:           true
		sourceRef: {
			kind: sourcev1.#GitRepositoryKind
			name: #workload.metadata.name
		}
	}
}
