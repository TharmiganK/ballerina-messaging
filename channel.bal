// import ballerina/log;
// import ballerina/uuid;

// # Channel is a collection of message handlers that can be executed in parallel or sequentially.
// public isolated class Channel {
//     final readonly & Handler[] handlers;
//     final DLStore? dlstore;
//     final boolean isParallel;
//     final boolean continueOnError;

//     # Initializes a new instance of Channel with the provided handlers.
//     public isolated function init(Handler[] handlers, DLStore? dlstore = (), boolean isParallel = false, boolean continueOnError = false) returns Error? {
//         self.handlers = handlers.cloneReadOnly();
//         self.dlstore = dlstore;
//         if isParallel && continueOnError {
//             log:printWarn("continue on error is not applicable for parallel execution. It will be ignored.");
//         }
//         self.isParallel = isParallel;
//         self.continueOnError = continueOnError;
//         check self.validatehandlers(handlers.cloneReadOnly());
//     }

//     # Replay the channel execution flow.
//     # 
//     # + message - The message to replay process.
//     # + return - Returns an error if any handler fails.
//     public isolated function replay(Message message) returns DispatchResult|DispatchError {
//         MessageContext msgContext = new(message);
//         log:printDebug("replay channel execution started", msgId = msgContext.getId());
//         return self.executeHandlersInParallel(msgContext);
//     }

//     # Dispatch a message to the channel for processing with the defined handlers.
//     # 
//     # + content - The message content to be processed.
//     # + skipHandlers - An array of handler names to skip during execution.
//     # + return - Returns an error if any handler fails.
//     public isolated function execute(anydata content, string[] skipHandlers = []) returns DispatchResult|DispatchError {
//         string id = uuid:createType1AsString();
//         MessageContext msgContext = new (id = id, content = content, metadata = {skipHandlers: skipHandlers});
//         log:printDebug("channel execution started", msgId = id);
//         return self.executeHandlersInParallel(msgContext);
//     }

//     isolated function executeHandlers(MessageContext msgContext) returns DispatchResult|DispatchError {
//         if self.isParallel {
//             return self.executeHandlersInParallel(msgContext);
//         } else {
//             return self.executeHandlersSequentionally(msgContext);
//         }
//     }

//     isolated function executeHandlersSequentionally(MessageContext msgContext) returns DispatchResult|DispatchError {
//         string id = msgContext.getId();
//         map<error> failedHandlers = {};
//         foreach Handler handler in self.handlers {
//             string? handlerName = self.getHandlerName(handler);
//             if handlerName is () {
//                 panic error Error("Handler name is not defined for one or more handlers");
//             }
//             if msgContext.isHandlerSkipped(handlerName) {
//                 log:printWarn("handler is requested to be skipped", handlerName = handlerName, msgId = id);
//             } else {
//                 error? result = handler(msgContext);
//                 if result is error {
//                     log:printDebug("handler execution failed", handlerName = handlerName, msgId = id, 'error = result);
//                     if self.continueOnError {
//                         failedHandlers[handlerName] = result;
//                         log:printDebug("continuing execution despite handler failure", handlerName = handlerName, msgId = id, 'error = result);
//                     } else {
//                         string errorMsg = string `Failed to execute handler: ${handlerName} - ${result.message()}`;
//                         msgContext.setErrorMsg(errorMsg);
//                         msgContext.setErrorStackTrace(result.stackTrace().toString());
//                         self.addToDLStore(msgContext);
//                         return error DispatchError(errorMsg, message = {...msgContext.getMessage()});
//                     }
//                 } else {
//                     msgContext.skipHandler(handlerName);
//                     log:printDebug("handler executed successfully", handlerName = handlerName, msgId = id);
//                 }
//             }
//         }
//         if failedHandlers.length() > 0 {
//             return self.reportMutipleHandlerFailure(failedHandlers, msgContext);
//         }
//         return { message: {...msgContext.getMessage()} };
//     }

