import ballerinax/rabbitmq;
import ballerina/log;
import ballerina/io;

# Dead Letter Store Type
public type DeadLetterStore isolated object {
    # Store the message in the dead letter store.
    #
    # + msg - The message to store in the dead letter store.
    # + return - An error if the message could not be stored, otherwise returns `()`.
    public isolated function store(Message msg) returns error?;
};

# Dead Letter Store implemented with a logger.
public isolated class LoggerDLStore {
    *DeadLetterStore;

    # Store the message in the dead letter store by logging it.
    #
    # + msg - The message to store in the dead letter store.
    # + return - An error if the message could not be stored, otherwise returns `()`.
    public isolated function store(Message msg) returns error? {
        log:printInfo("storing message in dead letter store", message = msg);
    }
}

# Dead Letter Store implemented with a local file system.
public isolated class LocalFileDeadLetterStore {
    *DeadLetterStore;

    final string dlsDirectory;

    # Creates a new instance of LocalFileDeadLetterStore.
    # 
    # + dlsDirectory - The absolute path to the directory where dead letter messages will be stored.
    # + return - An error if the store could not be initialized, otherwise returns `()`.
    public isolated function init(string dlsDirectory) returns error? {
        self.dlsDirectory = dlsDirectory;
    }

    # Store the message in the dead letter store.
    # 
    # + msg - The message to store in the dead letter store.
    # + return - An error if the message could not be stored, otherwise returns `()`.
    public isolated function store(Message msg) returns error? {
        string id = msg.id;
        string filePath = self.dlsDirectory + "/" + id + ".json";
        json msgContent = msg.toJson();
        check io:fileWriteJson(filePath, msgContent);
        log:printInfo("message stored in dead letter store", id = id, path = filePath);
    }
}

# RabbitMQ Publish Message Configuration
#
# + exchange - The exchange to publish the message to.
# + deliveryTag - The delivery tag for the message, if applicable.
# + properties - The properties of the message, if applicable.
public type RabbitMqPublishMessageConfiguration record {|
    string exchange = "";
    int deliveryTag?;
    rabbitmq:BasicProperties properties?;
|};

# Dead Letter Store implemented with RabbitMQ.
public isolated class RabbitMqDLStore {
    *DeadLetterStore;

    private final rabbitmq:Client 'client;
    private final readonly & RabbitMqPublishMessageConfiguration publishConfig;
    private final string dlqRoutingKey;

    # Creates a new instance of RabbitMqDLStore.
    #
    # + host - The RabbitMQ host.
    # + port - The RabbitMQ port.
    # + dlqRoutingKey - The routing key for the dead letter queue.
    # + publishConfig - The configuration for publishing messages.
    # + return - An error if the store could not be initialized, otherwise returns `()`.
    public isolated function init(string host, int port, string dlqRoutingKey, *RabbitMqPublishMessageConfiguration publishConfig) returns error? {
        self.'client = check new (host, port);
        self.publishConfig = publishConfig.cloneReadOnly();
        self.dlqRoutingKey = dlqRoutingKey;
    }

    # Store the message in the dead letter store.
    #
    # + msg - The message to store in the dead letter store.
    # + return - An error if the message could not be stored, otherwise returns `()`.
    public isolated function store(Message msg) returns error? {
        return self.'client->publishMessage({
            content: msg,
            routingKey: self.dlqRoutingKey,
            ...self.publishConfig
        });
    }
}
