import ballerina/http;
import ballerina/log;

import tharmigan/reliable.messaging;

// final messaging:InMemoryMessageStore messageStore = new;
final messaging:RabbitMqMessageStore messageStore = check new("messages.bi");

public type Message record {|
    string id;
    string content;
|};

service /api on new http:Listener(9090) {

    isolated resource function post messages(Message message) returns http:Accepted|error {
        log:printInfo("message received at http service", id = message.id);
        check messageStore.store(message);
        return http:ACCEPTED;
    }
}

listener messaging:MessageStoreListener msgStoreListener = check new (
    messageStore = messageStore,
    maxRetries = 3,
    pollingConfig = {
        pollingInterval: 10,
        maxMessagesPerPoll: 2
    }
);

service on msgStoreListener {

    public isolated function onMessage(anydata payload) returns error? {
        Message message = check payload.toJson().fromJsonWithType();
        log:printInfo("start processing message", id = message.id, content = message.content);
    }
}
