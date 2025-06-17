import ballerina/lang.runtime;
import ballerina/log;

isolated function startReplayListener(Channel channel, DeadLetterStoreConfiguration config) returns Error? {
    ReplayListenerConfiguration? listenerConfig = config.listenerConfig;
    if listenerConfig is () {
        return;
    }

    if !listenerConfig.enabled {
        log:printDebug("replay listener is not enabled, skipping start");
        return;
    }

    MessageStore targetStore = listenerConfig?.targetStore ?: config.dlstore;
    do {
        MessageStoreListener replayListener = check new (
            messageStore = targetStore,
            maxRetries = listenerConfig.maxRetries,
            pollingConfig = listenerConfig.pollingConfig
        );
        ReplayService replayService = new (channel);
        check replayListener.attach(replayService);
        check replayListener.'start();
        runtime:registerListener(replayListener);
        log:printInfo("replay listener started successfully", channel = channel.getName());
    } on fail error err {
        log:printError("failed to start replay listener", 'error = err);
        return error Error("Failed to start replay listener", err);
    }
}

isolated service class ReplayService {
    *MessageStoreService;

    private final Channel channel;

    isolated function init(Channel channel) {
        self.channel = channel;
    }

    public isolated function onMessage(anydata message) returns error? {
        Message|error replayableMessage = message.toJson().fromJsonWithType();
        if replayableMessage is error {
            log:printError("error converting message to replayable type", 'error = replayableMessage);
            return replayableMessage;
        }
        
        ExecutionResult|error executionResult = self.channel.replay(replayableMessage);
        if executionResult is error {
            log:printError("error replaying message", 'error = executionResult);
            return executionResult;
        }
    }
}
