import ballerina/log;
import ballerina/uuid;

# Represents the flow of the message in the channe;, which includes the source flow and the destinations flow.
# 
# + sourceFlow - The source flow that processes the message context.
# + destinationsFlow - The destinations flow that processes the message context and sends the 
# message to one or more destinations.
public type MessageFlow record {|
    SourceFlow sourceFlow;
    DestinationsFlow destinationsFlow;
|};

# Represent the configuration for a channel.
#
# + dlstore - An optional dead letter store to handle messages that could not be processed.
public type ChannelConfiguration record {|
    *MessageFlow;
    DeadLetterStore? dlstore = ();
|};

isolated class SkippedDestination {
    private final SourceExecutionResult executionResult;

    isolated function init(SourceExecutionResult executionResult) {
        self.executionResult = executionResult.clone();
    }

    isolated function getExecutionResult() returns SourceExecutionResult {
        lock {
            return self.executionResult.clone();
        }
    }
};

# Channel is a collection of processors and destination that can process messages in a defined flow.
public isolated class Channel {
    final readonly & Processor[] sourceProcessors;
    final readonly & (DestinationRouter|DestinationWithProcessors[]) destinations;
    final DeadLetterStore? dlstore;

    # Initializes a new instance of Channel with the provided processors and destination.
    #
    # + config - The configuration for the channel, which includes source flow, destinations flow, 
    # and dead letter store.
    # + return - An error if the channel could not be initialized, otherwise returns `()`.
    public isolated function init(*ChannelConfiguration config) returns Error? {
        readonly & SourceFlow  sourceFlow = config.sourceFlow.cloneReadOnly(); 
        if sourceFlow is Processor {
            self.sourceProcessors = [sourceFlow];
        } else {
            self.sourceProcessors = sourceFlow;
        }

        if self.sourceProcessors.length() == 0 {
            return error Error("Channel must have at least one source processor");
        }

        readonly & DestinationsFlow destinations = config.destinationsFlow.cloneReadOnly();
        if destinations is DestinationRouter {
            self.destinations = destinations;
        } else if destinations is DestinationFlow {
            DestinationWithProcessors destinationWithProcessors = getDestionationWithProcessors(destinations);
            self.destinations = [destinationWithProcessors.cloneReadOnly()];
        } else {
            DestinationWithProcessors[] destinationFlows = [];
            foreach DestinationFlow destinationFlow in destinations {
                destinationFlows.push(getDestionationWithProcessors(destinationFlow).cloneReadOnly());
            }
            self.destinations = destinationFlows.cloneReadOnly();
        }

        self.dlstore = config.dlstore;
        check validateProcessors(self.sourceProcessors);
        check validateDestinations(self.destinations);
    }

    # Replay the channel execution flow.
    #
    # + message - The message to replay process.
    # + return - Returns an error if the message could not be processed, otherwise returns the execution result.
    public isolated function replay(Message message) returns ExecutionResult|ExecutionError {
        MessageContext msgContext = new (message);
        log:printDebug("replay channel execution started", msgId = msgContext.getId());
        msgContext.cleanErrorInfoForReplay();
        return self.executeInternal(msgContext);
    }

    # Dispatch a message to the channel for processing with the defined processors and destinations.
    #
    # + content - The message content to be processed.
    # + skipDestinations - An array of destination names to skip during execution.
    # + return - Returns the execution result or an error if the processing failed.
    public isolated function execute(anydata content, string[] skipDestinations = []) returns ExecutionResult|ExecutionError {
        string id = uuid:createType1AsString();
        MessageContext msgContext = new (id = id, content = content, metadata = {skipDestinations: skipDestinations});
        log:printDebug("channel execution started", msgId = id);
        return self.executeInternal(msgContext);
    }

    isolated function executeInternal(MessageContext msgContext) returns ExecutionResult|ExecutionError {
        string id = msgContext.getId();
        // Take a copy of the message context to avoid modifying the original message.
        MessageContext msgCtxSnapshot = msgContext.clone();
        // First execute all processors
        foreach Processor processor in self.sourceProcessors {
            string processorName = getProcessorName(processor);
            SourceExecutionResult|error? result = self.executeProcessor(processor, msgContext);
            if result is error {
                // If the processor execution failed, add to dead letter store and return error.
                log:printDebug("processor execution failed", processorName = processorName, msgId = id, 'error = result);
                string errorMsg = string `Failed to execute processor: ${processorName} - ${result.message()}`;
                msgCtxSnapshot.setError(result, errorMsg);
                self.addToDLStore(msgCtxSnapshot);
                return error ExecutionError(errorMsg, message = {...msgCtxSnapshot.toRecord()});
            } else if result is SourceExecutionResult {
                // If the processor execution is returned with a result, stop further processing.
                return {...result};
            }
        }

        DestinationRouter|DestinationWithProcessors[] destinations = self.destinations;
        readonly & DestinationWithProcessors[] targetDestinations;

        if destinations is DestinationRouter {
            // If the destination is a router, execute the router to get the destination.
            DestinationFlow|error? routedDestination = destinations(msgContext);
            string destinationRouterName = getDestinationRouterName(destinations);
            if routedDestination is error {
                // If the routing failed, add to dead letter store and return error.
                log:printDebug("destination routing failed", msgId = id, 'error = routedDestination);
                string errorMsg = string `Failed to route destination by router: ${destinationRouterName} - ${routedDestination.message()}`;
                msgCtxSnapshot.setError(routedDestination, errorMsg);
                self.addToDLStore(msgCtxSnapshot);
                return error ExecutionError(errorMsg, message = {...msgCtxSnapshot.toRecord()});
            } else if routedDestination is () {
                // If the routing returned no destination, skip further processing.
                log:printDebug("destination router returned no destination, skipping further processing", msgId = id, destinationRouterName = destinationRouterName);
                return {message: {...msgContext.toRecord()}};
            } else {
                // If the routing was successful, continue with the destination execution.
                log:printDebug("destination routing successful", destinationName = getDestinationRouterName(destinations), msgId = id, destinationRouterName = destinationRouterName);
                targetDestinations = [getDestionationWithProcessors(routedDestination).cloneReadOnly()];
            }
        } else {
            targetDestinations = destinations.cloneReadOnly();
        }

        // Then execute all destinations in parallel
        map<future<any|error>> destinationExecutions = {};
        foreach DestinationWithProcessors destionationWithProcessors in targetDestinations {
            [[Processor...], Destination] [_, destination] = destionationWithProcessors;
            string destinationName = getDestinationName(destination);
            if msgContext.isDestinationSkipped(destinationName) {
                log:printWarn("destination is requested to be skipped", destinationName = destinationName, msgId = msgContext.getId());
            } else {
                future<any|error> destinationExecution = start self.executeDestination(destionationWithProcessors, msgContext.clone());
                destinationExecutions[destinationName] = destinationExecution;
            }
        }

        map<error> failedDestinations = {};
        map<any> successfulDestinations = {};
        foreach var [destinationName, destinationExecution] in destinationExecutions.entries() {
            any|error result = wait destinationExecution;
            if result is SkippedDestination {
                // If the destination execution returned a result, so destination execution is skipped by a preprocessor.
                log:printDebug("destination execution is skipped by a preprocessor", destinationName = destinationName, msgId = msgCtxSnapshot.getId());
            } else if result is any {
                // If the destination execution was successful, continue.
                msgCtxSnapshot.skipDestination(destinationName);
                log:printDebug("destination executed successfully", destinationName = destinationName, msgId = msgCtxSnapshot.getId());
                successfulDestinations[destinationName] = result;
                continue;
            } else {
                // If there was an error, collect the error.
                failedDestinations[destinationName] = result;
                log:printDebug("destination execution failed", destinationName = destinationName, msgId = msgCtxSnapshot.getId(), 'error = result);
            }
        }
        if failedDestinations.length() > 0 {
            return self.reportDestinationFailure(failedDestinations, msgCtxSnapshot);
        }
        return {message: {...msgContext.toRecord()}, destinationResults: successfulDestinations};
    }

    isolated function executeProcessor(Processor processor, MessageContext msgContext) returns SourceExecutionResult|error? {
        string processorName = getProcessorName(processor);
        string id = msgContext.getId();

        if processor is GenericProcessor {
            check processor(msgContext);
            log:printDebug("processor executed successfully", processorName = processorName, msgId = id);
        } else if processor is Filter {
            boolean filterResult = check processor(msgContext);
            if !filterResult {
                log:printDebug("processor filter returned false, skipping further processing", processorName = processorName, msgId = msgContext.getId());
                return {message: {...msgContext.toRecord()}};
            }
            log:printDebug("processor filter executed successfully", processorName = processorName, msgId = msgContext.getId());
        } else if processor is ProcessorRouter {
            Processor? routedProcessor = check processor(msgContext);
            if routedProcessor is () {
                log:printDebug("source router returned no processor, skipping further processing", msgId = msgContext.getId());
                return {message: {...msgContext.toRecord()}};
            }
            log:printDebug("processor router executed successfully", processorName = processorName, msgId = msgContext.getId());
            return self.executeProcessor(routedProcessor, msgContext);
        } else {
            anydata transformedContent = check processor(msgContext);
            msgContext.setContent(transformedContent);
            log:printDebug("processor transformer executed successfully", processorName = processorName, msgId = msgContext.getId());
        }
        return;
    }

    isolated function executeDestination(DestinationWithProcessors destinationWithProcessors, MessageContext msgContext) returns any|error {
        [[Processor...], Destination] [preprocessors, destination] = destinationWithProcessors;
        foreach Processor preprocessor in preprocessors {
            string preprocessorName = getProcessorName(preprocessor);
            if msgContext.isDestinationSkipped(preprocessorName) {
                log:printWarn("preprocessor is requested to be skipped", preprocessorName = preprocessorName, msgId = msgContext.getId());
                continue;
            }
            SourceExecutionResult|error? result = self.executeProcessor(preprocessor, msgContext);
            if result is error {
                return result;
            }
            if result is SourceExecutionResult {
                // If the preprocessor execution is returned with a result, stop further processing.
                log:printDebug("preprocessor executed successfully, skipping destination execution", preprocessorName = preprocessorName, msgId = msgContext.getId());
                return new SkippedDestination(result);
            }
        }
        // Execute the destination
        return destination(msgContext);
    }

    isolated function reportDestinationFailure(map<error> failedDestinations, MessageContext msgContext) returns ExecutionError {
        string errorMsg;
        if failedDestinations.length() == 1 {
            string destinationName = failedDestinations.keys()[0];
            error failedDestination = failedDestinations.get(destinationName);
            errorMsg = string `Failed to execute destination: ${destinationName} - ${failedDestination.message()}`;
            msgContext.setError(failedDestination, errorMsg); 
        } else {
            errorMsg = "Failed to execute destinations: ";
            foreach var [handlerName, err] in failedDestinations.entries() {
                msgContext.addError(handlerName, err);
                errorMsg += handlerName + ", ";
            }
            if errorMsg.length() > 0 {
                errorMsg = errorMsg.substring(0, errorMsg.length() - 2);
            }
            msgContext.setErrorMessage(errorMsg.trim());
        }
        self.addToDLStore(msgContext);
        return error ExecutionError(errorMsg, message = {...msgContext.toRecord()});
    }

    isolated function addToDLStore(MessageContext msgContext) {
        DeadLetterStore? dlstore = self.dlstore;
        if dlstore is () {
            log:printWarn("dead letter store is not configured, skipping storing the failed message", msgId = msgContext.getId());
            return;
        }
        string id = msgContext.getId();
        error? dlStoreError = dlstore.store(msgContext.toRecord());
        if dlStoreError is error {
            log:printError("failed to add message to dead letter store", 'error = dlStoreError, msgId = id);
        } else {
            log:printDebug("message added to dead letter store", msgId = id);
        }
        return;
    }
}

isolated function getDestionationWithProcessors(DestinationFlow destinationFlow) 
        returns DestinationWithProcessors {
    return destinationFlow is DestinationWithProcessors ? destinationFlow : [[], destinationFlow];
}

isolated function validateProcessors(Processor[] processors) returns Error? {
    foreach Processor processor in processors {
        string|error processorName = trap getProcessorName(processor);
        if processorName is Error {
            return processorName;
        }
    }
}

isolated function getProcessorName(Processor processor) returns string {
    string? name = (typeof processor).@ProcessorConfig?.name;
    if name is string {
        return name;
    }
    name = (typeof processor).@ProcessorRouterConfig?.name;
    if name is string {
        return name;
    }
    name = (typeof processor).@FilterConfig?.name;
    if name is string {
        return name;
    }
    name = (typeof processor).@TransformerConfig?.name;
    if name is () {
        panic error Error("Processor name is not defined");
    }
    return name;
};

isolated function validateDestinations(DestinationRouter|DestinationWithProcessors[] destinations) 
        returns Error? {
    if destinations is DestinationRouter {
        string|error routerName = trap getDestinationRouterName(destinations);
        if routerName is Error {
            return routerName;
        }
    } else {
        foreach [[Processor...], Destination] [processors, destination] in destinations {
            check validateProcessors(processors);
            string|error destinationName = trap getDestinationName(destination);
            if destinationName is Error {
                return error Error("Destination name is not defined for one or more destinations.");
            }
        }
    }
}

isolated function getDestinationName(Destination destination) returns string {
    string? name = (typeof destination).@DestinationConfig?.name;
    if name is () {
        panic error Error("Destination name is not defined");
    }
    return name;
};

isolated function getDestinationRouterName(DestinationRouter destinationRouter) returns string {
    string? name = (typeof destinationRouter).@DestinationRouterConfig?.name;
    if name is () {
        panic error Error("Destination router name is not defined");
    }
    return name;
};

