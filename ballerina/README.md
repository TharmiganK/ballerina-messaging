## Overview

This package is designed to process messages through a configurable channel, ensuring reliable delivery and intelligent handling of failures. The core idea is to process messages step-by-step, with the ability to transform, filter, and deliver them to various destinations, all while maintaining shared information through a central Context object.

## Core concepts

At the heart of reliable messaging are these fundamental concepts:

- **Message:** This is a container that holds the actual message content. It also incluses an identifier, metadata, and any other relevant information that needs to be processed or delivered. Think of it as the letter in an envelope.

- **Message Context**: This is the single, dynamic container that holds *everything* about the current message being processed. It contains the *Message* itself, along with any additional data or state that processors and destinations need to share or update during the message's journey. Think of it as the message's backpack, accumulating information as it moves.

- **Processor**: These are the *idempotent* workhorses of your pipeline. A *Processor* takes the *Context* (and thus the *Message* within it) and performs an action that transforms or filters or routes the message to a different processor. Because they are idempotent, running them multiple times with the same input *Context* will always produce the same result, making replay safe. If a processor decides a message should not continue, it can effectively act as a filter, preventing further processing or delivery.

- **Destination:** These are the final delivery points for your processed messages. A Destination takes the *copy of the Context* and delivers the message contained within to an external system, a database, another queue, or any other endpoint. Unlike Processors, these functions do not need to be idempotent, as they represent terminal actions.

- **DeadLetterStore (DLS):** This is your safety net. The *DeadLetterStore* is where messages are sent if they fail at any point during processing or delivery within a *Channel*. It intelligently captures the original message and the *Context* at the time of failure, allowing for later inspection and replay.

- **Message Flow:** This defines the source flow and destionations flow of the message. The source flow
is a sequence of *Processors* that the message goes through, while the destinations flow is a set of *Destinations* where the message is delivered.

- **Channel:** This is the orchestrator. A Channel defines a complete message flow. It handles errors, and integrates with the *DeadLetterStore*.

## How the Components Interact

1. **Message Ingress:** A raw message content enters a Channel. This could be from an external source like a message queue, an HTTP request, or any other input mechanism.

2. **Context Creation:** The Channel immediately wraps this content into a *Message* and the *Message* into a new *Context* object, providing the central container for all subsequent operations and shared data.

3. **Sequential Processing (Source Processors):**

   - The *Channel* iterates through its configured source *Processors* one by one.
   - Each *Processor* receives the *Context* object. It accesses the *Message* from the *Context* and can modify the message's content, update its metadata, or add information to the *Context* itself.
   - If a *Processor* decides to "drop" the message, can act as a filter. The *Channel* recognizes this signal and skips all subsequent processors and destinations for that message, marking it as successfully handled (dropped).
   - If a *Processor* decides to route the message to a different processor, it returns the target processor, and the *Channel* continues processing with that processor instead of the next one in line.
   - If any *Processor* encounters an error, the *Channel* catches it and sends the original *Message* and the current *Context* to the *DeadLetterStore* if configured to do so. This allows for later inspection and potential replay of the message.

