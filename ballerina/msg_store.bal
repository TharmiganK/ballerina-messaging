import ballerina/file;
import ballerina/io;
import ballerina/uuid;
import ballerinax/rabbitmq;
import ballerina/log;

# Represents a message store interface for storing and retrieving messages.
public type MessageStore isolated object {

    # Stores a message in the message store.
    #
    # + message - The message to be stored
    # + return - An error if the message could not be stored, or `()`
    public isolated function store(anydata message) returns error?;

    # Retrieves specified number of messages from the message store.
    #
    # + count - The number of messages to retrieve from the store. Defaults to 1
    # + return - The retrieved messages as an array, or an error if the store is empty or an error occurs
    public isolated function retrieve(int count = 1) returns anydata[]|error;

    # Retrieves all the messages from the message store.
    #
    # + return - An array of all messages in the store, or an error if the store is empty or an error occurs
    public isolated function retrieveAll() returns anydata[]|error;

    # Clears all messages from the message store.
    #
    # + return - An error if the store could not be cleared, or `()`
    public isolated function clear() returns error?;

    # Deletes specified number of messages from the message store.
    #
    # + count - The number of messages to delete from the store. Defaults to 1
    # + return - An error if the message could not be deleted, or `()`
    public isolated function delete(int count = 1) returns error?;
};

# Represents an in-memory message store implementation.
public isolated class InMemoryMessageStore {
    *MessageStore;

    private anydata[] messages;

    # Initializes a new instance of the InMemoryMessageStore class
    public isolated function init() {
        self.messages = [];
    }

    # Stores a message in the message store.
    #
    # + message - The message to be stored
    # + return - An error if the message could not be stored, or `()`
    public isolated function store(anydata message) returns error? {
        lock {
            self.messages.push(message.clone());
        }
    }

    # Retrieves specified number of messages from the message store.
    #
    # + count - The number of messages to retrieve from the store. Defaults to 1
    # + return - The retrieved messages as an array, or an error if the store is empty or an error occurs
    public isolated function retrieve(int count = 1) returns anydata[]|error {
        if count <= 0 {
            return error("Count must be greater than zero");
        }

        lock {
            if self.messages.length() == 0 {
                return [];
            }

            if count >= self.messages.length() {
                anydata[] messages = self.messages.clone();
                check self.clear();
                return messages.clone();
            }

            anydata[] retrievedMessages = [];
            foreach int i in 0 ... count {
                retrievedMessages.push(self.messages.pop());
            }
            return retrievedMessages.clone();
        }
    }

    # Retrieves all the messages from the message store.
    #
    # + return - An array of all messages in the store, or an error if the store is empty or an error occurs
    public isolated function retrieveAll() returns anydata[]|error {
        lock {
            anydata[] messages = self.messages.clone();
            check self.clear();
            return messages.clone();
        }
    }

    # Clears all messages from the message store.
    #
    # + return - An error if the store could not be cleared, or `()`.
    public isolated function clear() returns error? {
        lock {
            check trap self.messages.removeAll();
        }
    }

    # Deletes specified number of messages from the message store.
    #
    # + count - The number of messages to delete from the store. Defaults to 1
    # + return - An error if the message could not be deleted, or `()`
    public isolated function delete(int count = 1) returns error? {
        lock {
            if count <= 0 {
                return error("Count must be greater than zero");
            }

            if count > self.messages.length() {
                return self.clear();
            }

            foreach int i in 0 ... count {
                _ = check trap self.messages.pop();
            }
        }
    }
}

