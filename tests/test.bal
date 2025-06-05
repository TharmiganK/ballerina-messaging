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

@TransformerConfig {
    name: "transformer"
}
isolated function transformProcessor(MessageContext msgCtx) returns Order|error {
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
isolated function genericDestination(MessageContext msgCtx) returns error? {
    Order 'order = check msgCtx.getContent().ensureType();
    int totalPrice = check msgCtx.getProperty("totalPrice").ensureType(int);
    string fileName = "./target/test-resources/" + 'order.id + ".json";
    check io:fileWriteJson(fileName, {totalPrice, ...'order});
}

@FilterConfig {
    name: "destinationFilter"
}
isolated function destinationFilter(MessageContext msgCtx) returns boolean|error {
    // Only process orders with a total price greater than 10000
    int totalPrice = check msgCtx.getProperty("totalPrice").ensureType(int);
    return totalPrice > 10000;
}

@DestinationConfig {
    name: "specialDestination",
    preprocessors: [destinationFilter]
}
isolated function specialDestination(MessageContext msgCtx) returns error? {
    Order 'order = check msgCtx.getContent().ensureType();
    int totalPrice = check msgCtx.getProperty("totalPrice").ensureType(int);
    string fileName = "./target/test-resources/special-" + 'order.id + ".json";
    check io:fileWriteJson(fileName, {totalPrice, ...'order});
}

isolated class MockDLS {
    *DeadLetterStore;

    public isolated function clear() returns error? {
        return;
    }

    public isolated function retrieve() returns Message|error? {
        return;
    }

    public isolated function store(Message msg) returns error? {
        string fileName = "./target/test-resources/dls-" + msg.id + ".json";
        check io:fileWriteJson(fileName, msg.toJson());
        return;
    }
}

MockDLS dls = new ();

@test:Config
function testChannelExecution1() returns error? {
    Channel channel = check new ({
        processors: [
            transformProcessor,
            filterProcessor,
            processProcessor
        ],
        destinations: [
            genericDestination,
            specialDestination
        ],
        dlstore: dls
    });

    Order 'order = {
        id: "order-100",
        customerId: "customer-456",
        itemId: "item-789",
        quantity: 10,
        unitPrice: 80,
        status: "PROCESSED"
    };

    ExecutionResult _ = check channel.execute('order);
    string fileName = "./target/test-resources/" + 'order.id + ".json";
    test:assertFalse(check file:test(fileName, file:EXISTS));
}

@test:Config
function testChannelExecution2() returns error? {
    Channel channel = check new ({
        processors: [
            transformProcessor,
            filterProcessor,
            processProcessor
        ],
        destinations: [
            genericDestination,
            specialDestination
        ],
        dlstore: dls
    });
    
    Order 'order = {
        id: "order-101",
        customerId: "customer-456",
        itemId: "item-789",
        quantity: 10,
        unitPrice: 80,
        status: "PENDING"
    };

    ExecutionResult _ = check channel.execute('order);
    string fileName = "./target/test-resources/" + 'order.id + ".json";
    test:assertTrue(check file:test(fileName, file:EXISTS));

    json fileContent = check io:fileReadJson(fileName);
    record {int totalPrice; *Order;} orderData = check fileContent.fromJsonWithType();
    test:assertEquals(orderData.id, 'order.id);
    test:assertEquals(orderData.totalPrice, 800);
}

@test:Config
function testChannelExecution3() returns error? {
    Channel channel = check new ({
        processors: [
            transformProcessor,
            filterProcessor,
            processProcessor
        ],
        destinations: [
            genericDestination,
            specialDestination
        ],
        dlstore: dls
    });
    
    Order 'order = {
        id: "order-102",
        customerId: "customer-456",
        itemId: "item-789",
        quantity: 10,
        unitPrice: 1500,
        status: "PENDING"
    };

    ExecutionResult _ = check channel.execute('order);
    string fileName = "./target/test-resources/special-" + 'order.id + ".json";
    test:assertTrue(check file:test(fileName, file:EXISTS));

    json fileContent = check io:fileReadJson(fileName);
    record {int totalPrice; *Order;} orderData = check fileContent.fromJsonWithType();
    test:assertEquals(orderData.id, 'order.id);
    test:assertEquals(orderData.totalPrice, 15000);
}