//     isolated function executeHandlersInParallel(MessageContext msgContext) returns DispatchResult|DispatchError {
//         string id = msgContext.getId();
//         map<future<error?>> handlerExecutions = {};
//         foreach Handler handler in self.handlers {
//             string? handlerName = self.getHandlerName(handler);
//             if handlerName is () {
//                 panic error Error("Handler name is not defined for one or more handlers");
//             }
//             if msgContext.isHandlerSkipped(handlerName) {
//                 log:printWarn("handler is requested to be skipped", handlerName = handlerName, msgId = id);
//             } else {
//                 future<error?> handlerExecution = start handler(msgContext);
//                 handlerExecutions[handlerName] = handlerExecution;
//             }
//         }
//         map<error> failedhandlers = {};
//         foreach var [handlerName, handlerExecution] in handlerExecutions.entries() {
//             error? result = wait handlerExecution;
//             if result is () {
//                 // If the handler execution was successful, continue.
//                 msgContext.skipHandler(handlerName);
//                 log:printDebug("handler executed successfully", handlerName = handlerName, msgId = id);
//                 continue;
//             } else {
//                 // If there was an error, collect the error.
//                 failedhandlers[handlerName] = result;
//                 log:printDebug("handler execution failed", handlerName = handlerName, msgId = id, 'error = result);
//             }
//         }
//         if failedhandlers.length() > 0 {
//             return self.reportMutipleHandlerFailure(failedhandlers, msgContext);
//         }
//         return { message: {...msgContext.getMessage()} };
//     }

//     isolated function reportMutipleHandlerFailure(map<error> failedHandlers, MessageContext msgContext) returns DispatchError {
//         string errorMsg = "Failed to execute handlers: ";
//         foreach var [handlerName, err] in failedHandlers.entries() {
//             errorMsg += handlerName + " - " + err.message() + "; ";
//         }
//         msgContext.setErrorMsg(errorMsg.trim());
//         string stackTrace = "";
//         foreach var [handlerName, err] in failedHandlers.entries() {
//             stackTrace += handlerName + " - " + err.stackTrace().toString() + "\n";
//         }
//         if stackTrace.length() > 0 {
//             stackTrace = stackTrace.substring(0, stackTrace.length() - 1);
//         }
//         msgContext.setErrorStackTrace(stackTrace);
        
//         self.addToDLStore(msgContext);

//         return error DispatchError(errorMsg, message = {...msgContext.getMessage()});
//     }

//     isolated function validatehandlers(Handler[] handlers) returns Error? {
//         if handlers.length() == 0 {
//             return error Error("Channel must have at least one handler.");
//         }
//         foreach Handler handler in handlers {
//             string? handlerName = self.getHandlerName(handler);
//             if handlerName is () {
//                 return error Error("Handler name is not defined for one or more handlers.");
//             }
//         }
//     }

//     isolated function getHandlerName(Handler handler) returns string? {
//         return (typeof handler).@HandlerConfig?.name;
//     };

//     isolated function addToDLStore(MessageContext msgContext) {
//         DLStore? dlstore = self.dlstore;
//         if dlstore is DLStore {
//             string id = msgContext.getId();
//             error? dlStoreError = dlstore.store(msgContext.getMessage());
//             if dlStoreError is error {
//                 log:printError("failed to add message to dead letter store", 'error = dlStoreError, msgId = id);
//             } else {
//                 log:printDebug("message added to dead letter store", msgId = id);
//             }
//         }
//         log:printWarn("dead letter store is not configured, skipping storing the failed message", msgId = msgContext.getId());
//         return;
//     }
// }

import ballerina/log;
import ballerina/uuid;

