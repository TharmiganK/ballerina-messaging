import ballerina/log;
import ballerina/task;

# Message processor polling configuration
#
# + pollingInterval - The interval in seconds at which the message processor polls for new messages.
# + maxMessagesPerPoll - The maximum number of messages to process in a single polling cycle.
public type MessagePollingConfig record {|
    decimal pollingInterval = 1;
    int maxMessagesPerPoll = 10;
|};

# Represents the message store listener configuration,
# 
# + maxRetries - The maximum number of retries for processing a message.
# + pollingConfig - The configuration for polling messages from the message store.
public type MessageStoreListenerConfiguration record {|
    int maxRetries = 3;
    MessagePollingConfig pollingConfig = {};
|};

# Represents a message store listener that polls messages from a message store and processes them.
public isolated class MessageStoreListener {

    private MessageStore messageStore;
    private MessagePollingConfig pollingConfig;
    private MessageStoreService? messageStoreService = ();
    private task:JobId? pollJobId = ();
    private int maxRetries = 3;

    # Initializes a new instance of Message Store Listener.
    # 
    # + messageStore - The message store to retrieve messages from
    # + config - The configuration for the message store listener
    # + return - An error if the listener could not be initialized, or `()`
    public isolated function init(MessageStore messageStore, *MessageStoreListenerConfiguration config) returns error? {
        self.messageStore = messageStore;
        if config.maxRetries < 0 {
            return error("maxRetries cannot be negative");
        }
        self.maxRetries = config.maxRetries;
        self.pollingConfig = config.pollingConfig.clone();
    }

    # Attaches a message store service to the listener. Only one service can be attached to this listener.
    # 
    # + msgStoreService - The message store service to attach.
    # + path - The path is not relevant for this listener. Only allowing a nil value.
    # + return - An error if the service could not be attached, or `()`.
    public isolated function attach(MessageStoreService msgStoreService, () path = ()) returns error? {
        lock {
            if self.messageStoreService is MessageStoreService {
                return error("messageStoreService is already attached. Only one service can be attached to the message store listener");
            }
            self.messageStoreService = msgStoreService;
        }
    }


    # Detaches the message store service from the listener.
    # 
    # + msgStoreService - The message store service to detach.
    # + return - An error if the service could not be detached, or `()`.
    public isolated function detach(MessageStoreService msgStoreService) returns error? {
        lock {
            MessageStoreService? currentService = self.messageStoreService;
            if currentService is () {
                return error("no messageStoreService is attached");
            }
            if currentService === msgStoreService {
                self.messageStoreService = ();
            } else {
                return error("the provided messageStoreService is not attached to the listener");
            }
        }
    }

    # Starts the message store listener to poll and process messages.
    # 
    # + return - An error if the listener could not be started, or `()`.
    public isolated function 'start() returns error? {
        lock {
            MessageStoreService? currentService = self.messageStoreService;
            if currentService is () || self.pollJobId !is () {
                return;
            }

            log:printDebug("starting message store listener");
            
            PollAndProcessMessages pollTask = new(self.messageStore, currentService, self.maxRetries,  self.pollingConfig);
            task:JobId|error pollJob = task:scheduleJobRecurByFrequency(pollTask, self.pollingConfig.pollingInterval);
            if pollJob is error {
                return error("failed to start message store listener", cause = pollJob);
            }
            log:printInfo("message store listener started successfully");
        }
    }

    # Gracefully stops the message store listener.
    # 
    # + return - An error if the listener could not be stopped, or `()`.
    public isolated function gracefulStop() returns error? {
        lock {
            task:JobId? pollJobId = self.pollJobId;
            if pollJobId is () {
                return;
            }
            
            error? stopResult = task:unscheduleJob(pollJobId);
            if stopResult is error {
                return error("failed to stop message store listener", cause = stopResult);
            }
            log:printInfo("message store listener stopped successfully");
        }
    }

    # Immediately stops the message store listener without waiting for any ongoing processing to complete.
    # This is not implemented yet and will call gracefulStop.
    # 
    # + return - An error if the listener could not be stopped, or `()`.
    public isolated function immediateStop() returns error? {
        return self.gracefulStop();
    }

}

isolated class PollAndProcessMessages {
    // *task:Job;

    private MessageStore messageStore;
    private MessageStoreService messageStoreService;
    private readonly & MessagePollingConfig pollingConfig;
    private int maxRetries;

    public isolated function init(MessageStore messageStore, MessageStoreService messageStoreService, int maxRetries, *MessagePollingConfig pollingConfig) {
        self.messageStore = messageStore;
        self.messageStoreService = messageStoreService;
        self.pollingConfig = pollingConfig.cloneReadOnly();
        self.maxRetries = maxRetries;
    }

    public isolated function execute() {
        lock {
            anydata[]|error messages = self.messageStore.retrieve(self.pollingConfig.maxMessagesPerPoll);
            if messages is error {
                log:printError("error polling messages", 'error = messages);
                return;
            }
            foreach anydata message in messages {
                error? result = self.messageStoreService.onMessage(message);
                if result is () {
                    log:printDebug("message processed successfully", message = message);
                    continue;
                }
                log:printError("error processing message", 'error = result);
                if self.maxRetries <= 0 {
                    continue; // No retries configured, skip to the next message
                }
                int retries = 0;
                while retries < self.maxRetries {
                    error? retryResult = self.messageStoreService.onMessage(message);
                    retries += 1;
                    if retryResult is error {
                        log:printError("error processing message on retry", attempt = retries, 'error = retryResult);
                    } else {
                        log:printDebug("message processed successfully on retry");
                        break;
                    }
                    retries += 1;
                }
            }
        }
    }
}

# This service object defines the contract for processing messages from a message store.
public type MessageStoreService distinct isolated service object {

    # This function is called when a new message is received from the message store.
    # 
    # + message - The message to be processed.
    # + return - An error if the message could not be processed, or `()`.
    public isolated function onMessage(anydata message) returns error?;
};
