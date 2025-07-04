// Code generated by cue get go. DO NOT EDIT.

//cue:generate cue get go github.com/sudoswedenab/dockyards-backend/api/v1alpha3

package v1alpha3

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

#CredentialTemplateKind: "CredentialTemplate"

#CredentialOption: {
	default?:     string @go(Default)
	displayName?: string @go(DisplayName)
	key:          string @go(Key)
	plaintext?:   bool   @go(Plaintext)
	type?:        string @go(Type)
}

#CredentialTemplateSpec: {
	options: [...#CredentialOption] @go(Options,[]CredentialOption)
}

// +kubebuilder:object:root=true
// +kubebuilder:storageversion
#CredentialTemplate: {
	metav1.#TypeMeta
	metadata?: metav1.#ObjectMeta      @go(ObjectMeta)
	spec?:     #CredentialTemplateSpec @go(Spec)
}

// +kubebuilder:object:root=true
#CredentialTemplateList: {
	metav1.#TypeMeta
	metadata?: metav1.#ListMeta @go(ListMeta)
	items?: [...#CredentialTemplate] @go(Items,[]CredentialTemplate)
}
