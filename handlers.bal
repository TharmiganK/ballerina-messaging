# Represents a transformer function that processes the message content and returns a modified message content.
public type Transformer isolated function (MessageContext msgCtx) returns anydata|error;

# Represents a filter function that checks the message context and returns a boolean indicating whether the message should be processed further.
public type Filter isolated function (MessageContext msgCtx) returns boolean|error;

# Represents a processor router function that processes the message context and returns a processor or an error if the routing fails.
public type ProcessorRouter isolated function (MessageContext msgCtx) returns Processor|error?;

# Represents a destination function that processes the message context and returns a result or an error if it failed to send the message to the destination.
# Destinations are typically contains a sender or a writer that sends or writes the message to a specific destination.
public type Destination isolated function (MessageContext msgCtx) returns any|error;

# Represents a destination router function that processes the message context and returns a destination or an error if the routing fails, or nil if it wants to stop processing the message.
public type DestinationRouter isolated function (MessageContext msgCtx) returns Destination|error?;

# Represents a generic message processor that can process the message and return an error if the processing fails.
public type GenericProcessor isolated function (MessageContext msgCtx) returns error?;

# Represents a processor that can be a filter, transformer, or processor and can be attached to a channel for processing messages.
# Processors should be idompotent i.e. repeating the execution should not change the outcome or the channel state.
public type Processor GenericProcessor|Filter|Transformer|ProcessorRouter;

# Represents a destination configuration that includes the name of the destination, an optional filter, and an optional transformer.
#
# + name - The name of the destination.
# + preprocessors - An array of preprocessors that will be executed before sending the message to the destination.
public type DestinationConfiguration record {|
    string name;
    Processor[] preprocessors = [];
|};

# Destination configuration annotation.
public annotation DestinationConfiguration DestinationConfig on function;

# Processor related configuration.
#
# + name - The name of the processor.
public type ProcessorConfiguration record {|
    string name;
|};

# Processor configuration annotation.
public const annotation ProcessorConfiguration ProcessorConfig on function;

# Filter configuration annotation.
public const annotation ProcessorConfiguration FilterConfig on function;

# Transformer configuration annotation.
public annotation ProcessorConfiguration TransformerConfig on function;

# Processor router configuration annotation.
public annotation ProcessorConfiguration ProcessorRouterConfig on function;

# Destination router configuration annotation.
public annotation ProcessorConfiguration DestinationRouterConfig on function;