# Channel is a collection of message handlers that can be executed in parallel or sequentially.
public isolated class Channel {
    final readonly & Processor[] processors;
    final readonly & Destination[] destinations;
    final DLStore? dlstore;

    # Initializes a new instance of Channel with the provided processors and destinations.
    public isolated function init(Processor[] processors = [], Destination[] destinations = [], DLStore? dlstore = ()) returns Error? {
        if processors.length() == 0 && destinations.length() == 0 {
            return error Error("Channel must have at least one processor or destination.");
        }
        self.processors = processors.cloneReadOnly();
        self.destinations = destinations.cloneReadOnly();
        self.dlstore = dlstore;
        check self.validateProcessors(self.processors);
        check self.validateDestinations(self.destinations);
    }

    # Replay the channel execution flow.
    # 
    # + message - The message to replay process.
    # + return - Returns an error if any handler fails.
    public isolated function replay(Message message) returns ExecutionResult|ExecutionError {
        MessageContext msgContext = new(message);
        log:printDebug("replay channel execution started", msgId = msgContext.getId());
        return self.executeInternal(msgContext);
    }

    # Dispatch a message to the channel for processing with the defined handlers.
    # 
    # + content - The message content to be processed.
    # + skipHandlers - An array of handler names to skip during execution.
    # + return - Returns an error if any handler fails.
    public isolated function execute(anydata content, string[] skipHandlers = []) returns ExecutionResult|ExecutionError {
        string id = uuid:createType1AsString();
        MessageContext msgContext = new (id = id, content = content, metadata = {skipDestinations: skipHandlers});
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
        map<future<error?>> destinationExecutions = {};
        foreach Destination destination in self.destinations {
            string destinationName = self.getDestinationName(destination);
            if msgContext.isDestinationSkipped(destinationName) {
                log:printWarn("destination is requested to be skipped", destinationName = destinationName, msgId = msgContext.getId());
            } else {
                future<error?> destinationExecution = start self.executeDestination(destination, msgContext.clone());
                destinationExecutions[destinationName] = destinationExecution;
            }
        }

        map<error> failedDestinations = {};
        foreach var [destinationName, destinationExecution] in destinationExecutions.entries() {
            error? result = wait destinationExecution;
            if result is () {
                // If the destination execution was successful, continue.
                msgContext.skipDestination(destinationName);
                log:printDebug("destination executed successfully", destinationName = destinationName, msgId = msgContext.getId());
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
        return { message: {...msgContext.getMessage()} };
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
                return { message: {...msgContext.getMessage()} };
            }
        } else {
            anydata transformedContent = check processor(msgContext);
            msgContext.setContent(transformedContent);
            log:printDebug("processor transformer executed successfully", processorName = processorName, msgId = msgContext.getId());
        }
    }

    isolated function executeDestination(Destination destination, MessageContext msgContext) returns error? {
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
                return;
            }
        }
        // Execute the destination
        return destination(msgContext);
    }

    isolated function reportDestinationFailure(map<error> failedHandlers, MessageContext msgContext) returns ExecutionError {
        string errorMsg = "Failed to execute handlers: ";
        foreach var [handlerName, err] in failedHandlers.entries() {
            errorMsg += handlerName + " - " + err.message() + "; ";
        }
        msgContext.setErrorMsg(errorMsg.trim());
        string stackTrace = "";
        foreach var [handlerName, err] in failedHandlers.entries() {
            stackTrace += handlerName + " - " + err.stackTrace().toString() + "\n";
        }
        if stackTrace.length() > 0 {
            stackTrace = stackTrace.substring(0, stackTrace.length() - 1);
        }
        msgContext.setErrorStackTrace(stackTrace);
        self.addToDLStore(msgContext);
        return error ExecutionError(errorMsg, message = {...msgContext.getMessage()});
    }

    isolated function validateProcessors(Processor[] handlers) returns Error? {
        foreach Processor processor in handlers {
            string|error processorName = trap self.getProcessorName(processor);
            if processorName is Error {
                return processorName;
            }
        }
    }

    isolated function getProcessorName(Processor processor) returns string {
        string? name = (typeof processor).@ProcessorConfig?.name;
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
        DLStore? dlstore = self.dlstore;
        if dlstore is DLStore {
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

