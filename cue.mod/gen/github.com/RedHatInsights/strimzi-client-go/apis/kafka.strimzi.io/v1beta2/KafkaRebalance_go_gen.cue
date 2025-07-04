// Code generated by cue get go. DO NOT EDIT.

//cue:generate cue get go github.com/RedHatInsights/strimzi-client-go/apis/kafka.strimzi.io/v1beta2

package v1beta2

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	apiextensions "k8s.io/apiextensions-apiserver/pkg/apis/apiextensions/v1"
)

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// KafkaRebalance
#KafkaRebalance: {
	metav1.#TypeMeta
	metadata?: metav1.#ObjectMeta @go(ObjectMeta)

	// The specification of the Kafka rebalance.
	spec?: null | #KafkaRebalanceSpec @go(Spec,*KafkaRebalanceSpec)

	// The status of the Kafka rebalance.
	status?: null | #KafkaRebalanceStatus @go(Status,*KafkaRebalanceStatus)
}

// +kubebuilder:object:root=true
// KafkaRebalanceList contains a list of instances.
#KafkaRebalanceList: {
	metav1.#TypeMeta
	metadata?: metav1.#ListMeta @go(ListMeta)

	// A list of KafkaRebalance objects.
	items?: [...#KafkaRebalance] @go(Items,[]KafkaRebalance)
}

#KafkaRebalanceSpecMode: _ // #enumKafkaRebalanceSpecMode

#enumKafkaRebalanceSpecMode:
	#KafkaRebalanceSpecModeAddBrokers |
	#KafkaRebalanceSpecModeFull |
	#KafkaRebalanceSpecModeRemoveBrokers

// The specification of the Kafka rebalance.
#KafkaRebalanceSpec: {
	// The list of newly added brokers in case of scaling up or the ones to be removed
	// in case of scaling down to use for rebalancing. This list can be used only with
	// rebalancing mode `add-brokers` and `removed-brokers`. It is ignored with `full`
	// mode.
	brokers?: [...int32] @go(Brokers,[]int32)

	// The upper bound of ongoing partition replica movements between disks within
	// each broker. Default is 2.
	concurrentIntraBrokerPartitionMovements?: null | int32 @go(ConcurrentIntraBrokerPartitionMovements,*int32)

	// The upper bound of ongoing partition leadership movements. Default is 1000.
	concurrentLeaderMovements?: null | int32 @go(ConcurrentLeaderMovements,*int32)

	// The upper bound of ongoing partition replica movements going into/out of each
	// broker. Default is 5.
	concurrentPartitionMovementsPerBroker?: null | int32 @go(ConcurrentPartitionMovementsPerBroker,*int32)

	// A regular expression where any matching topics will be excluded from the
	// calculation of optimization proposals. This expression will be parsed by the
	// java.util.regex.Pattern class; for more information on the supported format
	// consult the documentation for that class.
	excludedTopics?: null | string @go(ExcludedTopics,*string)

	// A list of goals, ordered by decreasing priority, to use for generating and
	// executing the rebalance proposal. The supported goals are available at
	// https://github.com/linkedin/cruise-control#goals. If an empty goals list is
	// provided, the goals declared in the default.goals Cruise Control configuration
	// parameter are used.
	goals?: [...string] @go(Goals,[]string)

	// Mode to run the rebalancing. The supported modes are `full`, `add-brokers`,
	// `remove-brokers`.
	// If not specified, the `full` mode is used by default.
	//
	// * `full` mode runs the rebalancing across all the brokers in the cluster.
	// * `add-brokers` mode can be used after scaling up the cluster to move some
	// replicas to the newly added brokers.
	// * `remove-brokers` mode can be used before scaling down the cluster to move
	// replicas out of the brokers to be removed.
	//
	mode?: null | #KafkaRebalanceSpecMode @go(Mode,*KafkaRebalanceSpecMode)

	// Enables intra-broker disk balancing, which balances disk space utilization
	// between disks on the same broker. Only applies to Kafka deployments that use
	// JBOD storage with multiple disks. When enabled, inter-broker balancing is
	// disabled. Default is false.
	rebalanceDisk?: null | bool @go(RebalanceDisk,*bool)

	// A list of strategy class names used to determine the execution order for the
	// replica movements in the generated optimization proposal. By default
	// BaseReplicaMovementStrategy is used, which will execute the replica movements
	// in the order that they were generated.
	replicaMovementStrategies?: [...string] @go(ReplicaMovementStrategies,[]string)

	// The upper bound, in bytes per second, on the bandwidth used to move replicas.
	// There is no limit by default.
	replicationThrottle?: null | int32 @go(ReplicationThrottle,*int32)

	// Whether to allow the hard goals specified in the Kafka CR to be skipped in
	// optimization proposal generation. This can be useful when some of those hard
	// goals are preventing a balance solution being found. Default is false.
	skipHardGoalCheck?: null | bool @go(SkipHardGoalCheck,*bool)
}

#KafkaRebalanceSpecModeAddBrokers: #KafkaRebalanceSpecMode & "add-brokers"

#KafkaRebalanceSpecModeFull: #KafkaRebalanceSpecMode & "full"

#KafkaRebalanceSpecModeRemoveBrokers: #KafkaRebalanceSpecMode & "remove-brokers"

// The status of the Kafka rebalance.
#KafkaRebalanceStatus: {
	// List of status conditions.
	conditions?: [...#KafkaRebalanceStatusConditionsElem] @go(Conditions,[]KafkaRebalanceStatusConditionsElem)

	// The generation of the CRD that was last reconciled by the operator.
	observedGeneration?: null | int32 @go(ObservedGeneration,*int32)

	// A JSON object describing the optimization result.
	optimizationResult?: null | apiextensions.#JSON @go(OptimizationResult,*apiextensions.JSON)

	// The session identifier for requests to Cruise Control pertaining to this
	// KafkaRebalance resource. This is used by the Kafka Rebalance operator to track
	// the status of ongoing rebalancing operations.
	sessionId?: null | string @go(SessionId,*string)
}

#KafkaRebalanceStatusConditionsElem: {
	// Last time the condition of a type changed from one status to another. The
	// required format is 'yyyy-MM-ddTHH:mm:ssZ', in the UTC time zone.
	lastTransitionTime?: null | string @go(LastTransitionTime,*string)

	// Human-readable message indicating details about the condition's last
	// transition.
	message?: null | string @go(Message,*string)

	// The reason for the condition's last transition (a single word in CamelCase).
	reason?: null | string @go(Reason,*string)

	// The status of the condition, either True, False or Unknown.
	status?: null | string @go(Status,*string)

	// The unique identifier of a condition, used to distinguish between other
	// conditions in the resource.
	type?: null | string @go(Type,*string)
}
