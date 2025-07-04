// Code generated by cue get go. DO NOT EDIT.

//cue:generate cue get go github.com/sudoswedenab/dockyards-backend/api/v1alpha3

package v1alpha3

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

#IdentityProviderKind: "IdentityProvider"

#IdentityProviderSpec: {
	displayName?: null | string      @go(DisplayName,*string)
	oidc?:        null | #OIDCConfig @go(OIDCConfig,*OIDCConfig)
}

#OIDCConfig: {
	clientConfig:          #OIDCClientConfig          @go(OIDCClientConfig)
	providerDiscoveryURL?: null | string              @go(OIDCProviderDiscoveryURL,*string)
	providerConfig?:       null | #OIDCProviderConfig @go(OIDCProviderConfig,*OIDCProviderConfig)
}

#OIDCClientConfig: {
	clientID:      string @go(ClientID)
	redirectURL:   string @go(RedirectURL)
	clientSecret?: string @go(ClientSecret)
}

// Fields renamed from github.com/coreos/go-oidc ProviderConfig
#OIDCProviderConfig: {
	issuer:                       string @go(Issuer)
	authorizationEndpoint:        string @go(AuthorizationEndpoint)
	tokenEndpoint:                string @go(TokenEndpoint)
	deviceAuthorizationEndpoint?: string @go(DeviceAuthorizationEndpoint)
	userinfoEndpoint?:            string @go(UserinfoEndpoint)
	jwksURI:                      string @go(JWKSURI)
	idTokenSigningAlgs: [...string] @go(IDTokenSigningAlgs,[]string)
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:scope=Cluster
#IdentityProvider: {
	metav1.#TypeMeta
	metadata?: metav1.#ObjectMeta    @go(ObjectMeta)
	spec?:     #IdentityProviderSpec @go(Spec)
}

// +kubebuilder:object:root=true
#IdentityProviderList: {
	metav1.#TypeMeta
	metadata?: metav1.#ListMeta @go(ListMeta)
	items: [...#IdentityProvider] @go(Items,[]IdentityProvider)
}
