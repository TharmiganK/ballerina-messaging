## Overview

The messaging package provides a flexible and extensible message processing framework that allows parallel execution of message handlers. It's designed to handle messages through a series of handlers while maintaining context and supporting error handling.

### Handler

A handler is a fundamental unit of message processing in this framework. It's defined as an isolated function that accepts a `MessageContext` and returns an optional error:

```ballerina
public type Handler isolated function (MessageContext msgCtx) returns error?;
```

Each handler should be configured with a name using the `@messaging:HandlerConfig` annotation:

```ballerina
@messaging:HandlerConfig {
    name: "myHandler"
}
```

### Channel

A channel is a collection of message handlers that can be executed in parallel. It manages the execution flow, error handling, and handler skipping logic. The channel ensures that:

- At least one handler is present
- All handlers have valid names
- Handlers are executed in parallel
- Failed handler executions are properly handled
- Message context is maintained throughout the processing

#### The execute method

The `execute` method is the core functionality of the Channel class. It:

1. Creates a message context for the input message
2. Generates a unique message ID
3. Executes handlers in parallel
4. Handles handler failures
5. Returns either an execution result or an error

The method supports:
- Parallel handler execution
- Handler skipping
- Error collection and aggregation
- Debug logging

#### The replay method

The `replay` method allows re-executing the channel with a new message context. It can be used to retry processing after a failure or to reprocess messages with updated context.

### Example

Here's an example of how to use the messaging package:

```ballerina
import tharmigan/messaging;

@messaging:HandlerConfig {
    name: "uppercase"
}
isolated function upperCaseHandler(messaging:MessageContext msgCtx) returns error? {
    string content = check msgCtx.getContent().ensureType();
    msgCtx.setProperty("upperCase", content.toUpperAscii());
}

@messaging:HandlerConfig {
    name: "length"
}
isolated function lengthHandler(messaging:MessageContext msgCtx) returns error? {
    string content = check msgCtx.getContent().ensureType();
    msgCtx.setProperty("length", content.length());
}

public function main() returns error? {
    messaging:Handler[] handlers = [upperCaseHandler, lengthHandler];
    messaging:Channel channel = check new (handlers);
    
    do {
        // Execute the channel with a message
        messaging:ExecutionResult result = check channel.execute(content = "Hello, World!");

        // Process the result
    } on fail messaging:ExecutionError err {
        // Extract the message
        messaging:Message msgInfo = err.detail().message;

        // Replay the channel
        messaging:ExecutionResult replayResult = check channel.replay(msgInfo);
    }
}
```
