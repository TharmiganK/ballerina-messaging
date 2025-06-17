import ballerina/file;
import ballerina/io;
import ballerina/test;

type Order record {|
    string id;
    string customerId;
    string itemId;
    int quantity;
    int unitPrice;
    "PENDING"|"PROCESSED" status;
|};

@ProcessorRouterConfig {
    name: "dataTypeRouter"
}
isolated function dataTypeRouter(MessageContext msgCtx) returns Processor|error? {
    return msgCtx.getContent() is record {} ? transformProcessor : ();
}

@TransformerConfig {
    name: "transformer"
}
isolated function transformProcessor(MessageContext msgCtx) returns Order|error {
    msgCtx.setProperty("transformer", "executed");
    anydata content = msgCtx.getContent();
    return content.toJson().fromJsonWithType();
}

@FilterConfig {
    name: "filter"
}
isolated function filterProcessor(MessageContext msgCtx) returns boolean|error {
    Order 'order = check msgCtx.getContent().ensureType();
    return 'order.status == "PENDING";
}

@ProcessorConfig {
    name: "processor"
}
isolated function processProcessor(MessageContext msgCtx) returns error? {
    Order 'order = check msgCtx.getContent().ensureType();
    int totalPrice = 'order.quantity * 'order.unitPrice;
    msgCtx.setProperty("totalPrice", totalPrice);
}

@DestinationConfig {
    name: "genericDestination"
}
isolated function genericDestination(MessageContext msgCtx) returns string|error {
    Order 'order = check msgCtx.getContent().ensureType();
    int totalPrice = check msgCtx.getProperty("totalPrice").ensureType(int);
    string fileName = "./target/test-resources/" + 'order.id + ".json";
    check io:fileWriteJson(fileName, {totalPrice, ...'order});
    return "Order saved in the generic destination";
}

@DestinationRouterConfig {
    name: "destinationRouter"
}
isolated function destinationRouter(MessageContext msgCtx) returns Destination|error {
    // Only process orders with a total price greater than 10000
    int totalPrice = check msgCtx.getProperty("totalPrice").ensureType(int);
    return totalPrice > 10000 ? specialDestination : genericDestination;
}

@DestinationConfig {
    name: "specialDestination"
}
isolated function specialDestination(MessageContext msgCtx) returns string|error {
    Order 'order = check msgCtx.getContent().ensureType();
    int totalPrice = check msgCtx.getProperty("totalPrice").ensureType(int);
    string fileName = "./target/test-resources/special/" + 'order.id + ".json";
    check io:fileWriteJson(fileName, {totalPrice, ...'order});
    return "Order saved in the special destination";
}

isolated class MockDLS {
    // *DeadLetterStore;
    *MessageStore;

    public isolated function store(anydata message) returns error? {
        Message msg = check message.toJson().fromJsonWithType();
        string fileName = "./target/test-resources/dls/" + msg.id + ".json";
        check io:fileWriteJson(fileName, msg.toJson());
        return;
    }

    public isolated function clear() returns error? {
        return;
    }

    public isolated function delete(int count) returns error? {
        return;
    }

    public isolated function retrieve(int count) returns anydata[]|error {
        return [];
    }

    public isolated function retrieveAll() returns anydata[]|error {
        return [];
    }
}

MockDLS dls = new ();

@test:Config
function testChannelExecution1() returns error? {
    Channel channel = check new ("channel1", {
        sourceFlow: [
            dataTypeRouter,
            filterProcessor,
            processProcessor
        ],
        destinationsFlow: destinationRouter,
        dlstoreConfig: {dlstore: dls}
    });

    Order 'order = {
        id: "order-100",
        customerId: "customer-456",
        itemId: "item-789",
        quantity: 10,
        unitPrice: 80,
        status: "PROCESSED"
    };

    ExecutionResult result = check channel.execute('order);
    test:assertEquals(result.destinationResults, {}, "No destinations should be executed for processed orders");
    string fileName = "./target/test-resources/" + 'order.id + ".json";
    test:assertFalse(check file:test(fileName, file:EXISTS));
}

@test:Config
function testChannelExecution2() returns error? {
    Channel channel = check new ("channel2", {
        sourceFlow: [
            dataTypeRouter,
            filterProcessor,
            processProcessor
        ],
        destinationsFlow: destinationRouter,
        dlstoreConfig: {dlstore: dls}
    });

    Order 'order = {
        id: "order-101",
        customerId: "customer-456",
        itemId: "item-789",
        quantity: 10,
        unitPrice: 80,
        status: "PENDING"
    };

    ExecutionResult result = check channel.execute('order);
    test:assertEquals(result.destinationResults, {
                                                     "genericDestination": "Order saved in the generic destination"
                                                 }, "Generic destination should be executed for pending orders");
    string fileName = "./target/test-resources/" + 'order.id + ".json";
    test:assertTrue(check file:test(fileName, file:EXISTS));

    json fileContent = check io:fileReadJson(fileName);
    record {int totalPrice; *Order;} orderData = check fileContent.fromJsonWithType();
    test:assertEquals(orderData.id, 'order.id);
    test:assertEquals(orderData.totalPrice, 800);
}

@test:Config
function testChannelExecution3() returns error? {
    Channel channel = check new ("channel3", {
        sourceFlow: [
            dataTypeRouter,
            filterProcessor,
            processProcessor
        ],
        destinationsFlow: destinationRouter,
        dlstoreConfig: {dlstore: dls}
    });

    Order 'order = {
        id: "order-102",
        customerId: "customer-456",
        itemId: "item-789",
        quantity: 10,
        unitPrice: 1500,
        status: "PENDING"
    };

    ExecutionResult result = check channel.execute('order);
    test:assertEquals(result.destinationResults, {
                                                     "specialDestination": "Order saved in the special destination"
                                                 }, "Special destination should be executed for pending orders with total price > 10000");
    string fileName = "./target/test-resources/special/" + 'order.id + ".json";
    test:assertTrue(check file:test(fileName, file:EXISTS));

    json fileContent = check io:fileReadJson(fileName);
    record {int totalPrice; *Order;} orderData = check fileContent.fromJsonWithType();
    test:assertEquals(orderData.id, 'order.id);
    test:assertEquals(orderData.totalPrice, 15000);
}

@test:Config
function testChannelExecution4() returns error? {
    Channel channel = check new ("channel4", {
        sourceFlow: [
            dataTypeRouter,
            filterProcessor,
            processProcessor
        ],
        destinationsFlow: destinationRouter,
        dlstoreConfig: {dlstore: dls}
    });
    ExecutionResult result = check channel.execute("'order");
    test:assertFalse(result.message.properties.hasKey("transformer"), "Transformer should not be executed for non-json content");
}

@test:Config
function testChannelExecution5() returns error? {
    Channel channel = check new ("channel5", {
        sourceFlow: [
            dataTypeRouter,
            filterProcessor,
            processProcessor
        ],
        destinationsFlow: destinationRouter,
        dlstoreConfig: {dlstore: dls}
    });
    ExecutionResult|ExecutionError result = channel.execute({"test": "data"});
    if result is ExecutionResult {
        test:assertFail("Expected ExecutionError, but got ExecutionResult");
    }
    string fileName = "./target/test-resources/dls/" + result.detail().message.id + ".json";
    test:assertTrue(check file:test(fileName, file:EXISTS), "Dead letter store should store the message with json content");
}
