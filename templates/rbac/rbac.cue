package template

import (
	"encoding/yaml"
	"strings"

	rbac "k8s.io/kubernetes/pkg/apis/rbac"
	dockyardsv1 "github.com/sudoswedenab/dockyards-backend/api/v1alpha3"
)

#RoleRef: {
	apiGroup: string
	kind:     "Role" | "ClusterRole"
	name:     string
}

#RoleBindingSubject: {
	apiGroup:   string
	kind:       "User" | "Group" | "ServiceAccount"
	name:       string
	namespace?: string
}

#RoleBinding: {
	bindingName: string
	roleRef:     #RoleRef
	subjects: [...#RoleBindingSubject]
}

#Input: {
	clusterRoleBindings?: [...#RoleBinding]
	roleBindings?: [...#RoleBinding]
}

#workload: dockyardsv1.#Workload
#workload: spec: input: #Input

_roleBindingList: [
	for roleBinding in #workload.spec.input.roleBindings {
		rbac.#RoleBinding
		apiVersion: "rbac.authorization.k8s.io/v1"
		kind:       "RoleBinding"
		metadata: {
			name: roleBinding.bindingName
		}
		roleRef:  roleBinding.roleRef
		subjects: roleBinding.subjects
	},
]

_clusterRoleBindingList: [
	for clusterRoleBinding in #workload.spec.input.clusterRoleBindings {
		rbac.#ClusterRoleBinding
		apiVersion: "rbac.authorization.k8s.io/v1"
		kind:       "ClusterRoleBinding"
		metadata: {
			name: clusterRoleBinding.bindingName
		}
		roleRef:  clusterRoleBinding.roleRef
		subjects: clusterRoleBinding.subjects
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
			"roleBindings.yaml": '\(strings.Join([
						for roleBinding in _roleBindingList {
					"\(yaml.Marshal(roleBinding))"
				},
			], "\n---\n"))'
			"clusterRoleBindings.yaml": '\(strings.Join([
							for clusterRoleBinding in _clusterRoleBindingList {
					"\(yaml.Marshal(clusterRoleBinding))"
				},
			], "\n---\n"))'
		}
	}
}
