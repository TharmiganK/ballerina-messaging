import ballerina/file;
import ballerina/log;
import ballerina/io;

import tharmigan/reliable.messaging;

listener file:Listener directoryListener = new ({
    path: "./data",
    recursive: false
});

service on directoryListener {

    remote function onCreate(file:FileEvent m) {
        string filePath = m.name.toString();
        if !filePath.endsWith(".json") {
            log:printInfo("ignoring non-JSON file: " + filePath);
            return;
        }

        json|error jsonContent = io:fileReadJson(filePath);
        if jsonContent is error {
            log:printError("failed to read JSON file", 'error = jsonContent);
            return;
        }

        messaging:Message|error msg = jsonContent.fromJsonWithType();
        if msg is error {
            log:printError("failed to convert JSON to Message type", 'error = msg);
            return;
        }

        removeFile(filePath);

        messaging:ExecutionResult|messaging:ExecutionError result = msgChannel.replay(msg);
        if result is messaging:ExecutionError {
            log:printError("error processing the data file", 'error = result);
            return;
        }
        log:printInfo("message is replayed in the channel successfully", id = result.message.id);
    }
}

function removeFile(string filePath) {
    error? err = file:remove(filePath);
    if err is error {
        log:printError("failed to remove file after processing", 'error = err);
    } else {
        log:printInfo("file removed after processing", 'filePath = filePath);
    }
}
