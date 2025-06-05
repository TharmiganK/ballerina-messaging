## Overview

The messaging package is designed to process messages through a configurable pipeline, ensuring reliable delivery and intelligent handling of failures. The core idea is to process messages step-by-step, with the ability to transform, filter, and deliver them to various destinations, all while maintaining shared information through a central Context object.

## Core concepts

At the heart of messaging are these fundamental concepts:

- **Message:** This is a container that holds the actual message content. It also incluses an identifier, metadata, and any other relevant information that needs to be processed or delivered. Think of it as the letter in an envelope.

- **Message Context**: This is the single, dynamic container that holds *everything* about the current message being processed. It contains the *Message* itself, along with any additional data or state that processors and destinations need to share or update during the message's journey. Think of it as the message's backpack, accumulating information as it moves.

- **Processor**: These are the *idempotent* workhorses of your pipeline. A *Processor* takes the *Context* (and thus the *Message* within it) and performs an action that transforms or filters the message. Because they are idempotent, running them multiple times with the same input *Context* will always produce the same result, making replay safe. If a processor decides a message should not continue, it can effectively act as a filter, preventing further processing or delivery.

- **Destination:** These are the final delivery points for your processed messages. A Destination takes the *copy of the Context* and delivers the message contained within to an external system, a database, another queue, or any other endpoint. Unlike Processors, these functions do not need to be idempotent, as they represent terminal actions.

- **DeadLetterStore (DLS):** This is your safety net. The *DeadLetterStore* is where messages are sent if they fail at any point during processing or delivery within a *Channel*. It intelligently captures the original message and the *Context* at the time of failure, allowing for later inspection and replay.

- **Channel:** This is the orchestrator. A Channel defines a complete message flow, chaining together a sequence of *Processors* and a set of *Destinations*. It manages the execution order, handles errors, and integrates with the *DeadLetterStore*.

## How the Components Interact

1. **Message Ingress:** A raw message content enters a Channel. This could be from an external source like a message queue, an HTTP request, or any other input mechanism.

2. **Context Creation:** The Channel immediately wraps this content into a *Message* and the *Message* into a new *Context* object, providing the central container for all subsequent operations and shared data.

3. **Sequential Processing (Processors):**

   - The *Channel* iterates through its configured *Processors* one by one.
   - Each *Processor* receives the *Context* object. It accesses the *Message* from the *Context* and can modify the message's content, update its metadata, or add information to the *Context* itself.
   - If a *Processor* decides to "drop" the message, can act as a filter. The *Channel* recognizes this signal and skips all subsequent processors and destinations for that message, marking it as successfully handled (dropped).
   - If any *Processor* encounters an error, the *Channel* catches it and sends the original *Message* and the current *Context* to the *DeadLetterStore* if configured to do so. This allows for later inspection and potential replay of the message.

4. **Parallel Delivery (Destinations):**

   - If the message successfully passes all *Processors* (i.e., it wasn't dropped), the *Channel* then proceeds to its configured Destinations.
   - *Destinations* are run in parallel (all at once).
   - Each *Destination* receives a *copy of the Context* (including the processed *Message* within it). This ensures that actions by one destination do not unintentionally interfere with others, especially in parallel execution.
   - If any *Destination* fails to deliver the message, the *Channel* intercepts the error. It then sends the original *Message* and the *Context* (as it stood just before the destination phase began, or at the point of failure) to the *DeadLetterStore* if configured.

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

The package provides three types of processors:

- **Filter**: A processor that can drop messages based on a condition. This accepts the *Context* and returns a boolean indicating whether the message should continue processing.
- **Transformer**: A processor that modifies the message content or metadata. It accepts the *Context* and returns a modified message content.
- Generic Processor: A processor that can perform any action on the *Context*. It accepts the *Context* and returns nothing.

> **Note:** All processors are assumed to be idempotent, meaning that running them multiple times with the same input will always produce the same result. This is crucial for safe message replay. It is developer's responsibility to ensure that the logic within these processors adheres to this principle.

### Defining a Filter Processor

```ballerina
@messaging:Processor {name: "filter"}
isolated function filter(messaging:Context context) returns boolean|error {
    // Check some condition on the message
}
```

### Defining a Transformer Processor

```ballerina
@messaging:Processor {name: "transformer"}
isolated function transformer(messaging:Context context) returns anydata|error {
    // Modify the message content or metadata
    // Return the modified message content
}
```

### Defining a Generic Processor

```ballerina
@messaging:Processor {name: "generic"}
isolated function generic(messaging:Context context) returns error? {
    // Perform any action on the context
}
```

## Defining a Destination

A destination is similar to a generic processor but is used to deliver the message to an external system or endpoint. It accepts a copy of the *Context* and returns an error if the delivery fails.

```ballerina
@messaging:Destination {name: "destination"}
isolated function destination(messaging:Context context) returns error? {
    // Deliver the message to an external system or endpoint
}
```

A destination can additionally take one or more processors as preprocessors. These processors will be executed before the destination is called, allowing for any final modifications or checks on the message before delivery.

```ballerina
@messaging:Destination {
    name: "destinationWithPreprocessors",
    preprocessors: [preprocessor1, preprocessor2] // a list of processor functions
}
isolated function destinationWithPreprocessors(messaging:Context context) returns error? {
    // Deliver the message to an external system or endpoint
}
```

## Defining a Dead Letter Store

The package expose an interface for defining a Dead Letter Store (DLS) that can be used to capture messages that fail during processing or delivery. The DLS should implement the `messaging:DeadLetterStore` interface.
The DLS interface requires the implementation of three methods:

- `store`: This method is used to store a message in the dead letter store. It takes a `Message` object and returns an error if the message could not be stored.
- `retrieve`: This method retrieves the top message from the dead letter store. It returns a `Message` object or an error if the message could not be retrieved.
- `clear`: This method clears all messages from the dead letter store. It returns an error if the messages could not be cleared.

## Creating a Channel

To create a channel, you need to define the processors and destinations that will be part of the message processing pipeline. You can configure the channel with a sequence of processors and a set of destinations.

```ballerina
messaging:Channel channel = check new (
    [
        filter, // a filter processor
        transformer, // a transformer processor
        generic // a generic processor
    ],
    [
        destination, // a destination
        destinationWithPreprocessors // a destination with preprocessors
    ],
    deadLetterStore = deadLetterStore // an optional dead letter store
);
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
