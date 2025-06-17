// import ballerina/http;
// import ballerina/lang.runtime;
// import ballerina/log;

// isolated http:Listener? replayListener = ();

// configurable int replayListenerPort = 9095;

// final readonly & http:Service replayService = service object {

//     isolated resource function get channels() returns string[] {
//         lock {
//             return channels.keys().clone();
//         }
//     }

//     isolated resource function get channels/[string channelId]/failures()
//             returns Message[]|http:NotFound|http:NotImplemented|error {
//         lock {
//             if !channels.hasKey(channelId) {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Channel with ID '${channelId}' not found.`
//                     }
//                 };
//             }
//         }

//         Channel channel;
//         lock {
//             channel = channels.get(channelId);
//         }

//         DeadLetterStore? dlStore = channel.getDlStore();
//         if dlStore is DeadLetterStore {
//             return dlStore.retrieveAll();
//         }

//         return <http:NotImplemented>{
//             body: {
//                 "message": string `Dead letter store is not implemented for channel '${channelId}'.`
//             }
//         };
//     }

//     isolated resource function get channels/[string channelId]/failures/[string messageId]()
//             returns Message|http:NotFound|http:NotImplemented|error {
//         lock {
//             if !channels.hasKey(channelId) {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Channel with ID '${channelId}' not found.`
//                     }
//                 };
//             }
//         }

//         Channel channel;
//         lock {
//             channel = channels.get(channelId);
//         }

//         DeadLetterStore? dlStore = channel.getDlStore();
//         if dlStore is DeadLetterStore {
//             if dlStore.hasMessage(messageId) {
//                 return dlStore.retrieve(messageId);
//             } else {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Message with ID '${messageId}' not found in dead letter store for channel '${channelId}'.`
//                     }
//                 };
//             }
//         }

//         return <http:NotImplemented>{
//             body: {
//                 "message": string `Dead letter store is not implemented for channel '${channelId}'.`
//             }
//         };
//     }

//     isolated resource function delete channels/[string channelId]/failures/[string messageId]()
//             returns http:NoContent|http:NotFound|http:NotImplemented|error {
//         lock {
//             if !channels.hasKey(channelId) {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Channel with ID '${channelId}' not found.`
//                     }
//                 };
//             }
//         }

//         Channel channel;
//         lock {
//             channel = channels.get(channelId);
//         }

//         DeadLetterStore? dlStore = channel.getDlStore();
//         if dlStore is DeadLetterStore {
//             if dlStore.hasMessage(messageId) {
//                 _ = check dlStore.delete(messageId);
//                 return http:NO_CONTENT;
//             } else {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Message with ID '${messageId}' not found in dead letter store for channel '${channelId}'.`
//                     }
//                 };
//             }
//         }

//         return <http:NotImplemented>{
//             body: {
//                 "message": string `Dead letter store is not implemented for channel '${channelId}'.`
//             }
//         };
//     }

//     isolated resource function delete channels/[string channelId]/failures()
//             returns http:NoContent|http:NotFound|http:NotImplemented|error {
//         lock {
//             if !channels.hasKey(channelId) {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Channel with ID '${channelId}' not found.`
//                     }
//                 };
//             }
//         }

//         Channel channel;
//         lock {
//             channel = channels.get(channelId);
//         }

//         DeadLetterStore? dlStore = channel.getDlStore();
//         if dlStore is DeadLetterStore {
//             _ = check dlStore.clear();
//             return http:NO_CONTENT;
//         }

//         return <http:NotImplemented>{
//             body: {
//                 "message": string `Dead letter store is not implemented for channel '${channelId}'.`
//             }
//         };
//     }

//     isolated resource function post channels/[string channelId]/replay/[string messageId](Message? message)
//             returns http:Ok|http:NotFound|http:NotImplemented|error {
//         lock {
//             if !channels.hasKey(channelId) {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Channel with ID '${channelId}' not found.`
//                     }
//                 };
//             }
//         }

//         Channel channel;
//         lock {
//             channel = channels.get(channelId);
//         }

//         DeadLetterStore? dlStore = channel.getDlStore();
//         if dlStore is DeadLetterStore {
//             if dlStore.hasMessage(messageId) {
//                 Message messageToReplay = message.clone() ?: check dlStore.retrieve(messageId);
//                 _ = check dlStore.delete(messageId);
//                 _ = check channel.replay(messageToReplay);
//                 return <http:Ok>{
//                     body: {
//                         "message": string `Message with ID '${messageId}' replayed successfully in channel '${channelId}'.`
//                     }
//                 };
//             } else {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Message with ID '${messageId}' not found in dead letter store for channel '${channelId}'.`
//                     }
//                 };
//             }
//         }

//         return <http:NotImplemented>{
//             body: {
//                 "message": string `Dead letter store is not implemented for channel '${channelId}'.`
//             }
//         };
//     }

//     isolated resource function post channels/[string channelId]/replay()
//             returns http:Ok|http:NotFound|http:NotImplemented|error {
//         lock {
//             if !channels.hasKey(channelId) {
//                 return <http:NotFound>{
//                     body: {
//                         "message": string `Channel with ID '${channelId}' not found.`
//                     }
//                 };
//             }
//         }

//         Channel channel;
//         lock {
//             channel = channels.get(channelId);
//         }

//         DeadLetterStore? dlStore = channel.getDlStore();
//         if dlStore is DeadLetterStore {
//             Message[] messages = check dlStore.retrieveAll();
//             _ = check dlStore.clear();
//             foreach Message message in messages {
//                 _ = check channel.replay(message);
//             }
//             return <http:Ok>{
//                 body: {
//                     "message": string `All messages replayed successfully in channel '${channelId}'.`
//                 }
//             };
//         }

//         return <http:NotImplemented>{
//             body: {
//                 "message": string `Dead letter store is not implemented for channel '${channelId}'.`
//             }
//         };
//     }
// };

// isolated function initializeReplayListener() returns error? {
//     lock {
//         if replayListener is http:Listener {
//             return;
//         }
//         http:Listener httpListener = check new (replayListenerPort);
//         check httpListener.attach(replayService);
//         check httpListener.start();
//         runtime:registerListener(httpListener);
//         replayListener = httpListener;
//     }
//     log:printInfo(string `replay listener is started on port ${replayListenerPort} for failure inspection and replay.`);
// }
