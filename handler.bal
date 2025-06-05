
// # Message handler accepts the message context and do any processing on the message.
// public type Handler isolated function (MessageContext msgCtx) returns error?;

// # Message handler configuration
// # 
// # + name - The name of the handler, which is used to identify it in the context.
// # # + dependsOn - An array of handler names that this handler depends on. If any of these handlers fail, this handler will not be executed.
// public type HandlerConfiguration record {|
//     string name;
// |};

// # Handler configuration annotation
// public const annotation HandlerConfiguration HandlerConfig on function;
