import tharmigan/reliable.messaging;

final messaging:Channel msgChannel;

// final messaging:LocalFileDeadLetterStore dls = check new ("./dls");

final messaging:RabbitMqDLStore dls = check new ("messages.bi.dlq");

function init() returns error? {
    msgChannel = check new ("event-to-fhir", {
        sourceFlow: [
            hasEventDataType,
            extractPayload,
            routeByDataType
        ],
        destinationsFlow: [
            sendToFHIRServer,
            writePayloadToFile,
            sendToHttpEp
        ],
        dlstore: dls
    });
}