# Represents a Local file system based message store implementation.
public isolated class LocalFileMessageStore {
    *MessageStore;

    private final string directoryName;

    # Initializes a new instance of the LocalFileMessageStore class.
    #
    # + directoryName - The name of the directory where messages will be stored
    public isolated function init(string directoryName) {
        self.directoryName = directoryName;
    }

    # Stores a message in the local file system message store.
    # 
    # + message - The message to be stored
    # + return - An error if the message could not be stored, or `()`
    public isolated function store(anydata message) returns error? {
        string uuid = uuid:createType1AsString();
        string filePath = self.directoryName + "/" + uuid + ".json";
        error? result = io:fileWriteJson(filePath, message.toJson());
        if result is error {
            return error("Failed to store message in local file system", cause = result);
        }
    }

    # Retrieves specified number of messages from the local file system message store.
    # 
    # + count - The number of messages to retrieve from the store. Defaults to 1
    # + return - The retrieved messages as an array, or an error if the store is empty or an error occurs
    public isolated function retrieve(int count) returns anydata[]|error {
        if count <= 0 {
            return error("Count must be greater than zero");
        }

        anydata[] messages = [];
        file:MetaData[]|error files = file:readDir(self.directoryName);
        if files is error {
            return error("Failed to read directory", cause = files, directory = self.directoryName);
        }

        int retrievedCount = 0;
        foreach file:MetaData fileMetaData in files {
            if retrievedCount >= count {
                break;
            }
            if fileMetaData.dir == true || !fileMetaData.absPath.endsWith(".json") {
                continue; // Skip directories and non-JSON files
            }
            json|error fileContent = io:fileReadJson(fileMetaData.absPath);
            if fileContent is error {
                log:printError("failed to read file", 'error = fileContent, filePath = fileMetaData.absPath);
                continue; // Skip files that cannot be read
            }
            messages.push(fileContent);
            retrievedCount += 1;
            // delete the file after reading
            error? deleteResult = file:remove(fileMetaData.absPath);
            if deleteResult is error {
                log:printError("failed to delete file after reading", 'error = deleteResult, filePath = fileMetaData.absPath);
            }
        }
        return messages;
    }

    # Retrieves all the messages from the local file system message store.
    # 
    # + return - An array of all messages in the store, or an error if the store is empty or an error occurs
    public isolated function retrieveAll() returns anydata[]|error {
        anydata[] messages = [];
        file:MetaData[]|error files = file:readDir(self.directoryName);
        if files is error {
            return error("Failed to read directory", cause = files, directory = self.directoryName);
        }

        foreach file:MetaData fileMetaData in files {
            if fileMetaData.dir == true || !fileMetaData.absPath.endsWith(".json") {
                continue; // Skip directories and non-JSON files
            }
            json|error fileContent = io:fileReadJson(fileMetaData.absPath);
            if fileContent is error {
                log:printError("failed to read file", 'error = fileContent, filePath = fileMetaData.absPath);
                continue; // Skip files that cannot be read
            }
            messages.push(fileContent);
        }
        error? result = self.clear(); // Clear the store after retrieving all messages
        if result is error {
            return error("Failed to clear the message store after retrieval", cause = result);
        }
        return messages;
    }

    # Clears all messages from the local file system message store.
    # 
    # + return - An error if the store could not be cleared, or `()`.
    public isolated function clear() returns error? {
        check file:remove(self.directoryName, option = file:RECURSIVE);
    }

    # Deletes specified number of messages from the local file system message store.
    # 
    # + count - The number of messages to delete from the store. Defaults to 1
    # + return - An error if the message could not be deleted, or `()`
    public isolated function delete(int count) returns error? {
        if count <= 0 {
            return error("Count must be greater than zero");
        }

        file:MetaData[]|error files = file:readDir(self.directoryName);
        if files is error {
            return error("Failed to read directory", cause = files, directory = self.directoryName);
        }

        int deletedCount = 0;
        foreach file:MetaData fileMetaData in files {
            if deletedCount >= count {
                break;
            }
            if fileMetaData.dir == true || !fileMetaData.absPath.endsWith(".json") {
                continue; // Skip directories and non-JSON files
            }
            error? result = file:remove(fileMetaData.absPath);
            if result is error {
                log:printError("failed to delete file", 'error = result, filePath = fileMetaData.absPath);
                continue; // Skip files that cannot be deleted
            }
            deletedCount += 1;
        }
    }
}

# Represents a RabbitMQ client configuration.
# 
# + host - The RabbitMQ server host. Defaults to "localhost"
# + port - The RabbitMQ server port. Defaults to 5672
# + connectionData - The RabbitMQ connection configuration
# + publishConfig - The RabbitMQ publish configuration
public type RabbitMqClientConfiguration record {|
    string host = "localhost";
    int port = 5672;
    rabbitmq:ConnectionConfiguration connectionData = {};
    RabbitMqPublishConfiguration publishConfig = {};
|};

# Represents a RabbitMQ publish configuration.
# 
# + exchange - The RabbitMQ exchange to publish messages to. Defaults to an empty string
# + deliveryTag - The delivery tag for the message. Optional
# + properties - The RabbitMQ message properties. Optional
public type RabbitMqPublishConfiguration record {|
    string exchange = "";
    int deliveryTag?;
    rabbitmq:BasicProperties properties?;
|};

# Represents a RabbitMQ message store implementation.
public isolated class RabbitMqMessageStore {
    *MessageStore;

    private final rabbitmq:Client rabbitMqClient;
    private final readonly & RabbitMqPublishConfiguration publishConfig;
    private final string queueName;

    # Initializes a new instance of the RabbitMqMessageStore class.
    #
    # + queueName - The name of the RabbitMQ queue to use for storing messages
    # + clientCofig - The RabbitMQ client configuration
    public isolated function init(string queueName, RabbitMqClientConfiguration clientCofig = {}) returns error? {
        self.rabbitMqClient = check new (clientCofig.host, clientCofig.port, clientCofig.connectionData);
        self.publishConfig = clientCofig.publishConfig.cloneReadOnly();
        self.queueName = queueName;
    }

    # Stores a message in the RabbitMQ message store.
    #
    # + message - The message to be stored
    # + return - An error if the message could not be stored, or `()`
    public isolated function store(anydata message) returns error? {
        error? result = self.rabbitMqClient->publishMessage({
            content: message,
            routingKey: self.queueName,
            ...self.publishConfig
        });

        if result is error {
            return error("Failed to store message in RabbitMQ", cause = result);
        }
    }

    # Retrieves specified number of messages from the RabbitMQ message store.
    #
    # + count - The number of messages to retrieve from the store. Defaults to 1
    # + return - The retrieved messages as an array, or an error if the store is empty or an error occurs
    public isolated function retrieve(int count = 1) returns anydata[]|error {
        if count <= 0 {
            return error("Count must be greater than zero");
        }

        rabbitmq:AnydataMessage[] rabbitmqMessages = [];
        rabbitmq:AnydataMessage|error message = self.rabbitMqClient->consumeMessage(self.queueName);
        while message is rabbitmq:AnydataMessage {
            rabbitmqMessages.push(message);
            if rabbitmqMessages.length() >= count {
                break;
            }
            message = self.rabbitMqClient->consumeMessage(self.queueName);
        }
        return from rabbitmq:AnydataMessage rabbitmqMessage in rabbitmqMessages
            select rabbitmqMessage.content;
    }

    # Retrieves all the messages from the RabbitMQ message store.
    #
    # + return - An array of all messages in the store, or an error if the store is empty or an error occurs
    public isolated function retrieveAll() returns anydata[]|error {
        rabbitmq:AnydataMessage[] rabbitmqMessages = [];
        rabbitmq:AnydataMessage|error message = self.rabbitMqClient->consumeMessage(self.queueName);
        while message is rabbitmq:AnydataMessage {
            rabbitmqMessages.push(message);
            message = self.rabbitMqClient->consumeMessage(self.queueName);
        }
        return from rabbitmq:AnydataMessage rabbitmqMessage in rabbitmqMessages
            select rabbitmqMessage.content;
    }

    # Clears all messages from the RabbitMQ message store.
    #
    # + return - An error if the store could not be cleared, or `()`.
    public isolated function clear() returns error? {
        error? result = self.rabbitMqClient->queuePurge(self.queueName);
        if result is error {
            return error("Failed to clear RabbitMQ queue", cause = result);
        }
    }

    # Deletes specified number of messages from the RabbitMQ message store.
    #
    # + count - The number of messages to delete from the store. Defaults to 1.
    # + return - An error if the message could not be deleted, or `()`.
    public isolated function delete(int count = 1) returns error? {
        if count <= 0 {
            return error("Count must be greater than zero");
        }

        rabbitmq:AnydataMessage|error message = self.rabbitMqClient->consumeMessage(self.queueName);
        int deletedCount = 1;
        while message is rabbitmq:AnydataMessage {
            if deletedCount >= count {
                break;
            }
            message = self.rabbitMqClient->consumeMessage(self.queueName);
            deletedCount += 1;
        }
    }
}
