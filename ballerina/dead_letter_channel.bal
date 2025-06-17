// import ballerina/file;
// import ballerina/io;
// import ballerina/log;
// import ballerinax/rabbitmq;

// # Dead Letter Store Type
// public type DeadLetterStore isolated object {
//     # Store the message in the dead letter store.
//     #
//     # + msg - The message to store in the dead letter store.
//     # + return - An error if the message could not be stored, otherwise returns `()`.
//     public isolated function store(Message msg) returns error?;

//     # Retrieve all messages from the dead letter store.
//     #
//     # + return - An array of messages from the dead letter store, or an error if retrieval fails.
//     public isolated function retrieveAll() returns Message[]|error;

//     # Check if a message with the specified ID exists in the dead letter store.
//     #
//     # + id - The ID of the message to check.
//     # + return - `true` if the message exists, otherwise `false`.
//     public isolated function hasMessage(string id) returns boolean;

//     # Retrieve a specific message from the dead letter store by its ID.
//     #
//     # + id - The ID of the message to retrieve.
//     # + return - The message with the specified ID, or an error if retrieval fails.
//     public isolated function retrieve(string id) returns Message|error;

//     # Delete a specific message from the dead letter store by its ID.
//     #
//     # + id - The ID of the message to delete.
//     # + return - An error if the message could not be deleted, otherwise returns `()`.
//     public isolated function delete(string id) returns error?;

//     # Delete all messages from the dead letter store.
//     #
//     # + return - An error if the messages could not be deleted, otherwise returns `()`.
//     public isolated function clear() returns error?;
// };

// # Dead Letter Store implemented with in-memory table.
// public isolated class InMemoryDeadLetterStore {
//     *DeadLetterStore;

//     private final table<Message> key(id) msgStore = table [];

//     public isolated function store(Message msg) returns error? {
//         lock {
//             self.msgStore.add(msg.clone());
//         }
//     }

//     public isolated function retrieveAll() returns Message[]|error {
//         lock {
//             return self.msgStore.toArray().clone();
//         }
//     }

//     public isolated function hasMessage(string id) returns boolean {
//         lock {
//             return self.msgStore.hasKey(id);
//         }
//     }

//     public isolated function retrieve(string id) returns Message|error {
//         lock {
//             return self.msgStore.get(id).clone();
//         }
//     }

//     public isolated function delete(string id) returns error? {
//         lock {
//             if self.msgStore.hasKey(id) {
//                 _ = self.msgStore.remove(id);
//             } else {
//                 return error("Message not found with ID: " + id);
//             }
//         }
//     }

//     public isolated function clear() returns error? {
//         lock {
//             self.msgStore.removeAll();
//         }
//     }
// }

// # Dead Letter Store implemented with a local file system.
// public isolated class LocalFileDeadLetterStore {
//     *DeadLetterStore;

//     final string dlsDirectory;

//     # Creates a new instance of LocalFileDeadLetterStore.
//     #
//     # + dlsDirectory - The absolute path to the directory where dead letter messages will be stored.
//     # + return - An error if the store could not be initialized, otherwise returns `()`.
//     public isolated function init(string dlsDirectory) returns error? {
//         self.dlsDirectory = dlsDirectory;
//     }

//     public isolated function store(Message msg) returns error? {
//         string id = msg.id;
//         string filePath = self.dlsDirectory + "/" + id + ".json";
//         json msgContent = msg.toJson();
//         error? result = io:fileWriteJson(filePath, msgContent);
//         if result is error {
//             return error("Failed to store message with ID: " + id, cause = result);
//         }
//     }

//     public isolated function clear() returns error? {
//         error? result = file:remove(self.dlsDirectory, file:RECURSIVE);
//         if result is error {
//             return error("Failed to clear dead letter store", cause = result);
//         }
//     }

//     public isolated function delete(string id) returns error? {
//         string filePath = self.dlsDirectory + "/" + id + ".json";
//         error? result = file:remove(filePath);
//         if result is error {
//             return error("Failed to delete message with ID: " + id, cause = result);
//         }
//     }

//     public isolated function hasMessage(string id) returns boolean {
//         string filePath = self.dlsDirectory + "/" + id + ".json";
//         boolean|error result = file:test(filePath, file:EXISTS);
//         if result is error {
//             log:printDebug(string `Failed to check existence of message with ID: ${id}`, 'error = result);
//             return false; // If there's an error, assume the message does not exist
//         }
//         return result;
//     }

//     public isolated function retrieve(string id) returns Message|error {
//         string filePath = self.dlsDirectory + "/" + id + ".json";
//         json|error result = io:fileReadJson(filePath);
//         if result is error {
//             return error(string `Failed to retrieve message with ID: ${id}`, cause = result);
//         }
//         return result.fromJsonWithType();
//     }

//     public isolated function retrieveAll() returns Message[]|error {
//         Message[] messages = [];
//         file:MetaData[]|error files = file:readDir(self.dlsDirectory);
//         if files is error {
//             return error("Failed to read dead letter store directory", cause = files);
//         }
//         foreach file:MetaData fileMetaData in files {
//             if fileMetaData.dir == true || !fileMetaData.absPath.endsWith(".json") {
//                 continue; // Skip directories and non-JSON files
//             }
//             json|error fileContent = io:fileReadJson(fileMetaData.absPath);
//             if fileContent is error {
//                 log:printError(string `failed to read file: ${fileMetaData.absPath}`, 'error = fileContent);
//                 continue; // Skip files that cannot be read
//             }
//             Message|error message = check fileContent.fromJsonWithType();
//             if message is Message {
//                 messages.push(message);
//             } else {
//                 log:printError(string `failed to convert file content to Message type: ${fileMetaData.absPath}`, 'error = message);
//             }
//         }
//         return messages;
//     }
// }

