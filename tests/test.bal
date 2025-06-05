import ballerina/log;
import ballerina/test;

@HandlerConfig {
    name: "handler1"
}
isolated function handleMsg1(MessageContext msgCtx) returns error? {
    // Simulate handling the message
    anydata content = msgCtx.getContent();
    msgCtx.setProperty("handler1", "success");
    // Here you can add your handling logic
    log:printInfo("message processed by handler1", content = content);
}

@HandlerConfig {
    name: "handler2"
}
isolated function handleMsg2(MessageContext msgCtx) returns error? {
    // Simulate handling the message
    anydata content = msgCtx.getContent();
    msgCtx.setProperty("handler2", "success");
    // Here you can add your handling logic
    log:printInfo("message processed by handler2", content = content);
}

@test:Config
function testMessageHandling() returns error? {
    Channel msgChannel = check new Channel([handleMsg1, handleMsg2]);
    ExecutionResult result = check msgChannel.execute(content = "Test message content");
    test:assertEquals(result.message.properties, {
        "handler1": "success",
        "handler2": "success"
    }, msg = "Message properties should contain handler results");
}

@test:Config
function testChannelCreationFailure1() returns error? {
    Channel|error msgChannel = new Channel([]);
    if msgChannel is Channel {
        // If the channel was created successfully, we should fail the test
        test:assertFail("Channel creation should have failed due to handler failure");
    }
    test:assertEquals(msgChannel.message(), "Channel must have at least one handler.", msg = "Channel creation should fail with an error message");
}

isolated function handleMsgFail(MessageContext msgCtx) returns error? {}

@test:Config
function testChannelCreationFailure2() returns error? {
    Channel|error msgChannel = new Channel([handleMsgFail]);
    if msgChannel is Channel {
        // If the channel was created successfully, we should fail the test
        test:assertFail("Channel creation should have failed due to handler failure");
    }
    test:assertEquals(msgChannel.message(), "Handler name is not defined for one or more handlers.", msg = "Channel creation should fail with an error message");
}

@test:Config
function testSkipMessageHandling() returns error? {
    Channel msgChannel = check new Channel([handleMsg1, handleMsg2]);
    ExecutionResult result = check msgChannel.execute("Test message content", skipHandlers = ["handler1"]);
    test:assertEquals(result.message.properties, {
        "handler2": "success"
    }, msg = "Message properties should only contain results from handlers that were not skipped");
}
