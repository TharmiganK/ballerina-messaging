import ballerina/http;

final http:Client httpEndpoint = check new ("http://localhost:9090/api/v1");