// public type RabbitMqClientConfiguration record {|
//     string host = "localhost";
//     int port = 5672;
//     rabbitmq:ConnectionConfiguration connectionData = {};
//     RabbitMqPublishConfiguration publishConfig = {};
// |};

// public type RabbitMqPublishConfiguration record {|
//     string exchange = "";
//     int deliveryTag?;
//     rabbitmq:BasicProperties properties?;
// |};

// public type RabbitMqMessage record {|
//     *rabbitmq:AnydataMessage;
//     Message content;
// |};

// # Dead Letter Store implemented with RabbitMQ.
// public isolated class RabbitMqDLStore {
//     *DeadLetterStore;

//     private final rabbitmq:Client dlqClient;
//     private final readonly & RabbitMqPublishConfiguration dlqPublishConfig;
//     private final string dlqName;

//     # Creates a new instance of RabbitMqDLStore.
//     #
//     # + dlqName - The name of the dead letter queue.
//     # + replayQueueName - The name of the replay queue.
//     # + dlqCofig - The RabbitMQ connection configuration for the dead letter queue.
//     # + replayConfig - The RabbitMQ connection configuration for the replay channel.
//     # + return - An error if the store could not be initialized, otherwise returns `()`.
//     public isolated function init(string dlqName, RabbitMqClientConfiguration dlqCofig = {}) returns error? {
//         self.dlqClient = check new (dlqCofig.host, dlqCofig.port, dlqCofig.connectionData);
//         self.dlqPublishConfig = dlqCofig.publishConfig.cloneReadOnly();
//         self.dlqName = dlqName;
//     }

//     public isolated function store(Message msg) returns error? {
//         error? result = self.dlqClient->publishMessage({
//             content: msg,
//             routingKey: self.dlqName,
//             ...self.dlqPublishConfig
//         });

//         if result is error {
//             return error(string `Failed to store message with ID: ${msg.id} in RabbitMQ dead letter queue`, cause = result);
//         }
//     }

//     public isolated function clear() returns error? {
//         error? result = self.dlqClient->queuePurge(self.dlqName);
//         if result is error {
//             return error(string `Failed to clear RabbitMQ dead letter queue: ${self.dlqName}`, cause = result);
//         }
//     }

//     public isolated function delete(string id) returns error? {
//         RabbitMqMessage[] rabbitmqMessages = self.retrieveMessages();
//         foreach int index in 0 ..< rabbitmqMessages.length() {
//             RabbitMqMessage rabbitmqMessage = rabbitmqMessages[index];
//             if rabbitmqMessage.content.id == id {
//                 _ = rabbitmqMessages.remove(index);
//             }
//         }
//         self.requeueMessages(rabbitmqMessages);
//     }

//     public isolated function hasMessage(string id) returns boolean {
//         RabbitMqMessage[] rabbitmqMessages = self.retrieveMessages();
//         boolean exists = false;
//         foreach RabbitMqMessage rabbitmqMessage in rabbitmqMessages {
//             if rabbitmqMessage.content.id == id {
//                 exists = true;
//                 break;
//             }
//         }
//         self.requeueMessages(rabbitmqMessages);
//         return exists;
//     }

//     public isolated function retrieve(string id) returns Message|error {
//         RabbitMqMessage[] rabbitmqMessages = self.retrieveMessages();
//         Message[] listResult = from RabbitMqMessage rabbitmqMessage in rabbitmqMessages
//             where rabbitmqMessage.content.id == id
//             select rabbitmqMessage.content;
//         self.requeueMessages(rabbitmqMessages);
//         if listResult.length() == 0 {
//             return error(string `Message with ID: ${id} not found in RabbitMQ dead letter queue`);
//         } else if listResult.length() > 1 {
//             return error(string `Multiple messages found with ID: ${id} in RabbitMQ dead letter queue`);
//         }
//         return listResult[0];
//     }

//     public isolated function retrieveAll() returns Message[]|error {
//         RabbitMqMessage[] rabbitmqMessages = self.retrieveMessages();
//         Message[] messages = from RabbitMqMessage rabbitmqMessage in rabbitmqMessages
//             select rabbitmqMessage.content;
//         self.requeueMessages(rabbitmqMessages);
//         return messages;
//     }

//     isolated function retrieveMessages() returns RabbitMqMessage[] {
//         RabbitMqMessage[] rabbitmqMessages = [];
//         RabbitMqMessage|error message = self.dlqClient->consumeMessage(self.dlqName, autoAck = false);
//         while message is RabbitMqMessage {
//             rabbitmqMessages.push(message);
//             message = self.dlqClient->consumeMessage(self.dlqName, autoAck = false);
//         }
//         return rabbitmqMessages;
//     }

//     isolated function requeueMessages(RabbitMqMessage[] rabbitmqMessages) {
//         while rabbitmqMessages.length() > 0 {
//             RabbitMqMessage rabbitmqMessage = rabbitmqMessages.pop();
//             error? result = self.dlqClient->basicNack(message = rabbitmqMessage, requeue = true);
//             if result is error {
//                 log:printDebug(string `Failed to nack message with ID: ${rabbitmqMessage.content.id}`, 'error = result);
//             }
//         }
//     }
// }
