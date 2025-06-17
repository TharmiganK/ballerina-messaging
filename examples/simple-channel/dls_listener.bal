import tharmigan/reliable.messaging;
import ballerina/log;
// import ballerina/file;
// import ballerina/io;

listener messaging:MessageStoreListener dlsListener = check new (
    messageStore = dlstore,
    maxRetries = 3,
    pollingConfig = {
        pollingInterval: 10,
        maxMessagesPerPoll: 2
    }
);

service on dlsListener {

    public isolated function onMessage(anydata message) returns error? {
        messaging:Message replayableMessage = check message.toJson().fromJsonWithType();
        do {
            _ = check channel.replay(replayableMessage);
            log:printInfo("message replayed successfully", id = replayableMessage.id);
        } on fail error err {
            log:printError("failed to replay message", 'error = err);
        }
    }
}

// listener file:Listener directoryListener = new ({
//     path: "./dls",
//     recursive: false
// });

// type HealthDataEventMessage record {|
//     *messaging:Message;
//     Message content;
// |};

// service on directoryListener {

//     remote function onCreate(file:FileEvent m) {
//         string filePath = m.name.toString();
//         if !filePath.endsWith(".json") {
//             log:printInfo("ignoring non-JSON file: " + filePath);
//             return;
//         }

//         json|error jsonContent = io:fileReadJson(filePath);
//         if jsonContent is error {
//             log:printError("failed to read JSON file", 'error = jsonContent);
//             return;
//         }

//         HealthDataEventMessage|error msg = jsonContent.fromJsonWithType();
//         if msg is error {
//             log:printError("failed to convert JSON to HealthDataEventMessage", 'error = msg);
//             return;
//         }

//         removeFile(filePath);

//         messaging:ExecutionResult|messaging:ExecutionError result = channel.replay(msg);
//         if result is messaging:ExecutionError {
//             log:printError("error processing the data file", 'error = result);
//             return;
//         }
//         log:printInfo("message is replayed in the channel successfully", id = result.message.id);
//     }
// }

// function removeFile(string filePath) {
//     error? err = file:remove(filePath);
//     if err is error {
//         log:printError("failed to remove file after processing", 'error = err);
//     } else {
//         log:printInfo("file removed after processing", 'filePath = filePath);
//     }
// }
