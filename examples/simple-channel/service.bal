import ballerina/http;
import ballerina/log;

import tharmigan/reliable.messaging;

final messaging:LocalFileMessageStore dlstore = new ("./dls");

service /api on new http:Listener(9090) {

    isolated resource function post messages(Message message) returns http:Ok|error {
        do {
            _ = check channel.execute(message);
            return http:OK;
        } on fail messaging:ExecutionError err {
            log:printError("failed to process message", 'error = err);
            error? result = dlstore.store(err.detail().message);
            if result is error {
                log:printError("failed to store message in dead letter store", 'error = result);
            } else {
                log:printInfo("message stored in dead letter store");
            }
            return err;
        }
    }
}
