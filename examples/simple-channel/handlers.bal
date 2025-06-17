import tharmigan/reliable.messaging;
import ballerina/log;
import ballerina/file;
import ballerina/io;
import ballerina/http;

@messaging:ProcessorConfig {
    name: "MsgProcessor"
}
isolated function processMessage(messaging:MessageContext ctx) returns error? {
    Message message = check ctx.getContent().toJson().fromJsonWithType(Message);
    log:printInfo("Processing message with ID: " + message.id);
    // Simulate message processing
    log:printInfo("message processed successfully", id = ctx.getId());
}

@messaging:DestinationConfig {
    name: "FileWriter"
}
isolated function writePayloadToFile(messaging:MessageContext ctx) returns error? {
    json payload = ctx.getContent().toJson();
    string filePath = "./processed_data/" + ctx.getId() + ".json";
    if check file:test(filePath, file:EXISTS) {
        return error("Cannot write to file, file already exists: " + filePath);
    }
    check io:fileWriteJson(filePath, payload);
    log:printInfo("payload written to file", filePath = filePath);
}

@messaging:DestinationConfig {
    name: "HttpEndpoint"
}
isolated function sendToHttpEp(messaging:MessageContext ctx) returns json|error {
    http:Client httpEndpoint = check new ("http://localhost:8080/api/v1");
    json payload = ctx.getContent().toJson();
    return httpEndpoint->/patients.post(payload);
}
