import ballerina/log;
import ballerina/uuid;

# Represent the configuration for a channel.
# 
# + processors - An array of processors to be executed in the channel.
# + destinations - An array of destinations to which the message will be sent.
# + dlstore - An optional dead letter store to handle messages that could not be processed.
public type ChannelConfiguration record {|
    Processor[] processors = [];
    Destination[] destinations = [];
    DeadLetterStore? dlstore = ();
|};

# Channel is a collection of processors and destinations that can process messages in a defined flow.
public isolated class Channel {
    final readonly & Processor[] processors;
    final readonly & Destination[] destinations;
    final DeadLetterStore? dlstore;

    # Initializes a new instance of Channel with the provided processors and destinations.
    #
    # + processors - An array of processors to be executed in the channel.
    # + destinations - An array of destinations to which the message will be sent.
    # + dlstore - An optional dead letter store to handle messages that could not be processed.
    # + return - An error if the channel could not be initialized, otherwise returns `()`.
    public isolated function init(*ChannelConfiguration config) returns Error? {
        if config.processors.length() == 0 && config.destinations.length() == 0 {
            return error Error("Channel must have at least one processor or destination.");
        }
        self.processors = config.processors.cloneReadOnly();
        self.destinations = config.destinations.cloneReadOnly();
        self.dlstore = config.dlstore;
        check self.validateProcessors(self.processors);
        check self.validateDestinations(self.destinations);
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
            ExecutionResult|error? result = self.executeProcessor(processor, msgContext);
            if result is error {
                // If the processor execution failed, add to dead letter store and return error.
                log:printDebug("processor execution failed", processorName = processorName, msgId = id, 'error = result);
                string errorMsg = string `Failed to execute processor: ${processorName} - ${result.message()}`;
                msgCtxSnapshot.setErrorMsg(errorMsg);
                msgCtxSnapshot.setErrorStackTrace(result.stackTrace().toString());
                self.addToDLStore(msgCtxSnapshot);
                return error ExecutionError(errorMsg, message = {...msgCtxSnapshot.getMessage()});
            } else if result is ExecutionResult {
                // If the processor execution is returned with a result, stop further processing.
                return result;
            }
        }

        // Then execute all destinations in parallel
        map<future<ExecutionResult|error?>> destinationExecutions = {};
        foreach Destination destination in self.destinations {
            string destinationName = self.getDestinationName(destination);
            if msgContext.isDestinationSkipped(destinationName) {
                log:printWarn("destination is requested to be skipped", destinationName = destinationName, msgId = msgContext.getId());
            } else {
                future<ExecutionResult|error?> destinationExecution = start self.executeDestination(destination, msgContext.clone());
                destinationExecutions[destinationName] = destinationExecution;
            }
        }

        map<error> failedDestinations = {};
        foreach var [destinationName, destinationExecution] in destinationExecutions.entries() {
            ExecutionResult|error? result = wait destinationExecution;
            if result is () {
                // If the destination execution was successful, continue.
                msgContext.skipDestination(destinationName);
                log:printDebug("destination executed successfully", destinationName = destinationName, msgId = msgContext.getId());
                continue;
            } else if result is ExecutionResult {
                // If the destination execution returned a result, so destination execution is skipped by a preprocessor.
                log:printDebug("destination execution is skipped by a preprocessor", destinationName = destinationName, msgId = msgContext.getId());
            } else {
                // If there was an error, collect the error.
                failedDestinations[destinationName] = result;
                log:printDebug("destination execution failed", destinationName = destinationName, msgId = msgContext.getId(), 'error = result);
            }
        }
        if failedDestinations.length() > 0 {
            return self.reportDestinationFailure(failedDestinations, msgContext);
        }
        return {message: {...msgContext.getMessage()}};
    }

    isolated function executeProcessor(Processor processor, MessageContext msgContext) returns ExecutionResult|error? {
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
        } else {
            anydata transformedContent = check processor(msgContext);
            msgContext.setContent(transformedContent);
            log:printDebug("processor transformer executed successfully", processorName = processorName, msgId = msgContext.getId());
        }
        return;
    }

    isolated function executeDestination(Destination destination, MessageContext msgContext) returns ExecutionResult|error? {
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
            ExecutionResult|error? result = self.executeProcessor(preprocessor, msgContext);
            if result is error {
                return result;
            }
            if result is ExecutionResult {
                // If the preprocessor execution is returned with a result, stop further processing.
                return result;
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

    isolated function validateDestinations(Destination[] destinations) returns Error? {
        foreach Destination destination in destinations {
            string|error destinationName = trap self.getDestinationName(destination);
            if destinationName is Error {
                return error Error("Destination name is not defined for one or more destinations.");
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

    isolated function getDestinationPreprocessors(Destination destination) returns Processor[]? {
        return (typeof destination).@DestinationConfig?.preprocessors;
    };

    isolated function addToDLStore(MessageContext msgContext) {
        DeadLetterStore? dlstore = self.dlstore;
        if dlstore is DeadLetterStore {
            string id = msgContext.getId();
            error? dlStoreError = dlstore.store(msgContext.getMessage());
            if dlStoreError is error {
                log:printError("failed to add message to dead letter store", 'error = dlStoreError, msgId = id);
            } else {
                log:printDebug("message added to dead letter store", msgId = id);
            }
        }
        log:printWarn("dead letter store is not configured, skipping storing the failed message", msgId = msgContext.getId());
        return;
    }
}