4. **Parallel Delivery (Destinations):**

   - If the message successfully passes all source *Processors* (i.e., it wasn't dropped), the *Channel* then proceeds to its configured Destinations.
   - *Destinations* are run in parallel (all at once).
   - Each *Destination* receives a *copy of the Context* (including the processed *Message* within it). This ensures that actions by one destination do not unintentionally interfere with others, especially in parallel execution.
   - If any *Destination* fails to deliver the message, the *Channel* intercepts the error. It then sends the original *Message* and the *Context* (as it stood just before the destination phase began, or at the point of failure) to the *DeadLetterStore* if configured.
   - If all the *Destinations* succeed, the *ExecutionResult* will contain the results from each destionation as a map.

5. **Dead Letter Store (DLS) Interaction:**

   - This is an optional configuration for the *Channel*. If enabled, it acts as a safety net for messages that fail during processing or delivery.
   - When a message fails processing or delivery, the *Channel* persists the original *Message* and its *Context* in the *DeadLetterStore*.
   - The *Channel* also provides an API to replay a failed message. When replayed, the *Channel* accepts the processed context and attempts to reprocess the message through its configured *Processors* and *Destinations*. Additionally, the *Channel* intelligently skips any *Destinations* that have already successfully processed the message in previous attempts, ensuring that only the necessary steps are retried.

![Messaging Flow Diagram](https://raw.githubusercontent.com/TharmiganK/ballerina-messaging/master/resources/diagram.png)

## Key features

- **Clean API:** Functions only need to accept the Context object, simplifying their signatures and making them easier to write and test.

- **Shared State:** The Context provides a central, mutable place for all parts of the pipeline to share and update information related to the message's processing.

- **Idempotency Enforcement:** The design clearly separates idempotent Processors from non-idempotent Destinations, which is crucial for safe message replay.

- **Robust Error Handling:** The DeadLetterStore mechanism ensures that no messages are silently lost, providing a recovery mechanism for failures.

- **Flexibility:** The modular design allows you to easily add, remove, or reorder Processors and Destinations to adapt to changing business logic without altering the core framework.

- **Asynchronous Readiness:** The design naturally lends itself to asynchronous operations, allowing for efficient handling of I/O-bound tasks in processors and destinations.

## Defining a Processor

The package provides four types of processors:

- **Filter**: A processor that can drop messages based on a condition. This accepts the *Context* and returns a boolean indicating whether the message should continue processing.
- **Transformer**: A processor that modifies the message content or metadata. It accepts the *Context* and returns a modified message content.
- **ProcessorRouter**: A processor that can route messages to different processors based on some criteria. It accepts the *Context* and returns the target processor to which the message should be routed. This allows for dynamic routing of messages based on their content or metadata.
- Generic Processor: A processor that can perform any action on the *Context*. It accepts the *Context* and returns nothing.

> **Note:** All processors are assumed to be idempotent, meaning that running them multiple times with the same input will always produce the same result. This is crucial for safe message replay. It is developer's responsibility to ensure that the logic within these processors adheres to this principle.

### Defining a Filter Processor

```ballerina
@messaging:Filter {name: "filter"}
isolated function filter(messaging:Context context) returns boolean|error {
    // Check some condition on the message
}
```

### Defining a Transformer Processor

```ballerina
@messaging:Transformer {name: "transformer"}
isolated function transformer(messaging:Context context) returns anydata|error {
    // Modify the message content or metadata
    // Return the modified message content
}
```

### Defining a Processor Router

```ballerina
@messaging:ProcessingRouter {name: "processorRouter"}
isolated function processorRouter(messaging:Context context) returns messaging:Processor|error {
    // Determine the target processor based on some criteria
    // Return the target processor to which the message should be routed
}
```

### Defining a Generic Processor

```ballerina
@messaging:Processor {name: "generic"}
isolated function generic(messaging:Context context) returns error? {
    // Perform any action on the context
}
```

## Defining the Source Flow

The source flow of a message is created as a sequence of processors that the message goes through before being delivered to any destinations. You can define the source flow by creating a sequence of processors and configuring them in the channel.

```ballerina
messaging:SourceFlow sourceFlow = [
    filter, // a filter processor
    transformer, // a transformer processor
    processorRouter, // a processor router
    generic // a generic processor
];
```

## Defining a Destination

A destination is similar to a generic processor but is used to deliver the message to an external system or endpoint. It accepts a copy of the *Context* and returns an error if the delivery fails. Additionally, it can return any result that is relevant to the delivery operation, such as a confirmation or status.

```ballerina
@messaging:Destination {name: "destination"}
isolated function destination(messaging:Context context) returns any|error {
    // Deliver the message to an external system or endpoint
}
```

## Defining a Destination Flow

A single destination can be configured as a destination flow, or it can be included with preprocessors
which are executed before the destination is called.

```ballerina
// A single destination flow
messaging:DestinationFlow destinationFlow = destination;

// A destination flow with preprocessors
messaging:DestinationFlow destinationWithPreprocessors = [
    [
        filter, // a filter processor
        transformer // a transformer processor
    ],
    destination // a destination
];
```

## Defining a Destination Router

A destination router is a special type of processor that can route messages to different destinations based on some criteria. It accepts the *Context* and returns the target destination flow to which the message should be routed.

```ballerina
@messaging:DestinationRouter {name: "destinationRouter"}
isolated function destinationRouter(messaging:Context context) returns messaging:DestinationFlow|error {
    // Determine the target destination based on some criteria
    // Return the target destination to which the message should be routed
}
```

## Defining the Destinations Flow

The destinations flow of a message can be a single destination router or a set of destination flows. The destination flows are executed in parallel, meaning that all destinations will receive a copy of the message and the context at the same time.

```ballerina
// A destination router as the destinations flow
messaging:DestinationsFlow destinationsFlow = destinationRouter;

// A set of destinations as the destinations flow
messaging:DestinationsFlow destinationsFlow = [
    destination, // a destination
    destinationWithPreprocessors // a destination with preprocessors
];
```

## Defining a Dead Letter Store

The package expose an interface for defining a Dead Letter Store (DLS) that can be used to capture messages that fail during processing or delivery. The DLS should implement the `messaging:DeadLetterStore` interface.

The DLS interface requires the implementation of the `store` method. This method is used to store a message in the dead letter store. It takes a `Message` object and returns an error if the message could not be stored.

## Creating a Channel

To create a channel, you need to define the processors and destinations that will be part of the message processing pipeline. You can configure the channel with a sequence of processors and a set of destinations.

```ballerina
messaging:Channel channel = check new ({
    sourceFlow: [
        filter, // a filter processor
        transformer, // a transformer processor
        processorRouter, // a processor router
        generic // a generic processor
    ],
    destinationsFlow: [
        destination, // a destination
        destinationWithPreprocessors // a destination with preprocessors
    ],
    deadLetterStore: deadLetterStore // an optional dead letter store
});
```

## Executing a Channel

To execute a channel, you can call the `execute` method with the raw message content. The channel will process the message through its configured processors and destinations.

```ballerina
messaging:ExecutionResult|messaging:ExecutionError result = channel.execute("raw message content");
```

A successful execution will return a `messaging:ExecutionResult` containing the final context after processing. If an error occurs during processing or delivery, it will return a `messaging:ExecutionError` with details about the failure. The `ExecutionError` error details will include a snapshot of the context at the time of failure, allowing you to inspect the message and replay it if necessary.

## Replaying a Message

To replay a message that has previously failed, you can use the `replay` method of the channel. This method accepts a `messaging:Message` that represents the state of the message at the time of failure.

```ballerina
messaging:ExecutionResult|messaging:ExecutionError replayResult = channel.replay(failedMessage);
```
