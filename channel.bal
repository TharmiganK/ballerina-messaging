import ballerina/log;
import ballerina/uuid;

# Represent the configuration for a channel.
#
# + processor - An array of processors to be executed in the channel.
# + destination - A single destination or an array of destinations or a destination router which will route the message to a destination.
# + dlstore - An optional dead letter store to handle messages that could not be processed.
public type ChannelConfiguration record {|
    Processor|Processor[] processor;
    DestinationRouter|Destination|Destination[] destination;
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
    final readonly & Processor[] processors;
    final readonly & (DestinationRouter|Destination[]) destination;
    final DeadLetterStore? dlstore;

    # Initializes a new instance of Channel with the provided processors and destination.
    #
    # + processors - An array of processors to be executed in the channel.
    # + destination - A single destination or an array of destinations or a destination router which will route the message to a destination.
    # + dlstore - An optional dead letter store to handle messages that could not be processed.
    # + return - An error if the channel could not be initialized, otherwise returns `()`.
    public isolated function init(*ChannelConfiguration config) returns Error? {
        readonly & (Processor|Processor[]) processors = config.processor.cloneReadOnly();
        if processors is Processor {
            self.processors = [processors];
        } else {
            self.processors = processors;
        }

        readonly & (DestinationRouter|Destination|Destination[]) destination = config.destination.cloneReadOnly();
        if destination is DestinationRouter {
            self.destination = destination;
        } else if destination is Destination {
            self.destination = [destination];
        } else {
            self.destination = destination;
        }
        self.dlstore = config.dlstore;
        check self.validateProcessors(self.processors);
        check self.validateDestinations(self.destination);
    }

    # Replay the channel execution flow.
    #
    # + message - The message to replay process.
    # + return - Returns an error if the message could not be processed, otherwise returns the execution result.
    public isolated function replay(Message message) returns ExecutionResult|ExecutionError {
        MessageContext msgContext = new (message);
        log:printDebug("replay channel execution started", msgId = msgContext.getId());
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
        foreach Processor processor in self.processors {
            string processorName = self.getProcessorName(processor);
            SourceExecutionResult|error? result = self.executeProcessor(processor, msgContext);
            if result is error {
                // If the processor execution failed, add to dead letter store and return error.
                log:printDebug("processor execution failed", processorName = processorName, msgId = id, 'error = result);
                string errorMsg = string `Failed to execute processor: ${processorName} - ${result.message()}`;
                msgCtxSnapshot.setErrorMsg(errorMsg);
                msgCtxSnapshot.setErrorStackTrace(result.stackTrace().toString());
                self.addToDLStore(msgCtxSnapshot);
                return error ExecutionError(errorMsg, message = {...msgCtxSnapshot.getMessage()});
            } else if result is SourceExecutionResult {
                // If the processor execution is returned with a result, stop further processing.
                return {...result};
            }
        }

        DestinationRouter|Destination[] destination = self.destination;

        if destination is DestinationRouter {
            // If the destination is a router, execute the router to get the destination.
            Destination|error? routedDestination = destination(msgContext);
            if routedDestination is error {
                // If the routing failed, add to dead letter store and return error.
                log:printDebug("destination routing failed", msgId = id, 'error = routedDestination);
                string errorMsg = string `Failed to route destination: ${routedDestination.message()}`;
                msgCtxSnapshot.setErrorMsg(errorMsg);
                msgCtxSnapshot.setErrorStackTrace(routedDestination.stackTrace().toString());
                self.addToDLStore(msgCtxSnapshot);
                return error ExecutionError(errorMsg, message = {...msgCtxSnapshot.getMessage()});
            } else if routedDestination is () {
                // If the routing returned no destination, skip further processing.
                log:printDebug("destination router returned no destination, skipping further processing", msgId = id);
                return {message: {...msgContext.getMessage()}};
            } else {
                // If the routing was successful, continue with the destination execution.
                log:printDebug("destination routing successful", destinationName = self.getDestinationRouterName(destination), msgId = id);
                destination = [routedDestination];
            }
        }

        // Then execute all destinations in parallel
        map<future<any|error>> destinationExecutions = {};
        foreach Destination destinationSingle in <Destination[]>destination {
            string destinationName = self.getDestinationName(destinationSingle);
            if msgContext.isDestinationSkipped(destinationName) {
                log:printWarn("destination is requested to be skipped", destinationName = destinationName, msgId = msgContext.getId());
            } else {
                future<any|error> destinationExecution = start self.executeDestination(destinationSingle, msgContext.clone());
                destinationExecutions[destinationName] = destinationExecution;
            }
        }

        map<error> failedDestinations = {};
        map<any> successfulDestinations = {};
        foreach var [destinationName, destinationExecution] in destinationExecutions.entries() {
            any|error result = wait destinationExecution;
            if result is SkippedDestination {
                // If the destination execution returned a result, so destination execution is skipped by a preprocessor.
                log:printDebug("destination execution is skipped by a preprocessor", destinationName = destinationName, msgId = msgContext.getId());
            } else if result is any {
                // If the destination execution was successful, continue.
                msgContext.skipDestination(destinationName);
                log:printDebug("destination executed successfully", destinationName = destinationName, msgId = msgContext.getId());
                successfulDestinations[destinationName] = result;
                continue;
            } else {
                // If there was an error, collect the error.
                failedDestinations[destinationName] = result;
                log:printDebug("destination execution failed", destinationName = destinationName, msgId = msgContext.getId(), 'error = result);
            }
        }
        if failedDestinations.length() > 0 {
            return self.reportDestinationFailure(failedDestinations, msgContext);
        }
        return {message: {...msgContext.getMessage()}, destinationResults: successfulDestinations};
    }

    isolated function executeProcessor(Processor processor, MessageContext msgContext) returns SourceExecutionResult|error? {
        string processorName = self.getProcessorName(processor);
        string id = msgContext.getId();

        if processor is GenericProcessor {
            check processor(msgContext);
            log:printDebug("processor executed successfully", processorName = processorName, msgId = id);
        } else if processor is Filter {
            boolean filterResult = check processor(msgContext);
            if !filterResult {
                log:printDebug("processor filter returned false, skipping further processing", processorName = processorName, msgId = msgContext.getId());
                return {message: {...msgContext.getMessage()}};
            }
        } else if processor is ProcessorRouter {
            Processor? routedProcessor = check processor(msgContext);
            if routedProcessor is () {
                log:printDebug("source router returned no processor, skipping further processing", msgId = msgContext.getId());
                return {message: {...msgContext.getMessage()}};
            }
            return self.executeProcessor(routedProcessor, msgContext);
        } else {
            anydata transformedContent = check processor(msgContext);
            msgContext.setContent(transformedContent);
            log:printDebug("processor transformer executed successfully", processorName = processorName, msgId = msgContext.getId());
        }
        return;
    }

    isolated function executeDestination(Destination destination, MessageContext msgContext) returns any|error {
        // Execute the preprocessors if any
        Processor[]? preprocessors = self.getDestinationPreprocessors(destination);
        if preprocessors is () {
            // If no preprocessors are defined, skip to destination execution.
            return destination(msgContext);
        }
        foreach Processor preprocessor in preprocessors {
            string preprocessorName = self.getProcessorName(preprocessor);
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
                return new SkippedDestination(result);
            }
        }
        // Execute the destination
        return destination(msgContext);
    }

    isolated function reportDestinationFailure(map<error> failedDestinations, MessageContext msgContext) returns ExecutionError {
        string errorMsg = "Failed to execute destinations: ";
        foreach var [handlerName, err] in failedDestinations.entries() {
            errorMsg += handlerName + " - " + err.message() + "; ";
        }
        msgContext.setErrorMsg(errorMsg.trim());
        string stackTrace = "";
        foreach var [handlerName, err] in failedDestinations.entries() {
            stackTrace += handlerName + " - " + err.stackTrace().toString() + "\n";
        }
        if stackTrace.length() > 0 {
            stackTrace = stackTrace.substring(0, stackTrace.length() - 1);
        }
        msgContext.setErrorStackTrace(stackTrace);
        self.addToDLStore(msgContext);
        return error ExecutionError(errorMsg, message = {...msgContext.getMessage()});
    }

    isolated function validateProcessors(Processor[] processors) returns Error? {
        foreach Processor processor in processors {
            string|error processorName = trap self.getProcessorName(processor);
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

    isolated function validateDestinations(DestinationRouter|Destination[] destination) returns Error? {
        if destination is DestinationRouter {
            string|error routerName = trap self.getDestinationRouterName(destination);
            if routerName is Error {
                return routerName;
            }
        } else {
            foreach Destination destinationSingle in destination {
                string|error destinationName = trap self.getDestinationName(destinationSingle);
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

    isolated function getDestinationPreprocessors(Destination destination) returns Processor[]? {
        return (typeof destination).@DestinationConfig?.preprocessors;
    };

    isolated function addToDLStore(MessageContext msgContext) {
        DeadLetterStore? dlstore = self.dlstore;
        if dlstore is () {
            log:printWarn("dead letter store is not configured, skipping storing the failed message", msgId = msgContext.getId());
            return;
        }
        string id = msgContext.getId();
        error? dlStoreError = dlstore.store(msgContext.getMessage());
        if dlStoreError is error {
            log:printError("failed to add message to dead letter store", 'error = dlStoreError, msgId = id);
        } else {
            log:printDebug("message added to dead letter store", msgId = id);
        }
        return;
    }
}

