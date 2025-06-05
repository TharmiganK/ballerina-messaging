import ballerinax/rabbitmq;

# Dead Letter Store Type
public type DLStore isolated object {
    # Store the message in the dead letter store.
    # 
    # + msg - The message to store in the dead letter store.
    # + return - An error if the message could not be stored, otherwise returns `()`.
    public isolated function store(Message msg) returns error?;

    # Retrieve the top message from the dead letter store.
    #
    # + return - An error if the message could not be retrieved, otherwise returns the message.
    public isolated function retrieve() returns Message|error?;

    # Clear all messages from the dead letter store.
    # 
    # + return - An error if the messages could not be cleared, otherwise returns `()`.
    public isolated function clear() returns error?;
};

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
    *DLStore;

    private final rabbitmq:Client 'client;
    private final readonly & RabbitMqPublishMessageConfiguration publishConfig;
    private final string dlqRoutingKey;

    # Creates a new instance of RabbitMqDLStore.
    # 
    # + host - The RabbitMQ host.
    # + port - The RabbitMQ port.
    # + dlqRoutingKey - The routing key for the dead letter queue.
    # + publishConfig - The configuration for publishing messages.
    # + connectionConfig - The RabbitMQ connection configuration.
    # + return - An error if the store could not be initialized, otherwise returns `()`.
    public isolated function init(string host, int port, string dlqRoutingKey, RabbitMqPublishMessageConfiguration publishConfig = {}, *rabbitmq:ConnectionConfiguration connectionConfig) returns error? {
        self.'client = check new (host, port, connectionConfig);
        self.publishConfig = publishConfig.cloneReadOnly();
        self.dlqRoutingKey = dlqRoutingKey;
    }

    # Pops the message from the dead letter store.
    # 
    # + return - An error if the message could not be retrieved, otherwise returns the message.
    public isolated function retrieve() returns Message|error? {
        record{|*rabbitmq:AnydataMessage; Message content;|} message = check self.'client->consumeMessage(self.dlqRoutingKey);
        return message.content;
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

    # Clear all messages from the dead letter store.
    # 
    # + return - An error if the messages could not be cleared, otherwise returns `()`.
    public isolated function clear() returns error? {
        return self.'client->queuePurge(self.dlqRoutingKey);
    }
}