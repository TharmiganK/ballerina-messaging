import tharmigan/reliable.messaging;

final messaging:Channel msgChannel;

final messaging:LocalFileDeadLetterStore localFileDls = check new ("./dls");

function init() returns error? {
    msgChannel = check new ({
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
        dlstore: localFileDls
    });
}
